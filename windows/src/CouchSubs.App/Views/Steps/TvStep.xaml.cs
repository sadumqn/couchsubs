// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using CouchSubs.App.Controls;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

/// <summary>
/// Kurulumun TV adımı (Mac TVSetupStep): ağdaki TV'ler kart kart, durum rozetleriyle; bağlantı ve kurulum çizelgesi; hata
/// kutusu. İşlev eskisiyle aynı: arama, elle adres (türü TV'ye sorulur), eşleştirme, Android TV, TV'siz devam.
/// </summary>
public partial class TvStep : UserControl
{
    /// <summary>Yalnız ekran görüntüsü aracı: sahte liste ve durumlar (Mac TVSetupStep.preview).</summary>
    public sealed record Preview(IReadOnlyList<LgTv> Tvs, bool Searching = false, string? PairingHost = null, string? PairError = null);

    public static Preview? PreviewState { get; set; }

    private readonly List<LgTv> found = [];
    private readonly DispatcherTimer tipClock = new() { Interval = TimeSpan.FromSeconds(5) };
    private AppController? controller;
    private bool searching;
    private string? pairingHost;
    private TvBrand? pairingBrand;
    private LgTv? lastPaired;
    private string? pairError;
    private int activeStep = -1;
    private DateTime activeSince = DateTime.Now;

    /// <summary>Olası nedenler (boş durum). Windows'a özgü ağ izni ve güvenlik duvarı maddeleri dahil.</summary>
    private static readonly string[] ReasonKeys =
    [
        "Is the TV on? Turn it on with the remote and wait for the home screen.",
        "No LG or Samsung TV found. Make sure the TV is on and on the same network.",
        "Guest networks and access point (AP) isolation stop devices from seeing each other; use the main network.",
        "If Windows asks whether CouchSubs may use the network, allow it for private networks.",
    ];

    public TvStep()
    {
        InitializeComponent();
        var text = Localizer.Current;
        for (var i = 0; i < ReasonKeys.Length; i++) Reasons.Children.Add(NumberedLine(i + 1, text[ReasonKeys[i]]));
        tipClock.Tick += (_, _) => ShowProgress();
        Loaded += async (_, _) =>
        {
            controller = (AppController)DataContext;
            controller.PropertyChanged += OnChanged;
            tipClock.Start();
            ShowState();
            if (PreviewState is { } preview)
            {
                found.Clear();
                found.AddRange(preview.Tvs);
                searching = preview.Searching;
                pairingHost = preview.PairingHost;
                pairError = preview.PairError;
                lastPaired = preview.Tvs.FirstOrDefault(tv => tv.Host == preview.PairingHost) ?? preview.Tvs.LastOrDefault();
                ShowList();
                return;
            }
            // Kurulum yarıda kaldıysa (ör. TV uygulaması kurulurken kapatıldı) eşleşmiş TV'deki uygulamaya yeniden bakılır.
            if (Controller.HasTv && Controller.TvApp.Kind == TvAppKind.Unknown) _ = Controller.RefreshTvAppAsync();
            await SearchAsync();
        };
        Unloaded += (_, _) =>
        {
            tipClock.Stop();
            if (controller is not null) controller.PropertyChanged -= OnChanged;
        };
    }

    private AppController Controller => (AppController)DataContext;

