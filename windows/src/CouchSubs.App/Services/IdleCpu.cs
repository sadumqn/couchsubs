// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Services;

/// <summary>
/// Boşta işlemci ölçümü (Perde hedefi: boşta ≤ %2). <c>CouchSubs.exe --olc-bosta saniye dosya</c>: uygulama penceresi
/// örnek verilerle (kurulum bitmiş, çeviri durmuş) Ana Ekran'da açılır, hareket kapısı açık tutulur (pencere öndeymiş gibi:
/// ortam ışığı süzülür), 3 sn ısınmadan sonra verilen süre boyunca sürecin işlemci zamanı ölçülür; ardından aynısı Geçmiş ve
/// Ayarlar için. Sonuç dosyaya yazılır: "sayfa: %tek-çekirdek %toplam" (Görev Yöneticisi'nin gösterdiği toplam orandır).
/// Ölçüm yöntemi: Process.TotalProcessorTime farkı / (geçen süre × çekirdek sayısı). WPF çizimi ekran kartında yapılır; ekran
/// kartı olmayan sanal makinede (CI) yazılımla çizildiği için sonuç gerçek bilgisayardakinden yüksek çıkar, bu yüzden CI'da
/// bilgi amaçlıdır; gerçek değer bir Windows bilgisayarda aynı komutla alınır.
/// </summary>
public static class IdleCpu
{
    public static void Run(Application app, string secondsText, string output)
    {
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        var seconds = double.TryParse(secondsText, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? Math.Clamp(value, 2, 120) : 10;
        var lines = new List<string>();
        try
        {
            ThemeManager.Apply(app.Resources, true);
            MotionGate.Forced = true;
            var controller = ScreenRenderer.Demo(OnboardingStep.Done);
            var window = new ShellWindow(controller) { Left = 40, Top = 40 };
            window.Show();
            foreach (var (tab, name) in new[] { (ShellTab.Home, "ana"), (ShellTab.History, "gecmis"), (ShellTab.Settings, "ayarlar") })
            {
                window.ShowForRender(tab);
                Wait(TimeSpan.FromSeconds(tab == ShellTab.Home ? 10 : 3)); // Ana Ekran: işlemci koruması (Controls/Perde.cs › AmbientGlow) karar versin.
                var process = Process.GetCurrentProcess();
                process.Refresh();
                var cpuStart = process.TotalProcessorTime;
                var clock = Stopwatch.StartNew();
                Wait(TimeSpan.FromSeconds(seconds));
                process.Refresh();
                var used = (process.TotalProcessorTime - cpuStart).TotalSeconds;
                var single = used / clock.Elapsed.TotalSeconds * 100;
                var total = single / Environment.ProcessorCount;
                lines.Add(string.Format(CultureInfo.InvariantCulture, "{0}: tek çekirdek %{1:0.0}, toplam %{2:0.00} ({3} çekirdek, {4:0} sn)",
                    name, single, total, Environment.ProcessorCount, clock.Elapsed.TotalSeconds));
            }
            lines.Add($"çizim katmanı: {System.Windows.Media.RenderCapability.Tier >> 16} (2 = ekran kartı), ortam ışığı süzülebilir: {Controls.AmbientGlow.Hardware} (false: yazılım çizimi, uzak masaüstü ya da işlemci koruması devrede)");
            window.Close();
        }
        catch (Exception error)
        {
            lines.Add("ölçüm hatası: " + error);
        }
        finally
        {
            MotionGate.Forced = null;
        }
        File.WriteAllLines(output, lines);
        app.Shutdown();
    }

    /// <summary>Arayüz iş parçacığını bloklamadan bekler (çizim ve animasyonlar sürer).</summary>
    private static void Wait(TimeSpan span)
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer { Interval = span };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            frame.Continue = false;
        };
        timer.Start();
        Dispatcher.PushFrame(frame);
    }
}
