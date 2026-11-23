// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

internal sealed class FakeUpdater(string current, string journalPath) : IUpdater
{
    public bool CanUpdateItself { get; set; } = true;
    public Uri DownloadPage { get; } = new("https://couchsubs.enmeraapps.com/#indir");
    public UpdateAttemptJournal? Attempts { get; } = new(journalPath, current);
    public string? UpdateLogPath => @"C:\Users\x\AppData\Local\CouchSubsApp\velopack.log";
    public string? Latest { get; set; }
    public bool Installed { get; private set; }
    public Exception? InstallError { get; set; }
    public Task<string?> CheckAsync() => Task.FromResult(Latest);
    public Task<IReadOnlyList<ReleaseNoteRun>> ReleaseNotesAsync(string version) => Task.FromResult<IReadOnlyList<ReleaseNoteRun>>([]);

    public Task InstallAsync(IProgress<double> progress, Action? beforeRestart = null)
    {
        if (InstallError is not null) throw InstallError;
        beforeRestart?.Invoke();
        Installed = true;
        return Task.CompletedTask;
    }
}

/// <summary>
/// "Şimdi güncelle"den sonra uygulama eski sürümle yeniden açılınca (güvenlik yazılımı, kilitli klasör) aynı "yeni sürüm
/// çıktı" şeridi sonsuza dek görünmez; kurulum dosyasını indirmesi istenir. Zip'ten açılmış kopya da kurulum dosyasına
/// yönlenir.
/// </summary>
public sealed class UpdateAttemptTests : IDisposable
{
    private readonly string folder = Path.Combine(Path.GetTempPath(), "couchsubs-update-" + Guid.NewGuid().ToString("N"));
    private string Journal => Path.Combine(folder, "guncelleme-denemesi.json");

    public void Dispose()
    {
        if (Directory.Exists(folder)) Directory.Delete(folder, recursive: true);
    }

    private static AppController Controller(FakeUpdater updater, List<Uri>? opened = null)
    {
        var controller = new AppController(new FakeServices { Updater = updater }, new MemoryStore(), new MemorySettings(),
            new FakeSleep(), Localizer.ForLanguage("tr"), action => action());
        if (opened is not null) controller.OpenInBrowser = opened.Add;
        return controller;
    }

    [Fact]
    public async Task UpdateNowRecordsTheAttemptBeforeRestarting()
    {
        var updater = new FakeUpdater("0.1.0-beta.83", Journal) { Latest = "0.1.0-beta.84" };
        var controller = Controller(updater);
        await controller.CheckForUpdateAsync();
        Assert.Equal("CouchSubs'ın yeni sürümü çıktı: 0.1.0-beta.84", controller.UpdateTitle);
        Assert.Equal("Şimdi güncelle", controller.UpdateButtonText);
        Assert.Null(controller.UpdateHint);

        await controller.InstallUpdateAsync();
        Assert.True(updater.Installed);
        var attempt = updater.Attempts!.Read();
        Assert.NotNull(attempt);
        Assert.Equal("0.1.0-beta.83", attempt.FromVersion);
        Assert.Equal("0.1.0-beta.84", attempt.TargetVersion);
    }

    [Fact]
    public async Task SameVersionAfterRestartShowsApplyFailedAndOpensTheWebsite()
    {
        new UpdateAttemptJournal(Journal, "0.1.0-beta.83").Record("0.1.0-beta.84");
        var updater = new FakeUpdater("0.1.0-beta.83", Journal) { Latest = "0.1.0-beta.84" };
        var opened = new List<Uri>();
        var controller = Controller(updater, opened);
        await controller.CheckForUpdateAsync();

        Assert.True(controller.UpdateFailed);
        Assert.Equal("CouchSubs 0.1.0-beta.84 sürümüne güncellenemedi", controller.UpdateTitle);
        Assert.Equal("Güncelleme uygulanamadı. Güvenlik yazılımı engellemiş olabilir; kurulum dosyasını sitemizden indirip kurun.",
            controller.UpdateHint);
        Assert.Equal("Kurulum Dosyasını İndir", controller.UpdateButtonText);

        await controller.InstallUpdateAsync();
        Assert.False(updater.Installed);
        Assert.Equal(new Uri("https://couchsubs.enmeraapps.com/#indir"), Assert.Single(opened));
    }

    [Fact]
    public async Task ApplyFailureIsShownEvenWithoutNetwork()
    {
        new UpdateAttemptJournal(Journal, "0.1.0-beta.83").Record("0.1.0-beta.84");
        var controller = Controller(new FakeUpdater("0.1.0-beta.83", Journal) { Latest = null });
        await controller.CheckForUpdateAsync();
        Assert.Equal("0.1.0-beta.84", controller.UpdateVersion);
        Assert.True(controller.UpdateFailed);
    }

    [Fact]
    public async Task ReachingTheTargetClearsTheAttempt()
    {
        new UpdateAttemptJournal(Journal, "0.1.0-beta.83").Record("0.1.0-beta.84");
        var updater = new FakeUpdater("0.1.0-beta.84", Journal);
        var controller = Controller(updater);
        await controller.CheckForUpdateAsync();
        Assert.False(controller.UpdateFailed);
        Assert.Null(controller.UpdateVersion);
        Assert.False(File.Exists(Journal));
    }

    [Fact]
    public async Task FailedDownloadIsNotCountedAsAnAttempt()
    {
        var updater = new FakeUpdater("0.1.0-beta.83", Journal) { Latest = "0.1.0-beta.84", InstallError = new IOException("ağ koptu") };
        var controller = Controller(updater);
        await controller.CheckForUpdateAsync();
        await controller.InstallUpdateAsync();
        Assert.Equal("ağ koptu", controller.UpdateError);
        Assert.Null(updater.Attempts!.Read());
        Assert.False(controller.UpdateFailed);
    }

    [Fact]
    public async Task CopyThatCannotUpdateItselfAsksForTheSetupFile()
    {
        var updater = new FakeUpdater("0.1.0-beta.83", Journal) { Latest = "0.1.0-beta.84", CanUpdateItself = false };
        var opened = new List<Uri>();
        var controller = Controller(updater, opened);
        await controller.CheckForUpdateAsync();
        Assert.Equal("CouchSubs'ın yeni sürümü çıktı: 0.1.0-beta.84", controller.UpdateTitle);
        Assert.Equal("Bu kopya kendini güncelleyemiyor. Kurulum dosyasıyla yeniden kurun.", controller.UpdateHint);
        Assert.Equal("Kurulum Dosyasını İndir", controller.UpdateButtonText);
        await controller.InstallUpdateAsync();
        Assert.False(updater.Installed);
        Assert.Single(opened);
    }

    [Fact]
    public void BrokenJournalIsIgnored()
    {
        Directory.CreateDirectory(folder);
        File.WriteAllText(Journal, "{bozuk");
        Assert.Null(new UpdateAttemptJournal(Journal, "0.1.0-beta.83").FailedAttempt());
    }
}
