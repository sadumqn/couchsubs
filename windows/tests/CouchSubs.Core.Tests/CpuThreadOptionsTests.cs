// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

public sealed class CpuThreadOptionsTests
{
    [Theory]
    [InlineData(8, new[] { 2, 4, 8 })]
    [InlineData(20, new[] { 2, 4, 8, 12 })]
    public void ChoicesNeverExceedLogicalProcessors(int logicalProcessors, int[] expected) =>
        Assert.Equal(expected, CpuThreadOptions.Available(logicalProcessors));

    [Theory]
    [InlineData(12, 8, 8)]
    [InlineData(8, 20, 8)]
    [InlineData(0, 8, 2)]
    public void SavedValueIsNormalizedToAnAvailableChoice(int saved, int logicalProcessors, int expected) =>
        Assert.Equal(expected, CpuThreadOptions.Normalize(saved, logicalProcessors));

    [Fact]
    public void WarningAppearsNearCpuCapacityButNotForTwelveOfTwenty()
    {
        Assert.True(CpuThreadOptions.NearCapacity(8, 8));
        Assert.False(CpuThreadOptions.NearCapacity(12, 20));
    }
}
