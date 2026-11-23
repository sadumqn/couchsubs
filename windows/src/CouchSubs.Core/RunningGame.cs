// SPDX-License-Identifier: AGPL-3.0-only

using System.Text;
using System.Text.RegularExpressions;

namespace CouchSubs.Core;

/// <summary>
/// PS5'te o an çalışan oyun: keşif yanıtındaki <c>running-app-titleid</c> ve <c>running-app-name</c>. Ortak havuza giden
/// satıra eklenir; yeni bir oyun (ör. GTA 6) çıkınca o oyunun satırları ayrı toplanıp hızla paket yapılır. Yalnız oyunun
/// kimliği ve adı gider. PS5 çoğu zaman çalışan oyunu bildirmiyor; o zaman oyun uygulamanın paketten tanıdığı ya da
/// kullanıcının seçtiği addır (<see cref="GameSense"/>): kimlik yoktur, yalnız ad gider. Mac'teki
/// CouchSubsCore/RunningGame.swift ile aynı kurallar (sunucu da aynısını doğrular).
/// </summary>
public sealed partial record RunningGame(string? TitleId, string? Name)
{
    public const int MaxName = 120;

    [GeneratedRegex(@"^[A-Z]{4}\d{5}(_\d{2})?$")]
    private static partial Regex TitleIdPattern();

    /// <summary>Kimlik PS5 biçiminde değilse null.</summary>
    public static RunningGame? Create(string? titleId, string? name)
    {
        if (NormalizedTitleId(titleId) is not { } id) return null;
        return new RunningGame(id, NormalizedName(name));
    }

    /// <summary>Yalnız adıyla bilinen oyun (paketten tanındı ya da kullanıcı seçti); ad boşsa null. Kimlik geçerliyse o da tutulur.</summary>
    public static RunningGame? Named(string? name, string? titleId = null) =>
        NormalizedName(name) is { } clean ? new RunningGame(NormalizedTitleId(titleId), clean) : null;

    internal static string? NormalizedTitleId(string? value)
    {
        var id = value?.Trim().ToUpperInvariant();
        return id is not null && TitleIdPattern().IsMatch(id) ? id : null;
    }

    /// <summary>Denetim karakterleri ve fazla boşluk atılır, en çok 120 karakter; boşsa null.</summary>
    internal static string? NormalizedName(string? value)
    {
        if (value is null) return null;
        var builder = new StringBuilder(value.Length);
        foreach (var rune in value.EnumerateRunes())
        {
            var category = Rune.GetUnicodeCategory(rune);
            builder.Append(category is System.Globalization.UnicodeCategory.Control or System.Globalization.UnicodeCategory.Format
                ? " " : rune.ToString());
        }
        var words = string.Join(' ', builder.ToString().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        var trimmed = (words.Length > MaxName ? words[..MaxName] : words).Trim();
        return trimmed.Length == 0 ? null : trimmed;
    }
}
