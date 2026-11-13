// Nepali date in the Windows notification area (system tray). All data comes from
// miti.exe: `miti today -j` once per Nepal day, `miti month Y-M` once per month shown.
//
// Written without access to Windows or a .NET SDK: it has never been compiled or run.

using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;
using Drawing = System.Drawing;
using WinForms = System.Windows.Forms;

namespace MitiTray;

/// <summary>One day, as printed by `miti today -j` (JSON keys are these names in snake_case).</summary>
record DayInfo(
    string Bs, string Ad, int Year, int Month, int Day, int Weekday,
    string YearNp, string MonthNp, string DayNp, string WeekdayNp, string MonthEn, string WeekdayEn,
    string Tithi, bool Holiday, string EventNp, string EventEn);

/// <summary>One month, as printed by `miti month Y-M`.</summary>
record MonthInfo(int Year, int Month, string YearNp, string MonthNp, string MonthEn, DayInfo[] Days);

static class Program
{
    static readonly string[] Weekdays = { "आइत", "सोम", "मंगल", "बुध", "बिही", "शुक्र", "शनि" };
    static readonly string[] AdMonths = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };

    static readonly Brush Bg = Hex("#2b2d31"), Fg = Hex("#e6e6e6"), Dim = Hex("#9a9ca3"),
        Red = Hex("#e5484d"), Accent = Hex("#5865f2");

    // A borderless button: rounded, with a faint hover wash laid over whatever Background the button has.
    static readonly Style Flat = (Style)XamlReader.Parse(@"
<Style xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
       xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='Button'>
  <Setter Property='Background' Value='Transparent'/>
  <Setter Property='BorderBrush' Value='Transparent'/>
  <Setter Property='BorderThickness' Value='2'/>
  <Setter Property='Padding' Value='4,2'/>
  <Setter Property='Cursor' Value='Hand'/>
  <Setter Property='HorizontalContentAlignment' Value='Stretch'/>
  <Setter Property='VerticalContentAlignment' Value='Stretch'/>
  <Setter Property='Template'>
    <Setter.Value>
      <ControlTemplate TargetType='Button'>
        <Border Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}'
                BorderThickness='{TemplateBinding BorderThickness}' CornerRadius='5'>
          <Border x:Name='wash' Background='Transparent' CornerRadius='3' Padding='{TemplateBinding Padding}'>
            <ContentPresenter HorizontalAlignment='{TemplateBinding HorizontalContentAlignment}'
                              VerticalAlignment='{TemplateBinding VerticalContentAlignment}'/>
          </Border>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property='IsMouseOver' Value='True'>
            <Setter TargetName='wash' Property='Background' Value='#22FFFFFF'/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>");

    static DayInfo? today;     // today's day
    static MonthInfo? month;   // the month on screen
    static DayInfo? sel;       // the day whose details are shown
    static DateTime hiddenAt;  // when the popup last hid itself
    static Window popup = null!;
    static StackPanel root = null!;
    static FrameworkElement converter = null!;  // built once, re-added on every Render
    static TextBlock convertError = null!;
    static WinForms.NotifyIcon tray = null!;

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr handle);

    [STAThread]
    static void Main()
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };

        root = new StackPanel { Margin = new Thickness(12), Width = 430 };
        BuildConverter();
        popup = new Window
        {
            Title = "Nepali Date",
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false,
            Topmost = true,
            SizeToContent = SizeToContent.WidthAndHeight,
            Background = Bg,
            Foreground = Fg,
            FontFamily = new FontFamily("Nirmala UI, Segoe UI"), // Nirmala UI is Windows' Devanagari font
            Content = new Border { BorderBrush = Dim, BorderThickness = new Thickness(1), Child = root },
        };
        popup.Deactivated += (_, _) => { popup.Hide(); hiddenAt = DateTime.UtcNow; };
        popup.SizeChanged += (_, _) => Place();
        popup.KeyDown += (_, e) => { if (e.Key == Key.Escape) popup.Hide(); };

        var menu = new WinForms.ContextMenuStrip();
        menu.Items.Add("Exit", null, (_, _) => { tray.Visible = false; app.Shutdown(); });
        tray = new WinForms.NotifyIcon
        {
            Visible = true,
            Text = "Nepali Date",
            Icon = Drawing.SystemIcons.Application,
            ContextMenuStrip = menu,
        };
        tray.MouseClick += (_, e) => { if (e.Button == WinForms.MouseButtons.Left) Toggle(); };

        // Poll the clock instead of one long timer: survives sleep and clock changes,
        // and retries if miti.exe was missing. Spawns only on a new day.
        Refresh();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        timer.Tick += (_, _) => Refresh();
        timer.Start();

        app.Run();
    }

    static Brush Hex(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }

    /// <summary>Runs miti.exe (beside this program, else on PATH) and parses its JSON. Null on any failure.</summary>
    static T? Run<T>(params string[] args) where T : class
    {
        try
        {
            var beside = Path.Combine(AppContext.BaseDirectory, "miti.exe");
            var info = new ProcessStartInfo(File.Exists(beside) ? beside : "miti")
            {
                RedirectStandardOutput = true,
                StandardOutputEncoding = Encoding.UTF8,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            foreach (var arg in args) info.ArgumentList.Add(arg);
            using var process = Process.Start(info)!;
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            return process.ExitCode == 0 ? JsonSerializer.Deserialize<T>(output, Json) : null;
        }
        catch (Exception)
        {
            return null; // miti.exe missing or output unreadable; the popup says so
        }
    }

    static void Refresh()
    {
        // The BS date rolls over at Nepal midnight (UTC+5:45).
        var nepalDay = DateTime.UtcNow.AddMinutes(5 * 60 + 45).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        if (today?.Ad == nepalDay) return;
        today = Run<DayInfo>("today", "-j");
        if (today == null) { Render(); return; }
        tray.Text = $"{today.YearNp} {today.MonthNp} {today.DayNp}, {today.WeekdayNp}";
        SetIcon(today.DayNp);
        Show(today.Year, today.Month);
    }

    /// <summary>Month arithmetic wraps the year; a month outside the table fails in miti and the view stays put.</summary>
    /// <param name="want">BS date to select instead of today (from the converter).</param>
    static void Show(int year, int monthNumber, string? want = null)
    {
        int n = year * 12 + monthNumber - 1;
        var got = Run<MonthInfo>("month", $"{n / 12}-{n % 12 + 1}");
        if (got == null) return;
        month = got;
        sel = got.Days.FirstOrDefault(d => d.Bs == want) ?? got.Days.FirstOrDefault(d => d.Bs == today?.Bs) ?? got.Days[0];
        Render();
    }

    /// <summary>Converter row: jump to the typed date; the details pane then shows it in both calendars.</summary>
    static void BuildConverter()
    {
        var input = new TextBox
        {
            Background = Hex("#1e1f22"), Foreground = Fg, CaretBrush = Fg, BorderBrush = Dim,
            Padding = new Thickness(4, 3, 4, 3), VerticalContentAlignment = VerticalAlignment.Center,
            ToolTip = "Date as YYYY-MM-DD",
        };
        AutomationProperties.SetName(input, "Date to convert, YYYY-MM-DD");
        convertError = Label("", 13, Red);

        void Convert(string command)
        {
            var d = Run<DayInfo>(command, input.Text.Trim(), "-j");
            convertError.Text = d == null ? "No such date in the table (BS 1901–2199)" : "";
            if (d != null) Show(d.Year, d.Month, d.Bs);
        }
        input.KeyDown += (_, e) => { if (e.Key == Key.Enter) Convert("ad2bs"); }; // Enter converts AD to BS

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(6, 0, 0, 0) };
        buttons.Children.Add(Nav("AD → BS", "Convert AD to BS", () => Convert("ad2bs")));
        buttons.Children.Add(Nav("BS → AD", "Convert BS to AD", () => Convert("bs2ad")));
        var row = new DockPanel { Margin = new Thickness(0, 8, 0, 0) };
        DockPanel.SetDock(buttons, Dock.Right);
        row.Children.Add(buttons);
        row.Children.Add(input);

        var panel = new StackPanel();
        panel.Children.Add(new Border { Height = 1, Background = Dim, Opacity = 0.4, Margin = new Thickness(0, 8, 0, 0) });
        panel.Children.Add(row);
        panel.Children.Add(convertError);
        converter = panel;
    }

    /// <summary>Draws the day number as the tray icon.</summary>
    static void SetIcon(string text)
    {
        using var bitmap = new Drawing.Bitmap(32, 32);
        using (var g = Drawing.Graphics.FromImage(bitmap))
        {
            g.TextRenderingHint = Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            g.Clear(Drawing.Color.FromArgb(0x58, 0x65, 0xf2));
            using var font = new Drawing.Font("Nirmala UI", 18, Drawing.FontStyle.Bold, Drawing.GraphicsUnit.Pixel);
            using var center = new Drawing.StringFormat
            {
                Alignment = Drawing.StringAlignment.Center,
                LineAlignment = Drawing.StringAlignment.Center,
            };
            g.DrawString(text, font, Drawing.Brushes.White, new Drawing.RectangleF(0, 0, 32, 32), center);
        }
        // Clone owns its own copy, so the GDI handle can be freed straight away.
        var handle = bitmap.GetHicon();
        tray.Icon = (Drawing.Icon)Drawing.Icon.FromHandle(handle).Clone();
        DestroyIcon(handle);
    }

    static void Toggle()
    {
        // Clicking the tray icon while the popup is open first deactivates (hides) it,
        // then lands here: treat that click as "close", not "reopen".
        if (popup.IsVisible || (DateTime.UtcNow - hiddenAt).TotalMilliseconds < 300)
        {
            popup.Hide();
            return;
        }
        // Every open starts on today, never on a stale pick.
        if (today != null) Show(today.Year, today.Month);
        popup.Show();
        popup.Activate();
    }

    // shortcut: assumes the taskbar is at the bottom of the primary screen, the Windows 11 default
    static void Place()
    {
        var area = SystemParameters.WorkArea;
        popup.Left = area.Right - popup.ActualWidth - 8;
        popup.Top = area.Bottom - popup.ActualHeight - 8;
    }

    static TextBlock Label(string text, double size, Brush color, bool bold = false) => new()
    {
        Text = text,
        FontSize = size,
        Foreground = color,
        FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
        TextWrapping = TextWrapping.Wrap,
    };

    static Button Nav(string text, string name, Action go)
    {
        var button = new Button { Style = Flat, Content = Label(text, 14, Fg), Padding = new Thickness(8, 2, 8, 2) };
        AutomationProperties.SetName(button, name);
        button.Click += (_, _) => go();
        return button;
    }

    /// <summary>"Oct – Nov 2026" for the AD days the month spans.</summary>
    static string AdSpan(MonthInfo m)
    {
        string[] a = m.Days[0].Ad.Split('-'), b = m.Days[^1].Ad.Split('-');
        string Name(string part) => AdMonths[int.Parse(part, CultureInfo.InvariantCulture) - 1];
        return $"{Name(a[1])}{(a[0] == b[0] ? "" : " " + a[0])} – {Name(b[1])} {b[0]}";
    }

    static Button Cell(DayInfo d)
    {
        bool isToday = d.Bs == today?.Bs, isSel = d.Bs == sel?.Bs;
        Brush ink = isToday ? Brushes.White : d.Holiday || d.Weekday == 6 ? Red : Fg;

        var grid = new Grid { MinHeight = 54 };
        if (d.EventNp != "")
        {
            // Dot: the day has an event.
            grid.Children.Add(new System.Windows.Shapes.Ellipse
            {
                Width = 5, Height = 5, Fill = ink, Margin = new Thickness(0, 4, 0, 0),
                HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top,
            });
        }
        var ad = Label(int.Parse(d.Ad[8..], CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture), 10, ink);
        ad.Opacity = 0.7;
        ad.HorizontalAlignment = HorizontalAlignment.Right;
        ad.VerticalAlignment = VerticalAlignment.Top;
        var day = Label(d.DayNp, 18, ink);
        day.HorizontalAlignment = HorizontalAlignment.Center;
        day.VerticalAlignment = VerticalAlignment.Center;
        var tithi = Label(d.Tithi, 10, ink);
        tithi.Opacity = 0.7;
        tithi.TextWrapping = TextWrapping.NoWrap;
        tithi.TextTrimming = TextTrimming.CharacterEllipsis;
        tithi.HorizontalAlignment = HorizontalAlignment.Center;
        tithi.VerticalAlignment = VerticalAlignment.Bottom;
        grid.Children.Add(ad);
        grid.Children.Add(day);
        grid.Children.Add(tithi);

        var button = new Button
        {
            Style = Flat,
            Content = grid,
            Margin = new Thickness(1),
            Background = isToday ? Accent : Brushes.Transparent,
            BorderBrush = !isSel ? Brushes.Transparent : isToday ? Brushes.White : Accent,
        };
        AutomationProperties.SetName(button, $"{d.Day} {d.MonthEn}, {d.Tithi} {d.EventEn}");
        button.Click += (_, _) => { sel = d; Render(); };
        return button;
    }

    /// <summary>Rebuilds the popup from `month` and `sel`.</summary>
    static void Render()
    {
        root.Children.Clear();
        if (month == null || sel == null)
        {
            root.Children.Add(Label("miti.exe not found", 16, Fg, bold: true));
            root.Children.Add(Label("Put miti.exe next to this program or on PATH.", 13, Dim));
            return;
        }
        MonthInfo m = month;
        DayInfo s = sel;

        // Header: month, AD span, navigation.
        var titles = new StackPanel();
        titles.Children.Add(Label($"{m.MonthNp} {m.YearNp}", 20, Fg, bold: true));
        titles.Children.Add(Label($"{m.MonthEn} {m.Year} · {AdSpan(m)}", 13, Dim));
        var nav = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        nav.Children.Add(Nav("←", "Previous month", () => Show(m.Year, m.Month - 1)));
        nav.Children.Add(Nav("आज", "Today", () => { if (today != null) Show(today.Year, today.Month); }));
        nav.Children.Add(Nav("→", "Next month", () => Show(m.Year, m.Month + 1)));
        var header = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        DockPanel.SetDock(nav, Dock.Right);
        header.Children.Add(nav);
        header.Children.Add(titles);
        root.Children.Add(header);

        // Weekday names, then the days. FirstColumn offsets day 1 to its weekday.
        var names = new UniformGrid { Columns = 7 };
        for (int i = 0; i < 7; i++)
        {
            var name = Label(Weekdays[i], 12, i == 6 ? Red : Dim);
            name.HorizontalAlignment = HorizontalAlignment.Center;
            names.Children.Add(name);
        }
        root.Children.Add(names);
        var days = new UniformGrid { Columns = 7, FirstColumn = m.Days[0].Weekday };
        foreach (var d in m.Days) days.Children.Add(Cell(d));
        root.Children.Add(days);
        root.Children.Add(new Border { Height = 1, Background = Dim, Opacity = 0.4, Margin = new Thickness(0, 8, 0, 8) });

        // Details of the selected day. Fixed minimum height so the popup does not jump.
        var details = new StackPanel { MinHeight = 120 };
        var heading = new StackPanel { Orientation = Orientation.Horizontal };
        heading.Children.Add(Label($"{s.YearNp} {s.MonthNp} {s.DayNp}, {s.WeekdayNp}", 16, Fg, bold: true));
        if (s.Holiday)
        {
            var holiday = Label("बिदा", 13, Red);
            holiday.Margin = new Thickness(8, 0, 0, 0);
            holiday.VerticalAlignment = VerticalAlignment.Center;
            heading.Children.Add(holiday);
        }
        details.Children.Add(heading);
        details.Children.Add(Label($"{s.WeekdayEn}, {s.MonthEn} {s.Day}, {s.Year} BS · {s.Ad} AD", 13, Dim));
        if (s.Tithi != "") details.Children.Add(Label($"तिथि: {s.Tithi}", 13, Fg));
        // English titles; Nepali only when the patro has no English one.
        var events = s.EventEn != "" ? s.EventEn : s.EventNp;
        if (events != "") details.Children.Add(Label(events.Replace(" / ", "\n"), 13, Fg));
        root.Children.Add(details);
        root.Children.Add(converter);
    }
}
