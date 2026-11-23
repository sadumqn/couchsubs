// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>Alanların ölçüldüğü görüntü: konsolun kendi akışı (PS5/Xbox) ya da yakalanan pencere (Remote Play, OBS).</summary>
public enum AreaSource { Stream, Window }

/// <summary>
/// Oyuna göre okuma alanları: kullanıcı bir oyunun altyazı alanını ve ek alanlarını kaydeder; o oyun yeniden
/// oynanınca alanlar kendiliğinden gelir. Profil oyun adıyla (<see cref="GameName.Key"/>) ve görüntünün kaynağıyla
/// anılır: pencereden okunan görüntüde kenarlar farklı olabildiği için aynı oyunun iki kaynağı ayrı tutulur.
/// Profilin ne zaman uygulanacağı <see cref="Decide"/>'dadır; Mac ve iPhone'daki AreaProfiles.swift ve Android'deki
/// AreaProfiles.kt ile aynı kurallar.
/// </summary>
public static class AreaProfiles
{
    /// <summary>En çok bu kadar profil saklanır; fazlasında en uzun süredir kullanılmayan silinir.</summary>
    public const int MaxCount = 50;

    /// <summary>Profilin anahtarı ("far cry 3|stream"); oyun adı boşsa null.</summary>
    public static string? Key(string? game, AreaSource source)
    {
        var name = GameName.Key(game);
        return name.Length == 0 ? null : name + "|" + (source == AreaSource.Window ? "window" : "stream");
    }

    /// <summary>Anahtarın görüntü kaynağı ("…|window" → pencere, gerisi akış).</summary>
    public static AreaSource SourceOfKey(string key) =>
        key.EndsWith("|window", StringComparison.Ordinal) ? AreaSource.Window : AreaSource.Stream;

    /// <summary>Profil listesinde yeni profil, ad değişikliği ya da çoğaltmanın sonucu.</summary>
    public enum Edit
    {
        Done,
        /// <summary>Ad boş (ya da yalnız noktalama).</summary>
        Empty,
        /// <summary>Bu adla başka bir oyunun profili var; üzerine yazılmaz.</summary>
        Exists,
        /// <summary>Profil bulunamadı.</summary>
        Missing,
    }

    public enum Step
    {
        /// <summary>Bir şey değişmez.</summary>
        None,
        /// <summary>Oyun kesin biliniyor (PS5 bildirdi ya da kullanıcı seçti): profil hemen uygulanır.</summary>
        Apply,
        /// <summary>Oyun yalnız paketten tanındı: alanlar sessizce değişmez, kullanıcıya sorulur.</summary>
        Offer,
        /// <summary>Başka bir oyuna geçildi ve onun profili yok: genel alanlara dönülür.</summary>
        UseGeneral,
    }

    public readonly record struct Decision(Step Step, string? Key = null);

    /// <summary>
    /// Oyun değişince ne yapılır. <paramref name="active"/>: şu an uygulanan profilin anahtarı (genel alanlarda null).
    /// <paramref name="declined"/>: bu oturumda kullanıcının geri aldığı ya da istemediği profiller; yeniden uygulanmaz.
    /// Oyun bilinmez olursa (PS5 bildirmeyi bıraktı) son uygulanan profil kalır: alanlar ileri geri oynamaz.
    /// </summary>
    public static Decision Decide(string? active, string? game, GameSense.GameSource? source, AreaSource areaSource,
                                  Func<string, bool> exists, Func<string, bool> declined)
    {
        if (Key(game, areaSource) is not { } key || source is null) return new Decision(Step.None);
        if (key == active) return new Decision(Step.None);
        if (exists(key) && !declined(key))
            return new Decision(source is GameSense.GameSource.Pack or GameSense.GameSource.Remembered ? Step.Offer : Step.Apply, key);
        return active is null ? new Decision(Step.None) : new Decision(Step.UseGeneral);
    }

    /// <summary>
    /// Profil eklendi ya da kullanıldı: aynı anahtarlı eskisi çıkar, yenisi sona eklenir (sıra son kullanımdır);
    /// <see cref="MaxCount"/>'u aşınca baştan, en uzun süredir kullanılmayan silinir.
    /// </summary>
    public static IReadOnlyList<T> Saved<T>(IReadOnlyList<T> profiles, T profile, Func<T, string> key)
    {
        var id = key(profile);
        var next = profiles.Where(item => key(item) != id).Append(profile).ToList();
        return next.Count > MaxCount ? next.Skip(next.Count - MaxCount).ToList() : next;
    }
}
