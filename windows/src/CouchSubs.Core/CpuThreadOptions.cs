// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>Windows yerel çevirisinin işlemciye göre sunulan iş parçacığı seçenekleri.</summary>
public static class CpuThreadOptions
{
    public const int Default = 2;
    private static readonly int[] Choices = [2, 4, 8, 12];

    public static IReadOnlyList<int> Available(int logicalProcessors) => logicalProcessors < 2
        ? [1]
        : Choices.Where(choice => choice <= logicalProcessors).ToArray();

    public static int Normalize(int requested, int logicalProcessors)
    {
        var available = Available(logicalProcessors);
        return available.Where(choice => choice <= requested).LastOrDefault(available[0]);
    }

    public static bool NearCapacity(int selected, int logicalProcessors) =>
        logicalProcessors > 0 && selected * 4 >= logicalProcessors * 3;
}
