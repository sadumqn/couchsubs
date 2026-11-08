// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

public partial class SettingsWindow : Window
{
    private static readonly (string Code, string Name)[] Languages =
        [("en", "English"), ("ja", "Japanese"), ("de", "German"), ("fr", "French"), ("es", "Spanish")];

    /// <summary>Ek bölgeler ilk açıldığında (sağ üst köşe, sağ alt köşe, ekranın ortası) bu alanlarla başlar.</summary>
    private static readonly CropRegion[] ExtraDefaults = [new(0.05, 0.28, 0.60, 0.97), new(0.72, 0.95, 0.60, 0.97)];

    /// <summary>Serbest alan sekmesi: kayıtlı bölge yoktur, seçilen alan hemen çevrilir.</summary>
    private const int FreeSlot = 3;
    private int freeVersion;

    private readonly AppController controller;
    private bool loading = true;
    /// <summary>Çerçevesi düzenlenen bölge: 0 altyazı, 1 ve 2 ek bölgeler, 3 serbest alan (kayıtsız).</summary>
    private int area;

    internal SettingsWindow(AppController controller)
    {
        this.controller = controller;
        InitializeComponent();
        var settings = controller.Settings;
        TextSize.Value = Math.Clamp(settings.Style.FontSize, TextSize.Minimum, TextSize.Maximum);
        TextSizeValue.Text = ((int)TextSize.Value).ToString();
        Position.Value = settings.Style.BottomPercent;
        Placement.SelectedItem = Placement.Items.Cast<ComboBoxItem>().First(item => (string)item.Tag == settings.Style.Placement.ToString());
        ShowPlacement(settings.Style.Placement);
        BackgroundOpacity.Value = settings.Style.Background;
        Bold.IsChecked = settings.Style.Bold;
        // Yalnız çeviri modeli olan diller listelenir; tek dil varsa seçim gösterilmez.
        foreach (var (code, name) in Languages.Where(l => controller.SupportsLanguage(l.Code)))
            GameLanguage.Items.Add(new ComboBoxItem { Content = Localizer.Current[name], Tag = code, IsSelected = code == settings.SourceLanguage });
        LanguageCard.Visibility = GameLanguage.Items.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        (settings.FreeAreaTarget switch { ResultTarget.Pc => FreePc, ResultTarget.Both => FreeBoth, _ => FreeTv }).IsChecked = true;
        Region.Frame = controller.LastFrame;
        ShowArea(0);
        // Num 8: oyunun o anki görüntüsü önizlemeye alınır.
        controller.SnapshotRequested += OnSnapshot;
        Closed += (_, _) => controller.SnapshotRequested -= OnSnapshot;
        Dubbing.Attach(controller);
        loading = false;
    }

    public static void Open(Window? owner, AppController controller) =>
        new SettingsWindow(controller) { Owner = owner }.ShowDialog();

    private void Update(Func<UserSettings, UserSettings> change)
    {
        if (!loading) controller.Settings = change(controller.Settings);
    }

    private void OnTextSize(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (loading) return;
        var size = (int)Math.Round(e.NewValue);
        TextSizeValue.Text = size.ToString();
        Update(s => s with { Style = s.Style with { FontSize = size } });
    }

    private void OnFreeTarget(object sender, RoutedEventArgs e)
    {
        if (loading || sender is not RadioButton { Tag: string tag }) return;
        var target = Enum.Parse<ResultTarget>(tag);
        Update(s => s with { FreeAreaTarget = target });
        if (area == FreeSlot) SetExtraRadio(target);
    }

    private void SetExtraRadio(ResultTarget target)
    {
        var wasLoading = loading;
        loading = true;
        (target switch { ResultTarget.Pc => ExtraPc, ResultTarget.Both => ExtraBoth, _ => ExtraTv }).IsChecked = true;
        loading = wasLoading;
    }

    /// <summary>Önizlemeyi oyunun şu anki görüntüsüyle yeniler (çerçeve olduğu gibi kalır).</summary>
    private void OnRefresh(object sender, RoutedEventArgs e) => Region.Frame = controller.LastFrame;

    private void OnSnapshot() => Dispatcher.Invoke(() => Region.Frame = controller.LastFrame);

    private void OnPosition(object sender, RoutedPropertyChangedEventArgs<double> e) =>
        Update(s => s with { Style = s.Style with { BottomPercent = (int)Math.Round(e.NewValue) } });

    private void OnPositionStart(object sender, System.Windows.Input.MouseButtonEventArgs e) => controller.SendTestSubtitle();

    private void OnPlacement(object sender, SelectionChangedEventArgs e)
    {
        if (Placement.SelectedItem is not ComboBoxItem { Tag: string tag }) return;
        var placement = Enum.Parse<SubtitlePlacement>(tag);
        ShowPlacement(placement);
        Update(s => s with { Style = s.Style with { Placement = placement } });
    }

