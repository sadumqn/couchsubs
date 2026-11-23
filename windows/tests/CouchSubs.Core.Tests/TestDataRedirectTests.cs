// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>Testler kullanıcının gerçek günlüklerine ve verisine yazmaz (Mac'te test satırları tvinstall.log'a karışıyordu).</summary>
public class TestDataRedirectTests
{
    [Fact]
    public void TestsNeverWriteToTheRealLocalAppData()
    {
        Assert.True(AppDataPaths.IsRedirected);
        Assert.NotEqual(AppDataPaths.RealRoot, AppDataPaths.Root);
        Assert.StartsWith(Path.GetTempPath(), AppDataPaths.Root);
        foreach (var path in new[] { SubtitleLog.DefaultPath, SubtitleHistory.DefaultFile, GameCoverStore.DefaultDirectory })
            Assert.False(path.StartsWith(AppDataPaths.RealRoot, StringComparison.OrdinalIgnoreCase), path);
    }
}
