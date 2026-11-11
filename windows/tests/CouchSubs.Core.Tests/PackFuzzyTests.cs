// SPDX-License-Identifier: AGPL-3.0-only

using System.Text;
using System.Text.Json;

namespace CouchSubs.Core.Tests;

/// <summary>Mac'teki PackFuzzyTests ve paket betiği (common.py) ile aynı imza: Fixtures/fuzzy-vectors.json.</summary>
public class PackFuzzyTests
{
    [Fact]
    public void SignatureVectors()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("fuzzy-vectors.json")));
        var signatures = document.RootElement.GetProperty("signatures").EnumerateArray().ToList();
        Assert.True(signatures.Count > 10);
        foreach (var vector in signatures)
        {
            var input = vector.GetProperty("input").GetString()!;
            var folded = new StringBuilder();
            foreach (var rune in PackFuzzy.Folded(input)) folded.Append(rune.ToString());
            Assert.Equal(vector.GetProperty("folded").GetString(), folded.ToString());
            Assert.Equal(vector.GetProperty("damaged").GetBoolean(), PackFuzzy.Damaged(input));
            var signature = PackFuzzy.Signature(input);
            if (vector.GetProperty("length").ValueKind == JsonValueKind.Null)
            {
                Assert.Null(signature);
                continue;
            }
            Assert.Equal(vector.GetProperty("length").GetInt32(), signature!.Value.Length);
            Assert.Equal(vector.GetProperty("bits").GetInt32(), PackFuzzy.Bits(signature.Value.Length));
            Assert.Equal(vector.GetProperty("bloom").GetString(), Convert.ToHexStringLower(signature.Value.Bytes));
        }
        foreach (var pair in document.RootElement.GetProperty("similarities").EnumerateArray())
        {
            var bits = pair.GetProperty("bits").GetInt32();
            var query = PackFuzzy.Bloom(PackFuzzy.TrigramHashes(PackFuzzy.Folded(pair.GetProperty("query").GetString()!)), bits);
            var entry = PackFuzzy.Bloom(PackFuzzy.TrigramHashes(PackFuzzy.Folded(pair.GetProperty("entry").GetString()!)), bits);
            Assert.Equal(pair.GetProperty("similarity").GetDouble(), PackFuzzy.Similarity(query, entry, 0, bits), 9);
        }
    }
}