    /// <summary>Elle ayarlanan yükseklik yalnız sabit yerleşimde anlamlıdır.</summary>
    private void ShowPlacement(SubtitlePlacement placement)
    {
        var isFixed = placement == SubtitlePlacement.Fixed;
        FixedPanel.Visibility = isFixed ? Visibility.Visible : Visibility.Collapsed;
        FollowsHint.Visibility = isFixed ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnBackground(object sender, RoutedPropertyChangedEventArgs<double> e) =>
        Update(s => s with { Style = s.Style with { Background = (int)Math.Round(e.NewValue) } });

    private void OnBold(object sender, RoutedEventArgs e) =>
        Update(s => s with { Style = s.Style with { Bold = Bold.IsChecked == true } });

    private void OnLanguage(object sender, SelectionChangedEventArgs e)
    {
        if (GameLanguage.SelectedItem is ComboBoxItem { Tag: string code }) Update(s => s with { SourceLanguage = code });
    }

    private void OnRegion(object? sender, CropRegion region)
    {
        var slot = area;
        if (slot == FreeSlot)
        {
            if (!loading) _ = TranslateFreeAsync(region);
            return;
        }
        Update(s => slot == 0 ? s with { Region = region } : s.WithExtraRegion(slot, region));
    }

    /// <summary>Resimde seçilen alanı hemen çevirir; sonuç ayara göre TV'ye gider, burada da gösterilir.</summary>
    private async Task TranslateFreeAsync(CropRegion region)
    {
        var text = Localizer.Current;
        var token = ++freeVersion;
        if (Region.Frame is not { } frame)
        {
            FreeResult.Text = text["Could not translate this area."];
            return;
        }
        FreeResult.Text = text["Translating…"];
        var (outcome, result) = await controller.TranslateAreaAsync(frame, region);
        if (token != freeVersion || area != FreeSlot) return;
        FreeResult.Text = outcome switch
        {
            ExtraRegionOutcome.Shown when result is not null => result.Translation,
            ExtraRegionOutcome.NoText => text["No text found in this area."],
            ExtraRegionOutcome.Busy => text["Translating…"],
            _ => text["Could not translate this area."],
        };
    }

    private void OnArea(object sender, RoutedEventArgs e)
    {
        if (!loading && sender is RadioButton { Tag: string tag }) ShowArea(int.Parse(tag));
    }

    /// <summary>Seçilen bölgenin çerçevesini gösterir; ek bölge kapalıysa çerçeve düzenlenemez.</summary>
    private void ShowArea(int slot)
    {
        area = slot;
        var wasLoading = loading;
        loading = true;
        FreeResultBox.Visibility = Visibility.Collapsed;
        var text = Localizer.Current;
        var settings = controller.Settings;
        if (slot == 0)
        {
            UseArea.Visibility = Visibility.Collapsed;
            ExtraTargetPanel.Visibility = Visibility.Collapsed;
            Region.IsEnabled = true;
            Region.DefaultRegion = new CropRegion();
            Region.ShowRegion(settings.Region);
            AreaHint.Text = text["Drag on the picture to draw the area where the game shows its subtitles. Drag the edges to resize it, or the inside to move it."];
        }
        else if (slot == FreeSlot)
        {
            freeVersion++;
            UseArea.Visibility = Visibility.Collapsed;
            ExtraTargetPanel.Visibility = Visibility.Visible;
            SetExtraRadio(settings.FreeAreaTarget);
            FreeResultBox.Visibility = Visibility.Visible;
            FreeResult.Text = "";
            Region.IsEnabled = true;
            Region.DefaultRegion = new CropRegion();
            Region.ShowRegion(new CropRegion());
            AreaHint.Text = text["Drag over the text on the picture and it is translated right away, like Num 5 but here. Press Refresh picture (Num 8) first to get the game's current frame."];
        }
        else
        {
            var extra = settings.ExtraRegion(slot);
            UseArea.Visibility = Visibility.Visible;
            UseArea.IsChecked = extra is not null;
            ExtraTargetPanel.Visibility = Visibility.Visible;
            (settings.ExtraTarget(slot) switch { ResultTarget.Pc => ExtraPc, ResultTarget.Both => ExtraBoth, _ => ExtraTv }).IsChecked = true;
            Region.IsEnabled = extra is not null;
            Region.DefaultRegion = ExtraDefaults[slot - 1];
            Region.ShowRegion(extra ?? ExtraDefaults[slot - 1]);
            AreaHint.Text = text["Draw the area to translate, for example a quest panel. While you play, press its key (Num 1 or 2) to read and translate it once. Choose where the result shows. It works even when CouchSubs is in the background."];
        }
        loading = wasLoading;
    }

    private void OnExtraTarget(object sender, RoutedEventArgs e)
    {
        if (loading || area == 0 || sender is not RadioButton { Tag: string tag }) return;
        var slot = area;
        var target = Enum.Parse<ResultTarget>(tag);
        if (slot == FreeSlot)
        {
            Update(s => s with { FreeAreaTarget = target });
            var wasLoading = loading;
            loading = true;
            (target switch { ResultTarget.Pc => FreePc, ResultTarget.Both => FreeBoth, _ => FreeTv }).IsChecked = true;
            loading = wasLoading;
            return;
        }
        Update(s => s.WithExtraTarget(slot, target));
    }

    private void OnUseArea(object sender, RoutedEventArgs e)
    {
        if (loading || area == 0 || area == FreeSlot) return;
        var on = UseArea.IsChecked == true;
        Region.IsEnabled = on;
        var slot = area;
        var region = Region.Region;
        Update(s => s.WithExtraRegion(slot, on ? region : null));
    }

    private void OnTest(object sender, RoutedEventArgs e) => controller.SendTestSubtitle();

    private void OnAbout(object sender, RoutedEventArgs e) => AboutWindow.Open(this);

    private void OnReset(object sender, RoutedEventArgs e)
    {
        var text = Localizer.Current;
        var answer = MessageBox.Show(this, text["The saved PS5, account and TV connection will be removed."], text["Set up again?"],
            MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (answer != MessageBoxResult.OK) return;
        controller.ResetSetup();
        Close();
    }

    private void OnDone(object sender, RoutedEventArgs e) => Close();
}
