// SPDX-License-Identifier: AGPL-3.0-only

using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using CouchSubs.Shell;

namespace CouchSubs.App.Services;

/// <summary>
/// Bağlı ekranlar: aygıt adı (<c>\\.\DISPLAY1</c>) ve alanı, WPF birimine çevrilmiş. Altyazı penceresi hangi ekranda
/// kaydedildiğini bununla hatırlar. Okunamazsa boş liste (pencere eskisi gibi tüm ekranlardaki yere göre açılır).
/// </summary>
internal static class Displays
{
    public static IReadOnlyList<DisplayArea> All(Visual? reference)
    {
        try
        {
            var raw = new List<(string Name, NativeRect Rect, bool Primary)>();
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (monitor, _, _, _) =>
            {
                var info = new MonitorInfoEx { Size = Marshal.SizeOf<MonitorInfoEx>() };
                if (GetMonitorInfo(monitor, ref info) && !string.IsNullOrEmpty(info.Device))
                    raw.Add((info.Device, info.Monitor, (info.Flags & MonitorInfoPrimary) != 0));
                return true;
            }, IntPtr.Zero);
            // Piksel → WPF birimi: pencere henüz açılmadıysa (kaynağı yok) ana ekranın piksel genişliğinden hesaplanır.
            var fromDevice = (reference is null ? null : PresentationSource.FromVisual(reference)?.CompositionTarget?.TransformFromDevice)
                             ?? PrimaryScale(raw);
            return [.. raw.Select(m =>
            {
                var topLeft = fromDevice.Transform(new Point(m.Rect.Left, m.Rect.Top));
                var bottomRight = fromDevice.Transform(new Point(m.Rect.Right, m.Rect.Bottom));
                return new DisplayArea(m.Name, new ScreenArea(topLeft.X, topLeft.Y, bottomRight.X - topLeft.X, bottomRight.Y - topLeft.Y));
            })];
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException or InvalidOperationException)
        {
            return [];
        }
    }

    private const uint MonitorInfoPrimary = 1;

    private static Matrix PrimaryScale(List<(string Name, NativeRect Rect, bool Primary)> monitors)
    {
        var primary = monitors.FirstOrDefault(m => m.Primary);
        var pixels = primary.Rect.Right - primary.Rect.Left;
        var scale = pixels > 0 && SystemParameters.PrimaryScreenWidth > 0 ? SystemParameters.PrimaryScreenWidth / pixels : 1;
        return new Matrix(scale, 0, 0, scale, 0, 0);
    }

    private delegate bool MonitorEnum(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfoEx
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect Work;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string Device;
    }

#pragma warning disable SYSLIB1054 // Geri çağrılı ve dizgi alanlı yapı: klasik P/Invoke sıralaması yeterli.
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnum callback, IntPtr data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfoEx info);
#pragma warning restore SYSLIB1054
}
