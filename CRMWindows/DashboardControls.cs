using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace CRMWindows
{
    public static class DashboardPalette
    {
        public static readonly Color Background = CrmTheme.Ground;
        public static readonly Color Text = CrmTheme.Text;
        public static readonly Color Muted = CrmTheme.Muted;
        public static readonly Color Blue = CrmTheme.Blue;
        public static readonly Color Indigo = CrmTheme.Lilac;
        public static readonly Color Orange = CrmTheme.Orange;
        public static readonly Color Green = CrmTheme.Green;
        public static readonly Color Red = CrmTheme.Red;
        public static readonly Color Line = CrmTheme.BorderSoft;
    }

    public static class DrawUtil
    {
        public static GraphicsPath RoundRect(RectangleF rect, float radius)
        {
            float d = radius * 2; GraphicsPath path = new GraphicsPath();
            path.AddArc(rect.X, rect.Y, d, d, 180, 90); path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90); path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90); path.CloseFigure(); return path;
        }
        public static void FillRound(Graphics g, Brush brush, RectangleF rect, float radius) { using (GraphicsPath p = RoundRect(rect, radius)) g.FillPath(brush, p); }
        public static void DrawRound(Graphics g, Pen pen, RectangleF rect, float radius) { using (GraphicsPath p = RoundRect(rect, radius)) g.DrawPath(pen, p); }
        public static void DrawText(Graphics g, string text, Font font, Color color, Rectangle bounds, TextFormatFlags alignment)
        {
            TextRenderer.DrawText(
                g,
                text ?? "",
                font,
                bounds,
                color,
                alignment | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix |
                TextFormatFlags.SingleLine | TextFormatFlags.PreserveGraphicsClipping);
        }
        public static string Money(double value) { return "¥" + value.ToString("N0"); }
    }

    public abstract class SmoothCard : Control
    {
        private bool hovered;
        private Point hoverPoint;
        private float hoverProgress;
        private readonly Timer motionTimer;
        private int lastPointerPaint;

        protected SmoothCard()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.Opaque, true);
            BackColor = DashboardPalette.Background;
            Margin = new Padding(8);
            Cursor = Cursors.Hand;
            TabStop = true;
            motionTimer = new Timer { Interval = 16 };
            motionTimer.Tick += delegate
            {
                float target = hovered ? 1F : 0F;
                hoverProgress += (target - hoverProgress) * 0.34F;
                if (Math.Abs(target - hoverProgress) < 0.025F) { hoverProgress = target; motionTimer.Stop(); }
                Invalidate();
            };
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) { OnClick(EventArgs.Empty); e.Handled = true; }
            base.OnKeyDown(e);
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            hovered = true;
            hoverPoint = PointToClient(Cursor.Position);
            motionTimer.Start();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int now = Environment.TickCount;
            int dx = e.X - hoverPoint.X, dy = e.Y - hoverPoint.Y;
            if (hovered && (dx * dx + dy * dy >= 64) && unchecked(now - lastPointerPaint) >= 36)
            {
                hoverPoint = e.Location;
                lastPointerPaint = now;
                Invalidate(new Rectangle(Math.Max(0, e.X - 130), Math.Max(0, e.Y - 130), 260, 260));
            }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            hovered = false;
            motionTimer.Start();
            base.OnMouseLeave(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias; e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            float lift = hoverProgress * 3F;
            RectangleF shadow = new RectangleF(3, 5 - lift, Width - 7, Height - 9);
            using (SolidBrush b = new SolidBrush(Color.FromArgb((int)(24 + 24 * hoverProgress), 58, 79, 113))) DrawUtil.FillRound(e.Graphics, b, shadow, 18);
            RectangleF card = new RectangleF(1, 1 - lift, Width - 6, Height - 8);
            using (LinearGradientBrush b = new LinearGradientBrush(card, Color.FromArgb(255, 255, 255), Color.FromArgb(246, 248, 255), 120F)) DrawUtil.FillRound(e.Graphics, b, card, 18);
            using (LinearGradientBrush borderBrush = new LinearGradientBrush(card, Blend(CrmTheme.Border, CrmTheme.Cyan, hoverProgress), Blend(CrmTheme.Border, CrmTheme.Lilac, hoverProgress), 0F))
            using (Pen border = new Pen(borderBrush, 1F + hoverProgress * 0.7F)) DrawUtil.DrawRound(e.Graphics, border, card, 18);
            if (hoverProgress > 0.02F) PaintPointerGlow(e.Graphics, card);
            PaintCard(e.Graphics, card);
        }

        private void PaintPointerGlow(Graphics graphics, RectangleF card)
        {
            GraphicsState state = graphics.Save();
            using (GraphicsPath clip = DrawUtil.RoundRect(card, 18)) graphics.SetClip(clip);
            RectangleF glowRect = new RectangleF(hoverPoint.X - 105, hoverPoint.Y - 105, 210, 210);
            using (GraphicsPath glowPath = new GraphicsPath())
            {
                glowPath.AddEllipse(glowRect);
                using (PathGradientBrush glow = new PathGradientBrush(glowPath))
                {
                    glow.CenterPoint = hoverPoint;
                    glow.CenterColor = Color.FromArgb((int)(18 + 42 * hoverProgress), CrmTheme.Cyan);
                    glow.SurroundColors = new[] { Color.FromArgb(0, CrmTheme.Lilac) };
                    graphics.FillPath(glow, glowPath);
                }
            }
            graphics.Restore(state);
        }

        private static Color Blend(Color a, Color b, float amount)
        {
            return Color.FromArgb((int)(a.R + (b.R - a.R) * amount), (int)(a.G + (b.G - a.G) * amount), (int)(a.B + (b.B - a.B) * amount));
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && motionTimer != null) motionTimer.Dispose();
            base.Dispose(disposing);
        }
        protected abstract void PaintCard(Graphics g, RectangleF card);
    }

    public class HeroDashboardCard : SmoothCard
    {
        public string PeriodTitle = "本月经营概览"; public string Subtitle = "数据会随客户和订单实时更新";
        protected override void PaintCard(Graphics g, RectangleF card)
        {
            using (LinearGradientBrush bg = new LinearGradientBrush(card, Color.FromArgb(41, 84, 221), Color.FromArgb(128, 61, 214), 8F)) DrawUtil.FillRound(g, bg, card, 18);
            using (LinearGradientBrush flare = new LinearGradientBrush(new RectangleF(Width - 330, 0, 330, Height), Color.FromArgb(0, CrmTheme.Cyan), Color.FromArgb(120, CrmTheme.Cyan), 0F)) g.FillRectangle(flare, Width - 330, 0, 330, Height);
            using (SolidBrush accent = new SolidBrush(Color.FromArgb(220, 105, 229, 255))) DrawUtil.FillRound(g, accent, new RectangleF(24, 18, 4, 62), 2);
            DrawUtil.DrawText(g, PeriodTitle, CrmTheme.PaintFont(20, FontStyle.Bold), Color.White, new Rectangle(42, 15, Width - 150, 38), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, Subtitle, CrmTheme.PaintFont(9.5F), Color.FromArgb(235, 244, 255), new Rectangle(43, 55, Width - 150, 25), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            using (Font f = new Font("Segoe UI Symbol", 24)) DrawUtil.DrawText(g, "▦", f, Color.White, new Rectangle(Width - 100, 15, 58, 58), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }

    public class MetricDashboardCard : SmoothCard
    {
        public string Title = "指标"; public string Value = "—"; public string Note = ""; public Color Accent = DashboardPalette.Blue; public string Symbol = "●";
        protected override void PaintCard(Graphics g, RectangleF card)
        {
            using (LinearGradientBrush stripe = new LinearGradientBrush(new RectangleF(0, 0, Width, 4), Accent, Color.FromArgb(130, CrmTheme.Lilac), 0F)) DrawUtil.FillRound(g, stripe, new RectangleF(18, 1, Width - 42, 3), 2);
            using (SolidBrush tint = new SolidBrush(Color.FromArgb(22, Accent))) DrawUtil.FillRound(g, tint, new RectangleF(20, 20, 42, 42), 12);
            using (Font f = new Font("Segoe UI Symbol", 14, FontStyle.Bold)) DrawUtil.DrawText(g, Symbol, f, Accent, new Rectangle(20, 20, 42, 42), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, Title, CrmTheme.PaintFont(9.5F), DashboardPalette.Muted, new Rectangle(76, 17, Width - 96, 25), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, Value, CrmTheme.PaintFont(18, FontStyle.Bold), Accent, new Rectangle(74, 41, Width - 96, 38), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, Note, CrmTheme.PaintFont(8.5F), DashboardPalette.Muted, new Rectangle(22, Height - 42, Width - 44, 28), TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
    }

    public class FollowUpDashboardCard : SmoothCard
    {
        public int RecentPending, NewPending, SecondPending;
        protected override void PaintCard(Graphics g, RectangleF card)
        {
            Title(g, "待跟进客户", "需优先处理的客户状态");
            DrawRow(g, 72, "15天内派发 · 未成交", "近期线索", RecentPending, DashboardPalette.Red, "!");
            DrawRow(g, 132, "暂未成交新单", "尚未产生首次成交", NewPending, DashboardPalette.Orange, "1");
            DrawRow(g, 192, "暂未成交二次", "已有新单，尚未复购", SecondPending, DashboardPalette.Blue, "2");
        }
        private void DrawRow(Graphics g, int y, string title, string sub, int count, Color color, string icon)
        {
            if (y > 75) using (Pen p = new Pen(DashboardPalette.Line)) g.DrawLine(p, 24, y - 8, Width - 30, y - 8);
            using (SolidBrush tint = new SolidBrush(Color.FromArgb(22, color))) DrawUtil.FillRound(g, tint, new RectangleF(24, y, 36, 36), 10);
            DrawUtil.DrawText(g, icon, CrmTheme.PaintFont(10, FontStyle.Bold), color, new Rectangle(24, y, 36, 36), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, title, CrmTheme.PaintFont(11, FontStyle.Bold), DashboardPalette.Text, new Rectangle(74, y - 4, Width - 190, 25), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, sub, CrmTheme.PaintFont(8.5F), DashboardPalette.Muted, new Rectangle(74, y + 19, Width - 190, 21), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, count + " 人", CrmTheme.PaintFont(14, FontStyle.Bold), color, new Rectangle(Width - 150, y + 2, 116, 34), TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
        }
        private void Title(Graphics g, string title, string subtitle)
        {
            DrawUtil.DrawText(g, title, CrmTheme.PaintFont(15, FontStyle.Bold), DashboardPalette.Text, new Rectangle(24, 15, Width - 48, 32), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, subtitle, CrmTheme.PaintFont(8.5F), DashboardPalette.Muted, new Rectangle(25, 43, Width - 50, 22), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }

    public class FunnelDashboardCard : SmoothCard
    {
        public int Leads, NewOrders, SecondOrders; public double NewAmount, SecondAmount; public bool HideRevenue;
        protected override void PaintCard(Graphics g, RectangleF card)
        {
            DrawUtil.DrawText(g, "销售漏斗", CrmTheme.PaintFont(15, FontStyle.Bold), DashboardPalette.Text, new Rectangle(24, 15, Width - 48, 32), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, "成交率与复购进度", CrmTheme.PaintFont(8.5F), DashboardPalette.Muted, new Rectangle(25, 43, Width - 50, 22), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawStage(g, 80, "新单", NewOrders, Leads, NewAmount, DashboardPalette.Blue);
            DrawStage(g, 160, "二次", SecondOrders, NewOrders, SecondAmount, DashboardPalette.Green);
        }
        private void DrawStage(Graphics g, int y, string title, int count, int total, double amount, Color color)
        {
            double rate = total > 0 ? Math.Min(1, (double)count / total) : 0; string rateText = total > 0 ? ((double)count / total).ToString("P1") : "—";
            DrawUtil.DrawText(g, title, CrmTheme.PaintFont(11, FontStyle.Bold), DashboardPalette.Text, new Rectangle(24, y - 4, Width - 180, 28), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, count + " / " + total + "     " + (HideRevenue ? "" : DrawUtil.Money(amount)), CrmTheme.PaintFont(9), DashboardPalette.Muted, new Rectangle(24, y + 23, Width - 180, 25), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, rateText, CrmTheme.PaintFont(18, FontStyle.Bold), color, new Rectangle(Width - 190, y - 6, 158, 38), TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
            RectangleF track = new RectangleF(24, y + 57, Width - 58, 8); using (SolidBrush b = new SolidBrush(DashboardPalette.Line)) DrawUtil.FillRound(g, b, track, 4);
            if (rate > 0) using (SolidBrush b = new SolidBrush(color)) DrawUtil.FillRound(g, b, new RectangleF(track.X, track.Y, (float)(track.Width * rate), track.Height), 4);
        }
    }

    public class DailyAuditRow { public DateTime Date; public int Leads; public double Cost; public int Orders; public double Revenue; }

    public class DailyAuditDashboardCard : SmoothCard
    {
        public List<DailyAuditRow> Rows = new List<DailyAuditRow>(); public bool HideCost, HideRevenue;
        protected override void PaintCard(Graphics g, RectangleF card)
        {
            DrawUtil.DrawText(g, "每日审阅", CrmTheme.PaintFont(15, FontStyle.Bold), DashboardPalette.Text, new Rectangle(24, 15, Width - 48, 32), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, "按日期核对资料录入与开单业绩", CrmTheme.PaintFont(8.5F), DashboardPalette.Muted, new Rectangle(25, 43, Width - 50, 22), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            int y = 78; foreach (DailyAuditRow row in Rows.Take(6))
            {
                using (SolidBrush tint = new SolidBrush(Color.FromArgb(20, DashboardPalette.Blue))) DrawUtil.FillRound(g, tint, new RectangleF(24, y, 50, 43), 11);
                DrawUtil.DrawText(g, row.Date.ToString("M/d"), CrmTheme.PaintFont(11, FontStyle.Bold), DashboardPalette.Blue, new Rectangle(24, y, 50, 43), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                DrawUtil.DrawText(g, "资料 " + row.Leads + " 份", CrmTheme.PaintFont(10, FontStyle.Bold), DashboardPalette.Text, new Rectangle(92, y - 3, Width / 2 - 110, 25), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                DrawUtil.DrawText(g, "录入客户资料", CrmTheme.PaintFont(9F), DashboardPalette.Muted, new Rectangle(92, y + 21, Width / 2 - 110, 24), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                DrawUtil.DrawText(g, "开单 " + row.Orders + " 笔", CrmTheme.PaintFont(10.5F, FontStyle.Bold), DashboardPalette.Red, new Rectangle(Width / 2, y - 3, Width / 2 - 32, 25), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                DrawUtil.DrawText(g, HideRevenue ? "业绩 —" : "业绩 " + DrawUtil.Money(row.Revenue), CrmTheme.PaintFont(10.5F, FontStyle.Bold), DashboardPalette.Red, new Rectangle(Width / 2, y + 21, Width / 2 - 32, 24), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                if (y < Height - 62) using (Pen p = new Pen(DashboardPalette.Line)) g.DrawLine(p, 24, y + 53, Width - 30, y + 53); y += 62;
            }
            if (Rows.Count == 0) DrawUtil.DrawText(g, "当前期间暂无资料和订单记录", CrmTheme.PaintFont(11), DashboardPalette.Muted, new Rectangle(24, 82, Width - 48, 30), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }

    public class ChannelOverviewDashboardCard : SmoothCard
    {
        public List<ChannelStat> Rows = new List<ChannelStat>(); public bool HideRevenue;
        public event Action<string> ChannelClicked;
        private readonly Color[] colors = { DashboardPalette.Blue, DashboardPalette.Orange, DashboardPalette.Green, DashboardPalette.Indigo, DashboardPalette.Red };
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            int index = (e.Y - 82) / 52;
            if (e.Y >= 82 && index >= 0 && index < Math.Min(5, Rows.Count) && ChannelClicked != null) ChannelClicked(Rows[index].Channel);
        }
        protected override void PaintCard(Graphics g, RectangleF card)
        {
            DrawUtil.DrawText(g, "渠道概览", CrmTheme.PaintFont(15, FontStyle.Bold), DashboardPalette.Text, new Rectangle(24, 15, Width - 48, 32), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(g, "线索、新单率和复购率一览", CrmTheme.PaintFont(8.5F), DashboardPalette.Muted, new Rectangle(25, 43, Width - 50, 22), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            int max = Rows.Count == 0 ? 1 : Math.Max(1, Rows.Max(delegate(ChannelStat x) { return x.Leads; })); int y = 82, i = 0;
            foreach (ChannelStat row in Rows.Take(5))
            {
                Color color = colors[i++ % colors.Length]; using (SolidBrush b = new SolidBrush(color)) g.FillEllipse(b, 25, y + 3, 10, 10);
                DrawUtil.DrawText(g, row.Channel, CrmTheme.PaintFont(10, FontStyle.Bold), DashboardPalette.Text, new Rectangle(45, y - 7, 90, 26), TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
                string text = row.Leads + " 条   新单 " + (row.Leads > 0 ? ((double)row.NewOrders / row.Leads).ToString("P0") : "—") + "   复购 " + (row.NewOrders > 0 ? ((double)row.Seconds / row.NewOrders).ToString("P0") : "—") + (HideRevenue ? "" : "   " + DrawUtil.Money(row.Revenue));
                DrawUtil.DrawText(g, text, CrmTheme.PaintFont(9), DashboardPalette.Muted, new Rectangle(135, y - 7, Width - 169, 26), TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
                RectangleF track = new RectangleF(45, y + 27, Width - 80, 6); using (SolidBrush b = new SolidBrush(DashboardPalette.Line)) DrawUtil.FillRound(g, b, track, 3); using (SolidBrush b = new SolidBrush(color)) DrawUtil.FillRound(g, b, new RectangleF(track.X, track.Y, track.Width * row.Leads / max, 6), 3); y += 52;
            }
            if (Rows.Count == 0) DrawUtil.DrawText(g, "暂无渠道数据", CrmTheme.PaintFont(11), DashboardPalette.Muted, new Rectangle(24, 82, Width - 48, 30), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }

    public class PolishedDashboard : UserControl
    {
        private FlowLayoutPanel canvas;
        public event Action<string> Navigate;
        public PolishedDashboard()
        {
            BackColor = DashboardPalette.Background; canvas = new BufferedFlowLayoutPanel { Dock = DockStyle.Fill, AutoScroll = true, WrapContents = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(22, 18, 22, 30), BackColor = DashboardPalette.Background }; Controls.Add(canvas); Resize += delegate { ResizeCards(); };
        }
        public void UpdateDashboard(List<Customer> customers, AppSettings settings, bool monthly, int year, int month, bool hideCost, bool hideRevenue, bool hideRoi)
        {
            canvas.SuspendLayout(); canvas.Controls.Clear(); PeriodStats s = StatisticsEngine.Summary(customers, monthly, year, month);
            Func<string, string, string> shown = delegate(string key, string fallback) { string value; return settings.demoEnabled && settings.disguiseDisplayValues != null && settings.disguiseDisplayValues.TryGetValue(key, out value) ? value : fallback; };
            double displayRevenue = DisplayNumber(shown("revenue", ""), s.Revenue);
            double displayCost = DisplayNumber(shown("cost", ""), s.Cost);
            double revenueScale = s.Revenue > 0 ? displayRevenue / s.Revenue : 1;
            double costScale = s.Cost > 0 ? displayCost / s.Cost : 1;
            double displayFunnelRevenue = s.FunnelRevenue * revenueScale;
            double displayOtherRevenue = Math.Max(0, displayRevenue - displayFunnelRevenue);
            int width = Math.Max(900, ClientSize.Width - 70); HeroDashboardCard hero = new HeroDashboardCard { Width = width, Height = 100, PeriodTitle = monthly ? year + "年" + month + "月经营概览" : "累计经营概览", Subtitle = "成本按资料录入日期 · 营业额按开单日期 · 数据实时更新" }; canvas.Controls.Add(hero); Break();
            int metricWidth = (width - 80) / 4;
            AddNavigable(new MetricDashboardCard { Width = metricWidth, Height = 148, Title = "ROI", Value = hideRoi ? "—" : shown("roi", displayCost > 0 ? (displayFunnelRevenue / displayCost).ToString("0.00") : "—"), Note = "漏斗业绩 ÷ 获客成本", Accent = DashboardPalette.Blue, Symbol = "↗" }, "roi");
            AddNavigable(new MetricDashboardCard { Width = metricWidth, Height = 148, Title = "资料成本", Value = hideCost ? "—" : shown("cost", DrawUtil.Money(s.Cost)), Note = shown("leads", s.Leads.ToString()) + " 份资料", Accent = DashboardPalette.Orange, Symbol = "¥" }, "cost");
            AddNavigable(new MetricDashboardCard { Width = metricWidth, Height = 148, Title = "营业额", Value = hideRevenue ? "—" : shown("revenue", DrawUtil.Money(s.Revenue)), Note = "漏斗 " + (hideRevenue ? "—" : DrawUtil.Money(displayFunnelRevenue)) + " + 其他 " + (hideRevenue ? "—" : DrawUtil.Money(displayOtherRevenue)), Accent = DashboardPalette.Indigo, Symbol = "▤" }, "revenue");
            int shownLeads, shownNewOrders; Int32.TryParse(shown("leads", s.Leads.ToString()), out shownLeads); Int32.TryParse(shown("neworders", s.NewCustomers.ToString()), out shownNewOrders);
            AddNavigable(new MetricDashboardCard { Width = metricWidth, Height = 148, Title = "新单成交率", Value = shown("newrate", shownLeads > 0 ? ((double)shownNewOrders / shownLeads).ToString("P1") : "—"), Note = shownNewOrders + " / " + shownLeads + " 位客户", Accent = DashboardPalette.Green, Symbol = "✓" }, "newrate"); Break();
            int half = (width - 40) / 2; DateTime cutoff = DateTime.Now.AddDays(-15);
            int recent = customers.Count(delegate(Customer c) { return c.dataType == "fullCustomer" && c.costEnabled && c.importDate >= cutoff && !c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单"; }); });
            int pendingNew = customers.Count(delegate(Customer c) { return c.dataType == "fullCustomer" && c.costEnabled && !c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单"; }); });
            int pendingSecond = customers.Count(delegate(Customer c) { return c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "新单"; }) && !c.ValidConversions.Exists(delegate(ConversionRecord r) { return r.type == "二次"; }) && !settings.dismissedPendingSecondCustomerIDs.Contains(c.id); });
            int parsed; Func<string, int, int> shownInt = delegate(string key, int fallback) { return Int32.TryParse(shown(key, fallback.ToString()), out parsed) ? parsed : fallback; };
            AddNavigable(new FollowUpDashboardCard { Width = half, Height = 294, RecentPending = shownInt("recentPending", recent), NewPending = shownInt("pendingNew", pendingNew), SecondPending = shownInt("pendingSecond", pendingSecond) }, "followup");
            AddNavigable(new FunnelDashboardCard { Width = half, Height = 294, Leads = shownInt("leads", s.Leads), NewOrders = shownInt("neworders", s.NewCustomers), SecondOrders = shownInt("secondorders", s.SecondOrders), NewAmount = s.NewAmount * revenueScale, SecondAmount = s.SecondAmount * revenueScale, HideRevenue = hideRevenue }, "funnel"); Break();
            List<DailyAuditRow> days = DailyRows(customers, monthly, year, month); int dailyHeight = Math.Max(155, 88 + Math.Min(6, days.Count) * 62);
            if (settings.demoEnabled) foreach (DailyAuditRow day in days) { day.Cost *= costScale; day.Revenue *= revenueScale; }
            AddNavigable(new DailyAuditDashboardCard { Width = half, Height = dailyHeight, Rows = days, HideCost = hideCost, HideRevenue = hideRevenue }, "daily");
            List<ChannelStat> channelRows = StatisticsEngine.Channels(customers, monthly, year, month); if (settings.demoEnabled) foreach (ChannelStat row in channelRows) row.Revenue *= revenueScale;
            ChannelOverviewDashboardCard channelCard = new ChannelOverviewDashboardCard { Width = half, Height = dailyHeight, Rows = channelRows, HideRevenue = hideRevenue, Cursor = Cursors.Hand };
            channelCard.ChannelClicked += delegate(string channel) { if (Navigate != null) Navigate("channel:" + channel); };
            canvas.Controls.Add(channelCard);
            canvas.ResumeLayout(); ResizeCards();
        }
        public void ScrollToSection(int section)
        {
            if (canvas.Controls.Count == 0) return;
            int index = section <= 0 ? 0 : (section == 1 ? 5 : 7);
            if (index >= canvas.Controls.Count) index = canvas.Controls.Count - 1;
            canvas.ScrollControlIntoView(canvas.Controls[index]);
            canvas.Controls[index].Focus();
        }
        private List<DailyAuditRow> DailyRows(List<Customer> customers, bool monthly, int year, int month)
        {
            Dictionary<DateTime, DailyAuditRow> map = new Dictionary<DateTime, DailyAuditRow>();
            foreach (Customer c in customers)
            {
                if ((!monthly || StatisticsEngine.InMonth(c.importDate, year, month)) && c.dataType == "fullCustomer" && c.costEnabled) { DateTime key = c.importDate.Date; if (!map.ContainsKey(key)) map[key] = new DailyAuditRow { Date = key }; map[key].Leads++; map[key].Cost += c.lineCost; }
                foreach (ConversionRecord r in c.ValidConversions) if (!monthly || StatisticsEngine.InMonth(r.date, year, month)) { DateTime key = r.date.Date; if (!map.ContainsKey(key)) map[key] = new DailyAuditRow { Date = key }; map[key].Orders++; map[key].Revenue += r.amount; }
            }
            return map.Values.OrderByDescending(delegate(DailyAuditRow x) { return x.Date; }).ToList();
        }
        private void Break() { canvas.SetFlowBreak(canvas.Controls[canvas.Controls.Count - 1], true); }
        private static double DisplayNumber(string text, double fallback)
        {
            if (String.IsNullOrWhiteSpace(text)) return fallback;
            string normalized = text.Replace("¥", "").Replace("￥", "").Replace(",", "").Trim();
            double value; return Double.TryParse(normalized, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out value) && value >= 0 ? value : fallback;
        }
        private void AddNavigable(Control card, string key) { card.Cursor = Cursors.Hand; card.Click += delegate { if (Navigate != null) Navigate(key); }; canvas.Controls.Add(card); }
        private void ResizeCards()
        {
            if (canvas.Controls.Count < 9) return;
            int width = Math.Max(900, ClientSize.Width - 70);
            canvas.Controls[0].Width = width;
            int metricWidth = (width - 80) / 4;
            for (int i = 1; i <= 4; i++) canvas.Controls[i].Width = metricWidth;
            int half = (width - 40) / 2;
            for (int i = 5; i < canvas.Controls.Count; i++) canvas.Controls[i].Width = half;
        }
    }
}
