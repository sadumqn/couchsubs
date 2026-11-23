// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell.Tests;

/// <summary>Ana ekrandaki sessizlik nedeni kartı ("Sorun Var").</summary>
public class HomeProblemTests
{
    private static readonly TimeSpan Second = TimeSpan.FromSeconds(1);

    [Fact]
    public void NothingWhenNotRunningOrInDemo()
    {
        Assert.Equal(HomeProblemKind.None, HomeProblem.For(running: false, demo: false, Second * 30, menuOpen: true, subtitlesOffTip: true));
        Assert.Equal(HomeProblemKind.None, HomeProblem.For(running: true, demo: true, Second * 30, menuOpen: true, subtitlesOffTip: true));
    }

    [Fact]
    public void NoFrameYetIsConnectingNotAProblem() =>
        Assert.Equal(HomeProblemKind.None, HomeProblem.For(true, false, sinceFrame: null, menuOpen: true, subtitlesOffTip: true));

    [Fact]
    public void PictureStopsAfterFiveSeconds()
    {
        Assert.Equal(HomeProblemKind.None, HomeProblem.For(true, false, Second * 4, false, false));
        Assert.Equal(HomeProblemKind.PictureStopped, HomeProblem.For(true, false, Second * 5, menuOpen: true, subtitlesOffTip: true));
    }

    [Fact]
    public void MenuComesBeforeSubtitlesOff()
    {
        Assert.Equal(HomeProblemKind.MenuOpen, HomeProblem.For(true, false, Second, menuOpen: true, subtitlesOffTip: true));
        Assert.Equal(HomeProblemKind.SubtitlesOff, HomeProblem.For(true, false, Second, menuOpen: false, subtitlesOffTip: true));
    }

    [Fact]
    public void SilenceCountsFromLastLineOrStart()
    {
        var start = new DateTime(2026, 11, 22, 12, 0, 0, DateTimeKind.Utc);
        Assert.Equal(12, HomeProblem.SilentSeconds(start.AddSeconds(12), lastLine: null, start));
        Assert.Equal(5, HomeProblem.SilentSeconds(start.AddSeconds(25), start.AddSeconds(20), start));
        // Önceki oturumun satırı sayılmaz.
        Assert.Equal(3, HomeProblem.SilentSeconds(start.AddSeconds(3), start.AddSeconds(-60), start));
    }
}
