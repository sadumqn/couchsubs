// SPDX-License-Identifier: AGPL-3.0-only

using System.Text;
using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>
/// "Ekranı çevir"de fiyat ve sayılar (GTA 6 dükkânı, bahşiş menüsü): yazı tanıma "$" işaretini "S" okuyor ("$200" →
/// "S200", "$$$$" → "SSSS"); bozuk okuma harf sayılıp çevirmene gidiyor, ekranda anlamsız bir yazı çıkıyordu. Burada
/// rakam bağlamındaki "S" ve yalnız "S"/"$"den oluşan sözcük "$"a döner (<see cref="Repair"/>); para ve ayraçlı sayılar
/// ("$1,250", "2.5") çevirmene uydurma bir adla gider ve çeviriden sonra olduğu gibi yerine konur
/// (<see cref="Protect"/>/<see cref="Restore"/>). Kurallar ortak deneme dosyasıyla sınanır
/// (core/Tests/CouchSubsCoreTests/Fixtures/price-text.json; Mac: PriceText.swift, Android: PriceText.kt).
/// </summary>
public static partial class PriceText
{
    /// <summary>Korunan bir sayı: çevirmene giden ad ve yerine konacak değer.</summary>
    public sealed record Value(string Name, string Text);

    /// <summary>Korunmuş metin: çevirmene gidecek metin ve sırayla kullanılan adlar.</summary>
    public sealed record Protected(string Text, IReadOnlyList<Value> Values);

    [GeneratedRegex(@"(?<![\p{L}\p{N}$])[S$](?=[0-9])([0-9OoIl.,]*[0-9OoIl])([KkMm]?)(?![\p{L}\p{N}])")]
    private static partial Regex MisreadPrice();

    [GeneratedRegex(@"(?<![\p{L}\p{N}])[S$]{2,}(?![\p{L}\p{N}])")]
    private static partial Regex DollarRun();

    [GeneratedRegex(@"(?<![\p{L}\p{N}])(?:\$+(?:[0-9][0-9.,]*[0-9]|[0-9])?[KkMm]?|[0-9]+(?:[.,:][0-9]+)+)(?![\p{L}\p{N}])")]
    private static partial Regex ProtectedNumber();

    /// <summary>Yazı tanımanın bozduğu fiyatları düzeltir; uzunluk değişmez (sözcük kutuları geçerli kalır).</summary>
    public static string Repair(string text)
    {
        if (!text.Contains('S') && !text.Contains('$')) return text;
        // "S200", "S2OO" → "$200": "S" ve içindeki O/I/l harfleri rakam bağlamında.
        var result = MisreadPrice().Replace(text, match =>
        {
            var digits = new StringBuilder();
            foreach (var c in match.Groups[1].Value) digits.Append(c switch { 'O' or 'o' => '0', 'I' or 'l' => '1', _ => c });
            return "$" + digits + match.Groups[2].Value;
        });
        // "SSSS" → "$$$$"; iki harflik "SS" ancak içinde "$" varsa ("$S").
        return DollarRun().Replace(result, match =>
            match.Length >= 3 || match.Value.Contains('$') ? new string('$', match.Length) : match.Value);
    }

    /// <summary>Sözcük fiyat ya da yalnız "$" mı ("$200", "$$$$"; düzeltilmiş okumada).</summary>
    public static bool IsMoney(string word)
    {
        var core = word.Trim('(', ')', '[', ']', '.', ',', ':', ';', '!', '?');
        if (!core.StartsWith('$')) return false;
        var match = ProtectedNumber().Match(core);
        return match.Success && match.Index == 0 && match.Length == core.Length;
    }

    /// <summary>Para ve ayraçlı sayıları adlarla değiştirir. Ad kalmazsa kalan sayılar olduğu gibi gider.</summary>
    public static Protected Protect(string text)
    {
        var matches = ProtectedNumber().Matches(text);
        if (matches.Count == 0) return new Protected(text, []);
        var free = new Queue<string>(TermProtector.Placeholders.Where(name => !text.Contains(name, StringComparison.OrdinalIgnoreCase)));
        var values = new List<Value>();
        var builder = new StringBuilder();
        var at = 0;
        foreach (Match match in matches)
        {
            if (free.Count == 0) break;
            var name = free.Dequeue();
            values.Add(new Value(name, match.Value));
            builder.Append(text, at, match.Index - at).Append(name);
            at = match.Index + match.Length;
        }
        builder.Append(text, at, text.Length - at);
        return new Protected(builder.ToString(), values);
    }

    /// <summary>
    /// Çevirideki adları değerlerine döndürür; adın Türkçe eki kesme işaretiyle korunur ("Zarmon'a" → "$200'a",
    /// "Zarmona" → "$200'a"). Çeviride bulunmayan değer sona eklenir (fiyat kaybolmasın).
    /// </summary>
    public static string Restore(string translation, IReadOnlyList<Value> values)
    {
        var text = translation;
        var missing = new List<string>();
        foreach (var value in values)
        {
            var pattern = new Regex(@"(?<![\p{L}\p{N}])" + Regex.Escape(value.Name) + @"(?:\s?['’`´](\p{L}+)|(\p{L}+))?(?![\p{L}\p{N}])",
                                    RegexOptions.IgnoreCase);
            if (!pattern.IsMatch(text))
            {
                missing.Add(value.Text);
                continue;
            }
            text = pattern.Replace(text, match =>
            {
                var suffix = match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Success ? match.Groups[2].Value : null;
                return value.Text + (suffix is null ? "" : "'" + suffix);
            });
        }
        return missing.Count == 0 ? text : string.Join(' ', [text, .. missing]);
    }
}
