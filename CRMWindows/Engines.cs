using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace CRMWindows
{
    public static class SmartPasteParser
    {
        private static readonly string[] Channels = { "小红书", "直播", "食谱", "问答", "抖音", "视频号", "朋友圈" };
        private static readonly Regex Phone = new Regex(@"(?<!\d)(1\d{10})(?!\d)", RegexOptions.Compiled);
        private static readonly Regex Bio = new Regex(@"(身高|体重|年龄)\s*[:：]?\s*(\d{1,3}(?:\.\d+)?)", RegexOptions.Compiled);
        private static readonly Regex Sf = new Regex(@"\bSF\d{8,18}\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public static List<ParsedCustomer> Parse(string text)
        {
            List<ParsedCustomer> result = new List<ParsedCustomer>();
            string[] lines = text.Replace("\r", "").Split(new char[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string rawLine in lines)
            {
                string line = rawLine.Trim(); if (line.Length == 0) continue;
                ParsedCustomer row = line.Contains("\t") ? ParseColumns(line) : ParseFlexible(line);
                row.Raw = line; row.NeedsReview = String.IsNullOrWhiteSpace(row.Name) || String.IsNullOrWhiteSpace(row.Phone) || !row.Height.HasValue || !row.Weight.HasValue || !row.Age.HasValue || String.IsNullOrWhiteSpace(row.Channel);
                result.Add(row);
            }
            return result;
        }

        private static ParsedCustomer ParseColumns(string line)
        {
            string[] c = line.Split('\t'); ParsedCustomer r = new ParsedCustomer();
            int offset = LooksLikeDate(c.Length > 0 ? c[0] : "") ? 1 : 0;
            if (offset == 1) r.ImportDate = ParseShortDate(c[0]);
            if (c.Length > offset) r.Name = c[offset].Trim();
            if (c.Length > offset + 1) r.Phone = Digits(c[offset + 1]);
            if (c.Length > offset + 2) r.Address = c[offset + 2].Trim();
            if (c.Length > offset + 3) r.Product = c[offset + 3].Trim();
            double d;
            if (c.Length > offset + 4 && TryNumber(c[offset + 4], out d)) r.LeadAmount = d;
            if (c.Length > offset + 5 && TryNumber(c[offset + 5], out d)) r.Height = d;
            if (c.Length > offset + 6 && TryNumber(c[offset + 6], out d)) r.Weight = d;
            int age; if (c.Length > offset + 7 && Int32.TryParse(Digits(c[offset + 7]), out age)) r.Age = age;
            if (c.Length > offset + 8) r.CustomerNumber = c[offset + 8].Trim();
            if (c.Length > offset + 9) r.Note = c[offset + 9].Trim();
            if (c.Length > offset + 10) r.Channel = DetectChannel(c[offset + 10]); else r.Channel = DetectChannel(line);
            return r;
        }

        private static ParsedCustomer ParseFlexible(string line)
        {
            ParsedCustomer r = new ParsedCustomer(); Match phone = Phone.Match(line);
            if (phone.Success)
            {
                r.Phone = phone.Groups[1].Value;
                string before = line.Substring(0, phone.Index).Trim(); string[] names = before.Split(new char[] { ' ', '，', ',' }, StringSplitOptions.RemoveEmptyEntries);
                if (names.Length > 0) r.Name = names[names.Length - 1];
                string after = line.Substring(phone.Index + phone.Length).Trim();
                int stop = after.Length;
                string[] markers = { "身高", "体重", "年龄", "SF", "植物茶", "脂肪粉", "草本膏", "中草饮", "产品", "金额", "线索", "食谱", "直播", "小红书", "问答", "抖音", "视频号", "朋友圈" };
                foreach (string m in markers) { int i = after.IndexOf(m, StringComparison.OrdinalIgnoreCase); if (i >= 0 && i < stop) stop = i; }
                r.Address = after.Substring(0, stop).Trim();
            }
            foreach (Match m in Bio.Matches(line))
            {
                double value; if (!TryNumber(m.Groups[2].Value, out value)) continue;
                if (m.Groups[1].Value == "身高") r.Height = value;
                else if (m.Groups[1].Value == "体重") r.Weight = value;
                else r.Age = (int)value;
            }
            Match sf = Sf.Match(line); if (sf.Success) r.CustomerNumber = sf.Value;
            r.Channel = DetectChannel(line);
            Match amount = Regex.Match(line, @"(?:线索金额|金额|线索)\s*[:：]?\s*[¥￥]?\s*(\d{2,6}(?:\.\d+)?)"); double a;
            if (amount.Success && TryNumber(amount.Groups[1].Value, out a)) r.LeadAmount = a;
            else r.LeadAmount = ExtractProductAmount(line);
            return r;
        }

        public static string DetectChannel(string text)
        {
            foreach (string channel in Channels) if (text.IndexOf(channel, StringComparison.OrdinalIgnoreCase) >= 0) return channel;
            return null;
        }
        private static double? ExtractProductAmount(string text)
        {
            string[] products = { "植物茶", "脂肪粉", "草本膏", "中草饮" };
            int start = -1;
            foreach (string product in products)
            {
                int index = text.IndexOf(product, StringComparison.OrdinalIgnoreCase);
                if (index >= 0 && (start < 0 || index < start)) start = index;
            }
            if (start < 0) return null;
            int end = text.Length;
            string[] stops = { "身高", "体重", "年龄", "SF", "食谱", "直播", "小红书", "问答", "抖音", "视频号", "朋友圈" };
            foreach (string stop in stops)
            {
                int index = text.IndexOf(stop, start, StringComparison.OrdinalIgnoreCase);
                if (index >= 0 && index < end) end = index;
            }
            string section = text.Substring(start, Math.Max(0, end - start));
            MatchCollection candidates = Regex.Matches(section, @"(?<![\p{L}\d])(\d{3,6}(?:\.\d+)?)(?!\d)");
            if (candidates.Count == 0) return null;
            double value;
            return TryNumber(candidates[candidates.Count - 1].Groups[1].Value, out value) ? (double?)value : null;
        }
        private static bool LooksLikeDate(string s) { return Regex.IsMatch(s.Trim(), @"^(?:\d{4}[-/.])?\d{1,2}[-/.]\d{1,2}$"); }
        private static DateTime ParseShortDate(string s)
        {
            s = s.Trim().Replace('.', '/').Replace('-', '/'); DateTime d;
            if (DateTime.TryParse(s, out d)) return d;
            if (DateTime.TryParse(DateTime.Now.Year + "/" + s, out d)) return d;
            return DateTime.Now;
        }
        private static string Digits(string s) { return Regex.Replace(s ?? "", @"\D", ""); }
        private static bool TryNumber(string s, out double value) { return Double.TryParse((s ?? "").Replace(",", "").Trim(), NumberStyles.Any, CultureInfo.InvariantCulture, out value); }
    }

    public static class LedgerParser
    {
        private static readonly string Types = "新单|首单|二次|三次|四次|五次|六次|七次|八次|复购|一次|多次|后续|后续开发|续单|续购|后续单";
        private static readonly Regex NumberPattern = new Regex(@"(?<id>\d{3,6})\s*(?<type>" + Types + @")\s*(?<amount>\d[\d,，.]*)", RegexOptions.Compiled);
        private static readonly Regex NamePattern = new Regex(@"(?<name>[^\s\d,，。、\r\n]{1,10})\s*(?<type>" + Types + @")\s*(?<amount>\d[\d,，.]*)", RegexOptions.Compiled);

        public static List<LedgerItem> Parse(string text)
        {
            string normalized = text.Replace('，', ' ').Replace('、', ' ').Replace('\t', ' '); List<LedgerItem> result = new List<LedgerItem>();
            MatchCollection numbers = NumberPattern.Matches(normalized);
            if (numbers.Count > 0) foreach (Match m in numbers) result.Add(Make(m.Groups["id"].Value, null, m.Groups["type"].Value, m.Groups["amount"].Value));
            else foreach (Match m in NamePattern.Matches(normalized)) result.Add(Make(null, m.Groups["name"].Value, m.Groups["type"].Value, m.Groups["amount"].Value));
            return result;
        }
        private static LedgerItem Make(string number, string name, string type, string amount)
        {
            double value; Double.TryParse(amount.Replace(",", "").Replace("，", ""), out value);
            return new LedgerItem { CustomerNumber = number, Name = name ?? ("编号" + number), Type = Resolve(type), Amount = value, Date = DateTime.Now };
        }
        private static string Resolve(string s)
        {
            if (s.Contains("二") || s == "2次" || s == "复购") return "二次";
            if (s.Contains("三") || s == "3次") return "三次"; if (s.Contains("四") || s == "4次") return "四次";
            if (s.Contains("五") || s == "5次") return "五次"; if (s.Contains("六") || s == "6次") return "六次";
            if (s.Contains("七") || s == "7次") return "七次"; if (s.Contains("八") || s == "8次") return "八次";
            if (s.Contains("多") || s.Contains("后续") || s.Contains("续")) return "多次"; return "新单";
        }
    }

    public class PeriodStats
    {
        public int Leads; public double Cost; public double FunnelRevenue; public double OtherRevenue;
        public int NewCustomers; public double NewAmount; public int SecondOrders; public double SecondAmount;
        public double Revenue { get { return FunnelRevenue + OtherRevenue; } }
        public double Roi { get { return Cost > 0 ? FunnelRevenue / Cost : 0; } }
    }

    public class ChannelStat { public string Channel; public int Leads; public int NewOrders; public int Seconds; public double Revenue; }
    public class AdvisorStat { public string Name; public bool IsInactive; public int Leads; public int NewOrders; public int Seconds; public int Pending; public double Revenue; public double Cost; public double Roi { get { return Cost > 0 ? Revenue / Cost : 0; } } }

    public static class StatisticsEngine
    {
        public static bool InMonth(DateTime d, int year, int month) { return d.Year == year && d.Month == month; }
        public static PeriodStats Summary(List<Customer> customers, bool monthly, int year, int month)
        {
            PeriodStats s = new PeriodStats();
            foreach (Customer c in customers)
            {
                bool leadInPeriod = !monthly || InMonth(c.importDate, year, month);
                bool funnel = c.dataType == "fullCustomer" && c.costEnabled && c.followUpTag != "已失去价值";
                if (funnel && leadInPeriod) { s.Leads++; s.Cost += c.lineCost; }
                bool hasNew = false;
                foreach (ConversionRecord r in c.ValidConversions)
                {
                    if (monthly && !InMonth(r.date, year, month)) continue;
                    if (funnel) s.FunnelRevenue += r.amount; else s.OtherRevenue += r.amount;
                    if (r.type == "新单") { hasNew = true; s.NewAmount += r.amount; }
                    if (r.type == "二次") { s.SecondOrders++; s.SecondAmount += r.amount; }
                }
                if (funnel && leadInPeriod && hasNew) s.NewCustomers++;
            }
            return s;
        }

        public static List<ChannelStat> Channels(List<Customer> customers, bool monthly, int year, int month)
        {
            Dictionary<string, ChannelStat> map = new Dictionary<string, ChannelStat>();
            foreach (Customer c in customers.Where(delegate(Customer x) { return x.dataType == "fullCustomer" && x.costEnabled; }))
            {
                ChannelStat s; if (!map.TryGetValue(c.ChannelDisplay, out s)) { s = new ChannelStat { Channel = c.ChannelDisplay }; map[c.ChannelDisplay] = s; }
                if (!monthly || InMonth(c.importDate, year, month))
                {
                    s.Leads++; if (c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单" && (!monthly || InMonth(r.date, year, month)); })) s.NewOrders++;
                    if (c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "二次" && (!monthly || InMonth(r.date, year, month)); })) s.Seconds++;
                }
                foreach (ConversionRecord r in c.ValidConversions) if (!monthly || InMonth(r.date, year, month)) s.Revenue += r.amount;
            }
            return map.Values.OrderByDescending(delegate(ChannelStat x) { return x.Leads; }).ToList();
        }

        public static List<AdvisorStat> Advisors(List<Customer> customers, AppSettings settings, bool monthly, int year, int month)
        {
            HashSet<string> inactive = new HashSet<string>(settings.inactiveAdvisors ?? new List<string>());
            HashSet<string> names = new HashSet<string>(settings.advisors.Where(delegate(string n) { return !inactive.Contains(n); }));
            foreach (string inactiveName in inactive) if (!String.IsNullOrWhiteSpace(inactiveName)) names.Add(inactiveName);
            foreach (Customer c in customers) { if (!String.IsNullOrWhiteSpace(c.advisor)) names.Add(c.advisor); foreach (ConversionRecord r in c.ValidConversions) foreach (AdvisorSplit sp in r.advisorSplits) if (!String.IsNullOrWhiteSpace(sp.name)) names.Add(sp.name); }
            List<AdvisorStat> result = new List<AdvisorStat>(); DateTime cutoff = DateTime.Now.AddDays(-15);
            foreach (string name in names)
            {
                AdvisorStat s = new AdvisorStat { Name = name, IsInactive = inactive.Contains(name) };
                foreach (Customer c in customers)
                {
                    bool funnel = c.dataType == "fullCustomer" && c.costEnabled && c.followUpTag != "已失去价值";
                    if (funnel && c.RoiAdvisorName == name && (!monthly || InMonth(c.importDate, year, month))) { s.Leads++; s.Cost += c.lineCost; }
                    if (funnel && c.RoiAdvisorName == name && c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单" && (!monthly || InMonth(r.date, year, month)); })) s.NewOrders++;
                    if (funnel && c.RoiAdvisorName == name && c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "二次" && (!monthly || InMonth(r.date, year, month)); })) s.Seconds++;
                    if (funnel && c.advisor == name && c.importDate >= cutoff && !c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单"; })) s.Pending++;
                    foreach (ConversionRecord r in c.ValidConversions)
                    {
                        if (monthly && !InMonth(r.date, year, month)) continue;
                        if (r.advisorSplits.Count == 0) { if (c.advisor == name) s.Revenue += r.amount; }
                        else foreach (AdvisorSplit sp in r.advisorSplits) if (sp.name == name) s.Revenue += r.amount * sp.ratio;
                    }
                }
                if (!monthly || !s.IsInactive || s.Leads > 0 || s.NewOrders > 0 || s.Seconds > 0 || s.Pending > 0 || s.Revenue > 0) result.Add(s);
            }
            return result.OrderByDescending(delegate(AdvisorStat x) { return x.Revenue; }).ToList();
        }

        public static string Region(string address)
        {
            if (String.IsNullOrWhiteSpace(address)) return "未知/其他";
            string[][] groups = { new string[] { "华南地区", "广东", "广州", "深圳", "广西", "海南", "香港", "澳门" }, new string[] { "华东地区", "上海", "江苏", "浙江", "安徽", "福建", "江西", "山东", "台湾" }, new string[] { "华北地区", "北京", "天津", "河北", "山西", "内蒙古", "内蒙" }, new string[] { "华中地区", "河南", "湖北", "湖南" }, new string[] { "东北地区", "辽宁", "吉林", "黑龙江" }, new string[] { "西南地区", "重庆", "四川", "贵州", "云南", "西藏" }, new string[] { "西北地区", "陕西", "甘肃", "青海", "宁夏", "新疆" } };
            foreach (string[] g in groups) for (int i = 1; i < g.Length; i++) if (address.Contains(g[i])) return g[0]; return "未知/其他";
        }
    }
}
