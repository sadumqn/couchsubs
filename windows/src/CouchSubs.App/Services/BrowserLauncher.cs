// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace CouchSubs.App.Services;

/// <summary>
/// Samsung giriş sayfasını varsayılan tarayıcıda açar ve tarayıcının öne gelmesine izin verir. Windows, öndeki
/// uygulama izin vermezse başka programın pencereyi öne almasını engeller; sayfa arkada açılınca kullanıcı giriş
/// penceresini hiç görmüyordu.
/// </summary>
internal static partial class BrowserLauncher
{
    private const int AnyProcess = -1; // ASFW_ANY

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool AllowSetForegroundWindow(int processId);

    public static void Open(Uri url)
    {
        try
        {
            AllowSetForegroundWindow(AnyProcess);
            Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true });
        }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException or EntryPointNotFoundException or DllNotFoundException)
        {
            // Tarayıcı açılamazsa kart "Sayfayı yeniden aç" ile bekler; neden günlükte görünsün.
            StartupGuard.Log("Tarayıcı açılamadı", error);
            new TvInstall.InstallLog(LiveServices.TvInstallLogPath).Write($"Tarayıcı açılamadı: {url.AbsoluteUri}: {error.Message}");
        }
    }
}