    private void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppController.TvApp) or nameof(AppController.Tv) or nameof(AppController.TvAppOutdated)
            or nameof(AppController.CanInstallTvApp))
            Dispatcher.BeginInvoke(ShowState);
    }

    private TvBrand Brand => pairingBrand ?? Controller.Tv?.Brand ?? found.FirstOrDefault()?.Brand ?? TvBrand.Lg;

    /// <summary>Liste, çizelge, hata kutusu ve TV uygulaması kartları bir arada yenilenir.</summary>
    private void ShowState()
    {
        if (controller is null) return;
        Layout.Message = Localizer.Current[Controller.Tv is not null
            ? "We found a TV on the network. Choose it and CouchSubs installs its app on the TV by itself."
            : "We're looking for TVs on the network. Choose yours and CouchSubs installs its app on the TV by itself."];
        // Uygulamayla TV paketi gelmediyse (geliştirici derlemesi) rehber gösterilir.
        ManualInstall.Visibility = Controller.Tv is null or { Brand: TvBrand.Lg } || Controller.CanInstallTvApp
            ? Visibility.Collapsed : Visibility.Visible;
        // Ön koşul listesi eşleşmeden önce de bulunan TV'nin markasına göre görünür (Mac needsChecklist).
        AppCard.FallbackBrand = found.Count > 0 ? Brand : null;
        ShowList();
    }

    private void ShowList()
    {
        Search.IsEnabled = !searching;
        PerdeProps.SetBusy(Search, searching);
        Search.Content = Localizer.Current[searching ? "Searching…" : "Search Again"];
        Searching.Visibility = searching && found.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        NotFound.Visibility = !searching && found.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        Tvs.Children.Clear();
        foreach (var tv in found) Tvs.Children.Add(Row(tv));
        Tvs.IsEnabled = pairingHost is null;
        AndroidChoice.Tag = Controller.Tv?.Brand == TvBrand.AndroidTv ? "selected" : null;
        PairError.Message = pairError;
        RetryPair.Visibility = lastPaired is null ? Visibility.Collapsed : Visibility.Visible;
        ShowProgress();
    }

    // ───────────── TV satırı ─────────────

    private enum RowStatus { Found, Connecting, ApproveOnTv, Paired, Installing, Installed, NeedsUpdate, Failed }

    private RowStatus StatusOf(LgTv tv)
    {
        if (pairingHost == tv.Host) return tv.Brand == TvBrand.AndroidTv ? RowStatus.Connecting : RowStatus.ApproveOnTv;
        if (pairError is not null && lastPaired?.Host == tv.Host) return RowStatus.Failed;
        if (Controller.Tv?.Host != tv.Host) return RowStatus.Found;
        if (Controller.TvAppOutdated is not null) return RowStatus.NeedsUpdate;
        return Controller.TvApp.Kind switch
        {
            TvAppKind.Working or TvAppKind.PressInstallOnTv or TvAppKind.SignIn => RowStatus.Installing,
            TvAppKind.UpToDate => RowStatus.Installed,
            TvAppKind.Failed => RowStatus.Failed,
            TvAppKind.NeedsPassphrase when Controller.TvApp.Error is not null => RowStatus.Failed,
            TvAppKind.ApproveOnTv => RowStatus.ApproveOnTv,
            _ => RowStatus.Paired,
        };
    }

    private static (string Key, ChipTone Tone) BadgeOf(RowStatus status) => status switch
    {
        RowStatus.Connecting => ("Connecting…", ChipTone.Amber),
        RowStatus.ApproveOnTv => ("Waiting for Approval on the TV", ChipTone.Amber),
        RowStatus.Paired => ("Paired", ChipTone.Amber),
        RowStatus.Installing => ("Installing…", ChipTone.Amber),
        RowStatus.Installed => ("Installed ✓", ChipTone.Ok),
        RowStatus.NeedsUpdate => ("Update Needed", ChipTone.Live),
        RowStatus.Failed => ("Error", ChipTone.Live),
        _ => ("Found", ChipTone.Muted),
    };

    /// <summary>
    /// TV kartı (Perde DSTVCard): simge karesi, ad + mono "marka · adres", durum hapı ve gerekiyorsa küçük "Bağlan"; seçiliyken
    /// amber kenar + ışıma. Kartlar bulundukça aşağıdan kayarak belirir.
    /// </summary>
    private Button Row(LgTv tv)
    {
        var text = Localizer.Current;
        var status = StatusOf(tv);
        var selected = Controller.Tv?.Host == tv.Host || pairingHost == tv.Host;
        var (key, tone) = BadgeOf(status);
        var card = new TvCard
        {
            TvName = tv.Name.Length == 0 ? BrandName(tv.Brand) : tv.Name,
            Detail = tv.Host.Length > 0 ? $"{BrandName(tv.Brand)} · {tv.Host}" : BrandName(tv.Brand),
            Status = text[key], StatusTone = tone, Selected = selected, ToolTip = $"{tv.Name} {tv.Host}",
        };
        if (status is RowStatus.Found or RowStatus.Failed)
        {
            var connect = new Border { Margin = Sp.T("xs", "0", "0", "0"), Child = new TextBlock { Text = text["Connect"], VerticalAlignment = VerticalAlignment.Center } };
            connect.SetResourceReference(StyleProperty, "ChipLabel");
            card.Trailing = connect;
        }
        System.Windows.Automation.AutomationProperties.SetName(card, $"{tv.Name} {tv.Host}");
        card.Click += async (_, _) => await PairAsync(tv);
        if (!shownHosts.Contains(tv.Host))
        {
            shownHosts.Add(tv.Host);
            card.Loaded += (_, _) => Motion.EnterFrom(card, 14, Motion.Medium);
        }
        return card;
    }

    /// <summary>Giriş hareketi bir kez oynasın diye gösterilmiş TV adresleri.</summary>
    private readonly HashSet<string> shownHosts = [];

    private static string BrandName(TvBrand brand) => brand switch
    {
        TvBrand.Samsung => "Samsung",
        TvBrand.AndroidTv => "Android TV",
        _ => "LG",
    };

    private static UIElement NumberedLine(int number, string text)
    {
        var digit = new TextBlock { Text = $"{number}.", Margin = Sp.T("0", "0", "xs", "0") };
        digit.SetResourceReference(TextBlock.FontSizeProperty, "smallFontSize");
        digit.SetResourceReference(TextBlock.ForegroundProperty, "mutedBrush");
        var body = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap };
        body.SetResourceReference(TextBlock.FontSizeProperty, "smallFontSize");
        body.SetResourceReference(TextBlock.ForegroundProperty, "textBrush");
        var line = new DockPanel();
        DockPanel.SetDock(digit, Dock.Left);
        line.Children.Add(digit);
        line.Children.Add(body);
        return line;
    }

    // ───────────── Çizelge ─────────────

    private enum Phase { Pending, Active, Done, Failed }

    /// <summary>
    /// Bağlan / Kur çizelgesi (Mac TVProgressCard): Bağlanılıyor → TV'de Onay → TV Uygulaması Kuruluyor → Hazır. Durumlar
    /// denetleyicinin kendi durumlarından; bir adım 15 sn'den uzun sürerse altında ipucu.
    /// </summary>
    private void ShowProgress()
    {
        if (controller is null) return;
        var pairing = pairingHost is not null;
        Progress.Visibility = pairing || Controller.Tv is not null ? Visibility.Visible : Visibility.Collapsed;
        if (Progress.Visibility != Visibility.Visible) return;
        var kind = Controller.TvApp.Kind;
        var brand = Brand;
        var paired = Controller.Tv is not null && !pairing;
        var installing = kind is TvAppKind.Working or TvAppKind.PressInstallOnTv or TvAppKind.SignIn or TvAppKind.NeedsPassphrase
            or TvAppKind.DevModeOff or TvAppKind.ChooseAndroidTv;
        var installed = kind == TvAppKind.UpToDate;
        var failed = kind == TvAppKind.Failed;
        var approveActive = (pairing && brand != TvBrand.AndroidTv) || kind == TvAppKind.ApproveOnTv;
        var approveDone = paired && kind != TvAppKind.ApproveOnTv && (brand != TvBrand.AndroidTv || installing || installed);
        (string Title, Phase Phase, string? Tip)[] steps =
        [
            ("Connecting", pairing ? Phase.Active : paired ? Phase.Done : Phase.Pending, null),
            ("Approve on the TV", approveActive ? Phase.Active : approveDone ? Phase.Done : Phase.Pending,
                "Confirm the permission shown on the TV screen with the remote."),
            ("Installing the TV App", failed ? Phase.Failed : installed ? Phase.Done : installing ? Phase.Active : Phase.Pending,
                "Keep the TV on and follow the steps on this screen; installing can take a minute."),
            ("Ready", installed ? Phase.Done : Phase.Pending, null),
        ];
        var active = Array.FindIndex(steps, step => step.Phase == Phase.Active);
        if (active != activeStep)
        {
            activeStep = active;
            activeSince = DateTime.Now;
        }
        // Adım çizelgesi (Perde DSStepTimeline): hata olunca da şimdiki adım (neden hata kutusunda); bir adım 15 sn'den uzun
        // sürerse altında ipucu.
        var text = Localizer.Current;
        Timeline.Steps = [.. steps.Select(step => new TimelineStep(text[step.Title],
            step.Phase == Phase.Active && step.Tip is not null && DateTime.Now - activeSince > TimeSpan.FromSeconds(15) ? text[step.Tip] : null,
            step.Phase switch { Phase.Done => StepPhase.Done, Phase.Active or Phase.Failed => StepPhase.Current, _ => StepPhase.Todo }))];
        // TV uygulaması kuruldu: başarı anı (≤ 1 sn) bir kez kurulur; her yenilemede yeniden oynamaz.
        if (installed && ReadyMoment.Content is null) ReadyMoment.Content = new SuccessMoment(text["Ready"]);
        ReadyMoment.Visibility = installed ? Visibility.Visible : Visibility.Collapsed;
    }

    // ───────────── İşler ─────────────

    private async Task SearchAsync()
    {
        searching = true;
        ShowList();
        var result = await Controller.DiscoverTvsAsync();
        // Elle eklenenler yeni aramada kaybolmasın (eski listede satırlar yalnız arama başında silinirdi).
        found.Clear();
        found.AddRange(result);
        searching = false;
        ShowState();
    }

    /// <summary>Elle yazılan adres: TV'nin türü (LG, Samsung, Android TV) TV'ye sorulur ve listeye eklenir. Hiçbir yoklamaya
    /// yanıt gelmezse seçilen marka kullanılır; LG seçiliyse bu eskisi gibi söylenir.</summary>
    private async Task AddManualAsync()
    {
        Error.Text = "";
        if (LgDiscovery.NormalizeHost(ManualHost.Text) is not { } host)
        {
            Error.Text = Localizer.Current["This is not a valid IP address. Type it like 192.168.1.20, without http:// or a port number."];
            return;
        }
        if (found.Any(tv => tv.Host == host)) return;
        AddManual.IsEnabled = false;
        var manual = await LgDiscovery.ManualTvAsync(host);
        var tv = manual.Tv;
        var chosen = ChosenBrand;
        if (!manual.Recognised && chosen != TvBrand.Lg) tv = new LgTv(BrandName(chosen), host, chosen);
        else if (!manual.Recognised) Error.Text = Localizer.Current.Format(ManualTvNotRecognised, host);
        found.Add(tv);
        ManualHost.Text = "";
        AddManual.IsEnabled = true;
        ShowState();
    }

    private const string ManualTvNotRecognised =
        "No TV at %@ answered as an LG, Samsung or Android TV, so it was added as an LG TV. If it is an Android TV / Google TV, press Select under Android TV / Google TV below.";

    private TvBrand ChosenBrand => BrandSamsung.IsChecked == true ? TvBrand.Samsung : BrandAndroid.IsChecked == true ? TvBrand.AndroidTv : TvBrand.Lg;

    private void OnBrand(object sender, RoutedEventArgs e)
    {
        if (ManualUnit is null) return;
        ManualUnit.Hint = Localizer.Current[ChosenBrand == TvBrand.AndroidTv
            ? "You can see the TV's address on the TV in Settings › Network & Internet."
            : "TV not in the list? Enter its IP address (on the TV under Settings › Network)."];
    }

    private async void OnAddManual(object sender, RoutedEventArgs e) => await AddManualAsync();

    private async void OnManualHostKey(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == System.Windows.Input.Key.Enter) await AddManualAsync();
    }

    private async Task PairAsync(LgTv tv)
    {
        if (pairingHost is not null) return;
        pairingHost = tv.Host;
        pairingBrand = tv.Brand;
        lastPaired = tv;
        pairError = null;
        // Samsung'da izin kutusu ve bekleme süresi açıkça söylenir.
        Waiting.Text = tv.Brand == TvBrand.Samsung
            ? Localizer.Current["Accept the permission box on the TV with the remote (Allow). CouchSubs waits 60 seconds."]
            : Localizer.Current["Accept the request on the TV…"];
        Waiting.Visibility = Visibility.Visible;
        Error.Text = "";
        ShowState();
        try
        {
            await Controller.PairAsync(tv);
        }
        catch (Exception error)
        {
            pairError = TvAppMessages.PairingProblem(error, tv.Brand, Localizer.Current);
        }
        pairingHost = null;
        Waiting.Visibility = Visibility.Collapsed;
        ShowState();
    }

    private async void OnSearch(object sender, RoutedEventArgs e) => await SearchAsync();

    private async void OnRetryPair(object sender, RoutedEventArgs e)
    {
        if (lastPaired is { } tv) await PairAsync(tv);
    }

    /// <summary>"TV'm yok": TV kurulmaz, altyazı bilgisayar ekranında gösterilir; sonraki adıma geçilir.</summary>
    private void OnNoTv(object sender, RoutedEventArgs e) => Controller.UseComputerScreen();

    private async void OnAndroidTv(object sender, RoutedEventArgs e) => await PairAsync(new LgTv("Android TV", "", TvBrand.AndroidTv));

    private void OnGuide(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("https://github.com/yorulmazsinan/couchsubs/blob/main/docs/tv-kurulum.md") { UseShellExecute = true });
}
