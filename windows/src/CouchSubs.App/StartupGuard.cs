// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;

namespace CouchSubs.App;

/// <summary>
/// Açılış hatalarını sessizce kapanmak yerine gösterir. Bu sınıf yalnız .NET'in kendi türlerini kullanır: uygulamanın
/// başka bir DLL'i eksik olsa da yüklenip çalışabilmeli.
/// </summary>
internal static class StartupGuard
{
    static bool Turkish => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "tr";

    static string LogPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CouchSubs", "hata.log");

    /// <summary>
    /// deps.json'da listelenen ama klasörde olmayan DLL'ler. Antivirüs bir dosyayı karantinaya alınca .NET açılışta
    /// FileNotFoundException verir ve pencere hiç açılmaz.
    /// </summary>
    public static IReadOnlyList<string> MissingFiles(string folder)
    {
        var deps = Path.Combine(folder, "CouchSubs.deps.json");
        if (!File.Exists(deps)) return [];
        try
        {
            using var json = JsonDocument.Parse(File.ReadAllText(deps));
            var names = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var target in json.RootElement.GetProperty("targets").EnumerateObject())
                foreach (var library in target.Value.EnumerateObject())
                    if (library.Value.TryGetProperty("runtime", out var runtime))
                        foreach (var file in runtime.EnumerateObject())
                            names.Add(Path.GetFileName(file.Name));
            return [.. names.Where(name => !File.Exists(Path.Combine(folder, name)))];
        }
        catch (Exception error) when (error is JsonException or KeyNotFoundException or InvalidOperationException or IOException)
        {
            return [];
        }
    }

    public static string MissingMessage(IReadOnlyList<string> files)
    {
        var list = string.Join("\n", files.Take(8).Select(f => "  • " + f)) + (files.Count > 8 ? "\n  • …" : "");
        return Turkish
            ? $"CouchSubs açılamadı: program klasöründe şu dosyalar yok:\n\n{list}\n\n" +
              "Bunun en sık nedeni antivirüs programının dosyayı karantinaya almasıdır. Windows Güvenliği › Virüs ve tehdit " +
              "koruması › Koruma geçmişi'nden dosyayı geri yükleyin ya da CouchSubs-windows-x64.zip'i yeniden indirip " +
              "\"Tümünü ayıkla\" ile bir klasöre çıkarın. Programı zip'in içinden çalıştırmayın."
            : $"CouchSubs could not start: these files are missing from its folder:\n\n{list}\n\n" +
              "This usually means an antivirus moved them to quarantine. Restore them from Windows Security › Virus & threat " +
              "protection › Protection history, or download CouchSubs-windows-x64.zip again and use \"Extract all\". " +
              "Do not run the app from inside the zip.";
    }

    public static string ErrorMessage(Exception error) =>
        (Turkish
            ? "CouchSubs beklenmeyen bir hatayla karşılaştı:\n\n"
            : "CouchSubs ran into an unexpected error:\n\n") +
        $"{error.GetType().Name}: {error.Message}\n\n" +
        (Turkish
            ? $"Ayrıntılar {LogPath} dosyasında. Sorunu bu dosyayla birlikte GitHub'daki Issues sayfasından bildirebilirsiniz."
            : $"Details are in {LogPath}. Please report it on the GitHub Issues page with that file.");

    /// <summary>Hatayı kaydeder, gösterir ve uygulamayı kapatır. Ekran görüntüsü kipinde pencere yerine errors.txt yazılır.</summary>
    public static void Fail(Application app, string message, Exception? error, string? renderFolder)
    {
        Log(message, error);
        if (renderFolder is null)
        {
            MessageBox.Show(message, "CouchSubs", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        else
        {
            Directory.CreateDirectory(renderFolder);
            File.AppendAllText(Path.Combine(renderFolder, "errors.txt"), message + "\n" + error + "\n");
        }
        app.Shutdown(3);
    }

    /// <summary>Bilgisayar ekranındaki altyazı penceresi açılamadı ya da çizilemedi; çeviri sürer.</summary>
    public static string OverlayFailedMessage(Exception error) =>
        (Turkish
            ? "Bilgisayar ekranındaki altyazı penceresi açılamadı. Çeviri sürüyor ama altyazılar bu pencerede görünmeyecek; " +
              "CouchSubs'ı yeniden açınca pencere yeniden denenir.\n\n"
            : "The subtitle window on this computer's screen could not be shown. Translation continues, but subtitles won't " +
              "appear in that window until you reopen CouchSubs.\n\n") +
        $"{error.GetType().Name}: {error.Message}\n\n" +
        (Turkish
            ? $"Ayrıntılar {LogPath} dosyasında. Sorunu bu dosyayla birlikte GitHub'daki Issues sayfasından bildirebilirsiniz."
            : $"Details are in {LogPath}. Please report it on the GitHub Issues page with that file.");

    /// <summary>Arka plandaki bir hata uygulamayı kapatıyor; hiç değilse nedeni görünsün.</summary>
    static string ClosingMessage(Exception? error) =>
        (Turkish
            ? "CouchSubs bir hata yüzünden kapanmak zorunda kaldı:\n\n"
            : "CouchSubs has to close because of an error:\n\n") +
        (error is null ? "" : $"{error.GetType().Name}: {error.Message}\n\n") +
        (Turkish
            ? $"Ayrıntılar {LogPath} dosyasında. Sorunu bu dosyayla birlikte GitHub'daki Issues sayfasından bildirebilirsiniz."
            : $"Details are in {LogPath}. Please report it on the GitHub Issues page with that file.");

    /// <summary>
    /// Açılıştan sonraki yakalanmamış hataları da sessiz kalmadan gösterir. Uygulama kapanmaz: kullanıcı yaptığı işi
    /// (ör. az önce bitirdiği PSN girişini) kaybetmesin ve çeviri sürsün.
    /// </summary>
    public static void Watch(Application app)
    {
        app.DispatcherUnhandledException += (_, e) =>
        {
            Log("DispatcherUnhandledException", e.Exception);
            // İleti burada, hatanın içinde açılmaz: düzen ya da çizim sırasında çıkan hatada MessageBox kendisi hata verir
            // (iletiler askıdayken pencere açılamaz) ve o ikinci hata uygulamayı kapatırdı. Her karede yinelenen bir hata
            // da iç içe yüzlerce pencere açıp yığını taşırırdı. İleti sonra, tek seferde gösterilir.
            e.Handled = true;
            Show(app, ErrorMessage(e.Exception));
        };
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            var error = e.ExceptionObject as Exception;
            Log(e.IsTerminating ? "UnhandledException (uygulama kapanıyor)" : "UnhandledException", error);
            // Arka plan iş parçacığındaki hata süreci kapatır; uygulama sessizce kaybolmasın.
            if (e.IsTerminating) ShowNow(ClosingMessage(error));
        };
        // Beklenmeyen görev hataları da kayda geçer (gözlenmemiş görev uygulamayı kapatmaz ama sorunun izi kalsın).
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            Log("UnobservedTaskException", e.Exception);
            e.SetObserved();
        };
    }

    static readonly object LogGate = new();
    static int showing;
    static string? lastShown;
    static DateTime lastShownAt;

    /// <summary>
    /// Hata iletisini arayüz boşalınca gösterir. Aynı anda tek ileti açılır; aynı ileti yarım dakika içinde yinelenirse
    /// yalnız kayda geçer (her karede yinelenen hata kullanıcıyı ileti yağmuruna tutmasın).
    /// </summary>
    public static void Show(Application? app, string message)
    {
        if (app is null) return;
        try
        {
            app.Dispatcher.InvokeAsync(() =>
            {
                if (showing > 0) return;
                if (message == lastShown && DateTime.UtcNow - lastShownAt < TimeSpan.FromSeconds(30)) return;
                showing++;
                try
                {
                    ShowNow(message);
                }
                finally
                {
                    showing--;
                    lastShown = message;
                    lastShownAt = DateTime.UtcNow;
                }
            }, DispatcherPriority.Background);
        }
        catch (Exception error)
        {
            Log("Hata iletisi sıraya alınamadı", error);
        }
    }

    static void ShowNow(string message)
    {
        try
        {
            MessageBox.Show(message, "CouchSubs", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        catch (Exception error)
        {
            Log("Hata iletisi gösterilemedi", error);
        }
    }

    /// <summary>%LOCALAPPDATA%\CouchSubs\hata.log dosyasına yazar; yazılamazsa sessizce geçer.</summary>
    internal static void Log(string message, Exception? error)
    {
        try
        {
            // Arka plan iş parçacıkları da yazar; aynı anda yazılan satırlar birbirini silmesin.
            lock (LogGate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
                File.AppendAllText(LogPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}\n{error}\n\n");
            }
        }
        catch (Exception)
        {
            // Kayıt yazılamasa da mesaj gösterilir; hata işleyicisinin içinden yeni hata çıkmamalı.
        }
    }
}
