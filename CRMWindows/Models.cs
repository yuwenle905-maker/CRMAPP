using System;
using System.Collections.Generic;

namespace CRMWindows
{
    public static class ConversionTypes
    {
        public static readonly string[] All = { "新单", "二次", "三次", "四次", "五次", "六次", "七次", "八次", "多次", "未知" };
    }

    public class AdvisorSplit
    {
        public string name { get; set; }
        public double ratio { get; set; }
        public AdvisorSplit() { name = ""; ratio = 1; }
        public string Display { get { return name + " " + Math.Round(ratio * 100) + "%"; } }
    }

    public class ConversionRecord
    {
        public string id { get; set; }
        public string type { get; set; }
        public double amount { get; set; }
        public DateTime date { get; set; }
        public string productNote { get; set; }
        public string note { get; set; }
        public string trackingNumber { get; set; }
        public List<AdvisorSplit> advisorSplits { get; set; }
        public bool isVoided { get; set; }

        public ConversionRecord()
        {
            id = Guid.NewGuid().ToString(); type = "新单"; date = DateTime.Now;
            productNote = null; note = null; advisorSplits = new List<AdvisorSplit>();
        }
    }

    public class Customer
    {
        public string id { get; set; }
        public string dataType { get; set; }
        public string name { get; set; }
        public string phone { get; set; }
        public string address { get; set; }
        public int? age { get; set; }
        public double? height { get; set; }
        public double? weight { get; set; }
        public string gender { get; set; }
        public string customerNumber { get; set; }
        public bool costEnabled { get; set; }
        public double? leadAmount { get; set; }
        public double lineCost { get; set; }
        public string importBatchID { get; set; }
        public DateTime importDate { get; set; }
        public List<string> tags { get; set; }
        public string followUpTag { get; set; }
        public string channel { get; set; }
        public string advisor { get; set; }
        public string roiAdvisor { get; set; }
        public List<ConversionRecord> conversions { get; set; }

        public Customer()
        {
            id = Guid.NewGuid().ToString(); dataType = "fullCustomer"; name = ""; phone = "";
            gender = "未知"; lineCost = 1200; importDate = DateTime.Now;
            tags = new List<string>(); conversions = new List<ConversionRecord>();
        }

        public string ChannelDisplay { get { return String.IsNullOrWhiteSpace(channel) ? "自然流量" : channel.Trim(); } }
        public string AdvisorDisplay { get { return String.IsNullOrWhiteSpace(advisor) ? "未分配" : advisor.Trim(); } }
        public string RoiAdvisorName
        {
            get
            {
                if (roiAdvisor != null) return String.IsNullOrWhiteSpace(roiAdvisor) ? null : roiAdvisor.Trim();
                return String.IsNullOrWhiteSpace(advisor) ? null : advisor.Trim();
            }
        }
        public List<ConversionRecord> ValidConversions
        {
            get { return conversions.FindAll(delegate(ConversionRecord r) { return !r.isVoided; }); }
        }
        public double TotalRevenue
        {
            get { double value = 0; foreach (ConversionRecord r in ValidConversions) value += r.amount; return value; }
        }
    }

    public class ImportBatch
    {
        public string id { get; set; }
        public string source { get; set; }
        public DateTime importDate { get; set; }
        public int recordCount { get; set; }
        public int fullCustomerCount { get; set; }
        public ImportBatch() { id = Guid.NewGuid().ToString(); source = "Windows导入"; importDate = DateTime.Now; }
    }

    public class AdvisorProfile
    {
        public string name { get; set; }
        public string role { get; set; }
        public string groupName { get; set; }
        public AdvisorProfile() { name = ""; role = "组员"; groupName = ""; }
    }

    public class AppSettings
    {
        public double leadUnitPrice { get; set; }
        public bool biometricLockEnabled { get; set; }
        public bool appPINEnabled { get; set; }
        public string appPIN { get; set; }
        public List<string> advisors { get; set; }
        public List<string> advisorGroups { get; set; }
        public List<AdvisorProfile> advisorProfiles { get; set; }
        public List<string> dismissedPendingSecondCustomerIDs { get; set; }
        public bool channelRevenueVisible { get; set; }
        public bool demoEnabled { get; set; }
        public List<string> hiddenMetrics { get; set; }
        public List<string> inactiveAdvisors { get; set; }

        public AppSettings()
        {
            leadUnitPrice = 1200; appPIN = ""; advisors = new List<string>();
            advisorGroups = new List<string>(new string[] { "销售一组", "销售二组" });
            advisorProfiles = new List<AdvisorProfile>(); dismissedPendingSecondCustomerIDs = new List<string>();
            channelRevenueVisible = true; hiddenMetrics = new List<string>();
            inactiveAdvisors = new List<string>();
        }
    }

    public class AppData
    {
        public int version { get; set; }
        public DateTime exportDate { get; set; }
        public List<Customer> customers { get; set; }
        public List<ImportBatch> batches { get; set; }
        public AppSettings settings { get; set; }
        public AppData()
        {
            version = 1; exportDate = DateTime.Now; customers = new List<Customer>();
            batches = new List<ImportBatch>(); settings = new AppSettings();
        }
    }

    public class ParsedCustomer
    {
        public bool Selected { get; set; }
        public string Name { get; set; }
        public string Phone { get; set; }
        public string Address { get; set; }
        public string Product { get; set; }
        public double? LeadAmount { get; set; }
        public double? Height { get; set; }
        public double? Weight { get; set; }
        public int? Age { get; set; }
        public string CustomerNumber { get; set; }
        public string Note { get; set; }
        public string Channel { get; set; }
        public string Advisor { get; set; }
        public DateTime ImportDate { get; set; }
        public bool NeedsReview { get; set; }
        public string Raw { get; set; }
        public ParsedCustomer() { Selected = true; Channel = null; ImportDate = DateTime.Now; }
    }

    public class LedgerItem
    {
        public bool Selected { get; set; }
        public string CustomerNumber { get; set; }
        public string Name { get; set; }
        public string Type { get; set; }
        public double Amount { get; set; }
        public DateTime Date { get; set; }
        public string Advisor1 { get; set; }
        public string Advisor2 { get; set; }
        public string MatchedCustomerId { get; set; }
        public LedgerItem() { Selected = true; Type = "新单"; Date = DateTime.Now; }
    }
}
