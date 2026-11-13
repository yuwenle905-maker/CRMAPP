using System;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;

namespace CRMWindows
{
    public class MainForm : Form
    {
        private DataStore store;
        private TabControl tabs;
        private CheckBox cumulative;
        private NumericUpDown year;
        private ComboBox month;
        private PolishedDashboard polishedDashboard;
        private DataGridView customerGrid, roiGrid, channelGrid, regionGrid, advisorGrid, profileGrid, smartGrid, ledgerGrid;
        private ContextMenuStrip customerCopyMenu;
        private FlowLayoutPanel analyticsCanvas;
        private TextBox customerSearch, smartText, ledgerText;
        private ComboBox customerChannelFilter, customerAdvisorFilter, customerOrderFilter;
        private Label customerFilterSummary;
        private List<ParsedCustomer> smartRows = new List<ParsedCustomer>();
        private List<LedgerItem> ledgerRows = new List<LedgerItem>();
        private Label dataPathLabel;
        private AutoImportService autoImportService;
        private Timer autoImportTimer;
        private Label autoImportStatusLabel;
        private Button oneClickSyncButton;
        private Label oneClickSyncStatusLabel;
        private bool oneClickSyncRunning;
        private NotifyIcon trayIcon;
        private bool allowApplicationExit;
        private bool trayHintShown;
        private readonly bool suppressAutomation;
        private Label contextTitle;
        private Label contextSubtitle;
        private FlowLayoutPanel contextNavigation;
        private readonly List<SidebarNavButton> navigationButtons = new List<SidebarNavButton>();
        private static readonly string[] CustomerOrderAmountColumns = { "新单", "二次", "三次", "四次", "五次", "六次", "七次", "八次", "多次" };
        private TabControl importTabs;
        private Timer customerSearchTimer;
        private Panel sidebarPanel;
        private Panel headerPanel;
        private readonly bool[] moduleDirty = { true, true, true, true, true, true };
        private bool refreshingModule;
        private bool updatingCustomerFilters;

        public MainForm(bool suppressAutomation = false)
        {
            this.suppressAutomation = suppressAutomation;
            store = new DataStore();
            autoImportService = new AutoImportService(store);
            Text = "私域 CRM · Windows"; Width = 1440; Height = 900; MinimumSize = new Size(1120, 700); AutoScaleMode = AutoScaleMode.Dpi;
            StartPosition = FormStartPosition.CenterScreen; Font = CrmTheme.Font(10F); BackColor = CrmTheme.Ground; ForeColor = CrmTheme.Text; Icon = SystemIcons.Application;
            BuildUi();
            FormClosed += delegate { if (customerCopyMenu != null) { customerCopyMenu.Dispose(); customerCopyMenu = null; } };
            autoImportTimer = new Timer();
            autoImportTimer.Tick += delegate { autoImportTimer.Stop(); if (RunScheduledAutomaticImport()) ScheduleNextAutomaticImport(); else ScheduleAutomaticImportRetry(); };
            customerSearchTimer = new Timer { Interval = 220 };
            customerSearchTimer.Tick += delegate { customerSearchTimer.Stop(); RefreshCustomers(); };
            if (!suppressAutomation) Shown += delegate { if (RunScheduledAutomaticImport()) ScheduleNextAutomaticImport(); else ScheduleAutomaticImportRetry(); };
            if (!suppressAutomation) InitializeTray();
        }

        private void InitializeTray()
        {
            ContextMenuStrip menu = new ContextMenuStrip { Font = CrmTheme.Font(9F), BackColor = CrmTheme.SurfaceRaised, ForeColor = CrmTheme.Text, ShowImageMargin = false };
            ToolStripMenuItem open = new ToolStripMenuItem("打开私域 CRM");
            ToolStripMenuItem refresh = new ToolStripMenuItem("刷新数据");
            ToolStripMenuItem exit = new ToolStripMenuItem("退出程序");
            open.Click += delegate { RestoreFromTray(); };
            refresh.Click += delegate { store.Load(); RefreshAll(); };
            exit.Click += delegate { allowApplicationExit = true; trayIcon.Visible = false; Close(); };
            menu.Items.Add(open); menu.Items.Add(refresh); menu.Items.Add(new ToolStripSeparator()); menu.Items.Add(exit);
            trayIcon = new NotifyIcon { Text = "私域 CRM · 后台运行中", Icon = Icon, ContextMenuStrip = menu, Visible = true };
            trayIcon.DoubleClick += delegate { RestoreFromTray(); };
            FormClosing += HandleFormClosing;
            FormClosed += delegate { if (trayIcon != null) { trayIcon.Visible = false; trayIcon.Dispose(); } };
        }

        private void HandleFormClosing(object sender, FormClosingEventArgs e)
        {
            if (allowApplicationExit || suppressAutomation || e.CloseReason == CloseReason.WindowsShutDown || e.CloseReason == CloseReason.TaskManagerClosing) return;
            if (e.CloseReason != CloseReason.UserClosing) return;
            e.Cancel = true;
            Hide();
            if (!trayHintShown)
            {
                trayHintShown = true;
                trayIcon.ShowBalloonTip(2500, "私域 CRM 正在后台运行", "定时同步会继续执行。双击托盘图标可恢复窗口。", ToolTipIcon.Info);
            }
        }

        private void RestoreFromTray()
        {
            if (!Visible) Show();
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            Activate();
            BringToFront();
        }

