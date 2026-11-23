// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Runtime.CompilerServices;
using Velopack;
using Velopack.Sources;

namespace CouchSubs.App;

/// <summary>
/// Arayüz açılamasa da güncelleme gelsin. Uygulamanın güncelleme denetimi ana pencereden yürür (AppController); arayüzde
/// açılış çökmesi olan bir sürüm, düzeltilmiş sürümü kendisi kuramazdı. Açılış başlarken bir işaret dosyası yazılır, ana
/// pencere çizilince silinir. İşaret önceki açılıştan kalmışsa (pencere hiç çizilmeden süreç kapandı; yerel çökme dahil)
/// ya da açılış hatayla düşerse GitHub'daki daha yeni sürüm indirilip kurulur ve uygulama yeniden başlar. Yalnız kurulum
/// dosyasıyla (Velopack) kurulan uygulamada çalışır; Velopack türleri ayrı yöntemde, DLL eksikse yalnız kayda geçer.
/// </summary>
internal static class RescueUpdate
{
    const string Repository = "https://github.com/yorulmazsinan/couchsubs";
    static readonly TimeSpan Limit = TimeSpan.FromSeconds(45);

    static string MarkerPath => Path.Combine(Path.GetDirectoryName(StartupGuard.LogPath)!, "acilis-suruyor");

    /// <summary>Program.Main, arayüzden önce: önceki açılış pencereye ulaşmadıysa güncellemeyi dener, sonra işaret yazar.</summary>
    public static void BeforeLaunch()
    {
        try
        {
            if (File.Exists(MarkerPath))
            {
                StartupGuard.Log("Önceki açılış ana pencereye ulaşmadı; kurtarma güncellemesi aranıyor", null);
                TryNow();
            }
            Directory.CreateDirectory(Path.GetDirectoryName(MarkerPath)!);
            File.WriteAllText(MarkerPath, DateTime.Now.ToString("O"));
        }
        catch (Exception error)
        {
            StartupGuard.Log("Açılış işareti yazılamadı", error);
        }
    }

    /// <summary>Ana pencere çizildi: açılış başarılı, işaret silinir.</summary>
    public static void Reached()
    {
        try
        {
            File.Delete(MarkerPath);
        }
        catch (Exception error)
        {
            StartupGuard.Log("Açılış işareti silinemedi", error);
        }
    }

    /// <summary>Daha yeni sürüm varsa indirir, kurar ve uygulamayı yeniden başlatır (dönmez); yoksa ya da olmazsa döner.</summary>
    public static void TryNow()
    {
        try
        {
            Run();
        }
        catch (Exception error)
        {
            StartupGuard.Log("Kurtarma güncellemesi yapılamadı", error);
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Run()
    {
        var manager = new UpdateManager(new GithubSource(Repository, null, false));
        if (!manager.IsInstalled) return;
        var download = Task.Run(async () =>
        {
            var found = await manager.CheckForUpdatesAsync().ConfigureAwait(false);
            if (found is not null) await manager.DownloadUpdatesAsync(found).ConfigureAwait(false);
            return found;
        });
        if (!download.Wait(Limit))
        {
            StartupGuard.Log("Kurtarma güncellemesi zamanında bitmedi; bu açılışta denenmeyecek", null);
            return;
        }
        var update = download.Result;
        if (update is null)
        {
            StartupGuard.Log("Kurtarma güncellemesi: daha yeni sürüm yok", null);
            return;
        }
        StartupGuard.Log($"Kurtarma güncellemesi uygulanıyor: {update.TargetFullRelease.Version}", null);
        // Yeni sürümün ilk açılışı bu açılışın işaretini görüp yeniden aramasın.
        Reached();
        manager.ApplyUpdatesAndRestart(update);
    }
}
