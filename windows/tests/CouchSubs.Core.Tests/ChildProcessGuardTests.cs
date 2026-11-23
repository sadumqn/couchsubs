// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Güncellemeden önce bütün yardımcı süreçler kapatılır: açık kalan python.exe/node.exe kurulum klasörünü kilitler ve
/// Velopack güncellemeyi uygulayamaz. StopAll izlenen her süreci kapatır; süreç başlatan başka testler (ProcessRunner)
/// aynı koleksiyonda, sırayla çalışır.
/// </summary>
[Collection(ChildProcessGuardTests.Group)]
public sealed class ChildProcessGuardTests
{
    public const string Group = "Yardımcı süreçler";

    private static Process LongRunning()
    {
        var info = OperatingSystem.IsWindows()
            ? new ProcessStartInfo("ping.exe") { ArgumentList = { "-n", "60", "127.0.0.1" } }
            : new ProcessStartInfo("sleep") { ArgumentList = { "60" } };
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.RedirectStandardOutput = true;
        return Process.Start(info)!;
    }

    [Fact]
    public void StopAllClosesAttachedProcessesAndWaits()
    {
        using var first = LongRunning();
        using var second = LongRunning();
        ChildProcessGuard.Attach(first);
        ChildProcessGuard.Attach(second);
        Assert.Equal(2, ChildProcessGuard.RunningCount);

        Assert.Equal(0, ChildProcessGuard.StopAll(TimeSpan.FromSeconds(10)));
        Assert.True(first.HasExited);
        Assert.True(second.HasExited);
        Assert.Equal(0, ChildProcessGuard.RunningCount);
    }

    [Fact]
    public void DisposedOrExitedProcessesAreSkipped()
    {
        var gone = LongRunning();
        ChildProcessGuard.Attach(gone);
        gone.Kill();
        gone.WaitForExit();
        gone.Dispose();
        Assert.Equal(0, ChildProcessGuard.RunningCount);
        Assert.Equal(0, ChildProcessGuard.StopAll(TimeSpan.FromSeconds(1)));
    }
}
