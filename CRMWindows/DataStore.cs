using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace CRMWindows
{
    public class DataStore
    {
        public AppData Data { get; private set; }
        public string DataDirectory { get; private set; }
        public string DataFile { get { return Path.Combine(DataDirectory, "crm_data.json"); } }
        public string DisguiseDataFile { get { return Path.Combine(DataDirectory, "crm_disguise_data.json"); } }
        public bool IsDisguiseActive { get; private set; }
        private AppData realData;

        public DataStore(string dataDirectory = null)
        {
            DataDirectory = String.IsNullOrWhiteSpace(dataDirectory) ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PrivateCRMWindows") : dataDirectory;
            Directory.CreateDirectory(DataDirectory);
            Data = new AppData();
            Load();
        }

        public void Load()
        {
            if (!File.Exists(DataFile)) return;
            try
            {
                Data = JsonCompat.Read(File.ReadAllText(DataFile, Encoding.UTF8)); Normalize(); realData = Data;
                if (realData.settings.demoEnabled && File.Exists(DisguiseDataFile))
                {
                    Data = JsonCompat.Read(File.ReadAllText(DisguiseDataFile, Encoding.UTF8)); Normalize();
                    Data.settings.demoEnabled = true; IsDisguiseActive = true;
                }
                else
                {
                    IsDisguiseActive = false;
                    if (realData.settings.demoEnabled) { realData.settings.demoEnabled = false; Data = realData; WriteDataFile(DataFile, realData); }
                }
            }
            catch (Exception ex)
            {
                string broken = Path.Combine(DataDirectory, "读取失败_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".json");
                File.Copy(DataFile, broken, true);
                throw new InvalidDataException("数据文件读取失败，原文件已保留：" + broken, ex);
            }
        }

        public void Save()
        {
            Normalize(); Data.exportDate = DateTime.Now;
            WriteDataFile(IsDisguiseActive ? DisguiseDataFile : DataFile, Data);
            if (!IsDisguiseActive) realData = Data;
        }

        private static void WriteDataFile(string path, AppData data)
        {
            string json = JsonCompat.Write(data);
            string temp = path + ".tmp";
            File.WriteAllText(temp, json, new UTF8Encoding(false));
            if (File.Exists(path))
            {
                string backup = path + ".bak";
                File.Replace(temp, path, backup, true);
            }
            else File.Move(temp, path);
        }

        public void ExportPlain(string path) { Save(); File.Copy(DataFile, path, true); }

        public void EnableDisguise()
        {
            if (IsDisguiseActive) return;
            Save(); realData = Data; realData.settings.demoEnabled = true; WriteDataFile(DataFile, realData);
            Data = JsonCompat.Read(JsonCompat.Write(realData)); Data.settings.demoEnabled = true;
            IsDisguiseActive = true; Normalize(); WriteDataFile(DisguiseDataFile, Data);
        }

        public void DisableDisguise()
        {
            if (!IsDisguiseActive) return;
            Save(); realData.settings.demoEnabled = false; Data = realData; IsDisguiseActive = false; Save();
        }

        public void ImportPlain(string path)
        {
            if (IsDisguiseActive) throw new InvalidOperationException("请先解除全局伪装，再导入真实数据备份。 ");
            AppData imported = JsonCompat.Read(File.ReadAllText(path, Encoding.UTF8));
            if (imported == null || imported.customers == null) throw new InvalidDataException("不是有效的 CRM JSON 备份");
            string safety = Path.Combine(DataDirectory, "导入前自动备份_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".json");
            if (File.Exists(DataFile)) File.Copy(DataFile, safety, true);
            Data = imported; Normalize(); Save();
        }

        public void Normalize()
        {
            if (Data == null) Data = new AppData();
            if (Data.customers == null) Data.customers = new List<Customer>();
            if (Data.batches == null) Data.batches = new List<ImportBatch>();
            if (Data.settings == null) Data.settings = new AppSettings();
            if (Data.settings.advisors == null) Data.settings.advisors = new List<string>();
            if (Data.settings.advisorGroups == null) Data.settings.advisorGroups = new List<string>();
            if (Data.settings.advisorProfiles == null) Data.settings.advisorProfiles = new List<AdvisorProfile>();
            if (Data.settings.dismissedPendingSecondCustomerIDs == null) Data.settings.dismissedPendingSecondCustomerIDs = new List<string>();
            if (Data.settings.hiddenMetrics == null) Data.settings.hiddenMetrics = new List<string>();
            if (Data.settings.inactiveAdvisors == null) Data.settings.inactiveAdvisors = new List<string>();
            foreach (Customer c in Data.customers)
            {
                if (String.IsNullOrEmpty(c.id)) c.id = Guid.NewGuid().ToString();
                if (String.IsNullOrEmpty(c.dataType)) c.dataType = "fullCustomer";
                if (c.tags == null) c.tags = new List<string>();
                if (c.conversions == null) c.conversions = new List<ConversionRecord>();
                if (c.lineCost <= 0) c.lineCost = Data.settings.leadUnitPrice > 0 ? Data.settings.leadUnitPrice : 1200;
                foreach (ConversionRecord r in c.conversions)
                {
                    if (String.IsNullOrEmpty(r.id)) r.id = Guid.NewGuid().ToString();
                    if (r.advisorSplits == null) r.advisorSplits = new List<AdvisorSplit>();
                }
            }
            foreach (string name in Data.settings.advisors)
            {
                if (!Data.settings.advisorProfiles.Exists(delegate(AdvisorProfile p) { return p.name == name; }))
                    Data.settings.advisorProfiles.Add(new AdvisorProfile { name = name, role = "组员", groupName = "" });
            }
        }

        public Customer FindCustomer(string number, string name)
        {
            if (!String.IsNullOrWhiteSpace(number))
            {
                List<Customer> numbered = Data.customers.FindAll(delegate(Customer c) { return c.customerNumber == number; });
                if (numbered.Count == 1) return numbered[0];
                if (numbered.Count > 1 && !String.IsNullOrWhiteSpace(name))
                {
                    List<Customer> exact = numbered.FindAll(delegate(Customer c) { return c.name == name; });
                    return exact.Count == 1 ? exact[0] : null;
                }
                return null;
            }
            List<Customer> matches = Data.customers.FindAll(delegate(Customer c) { return c.name == name; });
            return matches.Count == 1 ? matches[0] : null;
        }

        public int CustomerNumberMatchCount(string number)
        {
            if (String.IsNullOrWhiteSpace(number)) return 0;
            return Data.customers.FindAll(delegate(Customer c) { return c.customerNumber == number; }).Count;
        }

        public List<string> ActiveAdvisorNames()
        {
            HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            Action<string> add = delegate(string raw)
            {
                string name = (raw ?? "").Trim();
                if (name.Length == 0 || Data.settings.inactiveAdvisors.Exists(delegate(string inactive) { return String.Equals((inactive ?? "").Trim(), name, StringComparison.OrdinalIgnoreCase); })) return;
                names.Add(name);
            };
            foreach (string name in Data.settings.advisors) add(name);
            foreach (AdvisorProfile profile in Data.settings.advisorProfiles) add(profile.name);
            foreach (Customer customer in Data.customers)
            {
                add(customer.advisor);
                foreach (ConversionRecord record in customer.conversions)
                    foreach (AdvisorSplit split in record.advisorSplits) add(split.name);
            }
            List<string> result = new List<string>(names);
            result.Sort(StringComparer.CurrentCultureIgnoreCase);
            return result;
        }

        public void RenameAdvisor(string oldName, string newName)
        {
            oldName = (oldName ?? "").Trim(); newName = (newName ?? "").Trim();
            if (oldName.Length == 0 || newName.Length == 0 || oldName == newName) return;
            foreach (Customer c in Data.customers)
            {
                if (c.advisor == oldName) c.advisor = newName;
                if (c.roiAdvisor == oldName) c.roiAdvisor = newName;
                foreach (ConversionRecord r in c.conversions)
                    foreach (AdvisorSplit split in r.advisorSplits)
                        if (split.name == oldName) split.name = newName;
            }
            for (int i = 0; i < Data.settings.advisors.Count; i++)
                if (Data.settings.advisors[i] == oldName) Data.settings.advisors[i] = newName;
            foreach (AdvisorProfile p in Data.settings.advisorProfiles)
                if (p.name == oldName) p.name = newName;
            Data.settings.inactiveAdvisors.RemoveAll(delegate(string n) { return n == oldName || n == newName; });
        }

        public void DeleteAdvisor(string name)
        {
            foreach (Customer c in Data.customers)
            {
                if (c.advisor == name)
                {
                    foreach (ConversionRecord r in c.conversions)
                        if (r.advisorSplits.Count == 0) r.advisorSplits.Add(new AdvisorSplit { name = name, ratio = 1 });
                    c.advisor = null;
                    if (c.RoiAdvisorName == name) c.roiAdvisor = "";
                }
            }
            Data.settings.advisors.RemoveAll(delegate(string a) { return a == name; });
            Data.settings.advisorProfiles.RemoveAll(delegate(AdvisorProfile p) { return p.name == name; });
            if (!Data.settings.inactiveAdvisors.Contains(name)) Data.settings.inactiveAdvisors.Add(name);
            Save();
        }
    }

    public static class JsonCompat
    {
        private static JavaScriptSerializer Serializer()
        {
            JavaScriptSerializer s = new JavaScriptSerializer(); s.MaxJsonLength = Int32.MaxValue; s.RecursionLimit = 256; return s;
        }

        public static AppData Read(string json)
        {
            object rootObject = Serializer().DeserializeObject(json);
            Dictionary<string, object> root = AsDict(rootObject);
            if (root == null) throw new InvalidDataException("JSON 根节点格式错误");
            AppData data = new AppData();
            data.version = Int(root, "version", 1);
            data.exportDate = Date(root, "exportDate", DateTime.Now);
            object customers; if (root.TryGetValue("customers", out customers))
                foreach (object item in AsList(customers)) { Dictionary<string, object> d = AsDict(item); if (d != null) data.customers.Add(ReadCustomer(d)); }
            object batches; if (root.TryGetValue("batches", out batches))
                foreach (object item in AsList(batches)) { Dictionary<string, object> d = AsDict(item); if (d != null) data.batches.Add(ReadBatch(d)); }
            object settings; if (root.TryGetValue("settings", out settings) && AsDict(settings) != null) data.settings = ReadSettings(AsDict(settings));
            return data;
        }

        private static Customer ReadCustomer(Dictionary<string, object> d)
        {
            Customer c = new Customer();
            c.id = Str(d, "id", c.id); c.dataType = Str(d, "dataType", "fullCustomer");
            c.name = Str(d, "name", ""); c.phone = Str(d, "phone", ""); c.address = NullableStr(d, "address");
            c.age = NullableInt(d, "age"); c.height = NullableDouble(d, "height"); c.weight = NullableDouble(d, "weight");
            c.gender = Str(d, "gender", "未知"); c.customerNumber = NullableStr(d, "customerNumber");
            c.costEnabled = Bool(d, "costEnabled", false); c.leadAmount = NullableDouble(d, "leadAmount");
            c.lineCost = Double(d, "lineCost", 1200); c.importBatchID = NullableStr(d, "importBatchID");
            c.importDate = Date(d, "importDate", DateTime.Now); c.followUpTag = NullableStr(d, "followUpTag");
            c.channel = NullableStr(d, "channel"); c.advisor = NullableStr(d, "advisor"); c.roiAdvisor = NullableStrPreserve(d, "roiAdvisor");
            object tags; if (d.TryGetValue("tags", out tags)) foreach (object v in AsList(tags)) if (v != null) c.tags.Add(v.ToString());
            object conversions; if (d.TryGetValue("conversions", out conversions))
                foreach (object item in AsList(conversions)) { Dictionary<string, object> r = AsDict(item); if (r != null) c.conversions.Add(ReadConversion(r)); }
            return c;
        }

        private static ConversionRecord ReadConversion(Dictionary<string, object> d)
        {
            ConversionRecord r = new ConversionRecord();
            r.id = Str(d, "id", r.id); r.type = Str(d, "type", "未知"); r.amount = Double(d, "amount", 0);
            r.date = Date(d, "date", DateTime.Now); r.productNote = NullableStr(d, "productNote"); r.note = NullableStr(d, "note");
            r.trackingNumber = NullableStr(d, "trackingNumber");
            r.isVoided = Bool(d, "isVoided", false);
            object splits; if (d.TryGetValue("advisorSplits", out splits)) foreach (object item in AsList(splits))
            {
                Dictionary<string, object> s = AsDict(item); if (s != null) r.advisorSplits.Add(new AdvisorSplit { name = Str(s, "name", ""), ratio = Double(s, "ratio", 1) });
            }
            return r;
        }

        private static ImportBatch ReadBatch(Dictionary<string, object> d)
        {
            return new ImportBatch { id = Str(d, "id", Guid.NewGuid().ToString()), source = Str(d, "source", "导入"), importDate = Date(d, "importDate", DateTime.Now), recordCount = Int(d, "recordCount", 0), fullCustomerCount = Int(d, "fullCustomerCount", 0) };
        }

        private static AppSettings ReadSettings(Dictionary<string, object> d)
        {
            AppSettings s = new AppSettings();
            s.leadUnitPrice = Double(d, "leadUnitPrice", 1200); s.biometricLockEnabled = Bool(d, "biometricLockEnabled", false);
            s.appPINEnabled = Bool(d, "appPINEnabled", false); s.appPIN = Str(d, "appPIN", "");
            s.channelRevenueVisible = Bool(d, "channelRevenueVisible", true); s.demoEnabled = Bool(d, "demoEnabled", false);
            object v;
            if (d.TryGetValue("advisors", out v)) { s.advisors.Clear(); foreach (object x in AsList(v)) if (x != null) s.advisors.Add(x.ToString()); }
            if (d.TryGetValue("advisorGroups", out v)) { s.advisorGroups.Clear(); foreach (object x in AsList(v)) if (x != null) s.advisorGroups.Add(x.ToString()); }
            if (d.TryGetValue("advisorProfiles", out v)) { s.advisorProfiles.Clear(); foreach (object x in AsList(v)) { Dictionary<string, object> p = AsDict(x); if (p != null) s.advisorProfiles.Add(new AdvisorProfile { name = Str(p, "name", ""), role = Str(p, "role", "组员"), groupName = Str(p, "groupName", "") }); } }
            if (d.TryGetValue("dismissedPendingSecondCustomerIDs", out v)) { s.dismissedPendingSecondCustomerIDs.Clear(); foreach (object x in AsList(v)) if (x != null) s.dismissedPendingSecondCustomerIDs.Add(x.ToString()); }
            if (d.TryGetValue("hiddenMetrics", out v)) { s.hiddenMetrics.Clear(); foreach (object x in AsList(v)) if (x != null) s.hiddenMetrics.Add(x.ToString()); }
            if (d.TryGetValue("inactiveAdvisors", out v)) { s.inactiveAdvisors.Clear(); foreach (object x in AsList(v)) if (x != null) s.inactiveAdvisors.Add(x.ToString()); }
            return s;
        }

        public static string Write(AppData data)
        {
            Dictionary<string, object> root = new Dictionary<string, object>();
            root["version"] = data.version; root["exportDate"] = Iso(data.exportDate);
            List<object> customers = new List<object>(); foreach (Customer c in data.customers) customers.Add(WriteCustomer(c)); root["customers"] = customers;
            List<object> batches = new List<object>(); foreach (ImportBatch b in data.batches) batches.Add(new Dictionary<string, object> { { "id", b.id }, { "source", b.source }, { "importDate", Iso(b.importDate) }, { "recordCount", b.recordCount }, { "fullCustomerCount", b.fullCustomerCount } }); root["batches"] = batches;
            root["settings"] = WriteSettings(data.settings);
            return Serializer().Serialize(root);
        }

        private static Dictionary<string, object> WriteCustomer(Customer c)
        {
            Dictionary<string, object> d = new Dictionary<string, object>();
            d["id"] = c.id; d["dataType"] = c.dataType; d["name"] = c.name; d["phone"] = c.phone; d["address"] = c.address;
            d["age"] = c.age; d["height"] = c.height; d["weight"] = c.weight; d["gender"] = c.gender; d["customerNumber"] = c.customerNumber;
            d["costEnabled"] = c.costEnabled; d["leadAmount"] = c.leadAmount; d["lineCost"] = c.lineCost; d["importBatchID"] = c.importBatchID;
            d["importDate"] = Iso(c.importDate); d["tags"] = c.tags; d["followUpTag"] = c.followUpTag; d["channel"] = c.channel; d["advisor"] = c.advisor; d["roiAdvisor"] = c.roiAdvisor;
            List<object> conversions = new List<object>(); foreach (ConversionRecord r in c.conversions)
            {
                List<object> splits = new List<object>(); foreach (AdvisorSplit s in r.advisorSplits) splits.Add(new Dictionary<string, object> { { "name", s.name }, { "ratio", s.ratio } });
                conversions.Add(new Dictionary<string, object> { { "id", r.id }, { "type", r.type }, { "amount", r.amount }, { "date", Iso(r.date) }, { "productNote", r.productNote }, { "note", r.note }, { "trackingNumber", r.trackingNumber }, { "advisorSplits", splits }, { "isVoided", r.isVoided } });
            }
            d["conversions"] = conversions; return d;
        }

        private static Dictionary<string, object> WriteSettings(AppSettings s)
        {
            List<object> profiles = new List<object>(); foreach (AdvisorProfile p in s.advisorProfiles) profiles.Add(new Dictionary<string, object> { { "name", p.name }, { "role", p.role }, { "groupName", p.groupName } });
            return new Dictionary<string, object> { { "leadUnitPrice", s.leadUnitPrice }, { "biometricLockEnabled", s.biometricLockEnabled }, { "appPINEnabled", s.appPINEnabled }, { "appPIN", s.appPIN }, { "advisors", s.advisors }, { "advisorGroups", s.advisorGroups }, { "advisorProfiles", profiles }, { "dismissedPendingSecondCustomerIDs", s.dismissedPendingSecondCustomerIDs }, { "channelRevenueVisible", s.channelRevenueVisible }, { "demoEnabled", s.demoEnabled }, { "hiddenMetrics", s.hiddenMetrics }, { "inactiveAdvisors", s.inactiveAdvisors } };
        }

        private static Dictionary<string, object> AsDict(object value) { return value as Dictionary<string, object>; }
        private static List<object> AsList(object value)
        {
            List<object> result = new List<object>(); IEnumerable e = value as IEnumerable; if (e == null || value is string) return result;
            foreach (object x in e) result.Add(x); return result;
        }
        private static string Str(Dictionary<string, object> d, string k, string f) { object v; return d.TryGetValue(k, out v) && v != null ? v.ToString() : f; }
        private static string NullableStr(Dictionary<string, object> d, string k) { object v; if (!d.TryGetValue(k, out v) || v == null) return null; string s = v.ToString(); return String.IsNullOrWhiteSpace(s) ? null : s; }
        private static string NullableStrPreserve(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v != null ? v.ToString() : null; }
        private static bool Bool(Dictionary<string, object> d, string k, bool f) { object v; if (!d.TryGetValue(k, out v) || v == null) return f; bool b; return Boolean.TryParse(v.ToString(), out b) ? b : f; }
        private static int Int(Dictionary<string, object> d, string k, int f) { object v; if (!d.TryGetValue(k, out v) || v == null) return f; int x; return Int32.TryParse(v.ToString(), out x) ? x : f; }
        private static int? NullableInt(Dictionary<string, object> d, string k) { object v; if (!d.TryGetValue(k, out v) || v == null) return null; int x; return Int32.TryParse(v.ToString(), out x) ? (int?)x : null; }
        private static double Double(Dictionary<string, object> d, string k, double f) { object v; if (!d.TryGetValue(k, out v) || v == null) return f; double x; return System.Double.TryParse(v.ToString(), NumberStyles.Any, CultureInfo.InvariantCulture, out x) ? x : f; }
        private static double? NullableDouble(Dictionary<string, object> d, string k) { object v; if (!d.TryGetValue(k, out v) || v == null) return null; double x; return System.Double.TryParse(v.ToString(), NumberStyles.Any, CultureInfo.InvariantCulture, out x) ? (double?)x : null; }
        private static DateTime Date(Dictionary<string, object> d, string k, DateTime f) { object v; if (!d.TryGetValue(k, out v) || v == null) return f; return ParseDate(v, f); }
        private static DateTime ParseDate(object value, DateTime f)
        {
            DateTime dt; string s = value.ToString();
            if (DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out dt)) return dt.ToLocalTime();
            double n; if (System.Double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out n)) return new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(n).ToLocalTime();
            return f;
        }
        private static string Iso(DateTime dt) { return dt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture); }
    }
}
