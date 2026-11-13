using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace CRMWindows
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            if (args.Length > 0 && args[0] == "--self-test")
            {
                SelfTest.Run(); return;
            }
            if (args.Length >= 2 && args[0] == "--ui-self-test")
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                SelfTest.RunUi(args[1]); return;
            }
            if (args.Length >= 3 && args[0] == "--inspect-xlsx")
            {
                var rows = XlsxCustomerReader.Read(args[1]);
                int complete = rows.FindAll(delegate(SourceCustomerRow r) { return !String.IsNullOrWhiteSpace(r.Name) && !String.IsNullOrWhiteSpace(r.Phone); }).Count;
                File.WriteAllText(args[2], "rows=" + rows.Count + Environment.NewLine + "complete=" + complete + Environment.NewLine + "first=" + (rows.Count > 0 ? rows[0].Name + "|" + rows[0].Phone + "|" + rows[0].Date.ToString("yyyy-MM-dd") + "|" + rows[0].Channel : ""), new UTF8Encoding(false));
                return;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try { Application.Run(new MainForm()); }
            catch (Exception ex) { MessageBox.Show(ex.ToString(), "私域 CRM 启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
    }

    static class SelfTest
    {
        public static void Run()
        {
            var parsed = SmartPasteParser.Parse("8.01\t测试甲\t13900000001\t测试省测试市测试路1号\t植物茶2\t350\t162\t155\t39\tSF0000000000001\t上午9点\t食谱");
            if (parsed.Count != 1 || parsed[0].Height != 162 || parsed[0].Weight != 155 || parsed[0].Age != 39) throw new Exception("智能解析自检失败");
            var flexible = SmartPasteParser.Parse("测试乙 13900000002 测试省测试市测试路2号 植物茶2+脂肪粉2+草本膏1 350 身高160体重120年龄35 SF0000000000002");
            if (flexible.Count != 1 || flexible[0].LeadAmount != 350 || flexible[0].Channel != null || !flexible[0].NeedsReview) throw new Exception("灵活解析或缺失渠道复核自检失败");
            var ledger = LedgerParser.Parse("2583 新单 3260 2547 二次 9800 2475 多次 9200");
            if (ledger.Count != 3 || ledger[1].Type != "二次") throw new Exception("流水解析自检失败");
            AppData data = new AppData();
            Customer customer = new Customer { name = "测试客户", phone = "13900000003", costEnabled = true, lineCost = 1200, importDate = DateTime.Now };
            ConversionRecord testOrder = new ConversionRecord { type = "新单", amount = 3600, date = DateTime.Now, trackingNumber = "SFTEST123" };
            testOrder.advisorSplits.Add(new AdvisorSplit { name = "已离职顾问", ratio = 1 }); customer.conversions.Add(testOrder);
            ConversionRecord activeOrder = new ConversionRecord { type = "二次", amount = 1200, date = DateTime.Now };
            activeOrder.advisorSplits.Add(new AdvisorSplit { name = "在职顾问", ratio = 1 }); customer.conversions.Add(activeOrder);
            data.settings.inactiveAdvisors.Add("已离职顾问");
            data.customers.Add(customer);
            AppData restored = JsonCompat.Read(JsonCompat.Write(data));
            if (restored.customers.Count != 1 || restored.customers[0].TotalRevenue != 4800) throw new Exception("JSON兼容自检失败");
            AdvisorStat inactive = StatisticsEngine.Advisors(restored.customers, restored.settings, false, DateTime.Now.Year, DateTime.Now.Month).Find(delegate(AdvisorStat x) { return x.Name == "已离职顾问"; });
            if (restored.customers[0].conversions[0].trackingNumber != "SFTEST123" || inactive == null || !inactive.IsInactive || inactive.Revenue != 3600) throw new Exception("订单快递或离职顾问历史兼容自检失败");
            PeriodStats stats = StatisticsEngine.Summary(restored.customers, false, DateTime.Now.Year, DateTime.Now.Month);
            if (stats.Leads != 1 || stats.Revenue != 4800 || Math.Abs(stats.Roi - 4) > 0.001) throw new Exception("统计口径自检失败");
            string sandbox = Path.Combine(Path.GetTempPath(), "PrivateCRM_DisguiseTest_" + Guid.NewGuid().ToString("N"));
            try
            {
                DataStore isolated = new DataStore(sandbox); Customer realCustomer = new Customer { name = "测试客户", phone = "13900000004" }; ConversionRecord advisorOrder = new ConversionRecord(); advisorOrder.advisorSplits.Add(new AdvisorSplit { name = "在职顾问", ratio = 1 }); advisorOrder.advisorSplits.Add(new AdvisorSplit { name = "已离职顾问", ratio = 1 }); realCustomer.conversions.Add(advisorOrder); isolated.Data.settings.inactiveAdvisors.Add("已离职顾问"); isolated.Data.customers.Add(realCustomer); isolated.Save();
                List<string> activeNames = isolated.ActiveAdvisorNames();
                if (!activeNames.Contains("在职顾问") || activeNames.Contains("已离职顾问")) throw new Exception("顾问下拉名单自检失败");
                using (CustomerForm customerForm = new CustomerForm(isolated, realCustomer))
                {
                    bool foundActive = false, foundInactive = false;
                    foreach (ComboBox combo in FindControls<ComboBox>(customerForm))
                        foreach (object option in combo.Items)
                        {
                            string optionText = Convert.ToString(option);
                            if (optionText == "在职顾问") foundActive = true;
                            if (optionText == "已离职顾问") foundInactive = true;
                        }
                    if (!foundActive || foundInactive) throw new Exception("客户顾问下拉框自检失败");
                }
                isolated.EnableDisguise(); isolated.Data.customers[0].name = "伪装客户"; isolated.Save(); isolated.DisableDisguise();
                if (isolated.IsDisguiseActive || isolated.Data.customers[0].name != "测试客户") throw new Exception("全局伪装隔离自检失败");
            }
            finally { try { if (Directory.Exists(sandbox)) Directory.Delete(sandbox, true); } catch { } }
            Console.WriteLine("SELF_TEST_OK smart=" + parsed.Count + " ledger=" + ledger.Count);
        }

        public static void RunUi(string outputPath)
        {
            using (MainForm form = new MainForm(true))
            {
                form.Size = new Size(1440, 900);
                form.ShowInTaskbar = false;
                form.StartPosition = FormStartPosition.Manual;
                form.Location = new Point(-32000, -32000);
                form.Show();
                Application.DoEvents();
                form.PerformLayout();
                List<SidebarNavButton> navigation = FindControls<SidebarNavButton>(form);
                if (navigation.Count != 6) throw new Exception("UI 自检失败：侧栏模块数量不正确");
                List<HiddenTabControl> tabs = FindControls<HiddenTabControl>(form);
                if (tabs.Count < 2 || tabs[0].TabPages.Count != 6) throw new Exception("UI 自检失败：主模块或录入子模块缺失");
                Stopwatch coldSwitchWatch = Stopwatch.StartNew();
                for (int i = 0; i < navigation.Count; i++) { navigation[i].PerformClick(); Application.DoEvents(); }
                coldSwitchWatch.Stop();
                Stopwatch warmSwitchWatch = Stopwatch.StartNew();
                for (int cycle = 0; cycle < 3; cycle++)
                    for (int i = 0; i < navigation.Count; i++) { navigation[i].PerformClick(); Application.DoEvents(); }
                warmSwitchWatch.Stop();
                navigation[0].PerformClick(); Application.DoEvents();
                CaptureUi(form, outputPath);
                List<SmoothCard> cards = FindControls<SmoothCard>(form);
                if (cards.Count == 0) throw new Exception("UI 自检失败：未找到数据卡片");
                MethodInfo showDashboardDetail = typeof(MainForm).GetMethod("ShowDashboardDetail", BindingFlags.Instance | BindingFlags.NonPublic);
                foreach (string detailKey in new string[] { "roi", "cost", "revenue", "newrate", "followup", "funnel", "daily", "channel:直播" })
                {
                    showDashboardDetail.Invoke(form, new object[] { detailKey });
                    Application.DoEvents();
                }
                SmoothCard hoverCard = cards.Count > 1 ? cards[1] : cards[0];
                SimulateHover(hoverCard, hoverCard.Width / 2, hoverCard.Height / 2);
                CaptureUi(form, outputPath + "-hover.png");
                EndHover(hoverCard);
                string directory = Path.GetDirectoryName(outputPath);
                string stem = Path.GetFileNameWithoutExtension(outputPath);
                for (int i = 0; i < navigation.Count; i++)
                {
                    navigation[i].PerformClick();
                    Application.DoEvents();
                    CaptureUi(form, Path.Combine(directory, stem + "-module-" + (i + 1) + ".png"));
                }
                List<InteractiveSurfacePanel> surfaces = FindControls<InteractiveSurfacePanel>(form);
                List<InteractiveGroupBox> groups = FindControls<InteractiveGroupBox>(form);
                List<BufferedDataGridView> grids = FindControls<BufferedDataGridView>(form);
                if (surfaces.Count < 3 || groups.Count < 5 || grids.Count < 8) throw new Exception("UI 自检失败：非首页交互组件覆盖不完整");
                BufferedDataGridView copyEnabledCustomerGrid = grids.Find(delegate(BufferedDataGridView x) { return x.ContextMenuStrip != null && x.ContextMenuStrip.Items.Count == 3; });
                if (copyEnabledCustomerGrid == null || Convert.ToString(copyEnabledCustomerGrid.ContextMenuStrip.Items[0].Text) != "复制客户姓名" || Convert.ToString(copyEnabledCustomerGrid.ContextMenuStrip.Items[1].Text) != "复制客户电话" || Convert.ToString(copyEnabledCustomerGrid.ContextMenuStrip.Items[2].Text) != "复制客户编号") throw new Exception("UI 自检失败：客户右键复制菜单缺失");
                if (copyEnabledCustomerGrid.Columns.Contains("订单数") || copyEnabledCustomerGrid.Columns.Contains("业绩")) throw new Exception("UI 自检失败：客户列表仍显示旧订单汇总列");
                foreach (string amountColumn in new string[] { "新单", "二次", "三次", "四次", "五次", "六次", "七次", "八次", "多次" }) if (!copyEnabledCustomerGrid.Columns.Contains(amountColumn)) throw new Exception("UI 自检失败：客户订单金额列缺失 " + amountColumn);
                List<ComboBox> allComboBoxes = FindControls<ComboBox>(form);
                ComboBox channelFilter = allComboBoxes.Find(delegate(ComboBox x) { return x.Items.Contains("全部渠道"); });
                ComboBox advisorFilter = allComboBoxes.Find(delegate(ComboBox x) { return x.Items.Contains("全部顾问"); });
                ComboBox orderFilter = allComboBoxes.Find(delegate(ComboBox x) { return x.Items.Contains("已开单") && x.Items.Contains("未开单"); });
                if (channelFilter == null || advisorFilter == null || orderFilter == null) throw new Exception("UI 自检失败：客户筛选器缺失");
                foreach (string state in new string[] { "已开单", "未开单", "全部客户" }) { orderFilter.SelectedItem = state; Application.DoEvents(); }
                if (channelFilter.Items.Count > 1)
                {
                    string selectedChannel = Convert.ToString(channelFilter.Items[1]); channelFilter.SelectedIndex = 1; Application.DoEvents();
                    foreach (DataGridViewRow row in copyEnabledCustomerGrid.Rows) if (!String.Equals(Convert.ToString(row.Cells["渠道"].Value), selectedChannel, StringComparison.Ordinal)) throw new Exception("UI 自检失败：渠道筛选混入其他渠道");
                    channelFilter.SelectedIndex = 0; Application.DoEvents();
                }
                if (copyEnabledCustomerGrid.Rows.Count > 0)
                {
                    string rowChannel = Convert.ToString(copyEnabledCustomerGrid.Rows[0].Cells["渠道"].Value);
                    string rowAdvisor = Convert.ToString(copyEnabledCustomerGrid.Rows[0].Cells["归属顾问"].Value);
                    int channelIndex = channelFilter.Items.IndexOf(rowChannel), advisorIndex = advisorFilter.Items.IndexOf(rowAdvisor);
                    if (channelIndex > 0 && advisorIndex > 0)
                    {
                        channelFilter.SelectedIndex = channelIndex; advisorFilter.SelectedIndex = advisorIndex; Application.DoEvents();
                        foreach (DataGridViewRow row in copyEnabledCustomerGrid.Rows)
                            if (!String.Equals(Convert.ToString(row.Cells["渠道"].Value), rowChannel, StringComparison.Ordinal) || !String.Equals(Convert.ToString(row.Cells["归属顾问"].Value), rowAdvisor, StringComparison.Ordinal)) throw new Exception("UI 自检失败：渠道与顾问组合筛选混入不匹配客户");
                        channelFilter.SelectedIndex = 0; advisorFilter.SelectedIndex = 0; Application.DoEvents();
                    }
                }
                navigation[2].PerformClick(); Application.DoEvents();
                SimulateHover(surfaces[0], surfaces[0].Width / 2, 35);
                CaptureUi(form, Path.Combine(directory, stem + "-analytics-hover.png")); EndHover(surfaces[0]);
                navigation[1].PerformClick(); Application.DoEvents();
                BufferedDataGridView customerGrid = grids[0];
                SimulateHover(customerGrid, 90, customerGrid.ColumnHeadersHeight + customerGrid.RowTemplate.Height + 12);
                CaptureUi(form, Path.Combine(directory, stem + "-customer-hover.png")); EndHover(customerGrid);
                navigation[5].PerformClick(); Application.DoEvents();
                SimulateHover(groups[0], groups[0].Width / 2, 35);
                CaptureUi(form, Path.Combine(directory, stem + "-settings-hover.png")); EndHover(groups[0]);
                form.Size = form.MinimumSize;
                form.PerformLayout();
                for (int i = 0; i < navigation.Count; i++)
                {
                    navigation[i].PerformClick(); Application.DoEvents();
                    CaptureUi(form, Path.Combine(directory, stem + "-minimum-module-" + (i + 1) + ".png"));
                }
                form.Close();
                Console.WriteLine("UI_SELF_TEST_OK modules=" + navigation.Count + " cold_switch_ms=" + coldSwitchWatch.ElapsedMilliseconds + " warm_switch_ms=" + warmSwitchWatch.ElapsedMilliseconds + " screenshot=" + outputPath);
            }
        }

        private static List<T> FindControls<T>(Control root) where T : Control
        {
            List<T> result = new List<T>();
            foreach (Control child in root.Controls)
            {
                T matched = child as T;
                if (matched != null) result.Add(matched);
                result.AddRange(FindControls<T>(child));
            }
            return result;
        }

        private static void SimulateHover(Control control, int x, int y)
        {
            MethodInfo enter = control.GetType().GetMethod("OnMouseEnter", BindingFlags.Instance | BindingFlags.NonPublic);
            MethodInfo move = control.GetType().GetMethod("OnMouseMove", BindingFlags.Instance | BindingFlags.NonPublic);
            if (enter != null) enter.Invoke(control, new object[] { EventArgs.Empty });
            if (move != null) move.Invoke(control, new object[] { new MouseEventArgs(MouseButtons.None, 0, x, y, 0) });
            for (int frame = 0; frame < 9; frame++) { Thread.Sleep(18); Application.DoEvents(); }
        }

        private static void EndHover(Control control)
        {
            MethodInfo leave = control.GetType().GetMethod("OnMouseLeave", BindingFlags.Instance | BindingFlags.NonPublic);
            if (leave != null) leave.Invoke(control, new object[] { EventArgs.Empty });
        }

        private static void CaptureUi(Form form, string path)
        {
            using (Bitmap bitmap = new Bitmap(form.Width, form.Height))
            {
                form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size));
                bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            }
        }
    }
}
