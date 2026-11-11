// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Numerics;
using System.Text;
using System.Text.Json;

namespace CouchSubs.Core;

/// <summary>
/// Paketteki satırın bulanık imzası: OCR'ın bozduğu satırı (harf hatası, birleşmiş sözcük) bulmak için.
/// canon metnin boşlukları atılır, OCR'ın karıştırdığı harfler birleştirilir (l/1/ı/j → i, 0 → o, 5 → s), kalan dizinin
/// her farklı üçlüsü FNV-1a 64 ile özetlenip m bitten birine düşer (Bloom kümesi; m uzunlukla büyür: 64/128/256).
/// Her bit onlarca farklı üçlünün ortak izidir ve sıra tutulmaz: İngilizce metin geri çıkarılamaz.
/// Mac'teki CouchSubsCore/PackFuzzy.swift ve paket betiği (augment.py, common.py) ile birebir aynı; ortak deneme verisi
/// core/Tests/CouchSubsCoreTests/Fixtures/fuzzy-vectors.json.
/// </summary>
public static class PackFuzzy
{
    /// <summary>Bundan kısa satırda bulanık arama yok.</summary>
    public const int MinLength = 16;
    internal const int MaxBits = 256;
    internal const int BitsPerGram = 3;
    internal const double Margin = 5;
    /// <summary>OCR izi olmayan satır neredeyse aynı olmalı: (uzunluk sınırı, en düşük benzerlik).</summary>
    private static readonly (int Limit, double Value)[] CleanMinimum = [(24, 90), (256, 80)];
    /// <summary>OCR izi olan satır: (uzunluk sınırı, en düşük benzerlik).</summary>
    private static readonly (int Limit, double Value)[] DamagedMinimum = [(24, 70), (40, 60), (256, 55)];

    private static readonly Dictionary<int, int> Fold = new()
    {
        ['l'] = 'i', ['1'] = 'i', ['ı'] = 'i', ['j'] = 'i', ['0'] = 'o', ['5'] = 's', ['æ'] = 'a', ['ø'] = 'o', ['œ'] = 'o', ['ß'] = 's',
    };

    /// <summary>canon metin, boşluksuz ve OCR'ın karıştırdığı harfler birleşmiş.</summary>
    internal static List<Rune> Folded(string text)
    {
        var output = new List<Rune>();
        foreach (var rune in PackKey.Canon(text).EnumerateRunes())
        {
            if (rune.Value == ' ') continue;
            output.Add(Fold.TryGetValue(rune.Value, out var folded) ? new Rune(folded) : rune);
        }
        return output;
    }

    /// <summary>Uzunluğa göre Bloom boyu (bit).</summary>
    internal static int Bits(int length)
    {
        var bits = 64;
        while (bits < MaxBits && length * BitsPerGram > bits) bits *= 2;
        return bits;
    }

    internal static List<ulong> TrigramHashes(List<Rune> runes)
    {
        var hashes = new HashSet<ulong>();
        Span<byte> buffer = stackalloc byte[4];
        for (var index = 0; index + 3 <= runes.Count; index++)
        {
            var hash = 0xcbf29ce484222325UL;
            for (var offset = 0; offset < 3; offset++)
            {
                var written = runes[index + offset].EncodeToUtf8(buffer);
                for (var b = 0; b < written; b++)
                {
                    hash ^= buffer[b];
                    hash *= 0x100000001b3UL;
                }
            }
            hashes.Add(hash);
        }
        return [.. hashes];
    }

    internal static ulong[] Bloom(List<ulong> hashes, int bits)
    {
        var words = new ulong[bits / 64];
        foreach (var hash in hashes)
        {
            var bit = (int)(hash & (ulong)(bits - 1));
            words[bit >> 6] |= 1UL << (bit & 63);
        }
        return words;
    }

    /// <summary>
    /// İki yönlü, rastlantıdan arındırılmış kapsama (0-100): min(sorgunun üçlülerinin adayda olanı, adayınkinin sorguda
    /// olanı). <paramref name="entry"/>: dizindeki kelimeler, <paramref name="offset"/>'ten başlayarak bits / 64 tane.
    /// </summary>
    internal static double Similarity(ulong[] query, ulong[] entry, int offset, int bits)
    {
        int both = 0, inQuery = 0, inEntry = 0;
        for (var index = 0; index < bits / 64; index++)
        {
            ulong q = query[index], e = entry[offset + index];
            both += BitOperations.PopCount(q & e);
            inQuery += BitOperations.PopCount(q);
            inEntry += BitOperations.PopCount(e);
        }
        return Score(both, inQuery, inEntry, bits);
    }