        private void BuildUi()
        {
            Panel shell = new Panel { Dock = DockStyle.Fill, BackColor = CrmTheme.Ground };
            Controls.Add(shell);

            sidebarPanel = new Panel { Dock = DockStyle.Left, Width = 224, BackColor = CrmTheme.Sidebar, Padding = new Padding(14, 18, 14, 16) };
            Panel brand = new Panel { Dock = DockStyle.Top, Height = 84, BackColor = CrmTheme.Sidebar };
            Label mark = new Label { Text = "P", AutoSize = false, Width = 40, Height = 40, Location = new Point(4, 5), TextAlign = ContentAlignment.MiddleCenter, Font = CrmTheme.Font(14, FontStyle.Bold), ForeColor = CrmTheme.Ground, BackColor = CrmTheme.Coral };
            Label product = new Label { Text = "私域 CRM", AutoSize = true, Location = new Point(56, 5), Font = CrmTheme.Font(15, FontStyle.Bold), ForeColor = Color.White, BackColor = CrmTheme.Sidebar };
            Label edition = new Label { Text = "PRIVATE WORKSPACE", AutoSize = true, Location = new Point(58, 34), Font = CrmTheme.Font(7.2F, FontStyle.Bold), ForeColor = Color.FromArgb(139, 154, 190), BackColor = CrmTheme.Sidebar };
            brand.Controls.AddRange(new Control[] { mark, product, edition });
            string[] navText = { "数据看板", "客户档案", "经营分析", "顾问团队", "批量录入", "系统设置" };
            string[] navSymbol = { "▦", "人", "↗", "组", "＋", "⚙" };
            FlowLayoutPanel nav = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, BackColor = CrmTheme.Sidebar, Padding = new Padding(0), Margin = new Padding(0) };
            for (int i = 0; i < navText.Length; i++)
            {
                int index = i;
                SidebarNavButton button = new SidebarNavButton { Text = navText[i], Symbol = navSymbol[i], Width = 194, Margin = new Padding(0, 0, 0, 6), Selected = i == 0 };
                button.Click += delegate { SelectModule(index); };
                navigationButtons.Add(button);
                nav.Controls.Add(button);
            }
            Panel sidebarFooter = new Panel { Dock = DockStyle.Bottom, Height = 70, BackColor = CrmTheme.Sidebar };
            sidebarFooter.Controls.Add(new Label { Text = "本地数据 · 自动保存\nWindows 工作台", Dock = DockStyle.Fill, Padding = new Padding(10, 13, 0, 0), Font = CrmTheme.Font(8.5F), ForeColor = Color.FromArgb(127, 142, 176), BackColor = CrmTheme.Sidebar });
            TableLayoutPanel sidebarLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, BackColor = CrmTheme.Sidebar, Margin = new Padding(0), Padding = new Padding(0) };
            sidebarLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 84));
            sidebarLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            sidebarLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 70));
            sidebarLayout.Controls.Add(brand, 0, 0);
            sidebarLayout.Controls.Add(nav, 0, 1);
            sidebarLayout.Controls.Add(sidebarFooter, 0, 2);
            sidebarPanel.Controls.Add(sidebarLayout);

            Panel workspace = new Panel { Dock = DockStyle.Fill, BackColor = CrmTheme.Ground, Padding = new Padding(0) };
            headerPanel = new Panel { Dock = DockStyle.Top, Height = 104, BackColor = Color.FromArgb(249, 250, 255), Padding = new Padding(28, 14, 24, 10) };
            contextTitle = new Label { Text = "数据看板", AutoSize = true, Location = new Point(28, 15), Font = CrmTheme.Font(18F, FontStyle.Bold), ForeColor = CrmTheme.Text, BackColor = headerPanel.BackColor };
            contextSubtitle = new Label { Text = "经营健康度、待跟进与每日数据审阅", AutoSize = true, Location = new Point(30, 48), Font = CrmTheme.Font(8.5F), ForeColor = CrmTheme.Muted, BackColor = headerPanel.BackColor };
            contextNavigation = new FlowLayoutPanel { Location = new Point(28, 70), Height = 32, Width = 520, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, BackColor = headerPanel.BackColor, Padding = new Padding(0), Margin = new Padding(0) };

            FlowLayoutPanel periodTools = new FlowLayoutPanel { Dock = DockStyle.Right, Width = 370, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Padding = new Padding(0, 8, 0, 0), BackColor = headerPanel.BackColor };
            cumulative = new CheckBox { Text = "累计", Appearance = Appearance.Button, AutoSize = false, Width = 56, Height = 34, TextAlign = ContentAlignment.MiddleCenter, FlatStyle = FlatStyle.Flat, BackColor = CrmTheme.SurfaceRaised, ForeColor = CrmTheme.Text, Padding = new Padding(4, 0, 4, 0), Margin = new Padding(0, 0, 8, 0) };
            cumulative.FlatAppearance.BorderColor = CrmTheme.Border;
            cumulative.CheckedChanged += delegate { cumulative.BackColor = cumulative.Checked ? Color.FromArgb(219, 229, 248) : CrmTheme.SurfaceRaised; cumulative.ForeColor = cumulative.Checked ? CrmTheme.Blue : CrmTheme.Text; RefreshAll(); };
            year = new NumericUpDown { Minimum = 2020, Maximum = 2100, Value = DateTime.Now.Year, Width = 78, Height = 34, Margin = new Padding(0, 2, 8, 0), BorderStyle = BorderStyle.FixedSingle };
            month = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 72, Height = 34, Margin = new Padding(0, 2, 8, 0), FlatStyle = FlatStyle.Flat };
            for (int i = 1; i <= 12; i++) month.Items.Add(i + "月"); month.SelectedIndex = DateTime.Now.Month - 1;
            year.ValueChanged += delegate { RefreshAll(); }; month.SelectedIndexChanged += delegate { RefreshAll(); };
            Button refresh = MakeButton("刷新数据", CrmTheme.Coral); refresh.Margin = new Padding(0); refresh.Click += delegate { store.Load(); RefreshAll(); };
            periodTools.Controls.AddRange(new Control[] { cumulative, year, month, refresh });
            headerPanel.Controls.AddRange(new Control[] { contextTitle, contextSubtitle, contextNavigation, periodTools });

            tabs = new HiddenTabControl { Dock = DockStyle.Fill, Font = CrmTheme.Font(10F), BackColor = CrmTheme.Ground };
            tabs.TabPages.Add(BuildDashboard()); tabs.TabPages.Add(BuildCustomers()); tabs.TabPages.Add(BuildAnalytics());
            tabs.TabPages.Add(BuildAdvisors()); tabs.TabPages.Add(BuildImport()); tabs.TabPages.Add(BuildSettings());
            workspace.Controls.Add(tabs);
            workspace.Controls.Add(headerPanel);
            shell.Controls.Add(workspace);
            shell.Controls.Add(sidebarPanel);
            CrmTheme.StylePanelTree(this);
            SelectModule(0);
        }

        private void SelectModule(int index)
        {
            if (tabs == null || index < 0 || index >= tabs.TabPages.Count) return;
            tabs.SelectedIndex = index;
            for (int i = 0; i < navigationButtons.Count; i++) navigationButtons[i].Selected = i == index;
            string[] titles = { "数据看板", "客户档案", "经营分析", "顾问团队", "批量录入", "系统设置" };
            string[] subtitles = { "经营健康度、待跟进与每日数据审阅", "搜索、维护与同步全部客户资料", "ROI 趋势、渠道漏斗与客户画像", "小组 ROI、个人业绩与组织配置", "智能客户导入与订单流水确认", "成本、隐私、自动导入与数据备份" };
            contextTitle.Text = titles[index]; contextSubtitle.Text = subtitles[index];
            UpdateContextNavigation(index);
            RefreshModuleIfNeeded(index);
            if (sidebarPanel != null) sidebarPanel.Invalidate(true);
            if (headerPanel != null) headerPanel.Invalidate(true);
        }

        private void UpdateContextNavigation(int index)
        {
            contextNavigation.Controls.Clear();
            string[][] labels = {
                new string[] { "经营概览", "待跟进", "每日审阅" },
                new string[] { "客户总览" },
                new string[] { "ROI 趋势", "渠道漏斗", "客户画像" },
                new string[] { "业绩核算", "组织配置" },
                new string[] { "智能导入", "流水录入" },
                new string[] { "系统设置" }
            };
            for (int i = 0; i < labels[index].Length; i++)
            {
                int subIndex = i;
                ContextButton chip = new ContextButton { Text = labels[index][i], Selected = i == 0, Height = 32, Margin = new Padding(0, 0, 7, 0), Padding = new Padding(9, 0, 9, 0), Font = CrmTheme.Font(8.3F) };
                chip.Click += delegate { ActivateContextNavigation(index, subIndex, chip); };
                contextNavigation.Controls.Add(chip);
            }
        }

        private void ActivateContextNavigation(int moduleIndex, int subIndex, ContextButton chip)
        {
            foreach (Control c in contextNavigation.Controls) if (c is ContextButton) ((ContextButton)c).Selected = c == chip;
            contextNavigation.Invalidate(true);
            if (moduleIndex == 0 && polishedDashboard != null) polishedDashboard.ScrollToSection(subIndex);
            else if (moduleIndex == 1 && customerGrid != null) customerGrid.Focus();
            else if (moduleIndex == 2 && analyticsCanvas != null)
            {
                Control target = subIndex == 0 ? roiGrid.Parent : (subIndex == 1 ? channelGrid.Parent : regionGrid.Parent);
                if (target != null) { analyticsCanvas.ScrollControlIntoView(target); target.Focus(); }
            }
            else if (moduleIndex == 3)
            {
                Control target = subIndex == 0 ? (Control)advisorGrid : profileGrid;
                if (target != null) target.Focus();
            }
            else if (moduleIndex == 4 && importTabs != null) importTabs.SelectedIndex = subIndex;
        }

        private TabPage BuildDashboard()
        {
            TabPage page = Page("数据看板");
            page.Padding = new Padding(0);
            polishedDashboard = new PolishedDashboard { Dock = DockStyle.Fill };
            polishedDashboard.Navigate += ShowDashboardDetail;
            page.Controls.Add(polishedDashboard); return page;
        }

        private TabPage BuildCustomers()
        {
            TabPage page = Page("客户"); FlowLayoutPanel tools = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 104, BackColor = CrmTheme.Surface, Padding = new Padding(16, 13, 14, 10), WrapContents = true, FlowDirection = FlowDirection.LeftToRight };
            customerSearch = new TextBox { Width = 230, Height = 34, BorderStyle = BorderStyle.FixedSingle, Margin = new Padding(0, 4, 12, 5) }; customerSearch.TextChanged += delegate { customerSearchTimer.Stop(); customerSearchTimer.Start(); };
            customerChannelFilter = new ComboBox { Width = 112, Height = 34, DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat, Margin = new Padding(0, 4, 8, 5) };
            customerAdvisorFilter = new ComboBox { Width = 112, Height = 34, DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat, Margin = new Padding(0, 4, 8, 5) };
            customerOrderFilter = new ComboBox { Width = 112, Height = 34, DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat, Margin = new Padding(0, 4, 12, 5) };
            customerOrderFilter.Items.AddRange(new object[] { "全部客户", "已开单", "未开单" }); customerOrderFilter.SelectedIndex = 0;
            customerChannelFilter.SelectedIndexChanged += delegate { if (!updatingCustomerFilters) RefreshCustomers(); };
            customerAdvisorFilter.SelectedIndexChanged += delegate { if (!updatingCustomerFilters) RefreshCustomers(); };
            customerOrderFilter.SelectedIndexChanged += delegate { RefreshCustomers(); };
            Button add = MakeButton("新增客户", CrmTheme.Coral); add.Location = new Point(280, 14); add.Click += delegate { EditCustomer(null); };
            Button edit = MakeButton("查看 / 编辑", CrmTheme.Blue); edit.Location = new Point(385, 14); edit.Click += delegate { EditSelectedCustomer(); };
            Button copy = MakeButton("复制全部资料", CrmTheme.SurfaceSoft); copy.Location = new Point(510, 14); copy.Click += delegate { CopySelectedCustomer(); };
            Button delete = MakeButton("删除客户", CrmTheme.Red); delete.Location = new Point(650, 14); delete.Click += delegate { DeleteSelectedCustomer(); };
            oneClickSyncButton = MakeButton("一键同步资料", CrmTheme.Lilac); oneClickSyncButton.Location = new Point(755, 14); oneClickSyncButton.Click += delegate { StartOneClickSync(); };
            customerFilterSummary = new Label { Width = 330, Height = 36, Padding = new Padding(5, 9, 0, 0), AutoEllipsis = true, ForeColor = CrmTheme.Blue, Text = "", BackColor = Color.Transparent };
            oneClickSyncStatusLabel = new Label { Width = 260, Height = 36, Padding = new Padding(5, 9, 0, 0), AutoEllipsis = true, ForeColor = CrmTheme.Muted, Text = "更新余文乐资料并导入 CRM", BackColor = Color.Transparent };
            tools.Controls.AddRange(new Control[] { customerSearch, customerChannelFilter, customerAdvisorFilter, customerOrderFilter, add, edit, copy, delete, oneClickSyncButton, customerFilterSummary, oneClickSyncStatusLabel });
            customerGrid = MakeGrid(); customerGrid.CellDoubleClick += delegate { EditSelectedCustomer(); }; customerGrid.CellMouseEnter += delegate { customerGrid.Cursor = Cursors.Hand; }; customerGrid.CellMouseLeave += delegate { customerGrid.Cursor = Cursors.Default; };
            customerCopyMenu = new ContextMenuStrip { Font = CrmTheme.Font(9F), BackColor = CrmTheme.SurfaceRaised, ForeColor = CrmTheme.Text, ShowImageMargin = false };
            ToolStripMenuItem copyName = new ToolStripMenuItem("复制客户姓名"); copyName.Click += delegate { CopySelectedCustomerField("姓名"); };
            ToolStripMenuItem copyPhone = new ToolStripMenuItem("复制客户电话"); copyPhone.Click += delegate { CopySelectedCustomerField("电话"); };
            ToolStripMenuItem copyNumber = new ToolStripMenuItem("复制客户编号"); copyNumber.Click += delegate { CopySelectedCustomerField("编号"); };
            customerCopyMenu.Items.AddRange(new ToolStripItem[] { copyName, copyPhone, copyNumber });
            customerCopyMenu.Opening += delegate { Customer selected = SelectedCustomer(); copyName.Enabled = selected != null && !String.IsNullOrWhiteSpace(selected.name); copyPhone.Enabled = selected != null && !String.IsNullOrWhiteSpace(selected.phone); copyNumber.Enabled = selected != null && !String.IsNullOrWhiteSpace(selected.customerNumber); };
            customerGrid.ContextMenuStrip = customerCopyMenu;
            customerGrid.CellMouseDown += delegate(object sender, DataGridViewCellMouseEventArgs e) { if (e.Button == MouseButtons.Right && e.RowIndex >= 0 && e.ColumnIndex >= 0) { customerGrid.ClearSelection(); customerGrid.CurrentCell = customerGrid.Rows[e.RowIndex].Cells[e.ColumnIndex]; customerGrid.Rows[e.RowIndex].Selected = true; } };
            page.Controls.Add(customerGrid); page.Controls.Add(tools); return page;
        }

        private TabPage BuildAnalytics()
        {
            TabPage page = Page("分析"); page.Padding = new Padding(0);
            analyticsCanvas = new BufferedFlowLayoutPanel { Dock = DockStyle.Fill, AutoScroll = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(22), BackColor = CrmTheme.Ground };
            roiGrid = MakeGrid(); channelGrid = MakeGrid(); regionGrid = MakeGrid(); roiGrid.CellFormatting += FormatRoiCell;
            analyticsCanvas.Controls.Add(AnalyticsSection("近六个月 ROI 对比", roiGrid, 205));
            analyticsCanvas.Controls.Add(AnalyticsSection("渠道漏斗分析", channelGrid, 240));
            analyticsCanvas.Controls.Add(AnalyticsSection("地域 / 年龄 / 线索金额画像", regionGrid, 520));
            analyticsCanvas.Resize += delegate { foreach (Control c in analyticsCanvas.Controls) c.Width = Math.Max(700, analyticsCanvas.ClientSize.Width - 48); };
            page.Controls.Add(analyticsCanvas); return page;
        }

        private Panel AnalyticsSection(string title, DataGridView grid, int height)
        {
            Panel card = new InteractiveSurfacePanel { Height = height, Width = 1120, BackColor = CrmTheme.Surface, Margin = new Padding(0, 0, 0, 16), Padding = new Padding(14) };
            grid.Dock = DockStyle.Fill; grid.ScrollBars = ScrollBars.None;
            card.Controls.Add(grid); card.Controls.Add(HeadingDock(title)); return card;
        }

        private void FormatRoiCell(object sender, DataGridViewCellFormattingEventArgs e)
        {
            if (roiGrid.Columns[e.ColumnIndex].Name != "ROI" && roiGrid.Columns[e.ColumnIndex].Name != "盈亏状态") return;
            string value = Convert.ToString(e.Value); e.CellStyle.Font = CrmTheme.PaintFont(10, FontStyle.Bold);
            if (value == "盈利") e.CellStyle.ForeColor = CrmTheme.Green;
            else if (value == "亏损") e.CellStyle.ForeColor = CrmTheme.Red;
            else if (roiGrid.Columns[e.ColumnIndex].Name == "ROI") e.CellStyle.ForeColor = CrmTheme.Blue;
        }

        private TabPage BuildAdvisors()
        {
            TabPage page = Page("顾问"); SplitContainer split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, SplitterDistance = 390, BackColor = CrmTheme.Ground, SplitterWidth = 10 };
            advisorGrid = MakeGrid(); profileGrid = MakeGrid();
            Panel profileTools = new Panel { Dock = DockStyle.Top, Height = 54, BackColor = CrmTheme.Surface };
            Button add = MakeButton("新增顾问", CrmTheme.Coral); add.Location = new Point(16, 9); add.Click += delegate { EditAdvisor(null); };
            Button edit = MakeButton("编辑角色 / 小组", CrmTheme.Blue); edit.Location = new Point(120, 9); edit.Click += delegate { EditSelectedAdvisor(); };
            Button del = MakeButton("删除顾问", CrmTheme.Red); del.Location = new Point(275, 9); del.Click += delegate { DeleteSelectedAdvisor(); };
            profileTools.Controls.AddRange(new Control[] { add, edit, del });
            split.Panel1.Controls.Add(advisorGrid); split.Panel1.Controls.Add(HeadingDock("小组 ROI 与个人业绩"));
            split.Panel2.Controls.Add(profileGrid); split.Panel2.Controls.Add(profileTools); split.Panel2.Controls.Add(HeadingDock("员工与组织配置"));
            page.Controls.Add(split); return page;
        }

        private TabPage BuildImport()
        {
            TabPage page = Page("录入"); importTabs = new HiddenTabControl { Dock = DockStyle.Fill };
            importTabs.TabPages.Add(BuildSmartImport()); importTabs.TabPages.Add(BuildLedgerImport()); page.Controls.Add(importTabs); return page;
        }

        private TabPage BuildSmartImport()
        {
            TabPage page = Page("智能导入客户"); SplitContainer split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, SplitterDistance = 220 };
            smartText = new TextBox { Dock = DockStyle.Fill, Multiline = true, ScrollBars = ScrollBars.Both, Font = new Font("Consolas", 10), AcceptsTab = true, BackColor = CrmTheme.Surface, ForeColor = CrmTheme.Text, BorderStyle = BorderStyle.FixedSingle };
            Panel buttons = new Panel { Dock = DockStyle.Bottom, Height = 54, BackColor = CrmTheme.SurfaceRaised };
            Button parse = MakeButton("解析预览", CrmTheme.Blue); parse.Location = new Point(12, 9); parse.Click += delegate { ParseSmart(); };
            Button import = MakeButton("确认导入所选", CrmTheme.Coral); import.Location = new Point(125, 9); import.Click += delegate { ImportSmart(); };
            Label hint = new Label { Text = "支持制表符表格及：姓名 电话 地址 身高160体重120年龄35 SF编号 食谱/直播/小红书/问答", AutoSize = true, Location = new Point(270, 17), ForeColor = CrmTheme.Muted };
            buttons.Controls.AddRange(new Control[] { parse, import, hint }); split.Panel1.Controls.Add(smartText); split.Panel1.Controls.Add(buttons);
            smartGrid = MakeGrid(); smartGrid.ReadOnly = false; split.Panel2.Controls.Add(smartGrid); page.Controls.Add(split); return page;
        }

        private TabPage BuildLedgerImport()
        {
            TabPage page = Page("流水批量录入"); SplitContainer split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, SplitterDistance = 180 };
            ledgerText = new TextBox { Dock = DockStyle.Fill, Multiline = true, ScrollBars = ScrollBars.Both, Font = new Font("Consolas", 11), BackColor = CrmTheme.Surface, ForeColor = CrmTheme.Text, BorderStyle = BorderStyle.FixedSingle };
            Panel buttons = new Panel { Dock = DockStyle.Bottom, Height = 54, BackColor = CrmTheme.SurfaceRaised };
            Button parse = MakeButton("解析流水", CrmTheme.Blue); parse.Location = new Point(12, 9); parse.Click += delegate { ParseLedger(); };
            Button import = MakeButton("逐单确认并保存", CrmTheme.Coral); import.Location = new Point(125, 9); import.Click += delegate { ImportLedger(); };
            Label hint = new Label { Text = "格式：2583 新单 3260   2547 二次 9800   2475 多次 9200", AutoSize = true, Location = new Point(285, 17), ForeColor = CrmTheme.Muted };
            buttons.Controls.AddRange(new Control[] { parse, import, hint }); split.Panel1.Controls.Add(ledgerText); split.Panel1.Controls.Add(buttons);
            ledgerGrid = MakeGrid(); split.Panel2.Controls.Add(ledgerGrid); page.Controls.Add(split); return page;
        }

        private TabPage BuildSettings()
        {
            TabPage page = Page("设置"); FlowLayoutPanel flow = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(24), BackColor = CrmTheme.Ground };
            GroupBox price = new InteractiveGroupBox { Text = "成本设置", Width = 840, Height = 100, BackColor = CrmTheme.Surface, ForeColor = CrmTheme.Text, Padding = new Padding(14) };
            NumericUpDown unit = new NumericUpDown { Minimum = 0, Maximum = 1000000, DecimalPlaces = 2, Value = (decimal)store.Data.settings.leadUnitPrice, Location = new Point(145, 32), Width = 130 };
            price.Controls.Add(new Label { Text = "每份资料单价", Location = new Point(20, 35), AutoSize = true }); price.Controls.Add(unit);
            Button savePrice = MakeButton("保存", CrmTheme.Coral); savePrice.Location = new Point(300, 27); savePrice.Click += delegate { store.Data.settings.leadUnitPrice = (double)unit.Value; store.Save(); RefreshAll(); }; price.Controls.Add(savePrice);
            GroupBox disguise = new InteractiveGroupBox { Text = "全局伪装工作区", Width = 840, Height = 132, BackColor = CrmTheme.Surface, ForeColor = CrmTheme.Text, Padding = new Padding(14) };
            Label disguiseInfo = new Label { Location = new Point(20, 29), Width = 620, Height = 42, ForeColor = CrmTheme.Muted, Text = store.IsDisguiseActive ? "伪装工作区已开启：所有客户、订单、顾问和统计修改只写入隔离副本。" : "开启后会复制完整数据库；可自由修改截图数据，解除后恢复真实数据库。" };
            Button disguiseToggle = MakeButton(store.IsDisguiseActive ? "解除全局伪装" : "开启全局伪装", store.IsDisguiseActive ? CrmTheme.Orange : CrmTheme.Lilac); disguiseToggle.Location = new Point(20, 77);
            disguiseToggle.Click += delegate
            {
                if (store.IsDisguiseActive)
                {
                    if (MessageBox.Show("解除后将立即恢复真实数据库，伪装副本会保留但不再显示。确定解除吗？", "解除全局伪装", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                    store.DisableDisguise(); disguiseToggle.Text = "开启全局伪装"; disguiseToggle.BackColor = CrmTheme.Lilac; disguiseInfo.Text = "已恢复真实数据库。再次开启会从当前真实数据创建新的伪装副本。";
                    if (!suppressAutomation) ScheduleNextAutomaticImport();
                }
                else
                {
                    if (MessageBox.Show("将从当前真实数据库创建隔离副本。之后所有编辑只影响伪装数据，确定开启吗？", "开启全局伪装", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                    store.EnableDisguise(); disguiseToggle.Text = "解除全局伪装"; disguiseToggle.BackColor = CrmTheme.Orange; disguiseInfo.Text = "伪装工作区已开启：所有客户、订单、顾问和统计修改只写入隔离副本。"; autoImportTimer.Stop();
                }
                RefreshAll();
            };
            disguise.Controls.AddRange(new Control[] { disguiseInfo, disguiseToggle });
            GroupBox privacy = new InteractiveGroupBox { Text = "显示与伪装", Width = 840, Height = 140, BackColor = CrmTheme.Surface, ForeColor = CrmTheme.Text, Padding = new Padding(14) };
            CheckBox hideRevenue = new CheckBox { Text = "隐藏营业额", Location = new Point(20, 30), AutoSize = true, Checked = store.Data.settings.hiddenMetrics.Contains("revenue") };
            CheckBox hideCost = new CheckBox { Text = "隐藏成本", Location = new Point(150, 30), AutoSize = true, Checked = store.Data.settings.hiddenMetrics.Contains("cost") };
            CheckBox hideRoi = new CheckBox { Text = "隐藏 ROI", Location = new Point(270, 30), AutoSize = true, Checked = store.Data.settings.hiddenMetrics.Contains("roi") };
            CheckBox hidePhone = new CheckBox { Text = "隐藏电话", Location = new Point(390, 30), AutoSize = true, Checked = store.Data.settings.hiddenMetrics.Contains("phone") };
            CheckBox hideAddress = new CheckBox { Text = "隐藏地址", Location = new Point(510, 30), AutoSize = true, Checked = store.Data.settings.hiddenMetrics.Contains("address") };
            Button apply = MakeButton("应用显示设置", CrmTheme.Lilac); apply.Location = new Point(20, 70); apply.Click += delegate { SetHidden("revenue", hideRevenue.Checked); SetHidden("cost", hideCost.Checked); SetHidden("roi", hideRoi.Checked); SetHidden("phone", hidePhone.Checked); SetHidden("address", hideAddress.Checked); store.Save(); RefreshAll(); }; privacy.Controls.AddRange(new Control[] { hideRevenue, hideCost, hideRoi, hidePhone, hideAddress, apply });
            GroupBox autoImport = new InteractiveGroupBox { Text = "余文乐资料自动导入", Width = 840, Height = 160, BackColor = CrmTheme.Surface, ForeColor = CrmTheme.Text, Padding = new Padding(14) };
            CheckBox autoEnabled = new CheckBox { Text = "每天 11:00、20:00 自动检测并导入", Location = new Point(20, 30), AutoSize = true, Checked = autoImportService.Config.enabled };
            TextBox autoPath = new TextBox { Location = new Point(20, 62), Width = 570, ReadOnly = true, Text = autoImportService.Config.filePath };
            Button browseAuto = MakeButton("选择文件", CrmTheme.SurfaceSoft); browseAuto.Location = new Point(600, 57); browseAuto.Click += delegate { OpenFileDialog d = new OpenFileDialog { Filter = "Excel 文件|*.xlsx", FileName = autoPath.Text }; if (d.ShowDialog(this) == DialogResult.OK) { autoPath.Text = d.FileName; autoImportService.Config.filePath = d.FileName; autoImportService.Config.lastFileStamp = ""; autoImportService.SaveConfig(); CheckAutomaticImport(true); } };
            Button checkAuto = MakeButton("立即检测", CrmTheme.Blue); checkAuto.Location = new Point(20, 96); checkAuto.Click += delegate { autoImportService.Config.enabled = autoEnabled.Checked; autoImportService.SaveConfig(); CheckAutomaticImport(true); };
            autoEnabled.CheckedChanged += delegate { autoImportService.Config.enabled = autoEnabled.Checked; autoImportService.SaveConfig(); if (autoEnabled.Checked) { if (RunScheduledAutomaticImport()) ScheduleNextAutomaticImport(); else ScheduleAutomaticImportRetry(); } else { autoImportTimer.Stop(); if (autoImportStatusLabel != null) autoImportStatusLabel.Text = "自动导入已关闭"; } };
            autoImportStatusLabel = new Label { Location = new Point(135, 102), Width = 650, AutoSize = false, ForeColor = CrmTheme.Muted, Text = "等待检测：" + autoImportService.Config.filePath };
            autoImport.Controls.AddRange(new Control[] { autoEnabled, autoPath, browseAuto, checkAuto, autoImportStatusLabel });
            GroupBox backup = new InteractiveGroupBox { Text = "数据备份（与 iOS 明文 JSON 兼容）", Width = 840, Height = 140, BackColor = CrmTheme.Surface, ForeColor = CrmTheme.Text, Padding = new Padding(14) };
            Button export = MakeButton("导出 JSON", CrmTheme.Green); export.Location = new Point(20, 30); export.Click += delegate { ExportJson(); };
            Button import = MakeButton("导入 JSON", CrmTheme.Orange); import.Location = new Point(140, 30); import.Click += delegate { ImportJson(); };
            Button folder = MakeButton("打开数据目录", CrmTheme.SurfaceSoft); folder.Location = new Point(260, 30); folder.Click += delegate { System.Diagnostics.Process.Start("explorer.exe", store.DataDirectory); };
            dataPathLabel = new Label { Text = store.DataFile, AutoSize = true, Location = new Point(20, 80), ForeColor = CrmTheme.Muted };
            backup.Controls.AddRange(new Control[] { export, import, folder, dataPathLabel });
            flow.Controls.AddRange(new Control[] { price, disguise, privacy, autoImport, backup }); page.Controls.Add(flow); return page;
        }

        private bool CheckAutomaticImport(bool force)
        {
            if (store.IsDisguiseActive) { if (autoImportStatusLabel != null) autoImportStatusLabel.Text = "全局伪装期间已暂停真实资料同步"; return true; }
            AutoImportResult result = autoImportService.Check(force);
            if (autoImportStatusLabel != null) autoImportStatusLabel.Text = DateTime.Now.ToString("HH:mm:ss") + "  " + result.Message;
            if (result.Changed) RefreshAll();
            ReviewOrderCandidates(result.OrderCandidates);
            return result.Success;
        }

        private bool RunScheduledAutomaticImport()
        {
            if (!autoImportService.Config.enabled) return true;
            if (store.IsDisguiseActive) return true;
            DateTime now = DateTime.Now;
            DateTime? due = null;
            DateTime morning = now.Date.AddHours(11);
            DateTime evening = now.Date.AddHours(20);
            if (now >= evening) due = evening;
            else if (now >= morning) due = morning;
            if (!due.HasValue) return true;
            string slot = due.Value.ToString("yyyy-MM-dd HH:mm");
            if (autoImportService.Config.lastScheduledSlot == slot) return true;
            if (CheckAutomaticImport(true))
            {
                autoImportService.Config.lastScheduledSlot = slot;
                autoImportService.SaveConfig();
                return true;
            }
            return false;
        }

        private void ScheduleAutomaticImportRetry()
        {
            autoImportTimer.Stop(); autoImportTimer.Interval = 10 * 60 * 1000; autoImportTimer.Start();
            if (autoImportStatusLabel != null) autoImportStatusLabel.Text += "　将在 10 分钟后重试";
        }

        private void ScheduleNextAutomaticImport()
        {
            autoImportTimer.Stop();
            if (!autoImportService.Config.enabled) return;
            DateTime now = DateTime.Now;
            DateTime next = now.Date.AddHours(11);
            if (now >= next) next = now.Date.AddHours(20);
            if (now >= next) next = now.Date.AddDays(1).AddHours(11);
            double milliseconds = Math.Max(1000, (next - now).TotalMilliseconds);
            autoImportTimer.Interval = (int)Math.Min(Int32.MaxValue, milliseconds);
            autoImportTimer.Start();
            if (autoImportStatusLabel != null && !autoImportStatusLabel.Text.Contains("检测完成"))
                autoImportStatusLabel.Text = "下次自动检测：" + next.ToString("yyyy-MM-dd HH:mm") + "　文件：" + autoImportService.Config.filePath;
        }

        private void RefreshAll()
        {
            if (polishedDashboard == null) return;
            for (int i = 0; i < moduleDirty.Length; i++) moduleDirty[i] = true;
            RefreshModuleIfNeeded(tabs == null ? 0 : tabs.SelectedIndex);
        }

        private void RefreshModuleIfNeeded(int index)
        {
            if (refreshingModule || index < 0 || index >= moduleDirty.Length || !moduleDirty[index]) return;
            refreshingModule = true;
            try
            {
                if (index == 0)
                {
                    int y = (int)year.Value, m = month.SelectedIndex + 1; bool monthly = !cumulative.Checked;
                    polishedDashboard.UpdateDashboard(store.Data.customers, store.Data.settings, monthly, y, m, Hidden("cost"), Hidden("revenue"), Hidden("roi"));
                }
                else if (index == 1) RefreshCustomers();
                else if (index == 2) RefreshAnalytics();
                else if (index == 3) RefreshAdvisors();
                moduleDirty[index] = false;
            }
            finally { refreshingModule = false; }
        }

        private void RefreshCustomers()
        {
            if (customerGrid == null) return; string q = customerSearch == null ? "" : customerSearch.Text.Trim();
            RefreshCustomerFilterOptions();
            string selectedChannel = customerChannelFilter == null || customerChannelFilter.SelectedIndex <= 0 ? null : Convert.ToString(customerChannelFilter.SelectedItem);
            string selectedAdvisor = customerAdvisorFilter == null || customerAdvisorFilter.SelectedIndex <= 0 ? null : Convert.ToString(customerAdvisorFilter.SelectedItem);
            string selectedOrderState = customerOrderFilter == null || customerOrderFilter.SelectedIndex < 0 ? "全部客户" : Convert.ToString(customerOrderFilter.SelectedItem);
            DataTable dt = new DataTable(); dt.Columns.Add("ID"); dt.Columns.Add("录入日期"); dt.Columns.Add("编号"); dt.Columns.Add("姓名"); dt.Columns.Add("电话"); dt.Columns.Add("归属顾问"); dt.Columns.Add("渠道");
            foreach (string orderType in CustomerOrderAmountColumns) dt.Columns.Add(orderType);
            int visibleCustomers = 0, visibleOrders = 0; double visibleRevenue = 0;
            foreach (Customer c in store.Data.customers.OrderByDescending(delegate(Customer x) { return x.importDate; }))
            {
                if (q.Length > 0 && !(c.name.Contains(q) || c.phone.Contains(q) || (c.customerNumber ?? "").Contains(q) || c.AdvisorDisplay.Contains(q))) continue;
                if (selectedChannel != null && !String.Equals(c.ChannelDisplay, selectedChannel, StringComparison.Ordinal)) continue;
                if (selectedAdvisor != null && !String.Equals(c.AdvisorDisplay, selectedAdvisor, StringComparison.Ordinal)) continue;
                List<ConversionRecord> validOrders = c.ValidConversions;
                if (selectedOrderState == "已开单" && validOrders.Count == 0) continue;
                if (selectedOrderState == "未开单" && validOrders.Count > 0) continue;
                List<object> values = new List<object> { c.id, c.importDate.ToString("yyyy-MM-dd"), c.customerNumber ?? "", c.name, Hidden("phone") ? "•••••••••••" : c.phone, c.AdvisorDisplay, c.ChannelDisplay };
                foreach (string orderType in CustomerOrderAmountColumns)
                {
                    List<ConversionRecord> matching = validOrders.Where(delegate(ConversionRecord r) { return r.type == orderType; }).ToList();
                    values.Add(Hidden("revenue") ? "—" : (matching.Count == 0 ? "—" : Money(matching.Sum(delegate(ConversionRecord r) { return r.amount; }))));
                }
                dt.Rows.Add(values.ToArray());
                visibleCustomers++; visibleOrders += validOrders.Count; visibleRevenue += validOrders.Sum(delegate(ConversionRecord r) { return r.amount; });
            }
            customerGrid.DataSource = dt; HideId(customerGrid); ConfigureCustomerGridColumns(); ApplyCustomerDateGroups();
            if (customerFilterSummary != null) customerFilterSummary.Text = "当前 " + visibleCustomers + " 位客户 · " + visibleOrders + " 笔有效订单" + (Hidden("revenue") ? "" : " · 业绩 " + Money(visibleRevenue));
        }

        private void RefreshCustomerFilterOptions()
        {
            if (customerChannelFilter == null || customerAdvisorFilter == null) return;
            List<string> channels = store.Data.customers.Select(delegate(Customer c) { return c.ChannelDisplay; }).Where(delegate(string x) { return !String.IsNullOrWhiteSpace(x); }).Distinct().OrderBy(delegate(string x) { return x; }).ToList();
            List<string> advisors = store.Data.customers.Select(delegate(Customer c) { return c.AdvisorDisplay; }).Where(delegate(string x) { return !String.IsNullOrWhiteSpace(x); }).Distinct().OrderBy(delegate(string x) { return x; }).ToList();
            List<string> desiredChannels = new List<string> { "全部渠道" }; desiredChannels.AddRange(channels);
            List<string> desiredAdvisors = new List<string> { "全部顾问" }; desiredAdvisors.AddRange(advisors);
            updatingCustomerFilters = true;
            try
            {
                UpdateCustomerFilterItems(customerChannelFilter, desiredChannels);
                UpdateCustomerFilterItems(customerAdvisorFilter, desiredAdvisors);
            }
            finally { updatingCustomerFilters = false; }
        }

        private static void UpdateCustomerFilterItems(ComboBox filter, List<string> desired)
        {
            bool same = filter.Items.Count == desired.Count;
            if (same) for (int i = 0; i < desired.Count; i++) if (!String.Equals(Convert.ToString(filter.Items[i]), desired[i], StringComparison.Ordinal)) { same = false; break; }
            if (same) return;
            string previous = Convert.ToString(filter.SelectedItem);
            filter.BeginUpdate(); filter.Items.Clear(); filter.Items.AddRange(desired.Cast<object>().ToArray()); filter.EndUpdate();
            int index = desired.IndexOf(previous); filter.SelectedIndex = index >= 0 ? index : 0;
        }

        private void ConfigureCustomerGridColumns()
        {
            customerGrid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None;
            Dictionary<string, int> widths = new Dictionary<string, int> { { "录入日期", 112 }, { "编号", 82 }, { "姓名", 105 }, { "电话", 125 }, { "归属顾问", 95 }, { "渠道", 82 } };
            foreach (DataGridViewColumn column in customerGrid.Columns)
            {
                column.Frozen = false;
                int width; column.Width = widths.TryGetValue(column.Name, out width) ? width : 92;
                column.SortMode = DataGridViewColumnSortMode.NotSortable;
            }
            string[] ordered = new string[] { "ID", "录入日期", "编号", "姓名", "电话", "归属顾问", "渠道", "新单", "二次", "三次", "四次", "五次", "六次", "七次", "八次", "多次" };
            for (int i = 0; i < ordered.Length; i++) if (customerGrid.Columns.Contains(ordered[i])) customerGrid.Columns[ordered[i]].DisplayIndex = i;
            foreach (string frozen in new string[] { "ID", "录入日期", "编号", "姓名" }) if (customerGrid.Columns.Contains(frozen)) customerGrid.Columns[frozen].Frozen = true;
        }

        private void ApplyCustomerDateGroups()
        {
            string previousDate = null; bool blueGroup = false;
            for (int i = 0; i < customerGrid.Rows.Count; i++)
            {
                DataGridViewRow row = customerGrid.Rows[i]; string date = Convert.ToString(row.Cells["录入日期"].Value);
                if (date != previousDate) { blueGroup = !blueGroup; if (i > 0) customerGrid.Rows[i - 1].DividerHeight = 5; previousDate = date; }
                row.Height = 35;
                row.DefaultCellStyle.BackColor = blueGroup ? Color.FromArgb(247, 250, 255) : Color.White;
                row.DefaultCellStyle.SelectionBackColor = Color.FromArgb(35, 126, 219);
            }
            if (customerGrid.Rows.Count > 0) customerGrid.Rows[customerGrid.Rows.Count - 1].DividerHeight = 5;
        }

        private void StartOneClickSync()
        {
            if (oneClickSyncRunning) return;
            if (store.IsDisguiseActive) { MessageBox.Show("全局伪装期间不会同步或改动真实资料。请先在系统设置中解除伪装。", "同步已暂停", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            string script = ResolveSyncScript();
            if (String.IsNullOrWhiteSpace(script))
            {
                MessageBox.Show("未找到同步脚本。可将 update_wechat_tables.ps1 放在软件 Scripts 目录、文档\\表格目录，或设置 PRIVATE_CRM_SYNC_SCRIPT 环境变量。", "无法同步", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            oneClickSyncRunning = true;
            oneClickSyncButton.Enabled = false;
            oneClickSyncButton.Text = "同步中…";
            oneClickSyncStatusLabel.Text = "正在扫描并更新 CRM 资料，通常需要约 30 秒";

            System.Threading.ThreadPool.QueueUserWorkItem(delegate
            {
                int exitCode = -1; string error = null;
                try
                {
                    string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
                    ProcessStartInfo info = new ProcessStartInfo
                    {
                        FileName = powershell,
                        Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -CRMOnly",
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        WindowStyle = ProcessWindowStyle.Hidden
                    };
                    using (Process process = Process.Start(info)) { process.WaitForExit(); exitCode = process.ExitCode; }
                }
                catch (Exception ex) { error = ex.Message; }

                if (IsDisposed || !IsHandleCreated) return;
                BeginInvoke((MethodInvoker)delegate
                {
                    try
                    {
                        if (exitCode == 0 && error == null)
                        {
                            AutoImportResult result = autoImportService.Check(true);
                            if (result.Success)
                            {
                                RefreshAll();
                                ReviewOrderCandidates(result.OrderCandidates);
                                string summary = "同步完成：新增 " + result.Added + "，补全 " + result.Completed + "，已存在/已处理 " + result.Skipped;
                                oneClickSyncStatusLabel.Text = summary;
                                if (autoImportStatusLabel != null) autoImportStatusLabel.Text = DateTime.Now.ToString("HH:mm:ss") + "  " + summary;
                                MessageBox.Show(summary, "一键同步完成", MessageBoxButtons.OK, MessageBoxIcon.Information);
                            }
                            else
                            {
                                oneClickSyncStatusLabel.Text = "资料更新完成，但导入失败";
                                MessageBox.Show(result.Message, "CRM 导入失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            }
                        }
                        else
                        {
                            string log = Path.Combine(Path.GetDirectoryName(script), "update_log.txt");
                            string message = "同步任务执行失败" + (error == null ? "（退出代码 " + exitCode + "）" : "：" + error) + "\n请查看日志：\n" + log;
                            oneClickSyncStatusLabel.Text = "同步失败，请查看更新日志";
                            MessageBox.Show(message, "一键同步失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        }
                    }
                    finally
                    {
                        oneClickSyncRunning = false;
                        oneClickSyncButton.Enabled = true;
                        oneClickSyncButton.Text = "一键同步资料";
                    }
                });
            });
        }

        private static string ResolveSyncScript()
        {
            string configured = Environment.GetEnvironmentVariable("PRIVATE_CRM_SYNC_SCRIPT");
            string[] candidates = {
                configured,
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Scripts", "update_wechat_tables.ps1"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "表格", "update_wechat_tables.ps1")
            };
            foreach (string path in candidates) if (!String.IsNullOrWhiteSpace(path) && File.Exists(path)) return path;
            return null;
        }

        private void RefreshAnalytics()
        {
            if (channelGrid == null) return; int y = (int)year.Value, m = month.SelectedIndex + 1; bool monthly = !cumulative.Checked;
            DataTable roi = new DataTable(); roi.Columns.Add("月份"); roi.Columns.Add("派发成本"); roi.Columns.Add("漏斗业绩"); roi.Columns.Add("ROI"); roi.Columns.Add("盈亏状态");
            DateTime cursor = new DateTime(y, m, 1);
            for (int i = 5; i >= 0; i--)
            {
                DateTime d = cursor.AddMonths(-i); PeriodStats s = StatisticsEngine.Summary(store.Data.customers, true, d.Year, d.Month);
                roi.Rows.Add(d.ToString("yyyy年M月"), Money(s.Cost), Money(s.FunnelRevenue), s.Cost > 0 ? s.Roi.ToString("0.00") : "—", s.Cost <= 0 ? "暂无成本" : (s.Roi >= 1 ? "盈利" : "亏损"));
            }
            roiGrid.DataSource = roi;
            DataTable ch = new DataTable(); ch.Columns.Add("渠道"); ch.Columns.Add("线索"); ch.Columns.Add("新单率"); ch.Columns.Add("复购率"); if (!Hidden("revenue") && store.Data.settings.channelRevenueVisible) ch.Columns.Add("营业额");
            foreach (ChannelStat s in StatisticsEngine.Channels(store.Data.customers, monthly, y, m))
            {
                List<object> values = new List<object>(); values.Add(s.Channel); values.Add(s.Leads); values.Add(s.Leads > 0 ? ((double)s.NewOrders / s.Leads).ToString("P0") : "—"); values.Add(s.NewOrders > 0 ? ((double)s.Seconds / s.NewOrders).ToString("P0") : "—"); if (ch.Columns.Contains("营业额")) values.Add(Money(s.Revenue)); ch.Rows.Add(values.ToArray());
            }
            channelGrid.DataSource = ch;
            Dictionary<string, int> regions = new Dictionary<string, int>(); foreach (Customer c in store.Data.customers.Where(delegate(Customer x) { return x.dataType == "fullCustomer"; })) { string r = StatisticsEngine.Region(c.address); if (!regions.ContainsKey(r)) regions[r] = 0; regions[r]++; }
            DataTable profile = new DataTable(); profile.Columns.Add("分类"); profile.Columns.Add("项目"); profile.Columns.Add("人数"); profile.Columns.Add("占比"); int total = regions.Values.Sum(); foreach (var pair in regions.OrderByDescending(delegate(KeyValuePair<string, int> x) { return x.Value; })) profile.Rows.Add("地域", pair.Key, pair.Value, total > 0 ? ((double)pair.Value / total).ToString("P1") : "—");
            AddBands(profile, "年龄", store.Data.customers.Where(delegate(Customer c) { return c.age.HasValue; }).Select(delegate(Customer c) { return (double)c.age.Value; }).ToList(), new double[] { 0, 20, 30, 40, 121 }, new string[] { "20岁以下", "20-29岁", "30-39岁", "40岁以上" });
            AddBands(profile, "线索金额", store.Data.customers.Where(delegate(Customer c) { return c.leadAmount.HasValue; }).Select(delegate(Customer c) { return c.leadAmount.Value; }).ToList(), new double[] { 0, 301, 501, Double.MaxValue }, new string[] { "300元以内", "301-500元", "500元以上" }); regionGrid.DataSource = profile;
            SetAnalysisHeight(roiGrid, roi.Rows.Count);
            SetAnalysisHeight(channelGrid, ch.Rows.Count);
            SetAnalysisHeight(regionGrid, profile.Rows.Count);
        }

        private static void SetAnalysisHeight(DataGridView grid, int rowCount)
        {
            if (grid.Parent == null) return;
            int gridHeight = grid.ColumnHeadersHeight + Math.Max(1, rowCount) * 35 + 6;
            grid.Parent.Height = 84 + gridHeight;
        }

        private void ReviewOrderCandidates(List<ShipmentOrderCandidate> candidates)
        {
            if (candidates == null || candidates.Count == 0) return;
            foreach (ShipmentOrderCandidate candidate in candidates)
            {
                string detail = candidate.Customer.name + "（" + candidate.Customer.phone + "）\n快递单号：" + (candidate.Source.Tracking ?? "未提供") + "\n发货金额：" + Money(candidate.Source.Amount.GetValueOrDefault()) + "\n发货日期：" + candidate.Source.Date.ToString("yyyy-MM-dd") + "\n\n是否为该客户创建订单？\n\n是：打开订单编辑，可补录金额和顾问\n否：永久忽略此快递单，以后不再提醒\n取消：暂不处理，下次同步继续提醒";
                DialogResult answer = MessageBox.Show(detail, "检测到新发货数据", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                if (answer == DialogResult.Cancel) break;
                if (answer == DialogResult.No) { autoImportService.MarkProcessed(candidate.SourceKey); continue; }
                ConversionRecord record = new ConversionRecord { type = candidate.Customer.ValidConversions.Count == 0 ? "新单" : "二次", amount = candidate.Source.Amount.GetValueOrDefault(), date = candidate.Source.Date, productNote = candidate.Source.Product, trackingNumber = candidate.Source.Tracking, note = candidate.Source.Note };
                using (ConversionForm form = new ConversionForm(record, store.ActiveAdvisorNames(), candidate.Customer))
                {
                    if (form.ShowDialog(this) != DialogResult.OK) continue;
                    candidate.Customer.conversions.Add(record); autoImportService.MarkProcessed(candidate.SourceKey); store.Save();
                }
            }
            RefreshAll();
        }

        private void RefreshAdvisors()
        {
            if (advisorGrid == null) return; int y = (int)year.Value, m = month.SelectedIndex + 1; bool monthly = !cumulative.Checked;
            List<AdvisorStat> stats = StatisticsEngine.Advisors(store.Data.customers, store.Data.settings, monthly, y, m);
            DataTable dt = new DataTable(); dt.Columns.Add("小组"); dt.Columns.Add("角色"); dt.Columns.Add("顾问"); dt.Columns.Add("派发"); dt.Columns.Add("新单"); dt.Columns.Add("成交率"); dt.Columns.Add("二次"); dt.Columns.Add("业绩"); dt.Columns.Add("ROI"); dt.Columns.Add("15天未成交");
            Dictionary<string, AdvisorStat> statByName = stats.ToDictionary(delegate(AdvisorStat s) { return s.Name; }, delegate(AdvisorStat s) { return s; });
            List<string> groups = store.Data.settings.advisorProfiles.Where(delegate(AdvisorProfile p) { return !String.IsNullOrWhiteSpace(p.groupName) && !store.Data.settings.inactiveAdvisors.Contains(p.name); }).Select(delegate(AdvisorProfile p) { return p.groupName; }).Distinct().OrderBy(delegate(string g) { return g; }).ToList();
            foreach (string group in groups)
            {
                List<AdvisorProfile> members = store.Data.settings.advisorProfiles.Where(delegate(AdvisorProfile p) { return p.groupName == group && !store.Data.settings.inactiveAdvisors.Contains(p.name); }).ToList();
                List<AdvisorStat> memberStats = members.Where(delegate(AdvisorProfile p) { return statByName.ContainsKey(p.name); }).Select(delegate(AdvisorProfile p) { return statByName[p.name]; }).ToList();
                List<AdvisorStat> roiMembers = members.Where(delegate(AdvisorProfile p) { return p.role != "组长" && statByName.ContainsKey(p.name); }).Select(delegate(AdvisorProfile p) { return statByName[p.name]; }).ToList();
                int groupLeads = roiMembers.Sum(delegate(AdvisorStat s) { return s.Leads; }); double groupCost = roiMembers.Sum(delegate(AdvisorStat s) { return s.Cost; });
                int groupNew = roiMembers.Sum(delegate(AdvisorStat s) { return s.NewOrders; }); int groupSeconds = memberStats.Sum(delegate(AdvisorStat s) { return s.Seconds; }); double groupRevenue = memberStats.Sum(delegate(AdvisorStat s) { return s.Revenue; });
                string leaders = String.Join("、", members.Where(delegate(AdvisorProfile p) { return p.role == "组长"; }).Select(delegate(AdvisorProfile p) { return p.name; }).ToArray());
                dt.Rows.Add(group, "小组合计", leaders.Length == 0 ? "未设置组长" : "组长：" + leaders, groupLeads, groupNew, groupLeads > 0 ? ((double)groupNew / groupLeads).ToString("P0") : "—", groupSeconds, Hidden("revenue") ? "—" : Money(groupRevenue), Hidden("roi") ? "—" : (groupCost > 0 ? (groupRevenue / groupCost).ToString("0.00") : "—"), memberStats.Sum(delegate(AdvisorStat s) { return s.Pending; }));
                foreach (AdvisorProfile p in members.OrderBy(delegate(AdvisorProfile p) { return p.role == "组长" ? 0 : 1; }).ThenBy(delegate(AdvisorProfile p) { return p.name; }))
                    if (statByName.ContainsKey(p.name)) AddAdvisorRow(dt, statByName[p.name], p);
            }
            foreach (AdvisorStat s in stats.Where(delegate(AdvisorStat s) { return !s.IsInactive && !store.Data.settings.advisorProfiles.Exists(delegate(AdvisorProfile p) { return p.name == s.Name && !String.IsNullOrWhiteSpace(p.groupName); }); }))
                AddAdvisorRow(dt, s, store.Data.settings.advisorProfiles.Find(delegate(AdvisorProfile p) { return p.name == s.Name; }) ?? new AdvisorProfile { name = s.Name });
            foreach (AdvisorStat s in stats.Where(delegate(AdvisorStat s) { return s.IsInactive; })) AddAdvisorRow(dt, s, new AdvisorProfile { name = s.Name, role = "已离职", groupName = "历史顾问" });
            advisorGrid.DataSource = dt;
            foreach (DataGridViewRow row in advisorGrid.Rows) if (Convert.ToString(row.Cells["角色"].Value) == "小组合计") { row.DefaultCellStyle.BackColor = Color.FromArgb(232, 239, 253); row.DefaultCellStyle.Font = CrmTheme.Font(9F, FontStyle.Bold); row.DividerHeight = 2; }
            DataTable profiles = new DataTable(); profiles.Columns.Add("顾问"); profiles.Columns.Add("角色"); profiles.Columns.Add("小组"); foreach (AdvisorProfile p in store.Data.settings.advisorProfiles) profiles.Rows.Add(p.name, p.role, String.IsNullOrWhiteSpace(p.groupName) ? "未分组" : p.groupName); profileGrid.DataSource = profiles;
        }

        private void AddAdvisorRow(DataTable dt, AdvisorStat s, AdvisorProfile p)
        {
            dt.Rows.Add(s.IsInactive ? "历史顾问" : (String.IsNullOrWhiteSpace(p.groupName) ? "未分组" : p.groupName), s.IsInactive ? "已离职" : p.role, s.Name, s.Leads, s.NewOrders, s.Leads > 0 ? ((double)s.NewOrders / s.Leads).ToString("P0") : "—", s.Seconds, Hidden("revenue") ? "—" : Money(s.Revenue), Hidden("roi") ? "—" : (s.Cost > 0 ? s.Roi.ToString("0.00") : "—"), s.Pending);
        }

        private void ShowDashboardDetail(string key)
        {
            int y = (int)year.Value, m = month.SelectedIndex + 1; bool monthly = !cumulative.Checked;
            DataTable dt = new DataTable(); dt.Columns.Add("客户编号"); dt.Columns.Add("日期"); dt.Columns.Add("类别"); dt.Columns.Add("客户"); dt.Columns.Add("归属顾问"); dt.Columns.Add("金额 / 状态"); dt.Columns.Add("快递单号"); dt.Columns.Add("客户ID"); dt.Columns.Add("订单ID");
            string title = "明细";
            string selectedChannel = null;
            if (key.StartsWith("channel:", StringComparison.Ordinal)) selectedChannel = key.Substring("channel:".Length);
            foreach (Customer c in store.Data.customers.OrderByDescending(delegate(Customer x) { return x.importDate; }))
            {
                bool leadInPeriod = !monthly || StatisticsEngine.InMonth(c.importDate, y, m);
                bool funnel = c.dataType == "fullCustomer" && c.costEnabled && c.followUpTag != "已失去价值";
                if ((key == "roi" || key == "cost") && funnel && leadInPeriod) dt.Rows.Add(c.customerNumber ?? "", c.importDate.ToString("yyyy-MM-dd"), "派发资料", c.name, c.AdvisorDisplay, Money(c.lineCost), "", c.id, "");
                if (key == "newrate" && funnel && leadInPeriod && c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单" && (!monthly || StatisticsEngine.InMonth(r.date, y, m)); })) dt.Rows.Add(c.customerNumber ?? "", c.importDate.ToString("yyyy-MM-dd"), "新单客户", c.name, c.AdvisorDisplay, "已成交", "", c.id, "");
                if (key == "followup")
                {
                    bool noNew = funnel && !c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单"; });
                    bool noSecond = c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单"; }) && !c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "二次"; }) && !store.Data.settings.dismissedPendingSecondCustomerIDs.Contains(c.id);
                    if (noNew || noSecond) dt.Rows.Add(c.customerNumber ?? "", c.importDate.ToString("yyyy-MM-dd"), noNew ? "暂未成交新单" : "暂未成交二次", c.name, c.AdvisorDisplay, noNew ? "待跟进" : "待复购", "", c.id, "");
                }
                if ((key == "channel" || selectedChannel != null) && c.dataType == "fullCustomer" && leadInPeriod && (selectedChannel == null || String.Equals(c.ChannelDisplay, selectedChannel, StringComparison.Ordinal))) dt.Rows.Add(c.customerNumber ?? "", c.importDate.ToString("yyyy-MM-dd"), c.ChannelDisplay, c.name, c.AdvisorDisplay, c.ValidConversions.Count + " 笔订单", "", c.id, "");
                foreach (ConversionRecord r in c.ValidConversions)
                {
                    if (monthly && !StatisticsEngine.InMonth(r.date, y, m)) continue;
                    if (key == "revenue" || key == "funnel" || key == "daily") dt.Rows.Add(c.customerNumber ?? "", r.date.ToString("yyyy-MM-dd"), r.type, c.name, c.AdvisorDisplay, Money(r.amount), r.trackingNumber ?? "", c.id, r.id);
                }
                if (key == "daily" && leadInPeriod && funnel) dt.Rows.Add(c.customerNumber ?? "", c.importDate.ToString("yyyy-MM-dd"), "资料录入", c.name, c.AdvisorDisplay, "资料 1 份", "", c.id, "");
            }
            if (key == "roi") title = "ROI 漏斗资料明细"; else if (key == "cost") title = "资料成本明细"; else if (key == "revenue") title = "营业额订单明细"; else if (key == "newrate") title = "新单成交客户明细"; else if (key == "followup") title = "待跟进客户明细"; else if (key == "funnel") title = "销售漏斗订单明细"; else if (key == "daily") title = "每日审阅明细"; else if (selectedChannel != null) title = selectedChannel + "渠道客户明细"; else if (key == "channel") title = "渠道客户明细";
            using (Form form = new Form { Text = title, Width = 1050, Height = 680, StartPosition = FormStartPosition.CenterParent, Font = Font, BackColor = CrmTheme.Ground, ForeColor = CrmTheme.Text })
            {
                DataGridView grid = MakeGrid(); grid.DataSource = dt;
                Action editSelected = delegate
                {
                    if (grid.CurrentRow == null) return;
                    if (!grid.Columns.Contains("客户ID") || !grid.Columns.Contains("订单ID")) return;
                    string customerId = Convert.ToString(grid.CurrentRow.Cells["客户ID"].Value), orderId = Convert.ToString(grid.CurrentRow.Cells["订单ID"].Value);
                    Customer customer = store.Data.customers.Find(delegate(Customer c) { return c.id == customerId; }); if (customer == null) return;
                    if (String.IsNullOrWhiteSpace(orderId)) { EditCustomer(customer); form.Close(); return; }
                    ConversionRecord order = customer.conversions.Find(delegate(ConversionRecord r) { return r.id == orderId; }); if (order == null) return;
                    using (ConversionForm editor = new ConversionForm(order, store.ActiveAdvisorNames(), customer)) if (editor.ShowDialog(form) == DialogResult.OK) { store.Save(); RefreshAll(); form.Close(); }
                };
                grid.CellDoubleClick += delegate { editSelected(); };
                Panel tools = new Panel { Dock = DockStyle.Top, Height = 52, BackColor = CrmTheme.SurfaceRaised };
                Label hint = new Label { Text = "共 " + dt.Rows.Count + " 条　双击订单可编辑金额、日期、分配和快递单号", AutoSize = true, Location = new Point(14, 17), ForeColor = CrmTheme.Muted };
                Button edit = MakeButton("编辑所选订单", CrmTheme.Blue); edit.Location = new Point(520, 8); edit.Click += delegate { editSelected(); };
                Button copyTracking = MakeButton("复制快递单号", CrmTheme.Lilac); copyTracking.Location = new Point(660, 8); copyTracking.Click += delegate { if (grid.CurrentRow == null) return; string tracking = Convert.ToString(grid.CurrentRow.Cells["快递单号"].Value); if (String.IsNullOrWhiteSpace(tracking)) { MessageBox.Show("该订单没有快递单号。", "提示"); return; } Clipboard.SetText(tracking); MessageBox.Show("快递单号已复制：" + tracking, "复制成功"); };
                Button deleteOrder = MakeButton("删除所选订单", Color.Firebrick); deleteOrder.Location = new Point(800, 8); deleteOrder.Click += delegate
                {
                    if (grid.CurrentRow == null) return; string customerId = Convert.ToString(grid.CurrentRow.Cells["客户ID"].Value), orderId = Convert.ToString(grid.CurrentRow.Cells["订单ID"].Value);
                    if (String.IsNullOrWhiteSpace(orderId)) { MessageBox.Show("当前行不是订单记录。", "提示"); return; }
                    Customer customer = store.Data.customers.Find(delegate(Customer c) { return c.id == customerId; }); ConversionRecord order = customer == null ? null : customer.conversions.Find(delegate(ConversionRecord r) { return r.id == orderId; }); if (order == null) return;
                    if (MessageBox.Show("只删除“" + customer.name + "”的这笔 " + order.type + " 订单。\n客户资料及其他订单不会删除，业绩会立即重算。确定吗？", "确认删除单笔订单", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
                    customer.conversions.Remove(order); store.Save(); RefreshAll(); form.Close();
                };
                tools.Controls.AddRange(new Control[] { hint, edit, copyTracking, deleteOrder }); form.Controls.Add(grid); form.Controls.Add(tools);
                form.Load += delegate { if (grid.Columns.Contains("客户ID")) grid.Columns["客户ID"].Visible = false; if (grid.Columns.Contains("订单ID")) grid.Columns["订单ID"].Visible = false; };
                if (suppressAutomation) form.Shown += delegate { form.BeginInvoke((MethodInvoker)delegate { form.Close(); }); };
                form.ShowDialog(this);
            }
        }

        private void ParseSmart()
        {
            smartRows = SmartPasteParser.Parse(smartText.Text); DataTable dt = new DataTable(); dt.Columns.Add("导入", typeof(bool)); dt.Columns.Add("姓名"); dt.Columns.Add("电话"); dt.Columns.Add("地址"); dt.Columns.Add("线索金额"); dt.Columns.Add("身高"); dt.Columns.Add("体重"); dt.Columns.Add("年龄"); dt.Columns.Add("编号"); dt.Columns.Add("渠道"); dt.Columns.Add("顾问"); dt.Columns.Add("日期"); dt.Columns.Add("状态");
            foreach (ParsedCustomer r in smartRows) dt.Rows.Add(r.Selected, r.Name, r.Phone, r.Address, r.LeadAmount, r.Height, r.Weight, r.Age, r.CustomerNumber, r.Channel, r.Advisor, r.ImportDate.ToString("yyyy-MM-dd"), r.NeedsReview ? "需要核实" : "正常"); smartGrid.DataSource = dt;
        }

        private void ImportSmart()
        {
            if (smartGrid.DataSource == null) ParseSmart(); SyncSmartGrid(); int added = 0, merged = 0;
            foreach (ParsedCustomer r in smartRows.Where(delegate(ParsedCustomer x) { return x.Selected; }))
            {
                Customer existing = store.Data.customers.Find(delegate(Customer c) { return !String.IsNullOrWhiteSpace(r.Phone) && c.phone == r.Phone; });
                if (existing != null)
                {
                    DialogResult choice = MessageBox.Show(r.Name + "（" + r.Phone + "）已存在。\n是：补充资料并保留订单\n否：跳过", "重复客户", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                    if (choice == DialogResult.Cancel) return; if (choice == DialogResult.No) continue;
                    if (!String.IsNullOrWhiteSpace(r.Address)) existing.address = r.Address; existing.height = r.Height ?? existing.height; existing.weight = r.Weight ?? existing.weight; existing.age = r.Age ?? existing.age; existing.leadAmount = r.LeadAmount ?? existing.leadAmount; if (!String.IsNullOrWhiteSpace(r.Advisor)) existing.advisor = r.Advisor; merged++; continue;
                }
                Customer newCustomer = new Customer { name = r.Name ?? "待补录", phone = r.Phone ?? "", address = r.Address, age = r.Age, height = r.Height, weight = r.Weight, customerNumber = r.CustomerNumber, leadAmount = r.LeadAmount, costEnabled = true, lineCost = store.Data.settings.leadUnitPrice, importDate = r.ImportDate, channel = r.Channel, advisor = String.IsNullOrWhiteSpace(r.Advisor) ? null : r.Advisor, roiAdvisor = String.IsNullOrWhiteSpace(r.Advisor) ? null : r.Advisor };
                store.Data.customers.Add(newCustomer); added++;
            }
            store.Data.batches.Add(new ImportBatch { source = "Windows智能导入", recordCount = added + merged, fullCustomerCount = added }); store.Save(); RefreshAll(); MessageBox.Show("导入完成：新增 " + added + "，合并 " + merged, "完成");
        }

        private void SyncSmartGrid()
        {
            if (smartGrid.DataSource == null) return; DataTable dt = (DataTable)smartGrid.DataSource;
            for (int i = 0; i < dt.Rows.Count && i < smartRows.Count; i++)
            {
                DataRow x = dt.Rows[i]; ParsedCustomer r = smartRows[i]; r.Selected = ToBool(x["导入"]); r.Name = ToText(x["姓名"]); r.Phone = ToText(x["电话"]); r.Address = ToText(x["地址"]); r.LeadAmount = ToNullableDouble(x["线索金额"]); r.Height = ToNullableDouble(x["身高"]); r.Weight = ToNullableDouble(x["体重"]); r.Age = ToNullableInt(x["年龄"]); r.CustomerNumber = ToText(x["编号"]); r.Channel = ToText(x["渠道"]); r.Advisor = ToText(x["顾问"]); DateTime d; if (DateTime.TryParse(ToText(x["日期"]), out d)) r.ImportDate = d;
            }
        }

        private void ParseLedger()
        {
            ledgerRows = LedgerParser.Parse(ledgerText.Text); DataTable dt = new DataTable(); dt.Columns.Add("导入", typeof(bool)); dt.Columns.Add("编号"); dt.Columns.Add("姓名"); dt.Columns.Add("次数"); dt.Columns.Add("金额"); dt.Columns.Add("开单日期"); dt.Columns.Add("分配"); dt.Columns.Add("匹配状态");
            foreach (LedgerItem r in ledgerRows) { Customer c = store.FindCustomer(r.CustomerNumber, r.Name); int matches = store.CustomerNumberMatchCount(r.CustomerNumber); r.MatchedCustomerId = c == null ? null : c.id; string status = matches > 1 && c == null ? "编号重复，需人工选择" : (c == null ? "待确认" : "已匹配 " + c.name); dt.Rows.Add(true, r.CustomerNumber, c == null ? r.Name : c.name, r.Type, r.Amount, r.Date.ToString("yyyy-MM-dd"), "未分配", status); } ledgerGrid.DataSource = dt;
        }

        private void ImportLedger()
        {
            if (ledgerRows.Count == 0) ParseLedger(); int saved = 0;
            foreach (LedgerItem item in ledgerRows)
            {
                Customer suggested = store.FindCustomer(item.CustomerNumber, item.Name);
                using (LedgerConfirmForm form = new LedgerConfirmForm(store, item, suggested))
                {
                    if (form.ShowDialog(this) != DialogResult.OK) continue;
                    Customer customer = form.SelectedCustomer;
                    if (customer == null)
                    {
                        customer = new Customer { dataType = "ledgerEntry", name = String.IsNullOrWhiteSpace(item.Name) ? ("编号" + item.CustomerNumber) : item.Name, phone = "", customerNumber = item.CustomerNumber, costEnabled = false, lineCost = 0, importDate = item.Date };
                        store.Data.customers.Add(customer);
                    }
                    ConversionRecord record = new ConversionRecord { type = item.Type, amount = item.Amount, date = item.Date };
                    if (!String.IsNullOrWhiteSpace(item.Advisor1)) record.advisorSplits.Add(new AdvisorSplit { name = item.Advisor1, ratio = String.IsNullOrWhiteSpace(item.Advisor2) ? 1 : 0.5 });
                    if (!String.IsNullOrWhiteSpace(item.Advisor2)) record.advisorSplits.Add(new AdvisorSplit { name = item.Advisor2, ratio = 0.5 });
                    customer.conversions.Add(record); saved++;
                }
            }
            store.Save(); RefreshAll(); MessageBox.Show("已保存 " + saved + " 笔订单。", "流水导入完成");
        }

        private void EditCustomer(Customer customer)
        {
            bool isNew = customer == null; Customer target = customer ?? new Customer { lineCost = store.Data.settings.leadUnitPrice };
            using (CustomerForm form = new CustomerForm(store, target)) if (form.ShowDialog(this) == DialogResult.OK) { if (isNew) store.Data.customers.Add(target); store.Save(); RefreshAll(); }
        }
        private Customer SelectedCustomer() { if (customerGrid.CurrentRow == null) return null; string id = Convert.ToString(customerGrid.CurrentRow.Cells["ID"].Value); return store.Data.customers.Find(delegate(Customer c) { return c.id == id; }); }
        private void EditSelectedCustomer() { Customer c = SelectedCustomer(); if (c != null) EditCustomer(c); }
        private void DeleteSelectedCustomer() { Customer c = SelectedCustomer(); if (c != null && MessageBox.Show("删除客户会同时删除其订单与业绩，确定删除“" + c.name + "”？", "确认删除", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes) { store.Data.customers.Remove(c); store.Save(); RefreshAll(); } }
        private void CopySelectedCustomer() { Customer c = SelectedCustomer(); if (c != null) { Clipboard.SetText(CustomerText(c)); MessageBox.Show("客户全部资料已复制。", "复制成功"); } }
        private void CopySelectedCustomerField(string field)
        {
            Customer c = SelectedCustomer(); if (c == null) return;
            string value = field == "姓名" ? c.name : (field == "电话" ? c.phone : c.customerNumber);
            if (String.IsNullOrWhiteSpace(value)) { MessageBox.Show("该客户尚未录入" + field + "。", "无法复制", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            Clipboard.SetText(value.Trim());
        }

        private string CustomerText(Customer c)
        {
            StringBuilder b = new StringBuilder(); b.AppendLine("【基础资料】"); b.AppendLine("姓名：" + c.name); b.AppendLine("编号：" + (c.customerNumber ?? "未录入")); b.AppendLine("电话：" + c.phone); b.AppendLine("地址：" + (c.address ?? "未录入")); b.AppendLine("年龄/身高/体重：" + (c.age.HasValue ? c.age + "岁" : "-") + " / " + (c.height.HasValue ? c.height + "cm" : "-") + " / " + (c.weight.HasValue ? c.weight + "kg" : "-")); b.AppendLine(); b.AppendLine("【归属与录入】"); b.AppendLine("归属顾问：" + c.AdvisorDisplay); b.AppendLine("渠道：" + c.ChannelDisplay); b.AppendLine("线索金额：" + (c.leadAmount.HasValue ? Money(c.leadAmount.Value) : "未录入")); b.AppendLine("录入日期：" + c.importDate.ToString("yyyy-MM-dd")); b.AppendLine(); b.AppendLine("【成交记录】"); int i = 1; foreach (ConversionRecord r in c.conversions.OrderBy(delegate(ConversionRecord x) { return x.date; })) { b.AppendLine(i++ + ". " + r.date.ToString("yyyy-MM-dd") + "  " + r.type + "  " + Money(r.amount) + (r.isVoided ? "  [已作废]" : "")); if (!String.IsNullOrWhiteSpace(r.trackingNumber)) b.AppendLine("   快递单号：" + r.trackingNumber); b.AppendLine("   顾问分配：" + (r.advisorSplits.Count == 0 ? "未分配" : String.Join(" + ", r.advisorSplits.Select(delegate(AdvisorSplit x) { return x.Display; }).ToArray()))); } b.AppendLine(); b.AppendLine("【汇总】有效业绩：" + Money(c.TotalRevenue)); return b.ToString();
        }

        private void EditAdvisor(AdvisorProfile profile)
        {
            bool isNew = profile == null; AdvisorProfile p = profile ?? new AdvisorProfile(); string oldName = p.name; string oldRole = p.role; string oldGroup = p.groupName;
            using (AdvisorForm form = new AdvisorForm(p, store.Data.settings.advisorGroups)) if (form.ShowDialog(this) == DialogResult.OK)
            {
                bool duplicate = store.Data.settings.advisorProfiles.Exists(delegate(AdvisorProfile x) { return !Object.ReferenceEquals(x, p) && x.name == p.name; });
                if (duplicate) { p.name = oldName; p.role = oldRole; p.groupName = oldGroup; MessageBox.Show("顾问姓名已存在，请使用不同姓名。", "无法保存", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                if (isNew)
                {
                    store.Data.settings.inactiveAdvisors.RemoveAll(delegate(string n) { return n == p.name; });
                    if (!store.Data.settings.advisors.Contains(p.name)) store.Data.settings.advisors.Add(p.name);
                    store.Data.settings.advisorProfiles.Add(p);
                }
                else if (oldName != p.name) store.RenameAdvisor(oldName, p.name);
                store.Save(); RefreshAll();
            }
        }
        private string SelectedAdvisorName() { if (profileGrid != null && profileGrid.Focused && profileGrid.CurrentRow != null) return Convert.ToString(profileGrid.CurrentRow.Cells["顾问"].Value); if (advisorGrid != null && advisorGrid.CurrentRow != null) return Convert.ToString(advisorGrid.CurrentRow.Cells["顾问"].Value); if (profileGrid != null && profileGrid.CurrentRow != null) return Convert.ToString(profileGrid.CurrentRow.Cells["顾问"].Value); return null; }
        private void EditSelectedAdvisor() { string name = SelectedAdvisorName(); if (String.IsNullOrWhiteSpace(name)) { MessageBox.Show("请先在上方业绩表或下方配置表选择顾问。"); return; } AdvisorProfile profile = store.Data.settings.advisorProfiles.Find(delegate(AdvisorProfile p) { return p.name == name; }); if (profile == null) { profile = new AdvisorProfile { name = name }; store.Data.settings.advisorProfiles.Add(profile); } EditAdvisor(profile); }
        private void DeleteSelectedAdvisor() { string name = SelectedAdvisorName(); if (String.IsNullOrWhiteSpace(name)) { MessageBox.Show("请先选择要删除的顾问。"); return; } if (MessageBox.Show("删除顾问“" + name + "”后，其客户会变为未分配；历史客户、订单和业绩记录仍会保留。", "确认", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes) { store.DeleteAdvisor(name); RefreshAll(); MessageBox.Show("顾问已删除，原归属客户已转为未分配。", "完成"); } }

        private void ExportJson() { SaveFileDialog d = new SaveFileDialog { Filter = "CRM JSON|*.json", FileName = "CRMBackup_Windows_" + DateTime.Now.ToString("yyyy-MM-dd") + ".json" }; if (d.ShowDialog(this) == DialogResult.OK) { store.ExportPlain(d.FileName); MessageBox.Show("已导出：\n" + d.FileName); } }
        private void ImportJson() { OpenFileDialog d = new OpenFileDialog { Filter = "CRM JSON|*.json|所有文件|*.*" }; if (d.ShowDialog(this) == DialogResult.OK && MessageBox.Show("导入将覆盖当前数据，软件会先自动备份。继续吗？", "确认导入", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes) { try { store.ImportPlain(d.FileName); RefreshAll(); MessageBox.Show("恢复成功。", "完成"); } catch (Exception ex) { MessageBox.Show(ex.Message, "导入失败", MessageBoxButtons.OK, MessageBoxIcon.Error); } } }

        private static TabPage Page(string text) { return new TabPage(text) { BackColor = CrmTheme.Ground, ForeColor = CrmTheme.Text, Padding = new Padding(12) }; }
        private static Label Heading(string text) { return new Label { Text = text, Height = 52, Font = CrmTheme.Font(13F, FontStyle.Bold), Padding = new Padding(12, 13, 0, 0), BackColor = CrmTheme.Surface, ForeColor = CrmTheme.Text }; }
        private static Label HeadingDock(string text) { Label l = Heading(text); l.Dock = DockStyle.Top; return l; }
        private static Button MakeButton(string text, Color color) { LiquidButton button = new LiquidButton { Text = text, AutoSize = true, Height = 36, BaseColor = color, Neutral = color == CrmTheme.SurfaceSoft, BackColor = color, ForeColor = color == CrmTheme.SurfaceSoft ? CrmTheme.Text : Color.White, Padding = new Padding(10, 0, 10, 0), Font = CrmTheme.Font(9F, FontStyle.Bold) }; return button; }
        private static DataGridView MakeGrid() { DataGridView g = new BufferedDataGridView { Dock = DockStyle.Fill, ReadOnly = true, AllowUserToAddRows = false, AllowUserToDeleteRows = false, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, SelectionMode = DataGridViewSelectionMode.FullRowSelect, MultiSelect = false, RowHeadersVisible = false, EnableHeadersVisualStyles = false, ColumnHeadersHeight = 42, ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing }; g.DefaultCellStyle.Padding = new Padding(7, 3, 7, 3); g.ColumnHeadersDefaultCellStyle.Alignment = DataGridViewContentAlignment.MiddleLeft; CrmTheme.StyleGrid(g); return g; }
        private static string Money(double d) { return "¥" + d.ToString("N0"); }
        private bool Hidden(string key) { return store.Data.settings.hiddenMetrics.Contains(key); }
        private void SetHidden(string key, bool hidden) { if (hidden && !store.Data.settings.hiddenMetrics.Contains(key)) store.Data.settings.hiddenMetrics.Add(key); if (!hidden) store.Data.settings.hiddenMetrics.Remove(key); }
        private static void HideId(DataGridView g) { if (g.Columns.Contains("ID")) g.Columns["ID"].Visible = false; }
        private static bool ToBool(object v) { bool b; return Boolean.TryParse(Convert.ToString(v), out b) && b; }
        private static string ToText(object v) { return v == null || v == DBNull.Value ? "" : Convert.ToString(v); }
        private static double? ToNullableDouble(object v) { double x; return Double.TryParse(ToText(v), out x) ? (double?)x : null; }
        private static int? ToNullableInt(object v) { int x; return Int32.TryParse(ToText(v), out x) ? (int?)x : null; }
        private static void AddBands(DataTable dt, string category, List<double> values, double[] boundaries, string[] labels) { for (int i = 0; i < labels.Length; i++) { int count = values.Count(delegate(double x) { return x >= boundaries[i] && x < boundaries[i + 1]; }); if (count > 0) dt.Rows.Add(category, labels[i], count, ((double)count / values.Count).ToString("P1")); } }
    }

    public class BufferedDataGridView : DataGridView
    {
        private int hoverRow = -1;
        public BufferedDataGridView() { DoubleBuffered = true; SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true); }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            DataGridView.HitTestInfo hit = HitTest(e.X, e.Y);
            int next = hit.Type == DataGridViewHitTestType.Cell ? hit.RowIndex : -1;
            if (next != hoverRow)
            {
                int previous = hoverRow; hoverRow = next;
                if (previous >= 0 && previous < Rows.Count) InvalidateRow(previous);
                if (hoverRow >= 0 && hoverRow < Rows.Count) InvalidateRow(hoverRow);
            }
            base.OnMouseMove(e);
        }
        protected override void OnMouseLeave(EventArgs e)
        {
            int previous = hoverRow; hoverRow = -1;
            if (previous >= 0 && previous < Rows.Count) InvalidateRow(previous);
            base.OnMouseLeave(e);
        }
        protected override void OnCellPainting(DataGridViewCellPaintingEventArgs e)
        {
            if (e.RowIndex == hoverRow && e.RowIndex >= 0 && !Rows[e.RowIndex].Selected)
            {
                using (SolidBrush hover = new SolidBrush(Color.FromArgb(232, 241, 255))) e.Graphics.FillRectangle(hover, e.CellBounds);
                e.Paint(e.CellBounds, e.PaintParts & ~DataGridViewPaintParts.Background);
                if (e.ColumnIndex == FirstDisplayedScrollingColumnIndex) using (SolidBrush accent = new SolidBrush(CrmTheme.Cyan)) e.Graphics.FillRectangle(accent, e.CellBounds.X, e.CellBounds.Y + 4, 3, Math.Max(0, e.CellBounds.Height - 8));
                e.Handled = true;
                return;
            }
            base.OnCellPainting(e);
        }
    }

    public class BufferedTabControl : TabControl
    {
        public BufferedTabControl() { DoubleBuffered = true; SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true); }
    }

    public class BufferedFlowLayoutPanel : FlowLayoutPanel
    {
        public BufferedFlowLayoutPanel() { DoubleBuffered = true; SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true); }
    }
}
