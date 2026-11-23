// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using CouchSubs.App.Controls;
using CouchSubs.App.Theme;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using CouchSubs.Core;
using CouchSubs.RemotePlay;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

public partial class ConsoleStep : UserControl
{
    private string? selected;

    public ConsoleStep()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            ShowDone();
            await SearchAsync();
        };
    }

    private AppController Controller => (AppController)DataContext;

    private string Host => selected ?? ManualHost.Text.Trim();

    private IReadOnlyList<ConsoleInfo> found = [];
    private bool searching;
    private bool paired;

    /// <summary>Eşleşmiş PS5'in adı ve arama kartının başlığı, sonuç dairesi, "Bağlantı" çizelgesi.</summary>
    private void ShowDone()
    {
        var text = Localizer.Current;
        var name = Controller.Console?.Name;
        var any = found.Count > 0 || Controller.Console is not null;
        Done.Text = Controller.Console is not null ? (string.IsNullOrEmpty(name) ? "PS5" : name) : "";
        Done.Visibility = Done.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        SearchTitle.Text = text[!searching && any ? "PS5 Found" : "Searching for the PS5"];
        Rings.Visibility = searching ? Visibility.Visible : Visibility.Collapsed;
        ResultMark.Visibility = searching ? Visibility.Collapsed : Visibility.Visible;
        ResultDisc.SetResourceReference(System.Windows.Shapes.Shape.FillProperty, any ? "successSoftBrush" : "amberSoftBrush");
        ResultGlyph.Text = any ? "\uE73E" : "\uE721";
        ResultGlyph.SetResourceReference(TextBlock.ForegroundProperty, any ? "successTextBrush" : "amberTextBrush");
        Search.IsEnabled = !searching;
        PerdeProps.SetBusy(Search, searching);
        Search.Content = text[searching ? "Searching…" : "Search Again"];
        ShowTimeline();
    }

    /// <summary>"Bağlantı" adım çizelgesi (Mac ConnectPS5Step.connectionCard): biten amber + tik, şimdiki amber halka.</summary>
    private void ShowTimeline()
    {
        var text = Localizer.Current;
        var account = Controller.HasAccount;
        var isFound = Controller.Console is not null || selected is not null;
        var linked = Controller.Console is not null && paired;
        var chosen = selected is { } host ? text.Format("%@ selected.", found.FirstOrDefault(c => c.Host == host)?.Name is { Length: > 0 } n ? n : host) : null;
        Timeline.Steps =
        [
            new(text["PlayStation Account"], text["Signed in with the second account."], StepTimeline.Phase(account, true)),
            new(text[isFound ? "PS5 Found" : "Searching for the PS5"], chosen, StepTimeline.Phase(isFound, account)),
            new(text["Pairing and First Picture"], text["Setting up an encrypted connection with the PS5."], StepTimeline.Phase(linked, isFound)),
        ];
    }

    private async Task SearchAsync()
    {
        searching = true;
        ShowDone();
        Consoles.Children.Clear();
        found = await Controller.DiscoverConsolesAsync();
        searching = false;
        selected ??= found.FirstOrDefault()?.Host;
        var text = Localizer.Current;
        foreach (var console in found)
        {
            // Seçenek kartı (Perde): 40'lık simge karesi (seçiliyken amber), ad, mono "adres · Açık / Dinlenme Modunda".
            var icon = new IconSquare { Glyph = "\uE7FC", Size = 40, Tone = console.Host == selected ? IconTone.Amber : IconTone.Gray, Margin = Sp.T("0", "0", "m", "0") };
            var name = new TextBlock { Text = string.IsNullOrEmpty(console.Name) ? "PS5" : console.Name, TextTrimming = TextTrimming.CharacterEllipsis };
            name.SetResourceReference(StyleProperty, "UnitTitleText");
            var detail = new TextBlock { Text = $"{console.Host} · {text[console.IsAwake ? "On" : "In Rest Mode"]}", FontSize = 12, Margin = Sp.T("0", "line", "0", "0") };
            System.Windows.Documents.Typography.SetNumeralAlignment(detail, FontNumeralAlignment.Tabular);
            detail.SetResourceReference(TextBlock.ForegroundProperty, "mutedBrush");
            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            texts.Children.Add(name);
            texts.Children.Add(detail);
            var row = new DockPanel();
            DockPanel.SetDock(icon, Dock.Left);
            row.Children.Add(icon);
            row.Children.Add(texts);
            var option = new Controls.OptionCard { Content = row, IsChecked = console.Host == selected, GroupName = "ps5" };
            option.Checked += (_, _) =>
            {
                selected = console.Host;
                foreach (var other in Consoles.Children.OfType<Controls.OptionCard>())
                    if (other.Content is DockPanel { Children: [IconSquare square, ..] }) square.Tone = other == option ? IconTone.Amber : IconTone.Gray;
                ShowTimeline();
            };
            Consoles.Children.Add(option);
        }
        var none = found.Count == 0;
        NotFound.Visibility = ManualHost.Visibility = none ? Visibility.Visible : Visibility.Collapsed;
        ShowDone();
        if (none) await ShowChecksAsync(found.Count > 0);
        else ChecksCard.Visibility = Visibility.Collapsed;
    }

    /// <summary>"Neyin Eksik Olduğuna Baktık": aynı ağ, PS5'in yanıtı, Uzaktan Oynama, dinlenme modunda internet, 5 GHz, VPN.</summary>
    private async Task ShowChecksAsync(bool found)
    {
        var text = Localizer.Current;
        ChecksCard.Visibility = Visibility.Visible;
        TryAgain.IsEnabled = false;
        TryAgain.Content = text["Checking…"];
        PerdeProps.SetBusy(TryAgain, true);
        var results = await Services.NetworkChecks.RunAsync(found);
        ChecksRows.Children.Clear();
        Row(text["Same Network"], results.SameNetwork, "This Mac and the PS5 appear to be on the same network.",
            "This Mac isn't connected to a local network. Connect it to the same Wi-Fi as the PS5.");
        Row(text["PS5 Responds"], results.Ps5Responds, "The PS5 was found.", "The PS5 didn't answer the search. The PS5 must be on or in rest mode.");
        Row(text["Remote Play On"], results.RemotePlay, null, "On the second user, Settings › System › Remote Play › Enable Remote Play must be on.");
        Row(text["Internet in Rest Mode"], results.RestModeInternet, null,
            "Staying connected to the internet in rest mode must be on; otherwise the PS5 can't be woken up.");
        Row(text["Wi-Fi 5 GHz"], results.Wifi5Ghz, "You're on a 5 GHz network.", "This Mac is on a 2.4 GHz network. A 5 GHz network works more smoothly and reliably.",
            "This Mac is connected by cable or the Wi-Fi band couldn't be read.");
        Row(text["VPN Off"], results.VpnOff, "No active VPN was found.", "A VPN is on. Turn it off while playing; it can hide the PS5.");
        TryAgain.IsEnabled = true;
        TryAgain.Content = text["Try Again"];
        PerdeProps.SetBusy(TryAgain, false);
    }

    /// <summary>Denetim satırı: solda durum hapı (Geçti tik / Sorunlu ünlem / Bilinmiyor), başlık ve duruma göre açıklama.</summary>
    private void Row(string title, Services.CheckResult result, string? passed, string problem, string? unknown = null)
    {
        var text = Localizer.Current;
        var badge = new Chip
        {
            Text = text[result switch { Services.CheckResult.Passed => "Passed", Services.CheckResult.Problem => "Problem", _ => "Unknown" }],
            Tone = result switch { Services.CheckResult.Passed => ChipTone.Ok, Services.CheckResult.Problem => ChipTone.Live, _ => ChipTone.Muted },
            Glyph = result switch { Services.CheckResult.Passed => "\uE73E", Services.CheckResult.Problem => "\uE7BA", _ => null },
            MinWidth = 88, Margin = Sp.T("0", "0", "m", "0"),
        };
        var detail = result switch
        {
            Services.CheckResult.Passed => passed,
            Services.CheckResult.Problem => problem,
            _ => unknown ?? problem,
        };
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var heading = new TextBlock { Text = title };
        heading.SetResourceReference(StyleProperty, "RowTitle");
        texts.Children.Add(heading);
        if (detail is not null)
        {
            // Mac metni "Bu Mac" der; Windows'ta "bu bilgisayar".
            var hint = new TextBlock { Text = text[detail].Replace("Mac", text.Language == "tr" ? "bilgisayar" : "computer"), Margin = Sp.T("0", "xxs", "0", "0") };
            hint.SetResourceReference(StyleProperty, "HintText");
            texts.Children.Add(hint);
        }
        var line = new DockPanel();
        DockPanel.SetDock(badge, Dock.Left);
        line.Children.Add(badge);
        line.Children.Add(texts);
        var row = new Border { Child = line, Padding = Sp.T("0", "s", "0", "s") };
        row.SetResourceReference(StyleProperty, "SettingRow");
        ChecksRows.Children.Add(row);
        Theme.Motion.EnterFrom(row, 8, Theme.Motion.Medium, TimeSpan.FromMilliseconds(60 * ChecksRows.Children.Count));
    }

    private async void OnSearch(object sender, RoutedEventArgs e) => await SearchAsync();

    /// <summary>Kod ya da adres alanında Enter bağlanır. Olay işlendi sayılır; yoksa Enter, adımın kapalı "Devam"
    /// düğmesine (IsDefault) gidip sessizce hiçbir şey yapmıyordu.</summary>
    private void OnFieldKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key is not (Key.Enter or Key.Return)) return;
        e.Handled = true;
        if (!working && Connect.IsEnabled) OnConnect(sender, e);
    }

    private bool working;

    /// <summary>Eşleşme sonrası Bağlan kapalı kalır; yeni kod yazılınca yeniden açılır.</summary>
    private void OnPinChanged(object sender, TextChangedEventArgs e)
    {
        if (working || Pin.Text.Length == 0) return;
        Connect.IsEnabled = true;
        Connect.Visibility = Visibility.Visible;
        Paired.Visibility = Visibility.Collapsed;
    }

    /// <summary>
    /// Düğme çalışırken ve eşleşmeden sonra (kod değişene dek) kapalı; eksik kod ya da adres tıklanınca açıkça söylenir,
    /// hiçbir sonuç sessiz kalmaz. Eşleşince düğmenin altında yeşil ileti çıkar ve ~1 sn sonra sonraki adıma geçilir.
    /// </summary>
    private async void OnConnect(object sender, RoutedEventArgs e)
    {
        if (working) return;
        working = true;
        Connect.IsEnabled = false;
        PerdeProps.SetBusy(Connect, true);
        Connect.Content = Localizer.Current["Connecting…"];
        Working.Visibility = Visibility.Visible;
        Error.Message = null;
        Paired.Visibility = Visibility.Collapsed;
        paired = false;
        string? problem = null;
        try
        {
            await Controller.RegisterAsync(Host, Pin.Text);
            paired = true;
            ShowDone();
        }
        catch (AppException error)
        {
            problem = error.Message;
        }
        catch (Exception error)
        {
            RemotePlayLog.Note($"PS5 eşleştirme ekranında beklenmedik hata: {error}");
            problem = $"{AppException.Describe(AppError.RegistrationFailed, Localizer.Current)} ({error.Message}) "
                      + Localizer.Current.Format("If this keeps happening, send us this file: %@", RemotePlayLog.DisplayPath);
        }
        finally
        {
            working = false;
            PerdeProps.SetBusy(Connect, false);
            Connect.Content = Localizer.Current["Connect"];
            Working.Visibility = Visibility.Collapsed;
            Connect.IsEnabled = !paired;
            Error.Message = problem;
        }
        if (paired) await ShowPairedAsync();
    }

    /// <summary>Başarı iletisi görünür kılınır (kaydırılmış olsa da), kod alanı temizlenir, kısa süre sonra sonraki adım açılır.</summary>
    private async Task ShowPairedAsync()
    {
        // "Eşleşti" başarı anı (ışın + yaylı tik, ≤ 1 sn; hareket azaltılmışsa yalnız tik).
        Paired.Content = new SuccessMoment(Localizer.Current["Paired"], Controller.PairedText);
        Paired.Visibility = Visibility.Visible;
        Connect.Visibility = Visibility.Collapsed;
        Pin.Text = "";
        // Kod silinince TextChanged düğmeyi açmaz (boş kod); yine de açıkça kapalı tutulur.
        Connect.IsEnabled = false;
        Paired.UpdateLayout();
        Paired.BringIntoView();
        await Task.Delay(TimeSpan.FromSeconds(1));
        // Adım bu arada kapandıysa (Geri) denetleyici zaten ilerlemez; yalnız PS5 adımındayken geçer.
        if (IsLoaded) Controller.ContinueAfterPairing();
    }

    private void OnShowLog(object sender, RoutedEventArgs e) => LogFile.Show();
}
