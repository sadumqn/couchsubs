// SPDX-License-Identifier: AGPL-3.0-only

using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace CouchSubs.App.Views;

/// <summary>
/// Ayarlar, Geçmiş ve Hakkında: ana pencerenin ortasında açılan ama ona bağlanmayan tek pencere (#223, #268). WPF'te
/// <see cref="Window.Owner"/> verilen pencere hep sahibinin üstünde çizildiğinden Owner atanmaz; ana pencereye tıklayınca
/// o öne gelir. Aynı pencere zaten açıksa yenisi açılmaz, var olan öne getirilir. Sahibi kapanınca bu pencere de kapanır.
/// Kipli pencereler (oyun paketi içe aktarma, PSN girişi) bu yolu kullanmaz, Owner'lı kalır.
/// </summary>
internal static partial class OwnedWindow
{
    /// <summary>Açık olan ya da yeni açılan pencereyi döndürür.</summary>
    public static T Show<T>(Window? owner, Func<T> create) where T : Window
    {
        var open = Application.Current?.Windows.OfType<T>().FirstOrDefault(window => window.IsVisible);
        if (open is not null)
        {
            if (open.WindowState == WindowState.Minimized) open.WindowState = WindowState.Normal;
            open.Activate();
            return open;
        }
        var window = create();
        if (owner is null || !owner.IsLoaded)
        {
            window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        }
        else
        {
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            // İlk tahmin gösterilmeden önce; SizeToContent'li pencerede gerçek boy Loaded'da belli olur, orada düzeltilir.
            CenterOn(window, owner, Size(window.Width, window.MinWidth), Size(window.Height, window.MinHeight));
            window.Loaded += (_, _) => CenterOn(window, owner, window.ActualWidth, window.ActualHeight);
            EventHandler closeWithOwner = (_, _) => window.Close();
            owner.Closed += closeWithOwner;
            window.Closed += (_, _) => owner.Closed -= closeWithOwner;
        }
        window.Show();
        return window;
    }

    private static double Size(double value, double fallback) =>
        double.IsNaN(value) || value <= 0 ? Math.Max(fallback, 0) : value;

    /// <summary>Pencereyi sahibinin ortasına koyar; sahibin bulunduğu ekranın çalışma alanından taşırmaz.</summary>
    private static void CenterOn(Window window, Window owner, double width, double height)
    {
        // Simge durumundaki sahip -32000'de durur; o zaman eski (normal) konumu esas alınır.
        var bounds = owner.WindowState == WindowState.Normal
            ? new Rect(owner.Left, owner.Top, owner.ActualWidth, owner.ActualHeight)
            : owner.RestoreBounds;
        if (bounds.IsEmpty || double.IsNaN(bounds.Left)) return;

        var left = bounds.Left + (bounds.Width - width) / 2;
        var top = bounds.Top + (bounds.Height - height) / 2;

        var work = OwnerWorkArea(owner) ?? SystemParameters.WorkArea;
        left = Math.Max(work.Left, Math.Min(left, work.Right - width));
        top = Math.Max(work.Top, Math.Min(top, work.Bottom - height));

        window.Left = left;
        window.Top = top;
    }

    /// <summary>Sahibin bulunduğu ekranın çalışma alanı, WPF birimlerinde (DPI'a göre çevrilmiş).</summary>
    private static Rect? OwnerWorkArea(Window owner)
    {
        try
        {
            var handle = new WindowInteropHelper(owner).Handle;
            if (handle == IntPtr.Zero) return null;
            var monitor = MonitorFromWindow(handle, MonitorDefaultToNearest);
            if (monitor == IntPtr.Zero) return null;
            var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
            if (!GetMonitorInfo(monitor, ref info)) return null;
            var fromDevice = PresentationSource.FromVisual(owner)?.CompositionTarget?.TransformFromDevice;
            if (fromDevice is null) return null;
            var topLeft = fromDevice.Value.Transform(new Point(info.Work.Left, info.Work.Top));
            var bottomRight = fromDevice.Value.Transform(new Point(info.Work.Right, info.Work.Bottom));
            return new Rect(topLeft, bottomRight);
        }
        catch
        {
            return null;
        }
    }

    private const uint MonitorDefaultToNearest = 2;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect Work;
        public uint Flags;
    }

    [LibraryImport("user32.dll")]
    private static partial IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
}
