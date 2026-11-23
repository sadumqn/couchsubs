// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Velopack;

namespace CouchSubs.App;

public static class Program
{
    /// <summary>
    /// Velopack kurulum, güncelleme ve kaldırma sırasında uygulamayı kısa süreli çağırır (kanca); kanca 30 saniyede 0 ile
    /// dönmezse kurulum "Yükleme Kısmen Başarılı" uyarısı verir. Bu yöntem yalnız .NET'in kendi türlerine dokunur:
    /// .NET bir yöntemi derlerken içindeki bütün türleri yükler, o yüzden başka DLL isteyen her iş (güvenlik duvarı,
    /// Velopack, WPF) ayrı yöntemdedir. Böylece bir DLL eksik ya da güvenlik yazılımınca engelliyken de kanca 0 ile
    /// döner, normal açılış ise sessizce kapanmak yerine nedeni kaydedip gösterir.
    /// </summary>
    [STAThread]
    public static int Main(string[] args)
    {
        var hook = StartupGuard.InstallHook(args);
        try
        {
            if (hook is not null)
            {
                // Kurulum ve güncelleme kancalarında yapılacak iş yok; kaldırmada yalnız güvenlik duvarı kuralı silinir.
                if (hook == StartupGuard.UninstallHook) RemoveFirewallRule();
                return 0;
            }
            // İzin yardımcısı ikinci arayüzü/oturumu başlatmaz; kurulum yolu kendi sürecinden alınır.
            if (args.Length == 1 && args[0] == Services.WindowsFirewall.ConfigureArgument) return ConfigureFirewall();
            // Yalnız CI: kasıtlı çökme ve sonraki açılışın kaydı bulması (windows.yml).
            if (args is ["--crash-test", var kind]) return CrashTest(kind);
            if (args is ["--crash-report", var output]) return CrashReport(output);
            if (args is ["--stress-okuma", var seconds, var result]) return ReadStressRun(seconds, result);
            // Yerel çökmeler (erişim ihlali) .NET'in hata düzenine uğramaz; kayıt için işleyici en başta kurulur.
            InstallCrashHandler();
            try
            {
                StartVelopack();
            }
            catch (Exception error)
            {
                // Güncelleme kitaplığı açılamasa da uygulama açılır; eksik dosya varsa açılış denetimi söyler.
                StartupGuard.Log("Velopack başlatılamadı", error);
            }
            // Güncelleme denetimi ana pencereden yürür; önceki açılış pencereye ulaşmadıysa arayüzden önce burada denenir.
            if (args is not ["--render-screens", _] and not ["--olc-bosta", _, _]) RescueUpdate.BeforeLaunch();
            return RunApp();
        }
        catch (Exception error)
        {
            StartupGuard.Log("Açılış hatası (" + string.Join(' ', args) + ")", error);
            // Kanca arayüz gösteremez; kaldırma da kural silinemedi diye durmaz.
            if (hook is not null) return 0;
            var message = StartupGuard.LaunchMessage(error);
            if (args is ["--render-screens", var folder])
            {
                Directory.CreateDirectory(folder);
                File.AppendAllText(Path.Combine(folder, "errors.txt"), message + "\n" + error + "\n");
            }
            else
            {
                // Arayüz açılamadı: düzeltilmiş sürüm varsa kurulup uygulama yeniden başlar (RescueUpdate).
                RescueUpdate.TryNow();
                // WPF'in kendisi yüklenemiyor olabilir; ileti Windows'un kendi penceresiyle gösterilir.
                MessageBoxW(IntPtr.Zero, message, "CouchSubs", 0x10 | 0x10000);
            }
            return 3;
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static int ConfigureFirewall() => Services.WindowsFirewall.ConfigureCurrentProcess();

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void RemoveFirewallRule() => Services.WindowsFirewall.RemoveRuleQuietly();

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void InstallCrashHandler() => CrashHandler.Install();

    [MethodImpl(MethodImplOptions.NoInlining)]
    static int CrashTest(string kind) => Services.CrashWatch.RunTest(kind);

    [MethodImpl(MethodImplOptions.NoInlining)]
    static int CrashReport(string output) => Services.CrashWatch.RunReport(output);

    [MethodImpl(MethodImplOptions.NoInlining)]
    static int ReadStressRun(string seconds, string output) => Services.ReadStress.Run(seconds, output);

    /// <summary>İndirilmiş güncellemeyi uygular, eski paketleri siler. Kancalar buraya gelmez (Main).</summary>
    [MethodImpl(MethodImplOptions.NoInlining)]
    static void StartVelopack() => VelopackApp.Build().Run();

    [MethodImpl(MethodImplOptions.NoInlining)]
    static int RunApp()
    {
        var app = new App();
        app.InitializeComponent();
        return app.Run();
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int MessageBoxW(IntPtr window, string text, string caption, uint type);
}
