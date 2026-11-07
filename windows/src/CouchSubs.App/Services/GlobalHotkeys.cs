// SPDX-License-Identifier: AGPL-3.0-only

using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace CouchSubs.App.Services;

/// <summary>
/// Ek bölgeler için genel kısayollar: F8 → 1. ek bölge, F9 → 2. ek bölge. Kullanıcı kumandayla oynarken
/// bilgisayardaki pencere arka planda olsa da çalışır. Tuş başka bir uygulamada kullanılıyorsa sessizce atlanır.
/// </summary>
public sealed partial class GlobalHotkeys : IDisposable
{
    private const int WmHotkey = 0x0312;
    private const uint ModNoRepeat = 0x4000;
    /// <summary>Kısayol kimlikleri bu sayıdan başlar; ek bölge numarası = kimlik − FirstId + 1.</summary>
    private const int FirstId = 0x4353;
    private static readonly uint[] VirtualKeys = [0x77, 0x78];

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint virtualKey);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnregisterHotKey(IntPtr window, int id);

    private readonly IntPtr window;
    private readonly HwndSource? source;
    private readonly Action<int> pressed;
    private readonly List<int> registered = [];

    /// <param name="window">Pencerenin tutamağı (HWND).</param>
    /// <param name="pressed">Kısayola basılınca ek bölge numarasıyla (1 ya da 2) çağrılır.</param>
    public GlobalHotkeys(IntPtr window, Action<int> pressed)
    {
        this.window = window;
        this.pressed = pressed;
        source = HwndSource.FromHwnd(window);
        if (source is null) return;
        source.AddHook(Hook);
        for (var index = 0; index < VirtualKeys.Length; index++)
        {
            var id = FirstId + index;
            if (RegisterHotKey(window, id, ModNoRepeat, VirtualKeys[index])) registered.Add(id);
        }
    }

    private IntPtr Hook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message != WmHotkey) return IntPtr.Zero;
        var id = wParam.ToInt32();
        if (!registered.Contains(id)) return IntPtr.Zero;
        handled = true;
        pressed(id - FirstId + 1);
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        source?.RemoveHook(Hook);
        foreach (var id in registered) UnregisterHotKey(window, id);
        registered.Clear();
    }
}