    /// <summary>Benzerlik, bit sayılarından (ortak, sorgudaki, adaydaki).</summary>
    internal static double Score(int both, int inQuery, int inEntry, int bits)
    {
        if (inQuery == 0 || inEntry == 0) return 0;
        double fillQuery = (double)inQuery / bits, fillEntry = (double)inEntry / bits;
        if (fillQuery >= 1 || fillEntry >= 1) return 0;
        var queryCovered = ((double)both / inQuery - fillEntry) / (1 - fillEntry);
        var entryCovered = ((double)both / inEntry - fillQuery) / (1 - fillQuery);
        return 100.0 * Math.Min(queryCovered, entryCovered);
    }

    /// <summary>(uzunluk, Bloom baytları) — paket betiğinin yazdığıyla aynı; satır çok kısaysa null.</summary>
    internal static (int Length, byte[] Bytes)? Signature(string text)
    {
        var runes = Folded(text);
        if (runes.Count < MinLength) return null;
        var length = Math.Min(runes.Count, 255);
        var words = Bloom(TrigramHashes(runes), Bits(length));
        var bytes = new byte[words.Length * 8];
        for (var index = 0; index < words.Length; index++) BitConverter.TryWriteBytes(bytes.AsSpan(index * 8), words[index]);
        if (!BitConverter.IsLittleEndian) throw new PlatformNotSupportedException();
        return (length, bytes);
    }

    /// <summary>Kabul için en düşük benzerlik (0-100), OCR izine ve uzunluğa göre.</summary>
    internal static double Required(int length, bool damaged)
    {
        var table = damaged ? DamagedMinimum : CleanMinimum;
        foreach (var (limit, value) in table)
            if (length < limit) return value;
        return table[^1].Value;
    }

    private const string Edge = ".,!?;:'\"()[]-…“”’‘";
    private const string Typographic = "’‘“”—–…";

    internal static bool IsLetter(Rune rune) => Rune.IsLetter(rune);

    internal static bool IsDigit(Rune rune) => rune.IsBmp && CharUnicodeInfo.GetDigitValue((char)rune.Value) >= 0;

    /// <summary>
    /// OCR izi: İngilizce satırda ASCII dışı harf ya da işaret, sözcük içinde harf olmayan işaret ya da rakam, tek harfli
    /// garip sözcük, çok uzun (birleşmiş) sözcük. İzi olmayan satırın neredeyse aynı olması gerekir: temiz ama pakette
    /// olmayan satır büyük olasılıkla başka bir satırdır.
    /// </summary>
    internal static bool Damaged(string text)
    {
        foreach (var rune in text.EnumerateRunes())
            if (rune.Value > 127 && !Typographic.Contains(rune.ToString(), StringComparison.Ordinal)) return true;
        foreach (var word in text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
        {
            var core = word.EnumerateRunes().ToList();
            while (core.Count > 0 && Edge.Contains(core[0].ToString(), StringComparison.Ordinal)) core.RemoveAt(0);
            while (core.Count > 0 && Edge.Contains(core[^1].ToString(), StringComparison.Ordinal)) core.RemoveAt(core.Count - 1);
            if (core.Count == 0) continue;
            for (var index = 1; index < core.Count - 1; index++)
                if (IsLetter(core[index - 1]) && IsLetter(core[index + 1]) && !IsLetter(core[index])
                    && core[index].Value is not ('\'' or '’' or '-'))
                    return true;
            for (var index = 1; index < core.Count; index++)
            {
                Rune previous = core[index - 1], current = core[index];
                if ((IsLetter(previous) && IsDigit(current)) || (IsDigit(previous) && IsLetter(current))) return true;
            }
            if (core.Count == 1 && IsLetter(core[0]) && core[0].Value is not ('a' or 'A' or 'I' or 'o' or 'O')) return true;
            if (core.Count > 14) return true;
        }
        return false;
    }
}

/// <summary>Bir paketin bulanık dizini: imzalı satırlar uzunluğa göre sıralı, Bloom kelimeleri ardışık.</summary>
public sealed class PackFuzzyIndex
{
    private readonly byte[] lengths;
    private readonly ulong[] keys;
    private readonly int[] offsets;
    private readonly ulong[] words;
    /// <summary>Her satırın Bloom'undaki 1 bit sayısı.</summary>
    private readonly int[] ones;
    /// <summary>start[n]: uzunluğu n olan ilk satırın sırası.</summary>
    private readonly int[] start = new int[257];

    public int Count => keys.Length;

    private PackFuzzyIndex(byte[] lengths, ulong[] keys, int[] offsets, ulong[] words)
    {
        this.lengths = lengths;
        this.keys = keys;
        this.offsets = offsets;
        this.words = words;
        ones = new int[keys.Length];
        for (var index = 0; index < keys.Length; index++)
            for (var word = 0; word < PackFuzzy.Bits(lengths[index]) / 64; word++) ones[index] += BitOperations.PopCount(words[offsets[index] + word]);
        var position = 0;
        for (var length = 0; length <= 256; length++)
        {
            while (position < lengths.Length && lengths[position] < length) position++;
            start[length] = position;
        }
    }

