// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;

namespace CouchSubs.Translation.Tests;

/// <summary>
/// Paket eşleşme ölçümü (Mac'teki PackBenchmarkTests ile aynı): oyunun kendi satırlarından üretilmiş OCR benzeri ekranlar.
/// İngilizce metin depoda olmadığından yalnız <c>COUCHSUBS_PACK_BENCH=&lt;cases.json&gt;</c> verilince ölçer;
/// <c>COUCHSUBS_PACK_BENCH_PACK</c> paket dosyası (varsayılan gta-v.json.gz), <c>COUCHSUBS_PACK_BENCH_DIR</c> paketin
/// klasörü (varsayılan gömülü paketler). Sonuç <c>&lt;cases.json&gt;.&lt;paket&gt;.windows.txt</c> dosyasına yazılır.
/// </summary>
public class PackBenchmarkTests
{
    [Fact]
    public void PackMatchRate()
    {
        var path = Environment.GetEnvironmentVariable("COUCHSUBS_PACK_BENCH");
        if (string.IsNullOrEmpty(path)) return;
        var file = Environment.GetEnvironmentVariable("COUCHSUBS_PACK_BENCH_PACK") ?? "gta-v.json.gz";
        var directory = Environment.GetEnvironmentVariable("COUCHSUBS_PACK_BENCH_DIR");
        var library = new GamePackLibrary(() => directory is null
            ? GamePackLibrary.EmbeddedPacks().Where(pack => pack.Name == file)
            : new[] { (Name: file, Data: File.ReadAllBytes(Path.Combine(directory, file))) }, null);
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        Assert.NotNull(PackLookup.Match(library, document.RootElement.GetProperty("warmUp").GetString()!));
        var stats = new Dictionary<string, (int Total, int Hit, int Correct)>();
        var order = new List<string>();
        foreach (var item in document.RootElement.GetProperty("cases").EnumerateArray())
        {
            var category = item.GetProperty("cat").GetString()!;
            var parts = item.GetProperty("parts").EnumerateArray().Select(part => part.GetString()!).ToList();
            // Parçasız durum başka oyunun satırıdır: hiç eşleşmemeli, bulunursa yanlış sayılır.
            var expected = parts.Select(part => PackLookup.Match(library, part)?.Text).ToList();
            if (expected.Any(text => text is null)) continue;
            if (!stats.ContainsKey(category)) order.Add(category);
            var entry = stats.GetValueOrDefault(category);
            entry.Total++;
            if (PackLookup.Match(library, item.GetProperty("screen").GetString()!)?.Text is { } found)
            {
                entry.Hit++;
                if (expected.Count > 0 && expected.All(text => found.Contains(text!, StringComparison.Ordinal))) entry.Correct++;
            }
            stats[category] = entry;
        }
        var report = new List<string>();
        (int Total, int Hit, int Correct) all = default;
        string Row(string name, (int Total, int Hit, int Correct) entry) =>
            $"BENCH {file} {name} {entry.Total}  doğru {100.0 * entry.Correct / Math.Max(entry.Total, 1):F1}%  yanlış {100.0 * (entry.Hit - entry.Correct) / Math.Max(entry.Total, 1):F1}%";
        foreach (var category in order)
        {
            var entry = stats[category];
            all = (all.Total + entry.Total, all.Hit + entry.Hit, all.Correct + entry.Correct);
            report.Add(Row(category, entry));
        }
        report.Add(Row("TOPLAM", all));
        File.WriteAllLines($"{path}.{file}.windows.txt", report);
    }
}
