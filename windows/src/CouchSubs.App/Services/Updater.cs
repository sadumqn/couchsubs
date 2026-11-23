// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Net.Http;
using CouchSubs.Core;
using CouchSubs.Shell;
using Velopack;
using Velopack.Sources;

namespace CouchSubs.App.Services;

/// <summary>
/// GitHub'daki sürümlerden güncelleme (Velopack). Yalnız kurulum dosyasıyla (CouchSubs-Setup.exe) kurulan uygulama
/// kendini günceller; zip'ten açılan kopyada sitemizin indirme bölümü açılır.
/// </summary>
internal sealed class Updater : IUpdater
{
    private const string Repository = "https://github.com/yorulmazsinan/couchsubs";
    private readonly UpdateManager manager = new(new GithubSource(Repository, null, false));
    private UpdateInfo? pending;
    private readonly GitHubReleaseNotes notes = new(new HttpClient
        { Timeout = TimeSpan.FromSeconds(10), MaxResponseContentBufferSize = 2 * 1024 * 1024 });

    public bool CanUpdateItself => manager.IsInstalled;
    public Uri DownloadPage { get; } = new("https://couchsubs.enmeraapps.com/#indir");
    public UpdateAttemptJournal? Attempts { get; } =
        new(UpdateAttemptJournal.DefaultPath, AppVersion.Current(typeof(Updater).Assembly));

    /// <summary>
    /// Velopack kurulumu: %LOCALAPPDATA%\CouchSubsApp\current\CouchSubs.exe; Update.exe günlüğünü bir üst klasöre
    /// (velopack.log) yazar.
    /// </summary>
    public string? UpdateLogPath =>
        manager.IsInstalled ? Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "velopack.log")) : null;

    public Task<IReadOnlyList<ReleaseNoteRun>> ReleaseNotesAsync(string version) => notes.LoadAsync(version);

    public async Task<string?> CheckAsync()
    {
        if (!manager.IsInstalled) return await LatestTagAsync();
        pending = await manager.CheckForUpdatesAsync();
        return pending?.TargetFullRelease.Version.ToString();
    }

    public async Task InstallAsync(IProgress<double> progress, Action? beforeRestart = null)
    {
        if (pending is null) return;
        await manager.DownloadUpdatesAsync(pending, percent => progress.Report(percent / 100.0));
        beforeRestart?.Invoke();
        // Update.exe kurulum klasörünü değiştirir; açık kalan yardımcı süreç (CTranslate2 python.exe, Xbox köprüsü
        // node.exe, seslendirme motoru) klasörü kilitlerse güncelleme uygulanamaz ve eski sürüm yeniden açılır.
        var running = ChildProcessGuard.StopAllForUpdate(TimeSpan.FromSeconds(5));
        if (running > 0)
        {
            var message = Localizer.Current["The update was postponed because CouchSubs couldn't confirm that all helper processes have exited. Restart CouchSubs and try again."];
            SubtitleLog.Write($"Güncelleme ertelendi: {running} yardımcı süreç kapanışı doğrulanamadı; " +
                              $"{pending.TargetFullRelease.Version} sürümü uygulanmadı.");
            SubtitleLog.Flush();
            throw new InvalidOperationException(message);
        }
        SubtitleLog.Write($"Güncelleme uygulanıyor: {pending.TargetFullRelease.Version}");
        SubtitleLog.Flush();
        manager.ApplyUpdatesAndRestart(pending);
    }

    /// <summary>Zip kullanıcısı için: GitHub'daki en son sürümün etiketi, bu sürümden yeniyse.</summary>
    private static async Task<string?> LatestTagAsync()
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("CouchSubs");
            using var document = System.Text.Json.JsonDocument.Parse(
                await http.GetStringAsync("https://api.github.com/repos/yorulmazsinan/couchsubs/releases/latest"));
            var tag = document.RootElement.GetProperty("tag_name").GetString()?.TrimStart('v');
            return tag is not null && AppVersion.IsNewer(tag, AppVersion.Current(typeof(Updater).Assembly)) ? tag : null;
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException
                                          or KeyNotFoundException or InvalidOperationException)
        {
            return null;
        }
    }
}