    /// <summary>
    /// Paketteki "fuzzy" nesnesi. <paramref name="order"/>: paketteki bütün anahtarlar (entries + segments) sayı sırasıyla.
    /// Biçim tutmazsa null (paket yine de tam eşleşmeyle çalışır).
    /// </summary>
    internal static PackFuzzyIndex? Decode(JsonElement json, IReadOnlyList<ulong> order)
    {
        try
        {
            if (json.ValueKind != JsonValueKind.Object || !json.TryGetProperty("version", out var version) || version.GetInt32() != 1
                || !json.TryGetProperty("count", out var count) || count.GetInt32() != order.Count) return null;
            var mask = Convert.FromBase64String(json.GetProperty("mask").GetString() ?? "");
            var lengthBytes = Convert.FromBase64String(json.GetProperty("lengths").GetString() ?? "");
            var blooms = Convert.FromBase64String(json.GetProperty("blooms").GetString() ?? "");
            if (mask.Length != (order.Count + 7) / 8) return null;
            var items = new List<(byte Length, ulong Key, int Offset)>(lengthBytes.Length);
            var byteOffset = 0;
            for (var index = 0; index < order.Count; index++)
            {
                if (((mask[index >> 3] >> (index & 7)) & 1) == 0) continue;
                if (items.Count >= lengthBytes.Length) return null;
                var length = lengthBytes[items.Count];
                items.Add((length, order[index], byteOffset));
                byteOffset += PackFuzzy.Bits(length) / 8;
            }
            if (items.Count != lengthBytes.Length || byteOffset != blooms.Length) return null;
            items.Sort((a, b) => a.Length != b.Length ? a.Length.CompareTo(b.Length) : a.Key.CompareTo(b.Key));
            var words = new ulong[blooms.Length / 8];
            var offsets = new int[items.Count];
            var written = 0;
            for (var index = 0; index < items.Count; index++)
            {
                offsets[index] = written;
                var count64 = PackFuzzy.Bits(items[index].Length) / 64;
                for (var word = 0; word < count64; word++)
                    words[written++] = BitConverter.ToUInt64(blooms, items[index].Offset + word * 8);
            }
            return new PackFuzzyIndex([.. items.Select(i => i.Length)], [.. items.Select(i => i.Key)], offsets, words);
        }
        catch (Exception error) when (error is FormatException or InvalidOperationException or KeyNotFoundException)
        {
            return null;
        }
    }

    /// <summary>
    /// Eşik, uzunluk ve ikinci aday şartlarını sağlayan en benzer satırın anahtarı; yoksa null.
    /// <paramref name="translation"/>: anahtarın Türkçesi (aynı Türkçeli iki aday birbirinin rakibi sayılmaz).
    /// </summary>
    public ulong? Nearest(string text, Func<ulong, string?> translation)
    {
        var runes = PackFuzzy.Folded(text);
        if (runes.Count < PackFuzzy.MinLength || keys.Length == 0) return null;
        var length = Math.Min(runes.Count, 255);
        var need = PackFuzzy.Required(length, PackFuzzy.Damaged(text));
        var hashes = PackFuzzy.TrigramHashes(runes);
        // Sorgunun üç boydaki Bloom'u ve bit sayısı (64, 128, 256 bit).
        ulong[][] queries = [PackFuzzy.Bloom(hashes, 64), PackFuzzy.Bloom(hashes, 128), PackFuzzy.Bloom(hashes, 256)];
        var queryOnes = queries.Select(query => query.Sum(word => BitOperations.PopCount(word))).ToArray();
        var found = new List<(double Score, ulong Key)>();
        var floor = need - PackFuzzy.Margin;
        // Aday uzunluğu en çok ±%25 farklı: |aday - satır| * 4 <= satır.
        var lower = length - length / 4;
        var upper = Math.Min(255, length + length / 4);
        for (var index = start[lower]; index < start[upper + 1]; index++)
        {
            var tier = BitOperations.Log2((uint)PackFuzzy.Bits(lengths[index])) - 6;
            var query = queries[tier];
            var both = 0;
            for (var word = 0; word < query.Length; word++) both += BitOperations.PopCount(query[word] & words[offsets[index] + word]);
            var score = PackFuzzy.Score(both, queryOnes[tier], ones[index], 64 << tier);
            if (score >= floor) found.Add((score, keys[index]));
        }
        if (found.Count == 0) return null;
        var best = found[0];
        foreach (var candidate in found)
            if (candidate.Score > best.Score || (candidate.Score == best.Score && candidate.Key > best.Key)) best = candidate;
        if (best.Score < need) return null;
        var turkish = translation(best.Key);
        foreach (var other in found)
            if (other.Key != best.Key && other.Score > best.Score - PackFuzzy.Margin && translation(other.Key) != turkish) return null;
        return best.Key;
    }
}
