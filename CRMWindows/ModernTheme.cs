using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace CRMWindows
{
    public static class CrmTheme
    {
        private static readonly string PreferredFontName = ResolvePreferredFont();
        private static readonly Dictionary<string, Font> PaintFonts = new Dictionary<string, Font>();
        public static string TypefaceName { get { return PreferredFontName; } }
        public static readonly Color Ground = Color.FromArgb(238, 241, 250);
        public static readonly Color Sidebar = Color.FromArgb(22, 27, 48);
        public static readonly Color Surface = Color.FromArgb(249, 250, 255);
        public static readonly Color SurfaceRaised = Color.FromArgb(255, 255, 255);
        public static readonly Color SurfaceSoft = Color.FromArgb(239, 242, 251);
        public static readonly Color Border = Color.FromArgb(202, 210, 232);
        public static readonly Color BorderSoft = Color.FromArgb(220, 226, 241);
        public static readonly Color Text = Color.FromArgb(25, 29, 48);
        public static readonly Color Muted = Color.FromArgb(95, 105, 132);
        public static readonly Color Faint = Color.FromArgb(137, 146, 171);
        public static readonly Color Coral = Color.FromArgb(79, 70, 229);
        public static readonly Color Lilac = Color.FromArgb(139, 70, 232);
        public static readonly Color Blue = Color.FromArgb(37, 99, 235);
        public static readonly Color Green = Color.FromArgb(5, 172, 121);
        public static readonly Color Orange = Color.FromArgb(244, 117, 32);
        public static readonly Color Red = Color.FromArgb(239, 65, 94);
        public static readonly Color Cyan = Color.FromArgb(6, 182, 212);

        public static Font Font(float size, FontStyle style = FontStyle.Regular)
        {
            return new Font(PreferredFontName, size, style, GraphicsUnit.Point);
        }

        public static Font PaintFont(float size, FontStyle style = FontStyle.Regular)
        {
            string key = size.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture) + ":" + (int)style;
            Font font;
            if (!PaintFonts.TryGetValue(key, out font))
            {
                font = Font(size, style);
                PaintFonts[key] = font;
            }
            return font;
        }

        private static string ResolvePreferredFont()
        {
            string requested = Environment.GetEnvironmentVariable("PRIVATE_CRM_FONT");
            if (!String.IsNullOrWhiteSpace(requested))
            {
                try { using (Font probe = new Font(requested, 10F, FontStyle.Regular, GraphicsUnit.Point)) if (String.Equals(probe.Name, requested, StringComparison.OrdinalIgnoreCase)) return probe.Name; }
                catch { }
            }
            try
            {
                using (Font probe = new Font("Microsoft YaHei UI", 10F, FontStyle.Regular, GraphicsUnit.Point))
                    if (String.Equals(probe.Name, "Microsoft YaHei UI", StringComparison.OrdinalIgnoreCase)) return probe.Name;
            }
            catch { }
            return SystemFonts.MessageBoxFont.Name;
        }

        public static void StyleInput(Control control)
        {
            control.BackColor = SurfaceSoft;
            control.ForeColor = Text;
            control.Font = Font(9.5F);
            control.Enter += delegate { control.BackColor = SurfaceRaised; };
            control.Leave += delegate { control.BackColor = SurfaceSoft; };
        }

        public static void StyleGrid(DataGridView grid)
        {
            grid.BackgroundColor = Surface;
            grid.BorderStyle = BorderStyle.None;
            grid.GridColor = BorderSoft;
            grid.EnableHeadersVisualStyles = false;
            grid.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
            grid.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None;
            grid.ColumnHeadersDefaultCellStyle.BackColor = SurfaceRaised;
            grid.ColumnHeadersDefaultCellStyle.ForeColor = Muted;
            grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = SurfaceRaised;
            grid.ColumnHeadersDefaultCellStyle.SelectionForeColor = Text;
            grid.ColumnHeadersDefaultCellStyle.Font = Font(9.5F, FontStyle.Bold);
            grid.DefaultCellStyle.BackColor = Surface;
            grid.DefaultCellStyle.ForeColor = Text;
            grid.DefaultCellStyle.SelectionBackColor = Color.FromArgb(221, 229, 247);
            grid.DefaultCellStyle.SelectionForeColor = Text;
            grid.DefaultCellStyle.Font = Font(9.5F);
            grid.AlternatingRowsDefaultCellStyle.BackColor = Surface;
            grid.AlternatingRowsDefaultCellStyle.ForeColor = Text;
            grid.RowTemplate.Height = 38;
        }

        public static void StylePanelTree(Control root)
        {
            foreach (Control child in root.Controls)
            {
                if (child is DataGridView) StyleGrid((DataGridView)child);
                else if (child is TextBox || child is ComboBox || child is NumericUpDown) StyleInput(child);
                else if (child is CheckBox)
                {
                    child.ForeColor = Text;
                    child.BackColor = Color.Transparent;
                }
                else if (child is GroupBox)
                {
                    child.ForeColor = Text;
                    child.BackColor = Surface;
                    child.Font = Font(10.5F, FontStyle.Bold);
                }
                else if (child is Label && child.ForeColor == SystemColors.ControlText)
                {
                    child.ForeColor = Muted;
                    child.BackColor = Color.Transparent;
                }
                StylePanelTree(child);
            }
        }

        public static void StyleDialog(Form form)
        {
            form.BackColor = Ground;
            form.ForeColor = Text;
            form.Font = Font(9.5F);
            StyleDialogTree(form);
        }

        private static void StyleDialogTree(Control root)
        {
            foreach (Control child in root.Controls)
            {
                if (child is TabPage || child is TableLayoutPanel || child is FlowLayoutPanel || child is Panel)
                {
                    child.BackColor = Surface;
                    child.ForeColor = Text;
                }
                if (child is DataGridView) StyleGrid((DataGridView)child);
                else if (child is TextBox || child is ComboBox || child is NumericUpDown || child is DateTimePicker) StyleInput(child);
                else if (child is Label)
                {
                    child.ForeColor = child.ForeColor == Color.DarkOrange ? Orange : Muted;
                    child.BackColor = Color.Transparent;
                }
                else if (child is CheckBox)
                {
                    child.ForeColor = Text;
                    child.BackColor = Color.Transparent;
                }
                else if (child is Button && child.BackColor == SystemColors.Control)
                {
                    child.BackColor = SurfaceSoft;
                    child.ForeColor = Text;
                    ((Button)child).FlatStyle = FlatStyle.Flat;
                    ((Button)child).FlatAppearance.BorderColor = Border;
                }
                StyleDialogTree(child);
            }
        }
    }

    public class AuroraPanel : Panel
    {
        public AuroraPanel()
        {
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            using (LinearGradientBrush baseBrush = new LinearGradientBrush(ClientRectangle, Color.FromArgb(248, 247, 255), Color.FromArgb(227, 239, 252), 32F))
                e.Graphics.FillRectangle(baseBrush, ClientRectangle);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush violet = new SolidBrush(Color.FromArgb(31, CrmTheme.Lilac)))
                e.Graphics.FillEllipse(violet, Width - 520, -300, 690, 520);
            using (SolidBrush blue = new SolidBrush(Color.FromArgb(24, CrmTheme.Cyan)))
                e.Graphics.FillEllipse(blue, -280, Height - 360, 540, 500);
            using (SolidBrush coral = new SolidBrush(Color.FromArgb(16, CrmTheme.Red)))
                e.Graphics.FillEllipse(coral, Width / 3, Height - 260, 460, 360);
        }
    }

    public class GlassPanel : Panel
    {
        public int Radius = 18;
        public Color FillColor = CrmTheme.Surface;

        public GlassPanel()
        {
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF rect = new RectangleF(0.5F, 0.5F, Width - 1.5F, Height - 1.5F);
            using (SolidBrush fill = new SolidBrush(FillColor)) DrawUtil.FillRound(e.Graphics, fill, rect, Radius);
            using (Pen border = new Pen(CrmTheme.Border)) DrawUtil.DrawRound(e.Graphics, border, rect, Radius);
            base.OnPaint(e);
        }
    }

    public class InteractiveSurfacePanel : Panel
    {
        private bool hovered;
        private float progress;
        private Point pointer;
        private readonly Timer timer;
        private int lastPointerPaint;

        public InteractiveSurfacePanel()
        {
            BackColor = CrmTheme.Surface;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            timer = new Timer { Interval = 16 };
            timer.Tick += delegate
            {
                float target = hovered ? 1F : 0F;
                progress += (target - progress) * 0.35F;
                if (Math.Abs(target - progress) < 0.025F) { progress = target; timer.Stop(); }
                Invalidate();
            };
            MouseEnter += HandleEnter;
            MouseMove += HandleMove;
            MouseLeave += HandleLeave;
        }

        protected override void OnControlAdded(ControlEventArgs e)
        {
            base.OnControlAdded(e);
            Wire(e.Control);
        }

        private void Wire(Control control)
        {
            control.MouseEnter += HandleEnter;
            control.MouseMove += HandleMove;
            control.MouseLeave += HandleLeave;
            control.ControlAdded += delegate(object sender, ControlEventArgs e) { Wire(e.Control); };
            foreach (Control child in control.Controls) Wire(child);
        }

        private void HandleEnter(object sender, EventArgs e)
        {
            hovered = true;
            pointer = PointToClient(Cursor.Position);
            timer.Start();
        }

        private void HandleMove(object sender, MouseEventArgs e)
        {
            Point next = PointToClient(Cursor.Position);
            int now = Environment.TickCount;
            int dx = next.X - pointer.X, dy = next.Y - pointer.Y;
            if (dx * dx + dy * dy < 100 || unchecked(now - lastPointerPaint) < 40) return;
            pointer = next;
            lastPointerPaint = now;
            Invalidate();
        }

        private void HandleLeave(object sender, EventArgs e)
        {
            if (ClientRectangle.Contains(PointToClient(Cursor.Position))) return;
            hovered = false;
            timer.Start();
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(Parent == null ? CrmTheme.Ground : Parent.BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF shadow = new RectangleF(3, 4 - progress * 2F, Width - 6, Height - 7);
            using (SolidBrush b = new SolidBrush(Color.FromArgb((int)(12 + 20 * progress), 45, 63, 102))) DrawUtil.FillRound(e.Graphics, b, shadow, 16);
            RectangleF card = new RectangleF(1, 1 - progress * 2F, Width - 3, Height - 4);
            using (SolidBrush fill = new SolidBrush(CrmTheme.Surface)) DrawUtil.FillRound(e.Graphics, fill, card, 16);
            if (progress > 0.02F)
            {
                GraphicsState state = e.Graphics.Save();
                using (GraphicsPath clip = DrawUtil.RoundRect(card, 16)) e.Graphics.SetClip(clip);
                using (SolidBrush glow = new SolidBrush(Color.FromArgb((int)(28 * progress), CrmTheme.Cyan))) e.Graphics.FillEllipse(glow, pointer.X - 105, pointer.Y - 105, 210, 210);
                e.Graphics.Restore(state);
            }
            using (LinearGradientBrush borderBrush = new LinearGradientBrush(card, Blend(CrmTheme.Border, CrmTheme.Cyan, progress), Blend(CrmTheme.Border, CrmTheme.Lilac, progress), 0F))
            using (Pen border = new Pen(borderBrush, 1F + progress * 0.6F)) DrawUtil.DrawRound(e.Graphics, border, card, 16);
        }

        private static Color Blend(Color a, Color b, float amount)
        {
            return Color.FromArgb((int)(a.R + (b.R - a.R) * amount), (int)(a.G + (b.G - a.G) * amount), (int)(a.B + (b.B - a.B) * amount));
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && timer != null) timer.Dispose();
            base.Dispose(disposing);
        }
    }

    public class InteractiveGroupBox : GroupBox
    {
        private bool hovered;
        private float progress;
        private readonly Timer timer;

        public InteractiveGroupBox()
        {
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            timer = new Timer { Interval = 16 };
            timer.Tick += delegate
            {
                float target = hovered ? 1F : 0F;
                progress += (target - progress) * 0.35F;
                if (Math.Abs(target - progress) < 0.025F) { progress = target; timer.Stop(); }
                Invalidate();
            };
            MouseEnter += EnterCard;
            MouseLeave += LeaveCard;
        }

        protected override void OnControlAdded(ControlEventArgs e)
        {
            base.OnControlAdded(e);
            e.Control.MouseEnter += EnterCard;
            e.Control.MouseLeave += LeaveCard;
        }

        private void EnterCard(object sender, EventArgs e) { hovered = true; timer.Start(); }
        private void LeaveCard(object sender, EventArgs e)
        {
            if (ClientRectangle.Contains(PointToClient(Cursor.Position))) return;
            hovered = false; timer.Start();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent == null ? CrmTheme.Ground : Parent.BackColor);
            RectangleF rect = new RectangleF(1, 1 - progress * 1.5F, Width - 3, Height - 3);
            using (SolidBrush fill = new SolidBrush(CrmTheme.Surface)) DrawUtil.FillRound(e.Graphics, fill, rect, 14);
            Color start = Blend(CrmTheme.Border, CrmTheme.Cyan, progress);
            Color end = Blend(CrmTheme.Border, CrmTheme.Lilac, progress);
            using (LinearGradientBrush brush = new LinearGradientBrush(rect, start, end, 0F))
            using (Pen pen = new Pen(brush, 1F + progress * 0.7F)) DrawUtil.DrawRound(e.Graphics, pen, rect, 14);
            DrawUtil.DrawText(e.Graphics, Text, CrmTheme.PaintFont(10.5F, FontStyle.Bold), CrmTheme.Text, new Rectangle(14, 7, Width - 28, 24), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }

        private static Color Blend(Color a, Color b, float amount)
        {
            return Color.FromArgb((int)(a.R + (b.R - a.R) * amount), (int)(a.G + (b.G - a.G) * amount), (int)(a.B + (b.B - a.B) * amount));
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && timer != null) timer.Dispose();
            base.Dispose(disposing);
        }
    }

    public class SidebarNavButton : Button
    {
        private bool selected;
        private bool hovered;
        public string Symbol { get; set; }
        public bool Selected
        {
            get { return selected; }
            set { selected = value; Invalidate(); }
        }

        public SidebarNavButton()
        {
            Height = 48;
            Cursor = Cursors.Hand;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            TabStop = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            BackColor = CrmTheme.Sidebar;
        }

        protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovered = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush background = new SolidBrush(CrmTheme.Sidebar)) e.Graphics.FillRectangle(background, ClientRectangle);
            RectangleF rect = new RectangleF(4, 3, Width - 8, Height - 6);
            if (Selected || hovered)
            {
                Color start = Selected ? Color.FromArgb(56, CrmTheme.Blue) : Color.FromArgb(22, 255, 255, 255);
                Color end = Selected ? Color.FromArgb(66, CrmTheme.Lilac) : Color.FromArgb(22, 255, 255, 255);
                using (LinearGradientBrush b = new LinearGradientBrush(rect, start, end, 0F)) DrawUtil.FillRound(e.Graphics, b, rect, 12);
                if (Selected)
                {
                    using (SolidBrush liquid = new SolidBrush(Color.FromArgb(42, CrmTheme.Cyan))) e.Graphics.FillEllipse(liquid, Width - 64, -9, 76, 62);
                    using (SolidBrush accent = new SolidBrush(CrmTheme.Cyan)) DrawUtil.FillRound(e.Graphics, accent, new RectangleF(4, 11, 4, 26), 2);
                }
                if (hovered) using (Pen glow = new Pen(Color.FromArgb(120, CrmTheme.Cyan), 1.2F)) DrawUtil.DrawRound(e.Graphics, glow, rect, 12);
            }
            Color foreground = Selected ? Color.White : (hovered ? Color.FromArgb(232, 239, 255) : Color.FromArgb(169, 180, 207));
            DrawUtil.DrawText(e.Graphics, Symbol ?? "•", CrmTheme.PaintFont(11F, FontStyle.Bold), Selected ? CrmTheme.Cyan : foreground, new Rectangle(18, 4, 30, Height - 8), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            DrawUtil.DrawText(e.Graphics, Text, CrmTheme.PaintFont(10F, Selected ? FontStyle.Bold : FontStyle.Regular), foreground, new Rectangle(56, 0, Width - 70, Height), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }

    public class ContextButton : Button
    {
        private bool selected;
        private bool hovered;
        private bool pressed;
        public bool Selected { get { return selected; } set { selected = value; Invalidate(); } }
        public ContextButton()
        {
            AutoSize = true;
            Height = 34;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 1;
            Cursor = Cursors.Hand;
            Padding = new Padding(12, 0, 12, 0);
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        }
        protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { pressed = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnPaint(PaintEventArgs pevent)
        {
            pevent.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            pevent.Graphics.Clear(Parent == null ? CrmTheme.SurfaceRaised : Parent.BackColor);
            RectangleF rect = pressed ? new RectangleF(3, 3, Width - 6, Height - 6) : new RectangleF(1, 1, Width - 2, Height - 2);
            Color start = Selected ? Color.FromArgb(226, 231, 255) : (hovered ? Color.FromArgb(245, 247, 255) : CrmTheme.SurfaceRaised);
            Color end = Selected ? Color.FromArgb(239, 225, 255) : start;
            using (LinearGradientBrush fill = new LinearGradientBrush(rect, start, end, 0F)) DrawUtil.FillRound(pevent.Graphics, fill, rect, 10);
            if (Selected)
            {
                using (SolidBrush liquid = new SolidBrush(Color.FromArgb(42, CrmTheme.Cyan))) pevent.Graphics.FillEllipse(liquid, Width - 32, -10, 42, 42);
                using (Pen glow = new Pen(Color.FromArgb(175, CrmTheme.Lilac), 1.4F)) DrawUtil.DrawRound(pevent.Graphics, glow, rect, 10);
            }
            else using (Pen border = new Pen(hovered ? Color.FromArgb(150, CrmTheme.Blue) : CrmTheme.Border)) DrawUtil.DrawRound(pevent.Graphics, border, rect, 10);
            DrawUtil.DrawText(pevent.Graphics, Text, CrmTheme.PaintFont(8.5F, Selected ? FontStyle.Bold : FontStyle.Regular), Selected ? CrmTheme.Coral : (hovered ? CrmTheme.Text : CrmTheme.Muted), Rectangle.Round(rect), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }

    public class LiquidButton : Button
    {
        public Color BaseColor = CrmTheme.Blue;
        public bool Neutral;
        private bool hovered;
        private bool pressed;

        public LiquidButton()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            Cursor = Cursors.Hand;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        }

        protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { pressed = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Color parentColor = Parent == null ? CrmTheme.Surface : Parent.BackColor;
            e.Graphics.Clear(parentColor);
            RectangleF rect = pressed ? new RectangleF(3, 3, Width - 6, Height - 6) : new RectangleF(1, 1, Width - 2, Height - 2);
            Color start = Neutral ? (hovered ? Color.White : CrmTheme.SurfaceSoft) : BaseColor;
            Color end = Neutral ? start : (hovered ? Blend(BaseColor, CrmTheme.Cyan, 0.24F) : Blend(BaseColor, CrmTheme.Lilac, 0.18F));
            using (LinearGradientBrush fill = new LinearGradientBrush(rect, start, end, 0F)) DrawUtil.FillRound(e.Graphics, fill, rect, 10);
            if (hovered)
            {
                using (SolidBrush liquid = new SolidBrush(Color.FromArgb(Neutral ? 24 : 45, Color.White))) e.Graphics.FillEllipse(liquid, Width - 40, -15, 56, 56);
                using (Pen border = new Pen(Neutral ? Color.FromArgb(145, CrmTheme.Blue) : Color.FromArgb(160, CrmTheme.Cyan), 1.3F)) DrawUtil.DrawRound(e.Graphics, border, rect, 10);
            }
            else if (Neutral) using (Pen border = new Pen(CrmTheme.Border)) DrawUtil.DrawRound(e.Graphics, border, rect, 10);
            DrawUtil.DrawText(e.Graphics, Text, CrmTheme.PaintFont(9F, FontStyle.Bold), Neutral ? CrmTheme.Text : Color.White, Rectangle.Round(rect), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }

        private static Color Blend(Color a, Color b, float amount)
        {
            return Color.FromArgb((int)(a.R + (b.R - a.R) * amount), (int)(a.G + (b.G - a.G) * amount), (int)(a.B + (b.B - a.B) * amount));
        }
    }

    public class HiddenTabControl : TabControl
    {
        public HiddenTabControl()
        {
            Appearance = TabAppearance.FlatButtons;
            ItemSize = new Size(0, 1);
            SizeMode = TabSizeMode.Fixed;
            DoubleBuffered = true;
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }
        protected override void WndProc(ref Message m)
        {
            const int TCM_ADJUSTRECT = 0x1328;
            if (m.Msg == TCM_ADJUSTRECT && !DesignMode) m.Result = (IntPtr)1;
            else base.WndProc(ref m);
        }
    }
}
