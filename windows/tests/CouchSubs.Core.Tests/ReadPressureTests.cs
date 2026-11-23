// SPDX-License-Identifier: AGPL-3.0-only

using Xunit;

namespace CouchSubs.Core.Tests;

public class ReadPressureTests
{
    [Fact]
    public void BackgroundReadsSlowDownWhenSubtitleReadsAreSlow()
    {
        Assert.Equal(1, ReadPressure.Slowdown(null, 0));
        Assert.Equal(1, ReadPressure.Slowdown(120, 80));
        Assert.Equal(2, ReadPressure.Slowdown(ReadPressure.SlowReadMs, 0));
        Assert.Equal(2, ReadPressure.Slowdown(100, ReadPressure.SlowReadMs + 50));
        Assert.Equal(4, ReadPressure.Slowdown(ReadPressure.VerySlowReadMs, 0));
        Assert.Equal(4, ReadPressure.Slowdown(null, 9000));
    }

    [Fact]
    public void FrameGateReportsHowLongTheCurrentReadHasBeenRunning()
    {
        var gate = new FrameGate();
        Assert.Equal(0, gate.BusyMs(1000));
        var entry = gate.TryEnter(1000);
        Assert.Equal(1200, gate.BusyMs(2200));
        gate.Leave(entry.Token);
        Assert.Equal(0, gate.BusyMs(3000));
    }
}
