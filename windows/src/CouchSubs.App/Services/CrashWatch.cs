// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.IO;
using System.Windows;
using CouchSubs.Core;
using CouchSubs.RemotePlay;

namespace CouchSubs.App.Services;

/// <summary>
/// Açılışta önceki çalışmanın çöküp çökmediğine bakar (<see cref="CrashRecords"/>). Çöktüyse özeti modül sürümleri, son
/// günlük satırları ve Windows olay günlüğündeki kayıtla tamamlar; ana ekran bunu bir kez bildirir ("CouchSubs geçen sefer
/// beklenmedik biçimde kapandı"). Hiçbir şey kendiliğinden gönderilmez: kullanıcı dosyayı Dosya Gezgini'nde görür ya da
/// özeti panoya kopyalar.
/// </summary>
internal static class CrashWatch
{
    private static readonly object Gate = new();
    private static CrashRecord? pending;
    private static string pendingText = "";

    /// <summary>Bildirilecek kayıt hazır olunca (arka plan iş parçacığında) çağrılır.</summary>
    public static event Action? Changed;

    /// <summary>Önceki çalışmayı kapatan, kullanıcıya henüz gösterilmemiş kayıt.</summary>
    public static CrashRecord? Pending
    {
        get { lock (Gate) return pending; }
    }

    /// <summary>Kaydın tamamlanmış özeti (panoya kopyalanır).</summary>
    public static string PendingText
    {
        get { lock (Gate) return pendingText; }
    }

    /// <summary>Uygulama açılışı: önceki çalışmaya arka planda bakılır, olağan kapanışta oturum işareti silinir.</summary>
    public static void Start()
    {
        AppDomain.CurrentDomain.ProcessExit += (_, _) => CrashRecords.EndSession(CrashHandler.Folder, Environment.ProcessId);
        _ = Task.Run(() =>
        {
            try { Prepare(); }
            catch (Exception error) { StartupGuard.Log("Çökme kaydı okunamadı", error); }
        });
    }

