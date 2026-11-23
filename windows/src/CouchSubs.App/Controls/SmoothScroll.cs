// SPDX-License-Identifier: AGPL-3.0-only

using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace CouchSubs.App.Controls;

/// <summary>
/// Tekerlek ve dokunmatik yüzey kaydırması (docs/TASARIM.md › Kaydırma). WPF'in ScrollViewer'ı her tekerlek olayını,
/// büyüklüğüne bakmadan tam bir adım (3 satır = 48 px) sayar; hassas dokunmatik yüzeyler ve serbest dönen tekerlekler
/// saniyede onlarca küçük olay gönderdiği için Ayarlar gibi uzun sayfalar çok hızlı kayıyordu. Burada kayma olayın
/// büyüklüğüyle orantılıdır (120 birim = 48 px) ve kısa bir yumuşatmayla hedefe gider; azaltılmış harekette
/// (Windows'ta "Animasyonları göster" kapalı) doğrudan atlar.
/// </summary>
public static class SmoothScroll
{
    /// <summary>Bir tekerlek çentiği (120 birim) kaç piksel kaydırır: WPF'in varsayılanı gibi 3 satır × 16.</summary>
    private const double PixelsPerNotch = 48;
    /// <summary>Her karede kalan yolun ne kadarı gidilir; 60 Hz'de yaklaşık 120 ms'de hedefe varılır.</summary>
    private const double Ease = 0.3;

    private sealed class State
    {
        public double Target;
        public bool Running;
    }

    private static readonly ConditionalWeakTable<ScrollViewer, State> States = new();
    private static bool registered;

    /// <summary>Uygulamadaki bütün ScrollViewer'lar için bir kez çağrılır.</summary>
    public static void Register()
    {
        if (registered) return;
        registered = true;
        EventManager.RegisterClassHandler(typeof(ScrollViewer), UIElement.MouseWheelEvent, new MouseWheelEventHandler(OnMouseWheel));
    }

    private static void OnMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (e.Handled || sender is not ScrollViewer viewer) return;
        // Öğe öğe kayan listeler (CanContentScroll) ve kaydırılacak yeri olmayanlar WPF'te kalır; olay üstteki
        // kaydırıcıya geçer.
        if (viewer.CanContentScroll || viewer.ScrollableHeight <= 0) return;

        var state = States.GetOrCreateValue(viewer);
        if (!state.Running) state.Target = viewer.VerticalOffset;
        var lines = Math.Max(1, SystemParameters.WheelScrollLines);
        var step = e.Delta / 120.0 * PixelsPerNotch * lines / 3.0;
        var target = Math.Clamp(state.Target - step, 0, viewer.ScrollableHeight);
        // Kenara dayanmışken olay üstteki kaydırıcıya geçsin (iç içe kaydırma).
        if (target == state.Target && Math.Abs(viewer.VerticalOffset - target) < 0.5) return;
        e.Handled = true;
        state.Target = target;

        if (!SystemParameters.ClientAreaAnimation)
        {
            viewer.ScrollToVerticalOffset(target);
            return;
        }
        if (state.Running) return;
        state.Running = true;
        CompositionTarget.Rendering += Step;

        void Step(object? _, EventArgs __)
        {
            // Sayfa bu arada kısalmış olabilir; hedef ulaşılabilir kalsın.
            state.Target = Math.Clamp(state.Target, 0, viewer.ScrollableHeight);
            var current = viewer.VerticalOffset;
            var remaining = state.Target - current;
            if (Math.Abs(remaining) < 0.5 || !viewer.IsLoaded)
            {
                viewer.ScrollToVerticalOffset(state.Target);
                state.Running = false;
                CompositionTarget.Rendering -= Step;
                return;
            }
            viewer.ScrollToVerticalOffset(current + remaining * Ease);
        }
    }
}
