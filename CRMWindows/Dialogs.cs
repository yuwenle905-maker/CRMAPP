using System;
using System.Collections.Generic;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace CRMWindows
{
    public class CustomerForm : Form
    {
        private DataStore store; private Customer customer;
        private TextBox name, phone, number, address, lead, height, weight, age;
        private ComboBox gender, channel, advisor; private DateTimePicker importDate; private CheckBox costEnabled;
        private DataGridView orders;

        public CustomerForm(DataStore store, Customer customer)
        {
            this.store = store; this.customer = customer; Text = "客户资料 · " + (String.IsNullOrWhiteSpace(customer.name) ? "新增" : customer.name);
            Width = 900; Height = 720; StartPosition = FormStartPosition.CenterParent; Font = CrmTheme.Font(10); Build(); LoadValues(); RefreshOrders(); CrmTheme.StyleDialog(this);
        }

        private void Build()
        {
            TabControl tabs = new TabControl { Dock = DockStyle.Fill }; TabPage basic = new TabPage("基础资料"), history = new TabPage("订单与业绩"); tabs.TabPages.Add(basic); tabs.TabPages.Add(history);
            TableLayoutPanel table = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 4, Padding = new Padding(20), BackColor = Color.White };
            table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 95)); table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50)); table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 95)); table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            name = Box(); phone = Box(); number = Box(); address = Box(); lead = Box(); height = Box(); weight = Box(); age = Box();
            gender = Combo(new string[] { "未知", "女", "男" }); channel = Combo(new string[] { "自然流量", "食谱", "直播", "小红书", "问答", "抖音", "视频号", "朋友圈" });
            List<string> advisors = new List<string>(); advisors.Add("未分配"); advisors.AddRange(store.ActiveAdvisorNames()); advisor = Combo(advisors.ToArray()); importDate = new DateTimePicker { Format = DateTimePickerFormat.Custom, CustomFormat = "yyyy-MM-dd", Dock = DockStyle.Fill }; costEnabled = new CheckBox { Text = "纳入成本 / ROI", Dock = DockStyle.Fill, AutoSize = true };
            Add(table, 0, "姓名", name, "电话", phone); Add(table, 1, "编号", number, "归属顾问", advisor); Add(table, 2, "地址", address, "渠道", channel); Add(table, 3, "线索金额", lead, "录入日期", importDate); Add(table, 4, "身高", height, "体重", weight); Add(table, 5, "年龄", age, "性别", gender); Add(table, 6, "统计属性", costEnabled, "", new Label());
            Panel bottom = new Panel { Dock = DockStyle.Bottom, Height = 56 }; Button save = Button("保存客户", Color.FromArgb(24, 119, 242)); save.Location = new Point(680, 10); save.Click += delegate { SaveCustomer(); }; Button cancel = Button("取消", Color.Gray); cancel.Location = new Point(590, 10); cancel.Click += delegate { DialogResult = DialogResult.Cancel; }; bottom.Controls.AddRange(new Control[] { cancel, save }); basic.Controls.Add(table); basic.Controls.Add(bottom);
            Panel orderTools = new Panel { Dock = DockStyle.Top, Height = 52, BackColor = Color.White }; Button add = Button("新增订单", Color.SeaGreen); add.Location = new Point(12, 8); add.Click += delegate { EditOrder(null); }; Button edit = Button("编辑订单", Color.FromArgb(24, 119, 242)); edit.Location = new Point(115, 8); edit.Click += delegate { EditSelectedOrder(); }; Button voidButton = Button("作废 / 恢复", Color.DarkOrange); voidButton.Location = new Point(220, 8); voidButton.Click += delegate { ToggleVoid(); }; Button delete = Button("彻底删除订单", Color.Firebrick); delete.Location = new Point(350, 8); delete.Click += delegate { DeleteOrder(); }; orderTools.Controls.AddRange(new Control[] { add, edit, voidButton, delete }); orders = Grid(); orders.CellDoubleClick += delegate { EditSelectedOrder(); }; history.Controls.Add(orders); history.Controls.Add(orderTools); Controls.Add(tabs);
        }

        private void LoadValues()
        {
            name.Text = customer.name; phone.Text = customer.phone; number.Text = customer.customerNumber ?? ""; address.Text = customer.address ?? "";
            lead.Text = customer.leadAmount.HasValue ? customer.leadAmount.Value.ToString("0.##") : ""; height.Text = customer.height.HasValue ? customer.height.Value.ToString("0.##") : ""; weight.Text = customer.weight.HasValue ? customer.weight.Value.ToString("0.##") : ""; age.Text = customer.age.HasValue ? customer.age.Value.ToString() : "";
            gender.SelectedItem = customer.gender ?? "未知"; channel.SelectedItem = customer.ChannelDisplay; advisor.SelectedItem = customer.AdvisorDisplay; importDate.Value = customer.importDate.Year >= 2000 ? customer.importDate : DateTime.Now; costEnabled.Checked = customer.costEnabled;
        }

        private void SaveCustomer()
        {
            if (String.IsNullOrWhiteSpace(name.Text)) { MessageBox.Show("姓名不能为空。", "提示"); return; }
            string oldAdvisor = customer.advisor;
            customer.name = name.Text.Trim(); customer.phone = phone.Text.Trim(); customer.customerNumber = Empty(number.Text); customer.address = Empty(address.Text); customer.leadAmount = DoubleOrNull(lead.Text); customer.height = DoubleOrNull(height.Text); customer.weight = DoubleOrNull(weight.Text); customer.age = IntOrNull(age.Text); customer.gender = Convert.ToString(gender.SelectedItem); customer.channel = Convert.ToString(channel.SelectedItem) == "自然流量" ? null : Convert.ToString(channel.SelectedItem); customer.importDate = importDate.Value.Date; customer.costEnabled = costEnabled.Checked;
            string newAdvisor = Convert.ToString(advisor.SelectedItem); if (newAdvisor == "未分配") newAdvisor = null;
            if (oldAdvisor != newAdvisor)
            {
                if (customer.roiAdvisor == null) customer.roiAdvisor = !String.IsNullOrWhiteSpace(oldAdvisor) ? oldAdvisor : newAdvisor;
                if (!String.IsNullOrWhiteSpace(oldAdvisor) && oldAdvisor != newAdvisor) foreach (ConversionRecord r in customer.conversions) if (r.advisorSplits.Count == 0) r.advisorSplits.Add(new AdvisorSplit { name = oldAdvisor, ratio = 1 });
                customer.advisor = newAdvisor;
            }
            DialogResult = DialogResult.OK;
        }

        private void RefreshOrders()
        {
            DataTable dt = new DataTable(); dt.Columns.Add("ID"); dt.Columns.Add("日期"); dt.Columns.Add("次数"); dt.Columns.Add("金额"); dt.Columns.Add("快递单号"); dt.Columns.Add("分配"); dt.Columns.Add("状态");
            foreach (ConversionRecord r in customer.conversions.OrderByDescending(delegate(ConversionRecord x) { return x.date; })) dt.Rows.Add(r.id, r.date.ToString("yyyy-MM-dd"), r.type, "¥" + r.amount.ToString("N0"), r.trackingNumber ?? "", r.advisorSplits.Count == 0 ? "未分配" : String.Join(" + ", r.advisorSplits.Select(delegate(AdvisorSplit x) { return x.Display; }).ToArray()), r.isVoided ? "已作废" : "有效"); orders.DataSource = dt; orders.Columns["ID"].Visible = false;
        }
        private ConversionRecord SelectedOrder() { if (orders.CurrentRow == null) return null; string id = Convert.ToString(orders.CurrentRow.Cells["ID"].Value); return customer.conversions.Find(delegate(ConversionRecord r) { return r.id == id; }); }
        private void EditOrder(ConversionRecord r) { bool isNew = r == null; ConversionRecord target = r ?? new ConversionRecord(); using (ConversionForm form = new ConversionForm(target, store.ActiveAdvisorNames(), customer)) if (form.ShowDialog(this) == DialogResult.OK) { if (isNew) customer.conversions.Add(target); store.Save(); RefreshOrders(); } }
        private void EditSelectedOrder() { ConversionRecord r = SelectedOrder(); if (r != null) EditOrder(r); }
        private void ToggleVoid() { ConversionRecord r = SelectedOrder(); if (r != null) { r.isVoided = !r.isVoided; store.Save(); RefreshOrders(); } }
        private void DeleteOrder() { ConversionRecord r = SelectedOrder(); if (r != null && MessageBox.Show("彻底删除这笔订单后，相关业绩将立即重算。确定吗？", "确认", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes) { customer.conversions.Remove(r); store.Save(); RefreshOrders(); } }

        private static TextBox Box() { return new TextBox { Dock = DockStyle.Fill }; }
        private static ComboBox Combo(string[] values) { ComboBox c = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList }; c.Items.AddRange(values); if (c.Items.Count > 0) c.SelectedIndex = 0; return c; }
        private static void Add(TableLayoutPanel t, int row, string l1, Control c1, string l2, Control c2) { t.RowStyles.Add(new RowStyle(SizeType.Absolute, 48)); t.Controls.Add(new Label { Text = l1, Anchor = AnchorStyles.Left, AutoSize = true }, 0, row); t.Controls.Add(c1, 1, row); t.Controls.Add(new Label { Text = l2, Anchor = AnchorStyles.Left, AutoSize = true }, 2, row); t.Controls.Add(c2, 3, row); }
        private static Button Button(string text, Color color) { return new Button { Text = text, AutoSize = true, Height = 34, FlatStyle = FlatStyle.Flat, BackColor = color, ForeColor = Color.White }; }
        private static DataGridView Grid() { DataGridView grid = new DataGridView { Dock = DockStyle.Fill, ReadOnly = true, AllowUserToAddRows = false, RowHeadersVisible = false, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, SelectionMode = DataGridViewSelectionMode.FullRowSelect, MultiSelect = false }; CrmTheme.StyleGrid(grid); return grid; }
        private static string Empty(string s) { return String.IsNullOrWhiteSpace(s) ? null : s.Trim(); }
        private static double? DoubleOrNull(string s) { double d; return Double.TryParse(s, out d) ? (double?)d : null; }
        private static int? IntOrNull(string s) { int d; return Int32.TryParse(s, out d) ? (int?)d : null; }
    }

    public class ConversionForm : Form
    {
        private ConversionRecord record; private ComboBox type, mode, advisor1, advisor2; private NumericUpDown amount; private DateTimePicker date; private TextBox product, note, tracking; private CheckBox voided;
        public ConversionForm(ConversionRecord record, List<string> advisors, Customer customer)
        {
            this.record = record; Text = "编辑订单"; Width = 520; Height = 540; StartPosition = FormStartPosition.CenterParent; Font = CrmTheme.Font(10);
            TableLayoutPanel t = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Padding = new Padding(20) }; t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110)); t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            type = Combo(ConversionTypes.All); type.SelectedItem = record.type; amount = new NumericUpDown { Minimum = 0, Maximum = 100000000, DecimalPlaces = 2, ThousandsSeparator = true, Increment = 100, Dock = DockStyle.Fill, Value = (decimal)Math.Max(0, record.amount) }; date = new DateTimePicker { Format = DateTimePickerFormat.Custom, CustomFormat = "yyyy-MM-dd", Dock = DockStyle.Fill, Value = record.date.Year > 2000 ? record.date : DateTime.Now };
            mode = Combo(new string[] { "未分配", "单人100%", "双人各50%" }); List<string> names = new List<string>(); names.Add(""); names.AddRange(advisors); advisor1 = Combo(names.ToArray()); advisor2 = Combo(names.ToArray()); product = new TextBox { Dock = DockStyle.Fill, Text = record.productNote ?? "" }; tracking = new TextBox { Dock = DockStyle.Fill, Text = record.trackingNumber ?? "" }; note = new TextBox { Dock = DockStyle.Fill, Text = record.note ?? "" }; voided = new CheckBox { Text = "此订单已作废（不计业绩和成交率）", AutoSize = true, Checked = record.isVoided };
            if (record.advisorSplits.Count >= 2) { mode.SelectedIndex = 2; advisor1.SelectedItem = record.advisorSplits[0].name; advisor2.SelectedItem = record.advisorSplits[1].name; }
            else if (record.advisorSplits.Count == 1) { mode.SelectedIndex = 1; advisor1.SelectedItem = record.advisorSplits[0].name; } else mode.SelectedIndex = 0;
            Add(t, 0, "成交次数", type); Add(t, 1, "金额", amount); Add(t, 2, "开单日期", date); Add(t, 3, "分配方式", mode); Add(t, 4, "顾问一", advisor1); Add(t, 5, "顾问二", advisor2); Add(t, 6, "产品", product); Add(t, 7, "快递单号", tracking); Add(t, 8, "备注", note); Add(t, 9, "订单状态", voided);
            FlowLayoutPanel buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, Dock = DockStyle.Fill }; Button save = Btn("保存", Color.FromArgb(24, 119, 242)); save.Click += delegate { Save(); }; Button cancel = Btn("取消", Color.Gray); cancel.Click += delegate { DialogResult = DialogResult.Cancel; }; buttons.Controls.Add(save); buttons.Controls.Add(cancel); t.Controls.Add(buttons, 0, 10); t.SetColumnSpan(buttons, 2); Controls.Add(t); CrmTheme.StyleDialog(this); Shown += delegate { if (record.amount <= 0) { amount.Focus(); amount.Select(0, amount.Text.Length); } };
        }
        private void Save() { record.type = Convert.ToString(type.SelectedItem); record.amount = (double)amount.Value; record.date = date.Value.Date; record.productNote = Empty(product.Text); record.trackingNumber = Empty(tracking.Text); record.note = Empty(note.Text); record.isVoided = voided.Checked; record.advisorSplits.Clear(); if (mode.SelectedIndex == 1 && !String.IsNullOrWhiteSpace(Convert.ToString(advisor1.SelectedItem))) record.advisorSplits.Add(new AdvisorSplit { name = Convert.ToString(advisor1.SelectedItem), ratio = 1 }); if (mode.SelectedIndex == 2) { string a = Convert.ToString(advisor1.SelectedItem), b = Convert.ToString(advisor2.SelectedItem); if (String.IsNullOrWhiteSpace(a) || String.IsNullOrWhiteSpace(b) || a == b) { MessageBox.Show("双人分配请选择两位不同顾问。", "提示"); return; } record.advisorSplits.Add(new AdvisorSplit { name = a, ratio = .5 }); record.advisorSplits.Add(new AdvisorSplit { name = b, ratio = .5 }); } DialogResult = DialogResult.OK; }
        private static ComboBox Combo(string[] items) { ComboBox c = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList }; c.Items.AddRange(items); if (items.Length > 0) c.SelectedIndex = 0; return c; }
        private static void Add(TableLayoutPanel t, int row, string label, Control c) { t.RowStyles.Add(new RowStyle(SizeType.Absolute, 39)); t.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row); t.Controls.Add(c, 1, row); }
        private static Button Btn(string text, Color color) { return new Button { Text = text, AutoSize = true, FlatStyle = FlatStyle.Flat, BackColor = color, ForeColor = Color.White }; }
        private static string Empty(string s) { return String.IsNullOrWhiteSpace(s) ? null : s.Trim(); }
    }

    public class AdvisorForm : Form
    {
        private AdvisorProfile profile; private TextBox name; private ComboBox role, group;
        public AdvisorForm(AdvisorProfile profile, List<string> groups)
        {
            this.profile = profile; Text = "顾问角色与小组"; Width = 430; Height = 260; StartPosition = FormStartPosition.CenterParent; Font = CrmTheme.Font(10);
            TableLayoutPanel t = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Padding = new Padding(20) }; t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90)); t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            name = new TextBox { Dock = DockStyle.Fill, Text = profile.name }; role = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList }; role.Items.AddRange(new string[] { "组员", "组长" }); role.SelectedItem = profile.role;
            group = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDown }; group.Items.AddRange(groups.ToArray()); group.Text = profile.groupName;
            Add(t, 0, "姓名", name); Add(t, 1, "角色", role); Add(t, 2, "小组", group); Button save = new Button { Text = "保存", Dock = DockStyle.Fill, BackColor = Color.FromArgb(24, 119, 242), ForeColor = Color.White, FlatStyle = FlatStyle.Flat }; save.Click += delegate { if (String.IsNullOrWhiteSpace(name.Text)) { MessageBox.Show("姓名不能为空"); return; } profile.name = name.Text.Trim(); profile.role = Convert.ToString(role.SelectedItem); profile.groupName = group.Text.Trim(); DialogResult = DialogResult.OK; }; t.Controls.Add(save, 1, 3); Controls.Add(t); CrmTheme.StyleDialog(this);
        }
        private static void Add(TableLayoutPanel t, int row, string label, Control c) { t.RowStyles.Add(new RowStyle(SizeType.Absolute, 45)); t.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row); t.Controls.Add(c, 1, row); }
    }

    class CustomerChoice
    {
        public Customer Customer; public string Label; public override string ToString() { return Label; }
    }

    public class LedgerConfirmForm : Form
    {
        private DataStore store; private LedgerItem item; private ComboBox customer, type, mode, advisor1, advisor2; private DateTimePicker date; private NumericUpDown amount; private HashSet<string> prompted = new HashSet<string>();
        public Customer SelectedCustomer { get; private set; }
        public LedgerConfirmForm(DataStore store, LedgerItem item, Customer suggested)
        {
            this.store = store; this.item = item; Text = "确认单笔订单"; Width = 620; Height = 430; StartPosition = FormStartPosition.CenterParent; Font = CrmTheme.Font(10);
            TableLayoutPanel t = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Padding = new Padding(20) }; t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120)); t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            customer = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList }; customer.Items.Add(new CustomerChoice { Customer = null, Label = "暂不匹配，建立独立档案后期补录" });
            foreach (Customer c in store.Data.customers.Where(delegate(Customer x) { return x.dataType == "fullCustomer"; }).OrderBy(delegate(Customer x) { return x.name; })) customer.Items.Add(new CustomerChoice { Customer = c, Label = c.name + "  编号" + (c.customerNumber ?? "-") + "  " + c.phone });
            int selected = 0; if (suggested != null) for (int i = 1; i < customer.Items.Count; i++) if (((CustomerChoice)customer.Items[i]).Customer.id == suggested.id) selected = i; customer.SelectedIndex = selected;
            type = Combo(ConversionTypes.All); type.SelectedItem = item.Type; amount = new NumericUpDown { Maximum = 100000000, DecimalPlaces = 2, Value = (decimal)item.Amount, Dock = DockStyle.Fill }; date = new DateTimePicker { Format = DateTimePickerFormat.Custom, CustomFormat = "yyyy-MM-dd", Value = item.Date, Dock = DockStyle.Fill };
            mode = Combo(new string[] { "未分配（可后补）", "单人100%", "双人各50%" }); List<string> advisors = new List<string>(); advisors.Add(""); advisors.AddRange(store.ActiveAdvisorNames()); advisor1 = Combo(advisors.ToArray()); advisor2 = Combo(advisors.ToArray());
            Add(t, 0, "匹配客户", customer); Add(t, 1, "成交次数", type); Add(t, 2, "金额", amount); Add(t, 3, "开单日期", date); Add(t, 4, "分配方式", mode); Add(t, 5, "顾问一", advisor1); Add(t, 6, "顾问二", advisor2);
            Label hint = new Label { Text = "每笔订单都会经过此确认。客户或顾问暂时不确定时可后期补录。", ForeColor = Color.DarkOrange, AutoSize = true }; t.Controls.Add(hint, 0, 7); t.SetColumnSpan(hint, 2);
            Button save = new Button { Text = "确认保存本单", Dock = DockStyle.Fill, BackColor = Color.FromArgb(24, 119, 242), ForeColor = Color.White, FlatStyle = FlatStyle.Flat }; save.Click += delegate { Commit(); }; t.Controls.Add(save, 1, 8); Controls.Add(t);
            customer.SelectedIndexChanged += delegate { PromptHistorical(); }; Shown += delegate { PromptHistorical(); }; CrmTheme.StyleDialog(this);
        }
        private void PromptHistorical()
        {
            CustomerChoice choice = customer.SelectedItem as CustomerChoice; if (choice == null || choice.Customer == null || prompted.Contains(choice.Customer.id)) return; prompted.Add(choice.Customer.id);
            ConversionRecord latest = choice.Customer.conversions.Where(delegate(ConversionRecord r) { return !r.isVoided && r.advisorSplits.Count > 0; }).OrderByDescending(delegate(ConversionRecord r) { return r.date; }).FirstOrDefault(); if (latest == null) return;
            string text = String.Join(" + ", latest.advisorSplits.Select(delegate(AdvisorSplit x) { return x.Display; }).ToArray());
            if (MessageBox.Show(choice.Customer.name + " 上次业绩分配：\n" + text + "\n\n是否沿用？", "沿用上次业绩分配", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                if (latest.advisorSplits.Count >= 2) { mode.SelectedIndex = 2; advisor1.SelectedItem = latest.advisorSplits[0].name; advisor2.SelectedItem = latest.advisorSplits[1].name; }
                else { mode.SelectedIndex = 1; advisor1.SelectedItem = latest.advisorSplits[0].name; advisor2.SelectedIndex = 0; }
            }
        }
        private void Commit()
        {
            item.Type = Convert.ToString(type.SelectedItem); item.Amount = (double)amount.Value; item.Date = date.Value.Date; item.Advisor1 = ""; item.Advisor2 = "";
            if (mode.SelectedIndex >= 1) item.Advisor1 = Convert.ToString(advisor1.SelectedItem); if (mode.SelectedIndex == 2) item.Advisor2 = Convert.ToString(advisor2.SelectedItem);
            if (mode.SelectedIndex == 2 && (String.IsNullOrWhiteSpace(item.Advisor1) || String.IsNullOrWhiteSpace(item.Advisor2) || item.Advisor1 == item.Advisor2)) { MessageBox.Show("双人分配请选择两位不同顾问，或选择未分配后期补录。", "提示"); return; }
            CustomerChoice choice = customer.SelectedItem as CustomerChoice; SelectedCustomer = choice == null ? null : choice.Customer; DialogResult = DialogResult.OK;
        }
        private static ComboBox Combo(string[] items) { ComboBox c = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList }; c.Items.AddRange(items); if (items.Length > 0) c.SelectedIndex = 0; return c; }
        private static void Add(TableLayoutPanel t, int row, string label, Control c) { t.RowStyles.Add(new RowStyle(SizeType.Absolute, 40)); t.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row); t.Controls.Add(c, 1, row); }
    }
}
