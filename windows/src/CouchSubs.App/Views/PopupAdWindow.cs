// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CouchSubs.App.Services;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

/// <summary>Açılır reklamın yüklenmiş görseli ve bağlantısı (Enmera; yazı ve düğme yok).</summary>
public sealed record PopupAd(BitmapSource Image, Uri Link);

/// <summary>
/// Açılır reklam (tuval 18): yalnız görsel; görselin oranına göre yatay ya da dikey açılır; tıklanınca bağlantı tarayıcıda
/// açılır; köşede × ve küçük REKLAM etiketi. Ne zaman gösterileceği <see cref="PopupAdPolicy"/>'de.
/// </summary>
public static class PopupAdWindow
{
    /// <summary>
    /// Gösterilecek açılır reklamlar (reklamlar.json › popups; Mac aynı dosyayı okur). Görseli yüklenemeyen reklam listeye
    /// girmez; liste boşken açılır reklam hiç açılmaz (yer tutucu ya da logo asla).
    /// </summary>
    public static IReadOnlyList<PopupAd> Ads { get; set; } = AdCatalog.LoadPopups();

    public static void Offer(Window owner, AppController controller, PopupAdMoment moment)
    {
        // Gösterilmemiş ya da gizli ana pencereye sahip atanamaz (WPF hata verir; ekran görüntüsü kipinde pencere hiç
        // gösterilmez). O an reklam açılmaz, günlük hak da harcanmaz.
        // IsVisible tek başına yetmez: ekran görüntüsü kipinde ve açılışın ilk karelerinde pencere henüz gerçekten
        // gösterilmemiş olabilir (WPF "Cannot set Owner property to a Window that has not been shown previously").
        if (!owner.IsVisible || !owner.IsLoaded || PresentationSource.FromVisual(owner) is null) return;
        // Reklam hiçbir koşulda uygulamayı düşürmemeli (tercih kaydı, görsel, pencere).
        try
        {
            var now = DateTime.Now;
            if (!PopupAdPolicy.ShouldShow(moment, now, UiPreferences.Current.LastPopupAd, controller.IsRunning, controller.Step == OnboardingStep.Done,
                    StreamWindow.IsOpen, Ads.Count > 0))
                return;
            UiPreferences.Save(UiPreferences.Current with { LastPopupAd = now });
            if (PopupAdPolicy.Pick(Ads, now) is not { } ad) return;
            Show(owner, ad);
        }
        catch (Exception e)
        {
            SubtitleLog.Write($"Açılır reklam gösterilemedi: {e.GetType().Name}: {e.Message}");
            StartupGuard.Log("Açılır reklam gösterilemedi", e);
        }
    }

    private static void Show(Window owner, PopupAd ad)
    {
        var image = ad.Image;
        var aspect = (double)image.PixelWidth / image.PixelHeight;
        // Dikey görsel 340 × 604'e kadar, yatay 720 genişlikte; oran korunur.
        var width = aspect >= 1 ? 720 : Math.Min(340, 604 * aspect);
        var window = new Window
        {
            Owner = owner, WindowStyle = WindowStyle.None, AllowsTransparency = true, ShowInTaskbar = false, ResizeMode = ResizeMode.NoResize,
            Background = new SolidColorBrush(Color.FromArgb(0x73, 0x17, 0x18, 0x1B)), WindowStartupLocation = WindowStartupLocation.Manual,
            Left = owner.Left, Top = owner.Top, Width = owner.ActualWidth, Height = owner.ActualHeight, Title = Localizer.Current["Advertisement"],
        };
        var picture = new Border
        {
            Width = width, Height = width / aspect, CornerRadius = new CornerRadius(24), ClipToBounds = true, Cursor = Cursors.Hand,
            Background = new ImageBrush(image) { Stretch = Stretch.UniformToFill }, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        picture.MouseLeftButtonUp += (_, _) =>
        {
            BrowserLauncher.Open(ad.Link);
            window.Close();
        };
        var tag = new Border
        {
            Height = 22, Padding = Sp.T("xs", "0", "xs", "0"), CornerRadius = new CornerRadius(11), Background = new SolidColorBrush(Color.FromArgb(0x73, 0, 0, 0)),
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, Margin = Sp.T("s"), IsHitTestVisible = false,
            Child = new TextBlock { Text = Localizer.Current["AD"], FontSize = 10, Foreground = Brushes.White, VerticalAlignment = VerticalAlignment.Center,
                FontFamily = (FontFamily)Application.Current.FindResource("MonoFont") },
        };
        // Kapat: 32'lik cam daire (siyah %45 + beyaz %12 kenar), Segoe Fluent kapat simgesi.
        var close = new Button
        {
            BorderThickness = new Thickness(1),
            Width = 32, Height = 32, MinHeight = 32, Padding = new Thickness(0), Foreground = Brushes.White,
            Background = new SolidColorBrush(Color.FromArgb(0x73, 0, 0, 0)), BorderBrush = new SolidColorBrush(Color.FromArgb(0x1F, 0xFF, 0xFF, 0xFF)),
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = Sp.T("s"), ToolTip = Localizer.Current["Close"],
            Content = new TextBlock
            {
                Text = "", FontSize = 12, FontWeight = FontWeights.Bold, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center, FontFamily = (FontFamily)Application.Current.FindResource("IconFont"),
            },
        };
        System.Windows.Automation.AutomationProperties.SetName(close, Localizer.Current["Close"]);
        close.SetResourceReference(FrameworkElement.StyleProperty, "ButtonBase");
        close.Click += (_, _) => window.Close();
        var stage = new Grid { Width = picture.Width, Height = picture.Height, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        stage.Children.Add(picture);
        stage.Children.Add(tag);
        stage.Children.Add(close);
        window.Content = stage;
        window.KeyDown += (_, e) => { if (e.Key == Key.Escape) window.Close(); };
        window.Loaded += (_, _) => Motion.EnterFrom(stage, 16, Motion.Page);
        window.Show();
    }
}
