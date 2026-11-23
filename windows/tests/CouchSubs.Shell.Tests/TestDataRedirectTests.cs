// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.RemotePlay;
using CouchSubs.Shell;
using Xunit;

namespace CouchSubs.Shell.Tests;

/// <summary>
/// Denetleyici testleri (sahte TV'lerle kurulum, eşleşme) kullanıcının gerçek %LOCALAPPDATA%\CouchSubs günlüklerine yazmaz.
/// Mac'te 21–22 Kas'ta "paket 0.6.1", "TV'deki CouchSubs: 0.4.0" gibi test satırları gerçek tvinstall.log'a karışmıştı.
/// </summary>
public class TestDataRedirectTests
{
    [Fact]
    public void ShellTestsWriteOnlyToATemporaryFolder()
    {
        Assert.True(AppDataPaths.IsRedirected);
        Assert.StartsWith(Path.GetTempPath(), AppDataPaths.Root);
        foreach (var path in new[] { SubtitleLog.DefaultPath, RemotePlayLog.FilePath, UpdateAttemptJournal.DefaultPath })
            Assert.False(path.StartsWith(AppDataPaths.RealRoot, StringComparison.OrdinalIgnoreCase), path);
    }
}
