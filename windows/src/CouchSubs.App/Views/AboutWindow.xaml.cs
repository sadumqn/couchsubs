// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Media.Imaging;
using CouchSubs.App.Theme;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

public partial class AboutWindow : Window
{
    internal AboutWindow()
    {
        InitializeComponent();
        // Derleme sürümü (AssemblyVersion) ön sürüm ekini taşımaz: 0.1.0-beta.38 "0.1.0" görünüyordu. Etiketteki sürüm
        // InformationalVersion'dadır; güncelleme denetimi de onu kullanır.
        Version.Text = AppVersion.Current(Assembly.GetEntryAssembly() ?? typeof(AboutWindow).Assembly);
        ShowLogo();
        ThemeManager.Changed += ShowLogo;
        Closed += (_, _) => ThemeManager.Changed -= ShowLogo;
    }

    /// <summary>Enmera logosu: koyu temada beyaz, açık temada siyah.</summary>
    private void ShowLogo() =>
        EnmeraLogo.Source = new BitmapImage(new Uri($"pack://application:,,,/Assets/enmera-{(ThemeManager.IsDark ? "white" : "black")}.png"));

    public static void Open(Window? owner) => OwnedWindow.Show(owner, () => new AboutWindow());

    private void OnLink(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string url })
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }

    private void OnClose(object sender, RoutedEventArgs e) => Close();
}
