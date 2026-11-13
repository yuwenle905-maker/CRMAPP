using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Xml;

namespace CRMWindows
{
    public class AutoImportConfig
    {
        public bool enabled { get; set; }
        public string filePath { get; set; }
        public string lastFileStamp { get; set; }
        public string shipmentFilePath { get; set; }
        public string lastShipmentFileStamp { get; set; }
        public string lastScheduledSlot { get; set; }
        public List<string> processedRowKeys { get; set; }
        public List<string> processedShipmentKeys { get; set; }
        public bool shipmentHistoryBaselineApplied { get; set; }
        public AutoImportConfig()
        {
            enabled = true;
            filePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "余文乐资料.xlsx");
            shipmentFilePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "杂项", "自动更新发货 资料录入", "发货表.xlsx");
            lastFileStamp = "";
            lastShipmentFileStamp = "";
            lastScheduledSlot = "";
            processedRowKeys = new List<string>();
            processedShipmentKeys = new List<string>();
            shipmentHistoryBaselineApplied = false;
        }
    }

    public class AutoImportResult
    {
        public bool Success;
        public bool Changed;
        public int Added;
        public int Completed;
        public int Skipped;
        public string Message;
        public List<ShipmentOrderCandidate> OrderCandidates = new List<ShipmentOrderCandidate>();
    }

    public class ShipmentOrderCandidate
    {
        public string SourceKey; public Customer Customer; public SourceCustomerRow Source;
    }

    public class SourceCustomerRow
    {
        public DateTime Date;
        public string Name;
        public string Phone;
        public string Address;
        public string Product;
        public double? Amount;
        public double? Height;
        public double? Weight;
        public int? Age;
        public string Tracking;
        public string Note;
        public string Channel;
        public string Key;
    }

    public class AutoImportService
    {
        private readonly DataStore store;
        private readonly string configPath;
        private string observedStamp = "";
        public AutoImportConfig Config { get; private set; }

        public AutoImportService(DataStore dataStore)
        {
            store = dataStore;
            configPath = Path.Combine(store.DataDirectory, "auto_import_config.json");
            LoadConfig();
        }

        public void SaveConfig()
        {
            if (Config.processedRowKeys == null) Config.processedRowKeys = new List<string>();
            if (Config.processedShipmentKeys == null) Config.processedShipmentKeys = new List<string>();
            string temp = configPath + ".tmp";
            string json = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }.Serialize(Config);
            File.WriteAllText(temp, json, new UTF8Encoding(false));
            if (File.Exists(configPath)) File.Replace(temp, configPath, configPath + ".bak", true);
            else File.Move(temp, configPath);
        }

        public AutoImportResult Check(bool force)
        {
            AutoImportResult result = new AutoImportResult();
            if (!Config.enabled && !force) { result.Message = "自动导入已关闭"; return result; }
            string path = Config.filePath;
            string shipmentPath = ResolveShipmentPath();
            string snapshot = Path.Combine(store.DataDirectory, "余文乐资料_读取快照.xlsx");
            string shipmentSnapshot = Path.Combine(store.DataDirectory, "发货表_读取快照.xlsx");
            try
            {
                HashSet<string> processed = new HashSet<string>(Config.processedRowKeys ?? new List<string>(), StringComparer.OrdinalIgnoreCase);
                Dictionary<string, Customer> byPhone = store.Data.customers
                    .Where(delegate(Customer c) { return !String.IsNullOrWhiteSpace(NormalizePhone(c.phone)); })
                    .GroupBy(delegate(Customer c) { return NormalizePhone(c.phone); })
                    .ToDictionary(delegate(IGrouping<string, Customer> g) { return g.Key; }, delegate(IGrouping<string, Customer> g) { return g.First(); });

                int added = 0, completed = 0, skipped = 0;
                string batchId = Guid.NewGuid().ToString();
                string customerStamp = FileStamp(path);
                bool checkCustomers = File.Exists(path) && (force || customerStamp != Config.lastFileStamp);
                if (checkCustomers && !force && customerStamp != observedStamp)
                {
                    observedStamp = customerStamp;
                    checkCustomers = false;
                }
                if (checkCustomers)
                {
                    File.Copy(path, snapshot, true);
                    foreach (SourceCustomerRow row in XlsxCustomerReader.Read(snapshot))
                    {
                        if (processed.Contains(row.Key)) { skipped++; continue; }
                        string phone = NormalizePhone(row.Phone);
                        Customer existing;
                        if (phone.Length > 0 && byPhone.TryGetValue(phone, out existing))
                        {
                            if (CompleteEmptyFields(existing, row)) completed++; else skipped++;
                        }
                        else
                        {
                            Customer customer = new Customer
                            {
                                name = String.IsNullOrWhiteSpace(row.Name) ? "待补录" : row.Name.Trim(), phone = phone,
                                address = EmptyToNull(row.Address), age = row.Age, height = row.Height, weight = row.Weight,
                                leadAmount = row.Amount, costEnabled = true, lineCost = store.Data.settings.leadUnitPrice,
                                importBatchID = batchId, importDate = row.Date,
                                channel = String.IsNullOrWhiteSpace(row.Channel) ? null : row.Channel.Trim(), advisor = null, roiAdvisor = null
                            };
                            store.Data.customers.Add(customer);
                            if (phone.Length > 0) byPhone[phone] = customer;
                            added++;
                        }
                        processed.Add(row.Key);
                    }
                    Config.lastFileStamp = FileStamp(path);
                    observedStamp = Config.lastFileStamp;
                }

                Config.processedRowKeys = processed.ToList();
                ScanShipmentOrders(shipmentPath, shipmentSnapshot, byPhone, result, force, ref skipped);
                if (added + completed > 0)
                {
                    store.Data.batches.Add(new ImportBatch { id = batchId, source = "余文乐资料自动导入", importDate = DateTime.Now, recordCount = added + completed, fullCustomerCount = added });
                    store.Save();
                    result.Changed = true;
                }
                SaveConfig();
                result.Added = added; result.Completed = completed; result.Skipped = skipped;
                result.Success = true;
                result.Message = "检测完成：新增 " + added + "，补全 " + completed + "，待确认发货 " + result.OrderCandidates.Count + "，已存在/已处理 " + skipped;
                return result;
            }
            catch (Exception ex)
            {
                result.Message = "自动导入失败：" + ex.Message;
                return result;
            }
            finally
            {
                try { if (File.Exists(snapshot)) File.Delete(snapshot); } catch { }
                try { if (File.Exists(shipmentSnapshot)) File.Delete(shipmentSnapshot); } catch { }
            }
        }

        private void ScanShipmentOrders(string path, string snapshot, Dictionary<string, Customer> byPhone, AutoImportResult result, bool force, ref int skipped)
        {
            if (String.IsNullOrWhiteSpace(path) || !File.Exists(path)) return;
            string stamp = FileStamp(path);
            if (!force && stamp == Config.lastShipmentFileStamp) return;
            File.Copy(path, snapshot, true);
            HashSet<string> processed = new HashSet<string>(Config.processedShipmentKeys ?? new List<string>(), StringComparer.OrdinalIgnoreCase);
            List<SourceCustomerRow> shipmentRows = XlsxCustomerReader.ReadShipment(snapshot);
            if (!Config.shipmentHistoryBaselineApplied)
            {
                DateTime cutoff = DateTime.Today.AddDays(-7);
                foreach (SourceCustomerRow oldRow in shipmentRows)
                    if (oldRow.Date.Date < cutoff && !String.IsNullOrWhiteSpace(oldRow.Tracking)) processed.Add("SHIP:" + oldRow.Tracking.Trim().ToUpperInvariant());
                Config.shipmentHistoryBaselineApplied = true;
            }
            foreach (SourceCustomerRow row in shipmentRows)
            {
                if (String.IsNullOrWhiteSpace(row.Tracking)) { skipped++; continue; }
                string key = "SHIP:" + row.Tracking.Trim().ToUpperInvariant();
                if (processed.Contains(key)) { skipped++; continue; }
                Customer existing; string phone = NormalizePhone(row.Phone);
                if (phone.Length == 0 || !byPhone.TryGetValue(phone, out existing)) { skipped++; continue; }
                bool alreadyExists = existing.conversions.Any(delegate(ConversionRecord x) { return String.Equals((x.trackingNumber ?? "").Trim(), row.Tracking.Trim(), StringComparison.OrdinalIgnoreCase); });
                if (alreadyExists) { processed.Add(key); skipped++; continue; }
                result.OrderCandidates.Add(new ShipmentOrderCandidate { SourceKey = key, Customer = existing, Source = row });
            }
            Config.processedShipmentKeys = processed.ToList();
            Config.lastShipmentFileStamp = result.OrderCandidates.Count > 0 ? "" : FileStamp(path);
        }

        private string ResolveShipmentPath()
        {
            if (!String.IsNullOrWhiteSpace(Config.shipmentFilePath) && File.Exists(Config.shipmentFilePath)) return Config.shipmentFilePath;
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            string[] candidates = {
                Path.Combine(desktop, "杂项", "自动更新发货 资料录入", "发货表.xlsx"),
                Path.Combine(desktop, "自动更新发货 资料录入", "发货表.xlsx"),
                Path.Combine(desktop, "发货表.xlsx")
            };
            foreach (string candidate in candidates) if (File.Exists(candidate)) { Config.shipmentFilePath = candidate; return candidate; }
            return Config.shipmentFilePath;
        }

        private static string FileStamp(string path)
        {
            if (String.IsNullOrWhiteSpace(path) || !File.Exists(path)) return "";
            FileInfo info = new FileInfo(path); return info.LastWriteTimeUtc.Ticks + ":" + info.Length;
        }

        public void MarkProcessed(string key)
        {
            if (String.IsNullOrWhiteSpace(key)) return;
            if (key.StartsWith("SHIP:", StringComparison.OrdinalIgnoreCase))
            {
                if (!Config.processedShipmentKeys.Contains(key)) Config.processedShipmentKeys.Add(key);
            }
            else if (!Config.processedRowKeys.Contains(key)) Config.processedRowKeys.Add(key);
            SaveConfig();
        }

        private static bool CompleteEmptyFields(Customer c, SourceCustomerRow row)
        {
            bool changed = false;
            if (String.IsNullOrWhiteSpace(c.name) && !String.IsNullOrWhiteSpace(row.Name)) { c.name = row.Name.Trim(); changed = true; }
            if (String.IsNullOrWhiteSpace(c.address) && !String.IsNullOrWhiteSpace(row.Address)) { c.address = row.Address.Trim(); changed = true; }
            if (!c.height.HasValue && row.Height.HasValue) { c.height = row.Height; changed = true; }
            if (!c.weight.HasValue && row.Weight.HasValue) { c.weight = row.Weight; changed = true; }
            if (!c.age.HasValue && row.Age.HasValue) { c.age = row.Age; changed = true; }
            if (!c.leadAmount.HasValue && row.Amount.HasValue) { c.leadAmount = row.Amount; changed = true; }
            if (String.IsNullOrWhiteSpace(c.channel) && !String.IsNullOrWhiteSpace(row.Channel)) { c.channel = row.Channel.Trim(); changed = true; }
            return changed;
        }

        private void LoadConfig()
        {
            Config = new AutoImportConfig();
            if (!File.Exists(configPath)) { SaveConfig(); return; }
            try
            {
                AutoImportConfig loaded = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }.Deserialize<AutoImportConfig>(File.ReadAllText(configPath, Encoding.UTF8));
                if (loaded != null) Config = loaded;
                if (String.IsNullOrWhiteSpace(Config.filePath)) Config.filePath = new AutoImportConfig().filePath;
                if (String.IsNullOrWhiteSpace(Config.shipmentFilePath)) Config.shipmentFilePath = new AutoImportConfig().shipmentFilePath;
                if (Config.processedRowKeys == null) Config.processedRowKeys = new List<string>();
                if (Config.processedShipmentKeys == null) Config.processedShipmentKeys = new List<string>();
            }
            catch { Config = new AutoImportConfig(); }
        }

        private static string NormalizePhone(string value) { return Regex.Replace(value ?? "", @"\D", ""); }
        private static string EmptyToNull(string value) { return String.IsNullOrWhiteSpace(value) ? null : value.Trim(); }
    }

    public static class XlsxCustomerReader
    {
        private const string MainNs = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        private const string RelNs = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

        public static List<SourceCustomerRow> Read(string path)
        {
            return ReadSheet(path, new string[] { "资料录入", "订单明细" }, false);
        }

        public static List<SourceCustomerRow> ReadShipment(string path)
        {
            return ReadSheet(path, new string[] { "发货记录" }, true);
        }

        private static List<SourceCustomerRow> ReadSheet(string path, string[] sheetNames, bool shipment)
        {
            using (ZipArchive zip = ZipFile.OpenRead(path))
            {
                List<string> shared = ReadSharedStrings(zip);
                string sheetPath = null;
                foreach (string sheetName in sheetNames) { sheetPath = ResolveSheetPath(zip, sheetName); if (sheetPath != null) break; }
                if (sheetPath == null) throw new InvalidDataException("未找到工作表：" + String.Join("/", sheetNames));
                ZipArchiveEntry entry = zip.GetEntry(sheetPath);
                if (entry == null) throw new InvalidDataException("工作表内容不存在：" + sheetPath);
                XmlDocument doc = LoadXml(entry); XmlNamespaceManager ns = Ns(doc);
                XmlNodeList rowNodes = doc.SelectNodes("//m:sheetData/m:row", ns);
                Dictionary<string, int> headers = null; List<SourceCustomerRow> rows = new List<SourceCustomerRow>();
                foreach (XmlNode rowNode in rowNodes)
                {
                    Dictionary<int, string> cells = ReadRow(rowNode, ns, shared);
                    if (headers == null)
                    {
                        Dictionary<string, int> candidate = HeaderMap(cells);
                        if (candidate.ContainsKey("姓名") && candidate.ContainsKey("电话")) headers = candidate;
                        continue;
                    }
                    SourceCustomerRow row = ParseRow(cells, headers, shipment);
                    if (row != null) rows.Add(row);
                }
                if (headers == null) throw new InvalidDataException("未识别到姓名、电话表头");
                return rows;
            }
        }

        private static SourceCustomerRow ParseRow(Dictionary<int, string> cells, Dictionary<string, int> h, bool shipment)
        {
            string name = Cell(cells, h, "姓名").Trim(); string phone = Regex.Replace(Cell(cells, h, "电话"), @"\D", "");
            if (String.IsNullOrWhiteSpace(name) && String.IsNullOrWhiteSpace(phone)) return null;
            if (name.Contains("暂无资料") || name == "姓名") return null;
            string dateRaw = Cell(cells, h, "日期"); DateTime date = ParseDate(dateRaw);
            string tracking = First(cells, h, new string[] { "快递单号", "快递" }).Trim();
            SourceCustomerRow row = new SourceCustomerRow
            {
                Date = date,
                Name = name,
                Phone = phone,
                Address = Cell(cells, h, "地址").Trim(),
                Product = First(cells, h, new string[] { "产品", "产品+数量" }).Trim(),
                Amount = Number(First(cells, h, new string[] { "金额", "原表金额", "代收" })),
                Height = Number(Cell(cells, h, "身高")),
                Weight = Number(Cell(cells, h, "体重")),
                Age = Integer(Cell(cells, h, "年龄")),
                Tracking = tracking,
                Note = Cell(cells, h, "备注").Trim(),
                Channel = Cell(cells, h, "渠道").Trim()
            };
            string identity = tracking.Length > 0 ? (shipment ? "SHIP:" : "SF:") + tracking.ToUpperInvariant() : "ROW:" + phone + "|" + date.ToString("yyyy-MM-dd") + "|" + name + "|" + row.Address;
            row.Key = identity;
            return row;
        }

        private static string ResolveSheetPath(ZipArchive zip, string wantedName)
        {
            ZipArchiveEntry workbook = zip.GetEntry("xl/workbook.xml"); ZipArchiveEntry rels = zip.GetEntry("xl/_rels/workbook.xml.rels");
            if (workbook == null || rels == null) return null;
            XmlDocument wb = LoadXml(workbook); XmlNamespaceManager ns = Ns(wb);
            XmlNode chosen = null;
            foreach (XmlNode sheet in wb.SelectNodes("//m:sheets/m:sheet", ns))
            {
                string name = Attr(sheet, "name"); if (name == wantedName) { chosen = sheet; break; }
            }
            if (chosen == null) return null;
            string id = AttrNs(chosen, "id", RelNs); XmlDocument rd = LoadXml(rels);
            foreach (XmlNode rel in rd.DocumentElement.ChildNodes)
                if (Attr(rel, "Id") == id)
                {
                    string target = Attr(rel, "Target").Replace('\\', '/').TrimStart('/');
                    while (target.StartsWith("../")) target = target.Substring(3);
                    return target.StartsWith("xl/") ? target : "xl/" + target;
                }
            return null;
        }

        private static List<string> ReadSharedStrings(ZipArchive zip)
        {
            List<string> result = new List<string>(); ZipArchiveEntry entry = zip.GetEntry("xl/sharedStrings.xml"); if (entry == null) return result;
            XmlDocument doc = LoadXml(entry); XmlNamespaceManager ns = Ns(doc);
            foreach (XmlNode si in doc.SelectNodes("//m:si", ns))
            {
                StringBuilder text = new StringBuilder(); foreach (XmlNode t in si.SelectNodes(".//m:t", ns)) text.Append(t.InnerText); result.Add(text.ToString());
            }
            return result;
        }

        private static Dictionary<int, string> ReadRow(XmlNode row, XmlNamespaceManager ns, List<string> shared)
        {
            Dictionary<int, string> result = new Dictionary<int, string>();
            foreach (XmlNode c in row.SelectNodes("m:c", ns))
            {
                int index = ColumnIndex(Attr(c, "r")); string type = Attr(c, "t"); string value = "";
                XmlNode v = c.SelectSingleNode("m:v", ns);
                if (type == "inlineStr") { XmlNode t = c.SelectSingleNode("m:is/m:t", ns); if (t != null) value = t.InnerText; }
                else if (v != null && type == "s") { int i; if (Int32.TryParse(v.InnerText, out i) && i >= 0 && i < shared.Count) value = shared[i]; }
                else if (v != null) value = v.InnerText;
                result[index] = value;
            }
            return result;
        }

        private static Dictionary<string, int> HeaderMap(Dictionary<int, string> cells)
        {
            Dictionary<string, int> map = new Dictionary<string, int>();
            foreach (KeyValuePair<int, string> pair in cells)
            {
                string key = (pair.Value ?? "").Replace(" ", "").Replace("\r", "").Replace("\n", "");
                if (key.Length > 0 && !map.ContainsKey(key)) map[key] = pair.Key;
            }
            return map;
        }

        private static DateTime ParseDate(string raw)
        {
            string value = (raw ?? "").Trim(); double serial;
            if (Double.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out serial) && serial > 20000) return DateTime.FromOADate(serial).Date;
            Match chinese = Regex.Match(value, @"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日?");
            if (chinese.Success)
            {
                int year = chinese.Groups[1].Success ? Int32.Parse(chinese.Groups[1].Value) : DateTime.Now.Year;
                return new DateTime(year, Int32.Parse(chinese.Groups[2].Value), Int32.Parse(chinese.Groups[3].Value));
            }
            value = value.Replace('.', '/').Replace('-', '/'); DateTime date;
            if (DateTime.TryParse(value, CultureInfo.GetCultureInfo("zh-CN"), DateTimeStyles.None, out date))
            {
                if (!Regex.IsMatch(value, @"\d{4}")) date = new DateTime(DateTime.Now.Year, date.Month, date.Day);
                return date.Date;
            }
            return DateTime.Today;
        }

        private static double? Number(string value) { double n; return Double.TryParse((value ?? "").Replace(",", "").Trim(), NumberStyles.Any, CultureInfo.InvariantCulture, out n) ? (double?)n : null; }
        private static int? Integer(string value) { double? n = Number(value); return n.HasValue ? (int?)Convert.ToInt32(n.Value) : null; }
        private static string First(Dictionary<int, string> cells, Dictionary<string, int> h, string[] names) { foreach (string name in names) { string v = Cell(cells, h, name); if (v.Length > 0) return v; } return ""; }
        private static string Cell(Dictionary<int, string> cells, Dictionary<string, int> h, string name) { int i; string v; return h.TryGetValue(name, out i) && cells.TryGetValue(i, out v) ? (v ?? "") : ""; }
        private static int ColumnIndex(string reference) { int value = 0; foreach (char c in reference) { if (!Char.IsLetter(c)) break; value = value * 26 + (Char.ToUpperInvariant(c) - 'A' + 1); } return Math.Max(0, value - 1); }
        private static XmlDocument LoadXml(ZipArchiveEntry entry) { XmlDocument doc = new XmlDocument(); using (Stream stream = entry.Open()) doc.Load(stream); return doc; }
        private static XmlNamespaceManager Ns(XmlDocument doc) { XmlNamespaceManager ns = new XmlNamespaceManager(doc.NameTable); ns.AddNamespace("m", MainNs); return ns; }
        private static string Attr(XmlNode node, string name) { XmlAttribute a = node.Attributes[name]; return a == null ? "" : a.Value; }
        private static string AttrNs(XmlNode node, string name, string ns) { XmlAttribute a = node.Attributes[name, ns]; return a == null ? "" : a.Value; }
    }
}
