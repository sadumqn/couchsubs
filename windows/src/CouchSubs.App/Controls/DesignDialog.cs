// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using CouchSubs.App.Theme;

namespace CouchSubs.App.Controls;

/// <summary>
/// Yeni arayüzün açılır kartı (onay penceresi): sahibi pencerenin üstünde yarı saydam karartma, ortada 24 köşeli kart;
/// başlık, açıklama, sağda ikincil "Vazgeç" ve amber ana eylem. Esc vazgeçer, Enter onaylar. Kart alttan kayarak gelir.
/// </summary>
public static class DesignDialog
{
    /// <summary>Onaylanırsa true. Sahip yoksa ana pencere kullanılır.</summary>
    public static bool Confirm(Window? owner, string title, string message, string confirm, string cancel)
    {
        owner ??= Application.Current?.MainWindow;
        var result = false;
        var window = new Window
        {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false,
            Background = new SolidColorBrush(Color.FromArgb(0x73, 0x17, 0x18, 0x1B)), Title = title,
        };
        // Sahip YALNIZ gösterilmiş pencereye atanır (beta.87 dersi: gösterilmemiş pencereye Owner atamak WPF'te hata verir).
        if (owner is { IsLoaded: true, IsVisible: true } && PresentationSource.FromVisual(owner) is not null)
        {
            window.Owner = owner;
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            var bounds = owner.WindowState == WindowState.Maximized ? SystemParameters.WorkArea : new Rect(owner.Left, owner.Top, owner.ActualWidth, owner.ActualHeight);
            window.Left = bounds.Left;
            window.Top = bounds.Top;
            window.Width = bounds.Width;
            window.Height = bounds.Height;
        }
        else
        {
            window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            window.Width = 640;
            window.Height = 400;
        }

        var heading = new TextBlock { Text = title };
        heading.SetResourceReference(FrameworkElement.StyleProperty, "HeadlineText");
        var body = new TextBlock { Text = message, Margin = new Thickness(0, 4, 0, 0) };
        body.SetResourceReference(FrameworkElement.StyleProperty, "HintText");
        body.FontSize = 14;
        var no = new Button { Content = cancel, IsCancel = true };
        no.SetResourceReference(FrameworkElement.StyleProperty, "SecondaryButton");
        var yes = new Button { Content = confirm, IsDefault = true, Margin = new Thickness(12, 0, 0, 0) };
        yes.SetResourceReference(FrameworkElement.StyleProperty, "PrimaryButton");
        yes.Click += (_, _) => { result = true; window.Close(); };
        no.Click += (_, _) => window.Close();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 24, 0, 0) };
        buttons.Children.Add(no);
        buttons.Children.Add(yes);
        var stack = new StackPanel();
        stack.Children.Add(heading);
        stack.Children.Add(body);
        stack.Children.Add(buttons);
        var card = new Border { Child = stack, Width = 480, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        // Perde e2: yükseltilmiş yüzey, güçlü kıl çizgi, derin gölge.
        card.SetResourceReference(FrameworkElement.StyleProperty, "RaisedBorder");
        window.Content = card;
        window.SetResourceReference(System.Windows.Documents.TextElement.ForegroundProperty, "textPrimaryBrush");
        window.MouseDown += (_, e) => { if (e.OriginalSource == window) window.Close(); };
        window.KeyDown += (_, e) => { if (e.Key == Key.Escape) window.Close(); };
        window.Loaded += (_, _) => Motion.EnterFrom(card, 16, Motion.Page);
        window.ShowDialog();
        return result;
    }
}
