// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell.Tests;

/// <summary>Üst çubuktaki durum hapı (yeni arayüz; Mac ile aynı kurallar).</summary>
public class ShellStatusTests
{
    [Fact]
    public void DemoComesFirst() =>
        Assert.Equal(ShellStatusKind.Demo, ShellStatus.For(demo: true, setupDone: false, running: true, starting: false, StatusTone.Warning, StatusTone.Warning));

    [Fact]
    public void UnfinishedSetupIsShown() =>
        Assert.Equal(ShellStatusKind.SetupIncomplete, ShellStatus.For(false, setupDone: false, running: false, starting: false, StatusTone.Idle, StatusTone.Idle));

    [Fact]
    public void IdleAppIsReady() =>
        Assert.Equal(ShellStatusKind.Ready, ShellStatus.For(false, true, running: false, starting: false, StatusTone.Idle, StatusTone.Idle));

    [Fact]
    public void StartingIsConnecting() =>
        Assert.Equal(ShellStatusKind.Connecting, ShellStatus.For(false, true, running: false, starting: true, StatusTone.Idle, StatusTone.Idle));

    [Fact]
    public void RunningWithConsoleIsTranslationOn() =>
        Assert.Equal(ShellStatusKind.TranslationOn, ShellStatus.For(false, true, running: true, starting: false, StatusTone.Good, StatusTone.Good));

    [Fact]
    public void RunningBeforeConsoleConnectsIsConnecting() =>
        Assert.Equal(ShellStatusKind.Connecting, ShellStatus.For(false, true, running: true, starting: false, StatusTone.Idle, StatusTone.Good));

    [Theory]
    [InlineData(StatusTone.Warning, StatusTone.Good)]
    [InlineData(StatusTone.Good, StatusTone.Warning)]
    public void ConsoleOrTvWarningNeedsAttention(StatusTone console, StatusTone tv) =>
        Assert.Equal(ShellStatusKind.NeedsAttention, ShellStatus.For(false, true, running: true, starting: false, console, tv));
}