    /// <summary>Önceki çalışmanın kaydını bulur ve tamamlar; yoksa null.</summary>
    internal static CrashRecord? Prepare()
    {
        var folder = CrashHandler.Folder;
        var now = DateTime.Now;
        CrashRecords.Rotate(folder);
        var previous = CrashRecords.BeginSession(folder, Environment.ProcessId, now, IsRunning);
        var record = CrashRecords.Pending(folder, previous);
        if (record is null && previous is not null)
        {
            // Yerel işleyici kayıt bırakamadı (ör. __fastfail) ama süreç olağan biçimde kapanmadı: Windows kaydetmiş mi.
            var entries = EventLogEntries(previous.StartedAt.AddSeconds(-1), now, onlyFaults: true);
            if (entries.Count > 0)
                record = CrashRecords.WriteFromEventLog(folder, previous, entries[^1].Time, CrashHandler.Header, [.. entries.Select(e => e.Text)]);
        }
        if (record is null) return null;
        var until = record.Time.AddSeconds(2);
        var text = CrashRecords.Complete(record, new CrashDetails(
            VersionOf,
            [
                ("altyazi.log", CrashRecords.LogTail(CrashRecords.ReadEnd(SubtitleLog.DefaultPath), until, CrashRecords.LogLines)),
                ("remoteplay.log", CrashRecords.LogTail(CrashRecords.ReadEnd(RemotePlayLog.FilePath), until, 20)),
                ("hata.log", CrashRecords.LogTail(CrashRecords.ReadEnd(StartupGuard.LogPath, 32 * 1024), until, 20)),
            ],
            [.. EventLogEntries(record.Time.AddMinutes(-1), record.Time.AddMinutes(3), onlyFaults: false).Select(e => e.Text)],
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), Environment.UserName));
        lock (Gate)
        {
            pending = CrashRecords.Parse(record.SummaryPath) ?? record;
            pendingText = text;
        }
        Changed?.Invoke();
        return record;
    }

    /// <summary>Bildirim ana ekranda göründü: aynı kayıt bir daha bildirilmez.</summary>
    public static void MarkShown()
    {
        if (Pending is { } record) CrashRecords.MarkShown(CrashHandler.Folder, record);
    }

    /// <summary>Bildirim kapatıldı.</summary>
    public static void Dismiss()
    {
        lock (Gate) pending = null;
    }

    /// <summary>Özet dosyasını Dosya Gezgini'nde seçili açar (döküm aynı adla yanındadır).</summary>
    public static void ShowInExplorer()
    {
        if (Pending is not { } record) return;
        try
        {
            var arguments = File.Exists(record.SummaryPath) ? $"/select,\"{record.SummaryPath}\"" : $"\"{CrashHandler.Folder}\"";
            Process.Start(new ProcessStartInfo("explorer.exe", arguments) { UseShellExecute = false })?.Dispose();
        }
        catch (Exception error)
        {
            StartupGuard.Log("Çökme kaydı gösterilemedi", error);
        }
    }

    /// <summary>Özeti panoya kopyalar; kopyalanamazsa false.</summary>
    public static bool CopySummary()
    {
        try
        {
            Clipboard.SetText(PendingText);
            return true;
        }
        catch (Exception error)
        {
            // Pano başka bir uygulamada kilitliyken hata verir.
            StartupGuard.Log("Çökme özeti kopyalanamadı", error);
            return false;
        }
    }

    private static bool IsRunning(int processId)
    {
        try
        {
            using var other = Process.GetProcessById(processId);
            using var self = Process.GetCurrentProcess();
            return !other.HasExited && string.Equals(other.ProcessName, self.ProcessName, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception)
        {
            return false;
        }
    }

    private static string? VersionOf(string path)
    {
        try { return File.Exists(path) ? FileVersionInfo.GetVersionInfo(path).FileVersion : null; }
        catch (Exception) { return null; }
    }

    /// <summary>
    /// Windows'un Uygulama günlüğünde CouchSubs'ın kapanışına ait kayıtlar (.NET Runtime: yönetilen yığın izi; Application
    /// Error: hatalı modül ve uzaklık). Günlük okunamazsa boş liste. <paramref name="onlyFaults"/>: yalnız Application Error.
    /// </summary>
    internal static IReadOnlyList<(DateTime Time, string Text)> EventLogEntries(DateTime from, DateTime to, bool onlyFaults)
    {
        var found = new List<(DateTime, string)>();
        try
        {
            using var log = new EventLog("Application");
            var entries = log.Entries;
            // Kayıtlar zaman sırasındadır: sondan geriye, aralığın başına kadar (en çok birkaç bin kayıt) bakılır.
            for (int index = entries.Count - 1, looked = 0; index >= 0 && looked < 5000 && found.Count < 4; index--, looked++)
            {
                using var entry = entries[index];
                if (entry.TimeGenerated < from) break;
                if (entry.TimeGenerated > to) continue;
                var source = entry.Source;
                if (source != "Application Error" && (onlyFaults || source is not (".NET Runtime" or "Windows Error Reporting"))) continue;
                var message = entry.Message;
                if (!message.Contains("CouchSubs", StringComparison.OrdinalIgnoreCase)) continue;
                if (message.Length > 6000) message = message[..6000] + "…";
                found.Add((entry.TimeGenerated, $"[{entry.TimeGenerated:yyyy-MM-dd HH:mm:ss}] {source}:\n{message}"));
            }
        }
        catch (Exception)
        {
            // Olay günlüğü kapalı ya da okunamıyor: özet onsuz tamamlanır.
        }
        found.Reverse();
        return found;
    }

    // --- Deneme (CI: .github/workflows/windows.yml) ---

    public const string TestArgument = "--crash-test";
    public const string ReportArgument = "--crash-report";

    /// <summary>
    /// <c>CouchSubs.exe --crash-test &lt;tür&gt;</c>: çökme kaydını kurup kasıtlı hata yapar. Türler: <c>yerel</c> (P/Invoke
    /// altında yerel kodda geçersiz adrese yazma), <c>is-parcacigi</c> (yerel iş parçacığında aynısı), <c>atlama</c>
    /// (bırakılmış belleğe atlama; adres hiçbir modüle düşmez), <c>yonetilen</c> (yönetilen kodda geçersiz adrese yazma),
    /// <c>bos</c> (yakalanan NullReferenceException; kayıt bırakmamalı ve 0 ile dönmeli).
    /// </summary>
    public static unsafe int RunTest(string kind)
    {
        // Windows'un hata penceresi CI'ı bekletmesin (SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX).
        SetErrorMode(0x0001 | 0x0002);
        if (!CrashHandler.Install()) return 4;
        var folder = CrashHandler.Folder;
        CrashRecords.BeginSession(folder, Environment.ProcessId, DateTime.Now, IsRunning);
        switch (kind)
        {
            case "yerel": CrashHandler.cs_crash_test(0); break;
            case "is-parcacigi": CrashHandler.cs_crash_test(1); break;
            case "atlama": CrashHandler.cs_crash_test(2); break;
            case "yonetilen":
                var target = (int*)0x12345678;
                *target = 1;
                break;
            case "paralel-yonetilen":
                // #587'deki yığının biçimi: Parallel.For iş parçacığında yönetilen kodda geçersiz adrese yazma.
                System.Threading.Tasks.Parallel.For(0, 2, index => { if (index == 1) WriteInvalid(); else Thread.Sleep(200); });
                break;
            case "kisa-kare":
                // #587 için sınanan varsayım: AutoLevel'da dizinin dışına taşan bir yönetilen istisna, Parallel.For iş
                // parçacığında dağıtılırken erişim ihlaline dönüşüyor mu? Eski AutoLevel döngüsü kısa diziyle binlerce kez
                // paralel çalıştırılır; her tur IndexOutOfRangeException atmalı, süreç çökmemeli. Ardından bugünkü okuma
                // aynı kısa kareyi atlamalı (istisnasız, boş okuma).
                var thrown = 0;
                for (var round = 0; round < 200; round++)
                {
                    try
                    {
                        System.Threading.Tasks.Parallel.For(0, 16, _ =>
                        {
                            try { OldAutoLevelHistogram(new Core.Frame(new byte[(640 * 120 * 4) - 4096], 640, 120, 640 * 4)); }
                            catch (IndexOutOfRangeException) { Interlocked.Increment(ref thrown); throw; }
                        });
                    }
                    catch (AggregateException) { }
                }
                var reader = WindowsOcrReader.CreateWithoutEngine();
                var shortFrame = new Core.Frame(new byte[1000], 640, 120, 640 * 4);
                var reading = reader.ReadLines(shortFrame, deep: true);
                var screen = reader.ReadScreen(shortFrame);
                Console.WriteLine($"kisa-kare: {thrown} IndexOutOfRangeException, okuma {reading.Lines.Count} satır, ekran {screen.Lines.Count} satır");
                CrashRecords.EndSession(folder, Environment.ProcessId);
                // İlk istisnadan sonra Parallel.For yeni tur başlatmaz; her turda en az bir istisna atılmış olmalı.
                return thrown >= 200 && reading.Lines.Count == 0 && screen.Lines.Count == 0 ? 0 : 7;
            case "bos":
                try
                {
                    var nothing = Environment.GetEnvironmentVariable("COUCHSUBS_NO_SUCH_VARIABLE_FOR_TEST");
                    GC.KeepAlive(nothing!.Length);
                }
                catch (NullReferenceException)
                {
                    CrashRecords.EndSession(folder, Environment.ProcessId);
                    return 0;
                }
                break;
        }
        return 5; // buraya gelinmemeli
    }

    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static unsafe void WriteInvalid()
    {
        var target = (int*)0x12345678;
        *target = 1;
    }

    /// <summary>beta.67'deki AutoLevel'ın ilk döngüsü, denetimsiz hâliyle (yalnız "kisa-kare" denemesi için).</summary>
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static int OldAutoLevelHistogram(Core.Frame image)
    {
        var hist = new int[256];
        for (var y = 0; y < image.Height; y++)
            for (var x = 0; x < image.Width; x++)
            {
                var i = (y * image.Stride) + (x * 4);
                hist[(image.Pixels[i + 2] * 3 + image.Pixels[i + 1] * 6 + image.Pixels[i]) / 10]++;
            }
        return hist[0];
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    private static extern uint SetErrorMode(uint mode);

    /// <summary>
    /// <c>CouchSubs.exe --crash-report &lt;dosya&gt;</c>: sonraki açılışın yaptığını arayüzsüz yapar; bildirilecek kaydın
    /// tamamlanmış özetini dosyaya yazar (0), bildirilecek kayıt yoksa 6 döner.
    /// </summary>
    public static int RunReport(string output)
    {
        var record = Prepare();
        CrashRecords.EndSession(CrashHandler.Folder, Environment.ProcessId);
        if (record is null) return 6;
        MarkShown();
        File.WriteAllText(output, PendingText);
        return 0;
    }
}
