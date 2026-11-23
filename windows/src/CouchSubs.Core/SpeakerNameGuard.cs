// SPDX-License-Identifier: AGPL-3.0-only

using System.Collections.Concurrent;

namespace CouchSubs.Core;

/// <summary>
/// Konuşan etiketlerinden ("PRICE: …") öğrenilip cümle içinde çeviriden korunan adlar (#287: "Price, get down!" →
/// "Fiyat, yere yat!" olmasın). Mac/iPhone: SpeakerNames (SubtitleSegmenter.swift), Android: SpeakerNameGuard.kt;
/// kurallar ve hariç tutulan sözcükler aynı. Ad, cümlede büyük harfle başlayıp tam sözcük olarak geçince korunur.
/// </summary>
public sealed class SpeakerNameGuard
{
    private readonly ConcurrentDictionary<string, byte> _kept = new(StringComparer.Ordinal);

    /// <summary>Görev ve tür sözcükleri: etikette geçse de ad sayılmaz, cümle içinde korunmaz ("SOLDIER:", "OLD MAN:").</summary>
    public static readonly IReadOnlySet<string> NotNames = new HashSet<string>(StringComparer.Ordinal)
    {
        "soldier", "soldiers", "guard", "guards", "man", "men", "woman", "women", "boy", "girl", "kid", "child",
        "radio", "pilot", "copilot", "officer", "enemy", "enemies", "narrator", "voice", "announcer", "intercom",
        "speaker", "operator", "driver", "gunner", "sniper", "medic", "civilian", "hostage", "prisoner", "militia",
        "mercenary", "merc", "terrorist", "agent", "commander", "captain", "sergeant", "sgt", "lieutenant", "lt",
        "general", "colonel", "major", "corporal", "private", "admiral", "chief", "doctor", "dr", "mr", "mrs", "ms",
        "sir", "old", "young", "little", "big", "unknown", "stranger", "someone", "everyone", "all", "both", "team",
        "squad", "leader", "hq", "command", "control", "player", "you", "the", "a", "an", "of", "and", "friendly",
        "hostile", "female", "male", "tv", "news", "reporter", "crowd", "villager", "worker", "scientist", "nurse",
        "cop", "police",
    };

    /// <summary>Çeviriden korunacak adlar, cümlede beklenen yazılışla ("PRICE" etiketi → "Price").</summary>
    public IReadOnlySet<string> Protected => _kept.Keys.ToHashSet(StringComparer.Ordinal);

    /// <summary>Etiketteki adı öğrenir ("CAPTAIN PRICE" → "Price").</summary>
    public void Learn(string name)
    {
        foreach (var word in Protectable(name)) _kept[word] = 0;
    }

    /// <summary>
    /// Etiketteki addan korunacak sözcükler: en az iki harf, yalnız harf/kesme/tire, görev sözcüğü değil. Tümü büyük
    /// harfli sözcük cümle düzeninde beklenir ("PRICE" → "Price"); küçük harfle başlayan sözcük alınmaz.
    /// </summary>
    public static IReadOnlyList<string> Protectable(string name)
    {
        var result = new List<string>();
        foreach (var word in name.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            if (word.Count(char.IsLetter) < 2 || !word.All(c => char.IsLetter(c) || c is '\'' or '’' or '-')
                || !char.IsUpper(word[0]) || NotNames.Contains(word.ToLowerInvariant())) continue;
            result.Add(word.Any(char.IsLower) ? word : word[..1] + word[1..].ToLowerInvariant());
        }
        return result;
    }

    /// <summary>
    /// <paramref name="names"/> içinden metinde tam sözcük olarak geçenler, sıralı. <paramref name="exact"/>: yalnız aynı
    /// büyük/küçük harfle.
    /// </summary>
    public static IReadOnlyList<string> Occurring(IEnumerable<string> names, string text, bool exact)
    {
        static bool Boundary(string text, int index) => index < 0 || index >= text.Length || !char.IsLetterOrDigit(text[index]);
        var comparison = exact ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
        return names.Where(name =>
        {
            var start = 0;
            while (start <= text.Length - name.Length)
            {
                var index = text.IndexOf(name, start, comparison);
                if (index < 0) return false;
                if (Boundary(text, index - 1) && Boundary(text, index + name.Length)) return true;
                start = index + 1;
            }
            return false;
        }).Order(StringComparer.Ordinal).ToList();
    }
}
