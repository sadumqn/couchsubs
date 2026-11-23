// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Hattın karara bağladığı (atılan ya da gösterilen) satırlar, ekranda durdukları sürece. PS5'in Türkçe ana ekranında
/// (beta.89, Mac) alandaki satırlar her karede okunuyor, seçilen blok ise her iki üç saniyede bir değişiyordu ("One [Ikan
/// Ipufl", "Yakin zamanda olu...", "e [Ikan Ipuflari Yakin zamanda olu..."): doğru okunan Türkçe satır "zaten hedef
/// dilde" diye atılıyor, bozuk okunan parçası İngilizce sanılıp çevriliyor ve TV'de altyazı olarak beliriyordu; aynı
/// döngü ekran değişmeden her 2,5 sn'de bir yineleniyordu. Üç kural:
///  1. Kaynağı zaten hedef dilde olan bloğun (Target) aynı yerdeki bozuk okunmuş parçası (<see cref="IsTargetFragment"/>)
///     altyazı adayı değildir.
///  2. Karara bağlanmış satır (<see cref="IsSettled"/>) ekranda durdukça yeniden işlenmez, günlüğe de yeniden yazılmaz.
///  3. Satır karenin okunan yazısında artık yoksa unutulur: atılan satır <see cref="DroppedAbsentMs"/> sonra, gösterilen
///     satır ilk yokluğunda (aynı satır gerçekten yeniden gelirse her zamanki gibi çevrilir).
/// Mac/iPhone (SettledText.swift) ve Android (SettledText.kt) aynı kuralları uygular; ortak deneme dosyası settled-text.json.
/// </summary>
public sealed class SettledText
{
    /// <summary>Atılan satır bu süre boyunca karede okunmazsa unutulur (yazı tanımanın tek tük kaçırdığı kareler sayılmaz).</summary>
    public const int DroppedAbsentMs = 1500;
    /// <summary>Parçanın büyük yazıda kesintisiz geçen en uzun bölümü, parçanın en az bu oranı olmalı.</summary>
    public const double Coverage = 0.7;
    /// <summary>Aynı satırın yeniden okuması sayılan benzerlik (Levenshtein oranı).</summary>
    public const double Similarity = 0.8;
    /// <summary>Bundan kısa (sadeleştirilmiş) satır akılda tutulmaz ("No.", "Go!" yeniden söylenebilir).</summary>
    public const int MinLength = 6;
    public const int Capacity = 16;

    /// <param name="Loose">
    /// Altyazı adayı sayılmadan atıldı (Türkçe, Türkçe bloğun parçası, çöp okuma): yazı tanıma farkı kadar değişmiş okuması
    /// da aynı satırdır. Çevirisi aslıyla aynı çıkan satırda yalnız aynı metin sayılır (düzelen okuma, ör. "I can do" →
    /// "I can't do", yeniden çevrilir).
    /// </param>
    private sealed record Entry(string Text, double? Top, double? Bottom, bool Target, bool Shown, bool Loose)
    {
        public long SeenAt { get; set; }
    }

    private readonly List<Entry> entries = [];

    /// <summary>Karenin bütün okunan satırları: ekranda duran kayıtların görüldüğü an yenilenir, ekrandan kalkanlar unutulur.</summary>
    public void Observe(IEnumerable<string> lines, long time)
    {
        if (entries.Count == 0) return;
        var frame = TextMatch.Normalize(string.Join(' ', lines));
        foreach (var entry in entries)
            if (Covered(entry.Text, frame)) entry.SeenAt = time;
        entries.RemoveAll(entry => time - entry.SeenAt > (entry.Shown ? 0 : DroppedAbsentMs));
    }

    /// <summary>Satır karara bağlandı (atıldı ya da gösterildi).</summary>
    public void Settle(string source, TextBox? box, bool target, bool shown, long time, bool loose = false)
    {
        var text = TextMatch.Normalize(source);
        if (text.Length < MinLength) return;
        entries.RemoveAll(entry => entry.Text == text);
        entries.Add(new Entry(text, box?.Top, box?.Bottom, target, shown, loose && !shown) { SeenAt = time });
        if (entries.Count > Capacity) entries.RemoveRange(0, entries.Count - Capacity);
    }

    /// <summary>
    /// Satır karara bağlanmış ve hâlâ ekranda. Altyazı adayı sayılmadan atılan satırın (Loose) yazı tanıma farkı kadar
    /// değişmiş okuması da sayılır; öbürlerinde yalnız aynı metin (uzamış ya da düzelmiş okuması her zamanki gibi gider).
    /// </summary>
    public bool IsSettled(string source)
    {
        var text = TextMatch.Normalize(source);
        if (text.Length < MinLength) return false;
        return entries.Any(entry => entry.Text == text || (entry.Loose && TextMatch.IsSimilar(text, entry.Text, Similarity)));
    }

    /// <summary>
    /// Satır, aynı yerde duran ve kaynağı zaten hedef dilde olan bir bloğun bozuk okunmuş parçası mı ("One [Ikan Ipufl"
    /// ⊂ "e [Ikan Ipuflari Yakin zamanda olu..."). Yerler biliniyorsa dikeyde örtüşmeleri gerekir. Türkçe olduğu burada
    /// anlaşılan (Loose) bloğun parçası okuma farkıyla biraz uzun da olabilir; çevirmenin aslıyla aynı döndürdüğü bloğun
    /// parçası ondan kısa olmalı ve cümle gibi bitmemeli (tam cümle, ör. "I said that I would help you.", altyazıdır).
    /// </summary>
    public bool IsTargetFragment(string source, TextBox? box)
    {
        var text = TextMatch.Normalize(source);
        if (text.Length < MinLength) return false;
        var sentence = SubtitleStabilizer.EndsSentence(source);
        return entries.Any(entry =>
        {
            var fits = entry.Loose ? text.Length <= entry.Text.Length + 2 : text.Length < entry.Text.Length && !sentence;
            if (!entry.Target || !fits || !Covered(text, entry.Text)) return false;
            if (box is not { } b || entry.Top is not { } top || entry.Bottom is not { } bottom) return true;
            return b.Top < bottom && top < b.Bottom;
        });
    }

    public void Reset() => entries.Clear();

    /// <summary><paramref name="part"/>'ın <paramref name="whole"/> içinde kesintisiz geçen en uzun bölümü, kendisinin en az <see cref="Coverage"/> oranı mı.</summary>
    public static bool Covered(string part, string whole)
    {
        if (part.Length == 0 || whole.Length == 0) return false;
        return LongestRun(part, whole) >= Coverage * part.Length;
    }

    /// <summary>İki metnin ortak en uzun kesintisiz bölümünün uzunluğu (karakter).</summary>
    public static int LongestRun(string a, string b)
    {
        var previous = new int[b.Length + 1];
        var best = 0;
        for (var i = 1; i <= a.Length; i++)
        {
            var row = new int[b.Length + 1];
            for (var j = 1; j <= b.Length; j++)
            {
                if (a[i - 1] != b[j - 1]) continue;
                row[j] = previous[j - 1] + 1;
                if (row[j] > best) best = row[j];
            }
            previous = row;
        }
        return best;
    }
}
