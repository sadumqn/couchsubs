// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using CouchSubs.Core.Dubbing;

namespace CouchSubs.Core;

/// <summary>
/// Deneme modu (Mac/iPhone <c>DemoScript</c>, Android <c>DemoScript.kt</c> ile aynı): konsol olmadan uygulamanın bütün
/// hattını gösterir. Konsol akışının yerine <see cref="DemoFrameSource"/> örnek "oyun" kareleri verir; kareler gerçek
/// hattan geçer (bölge, yazı tanıma, kararlılık, çeviri, TV). Görseller ve satırlar bizimdir: oyun, marka ya da logo yoktur.
/// </summary>
public static class DemoScript
{
    public sealed record Line(string English, string Turkish);

    /// <summary>Döngüde sırayla gösterilen altyazılar (özgün, telifsiz macera diyalogları).</summary>
    public static readonly IReadOnlyList<Line> Lines =
    [
        new("We should reach the lighthouse before dark.", "Hava kararmadan deniz fenerine varmalıyız."),
        new("The bridge is gone. We need another way across.", "Köprü yıkılmış. Karşıya geçmek için başka bir yol lazım."),
        new("Stay close to me and keep your voice down.", "Yanımdan ayrılma ve sesini alçak tut."),
        new("I found a map in the old captain's cabin.", "Yaşlı kaptanın kamarasında bir harita buldum."),
        new("Do you hear that? Something is moving in the fog.", "Duydun mu? Siste bir şey hareket ediyor."),
        new("Light the lantern. We can't see a thing out here.", "Feneri yak. Burada hiçbir şey göremiyoruz."),
        new("The storm will reach the harbor within an hour.", "Fırtına bir saat içinde limana ulaşacak."),
        new("If we take the boat, we can be there by morning.", "Tekneyi alırsak sabaha orada olabiliriz."),
        new("Thank you for coming back for me.", "Benim için geri döndüğün için teşekkürler."),
        new("Keep the key safe. We will need it at the gate.", "Anahtarı sakla. Kapıda ona ihtiyacımız olacak."),
        new("Follow the river north until you see the tower.", "Kuleyi görene kadar nehri kuzeye doğru takip et."),
        new("Rest now. Tomorrow will be a long day.", "Şimdi dinlen. Yarın uzun bir gün olacak."),
    ];

    /// <summary>Karenin sol üstündeki görev yazısı ("Ekranı çevir" ve ek alanlar bunu da çevirir).</summary>
    public static readonly Line Objective = new("Objective: Reach the lighthouse", "Görev: Deniz fenerine ulaş");

    /// <summary>Gömülü hazır çeviri: okunan metin örnek satırlardan birine benziyorsa Türkçesi (ağ ve anahtar gerekmez).</summary>
    public static string? Translation(string text)
    {
        var wanted = TextMatch.Normalize(text);
        if (wanted.Length == 0) return null;
        Line[] all = [.. Lines, Objective];
        if (all.FirstOrDefault(line => TextMatch.Normalize(line.English) == wanted) is { } exact) return exact.Turkish;
        return all.FirstOrDefault(line => TextMatch.IsSimilar(TextMatch.Normalize(line.English), wanted, 0.8))?.Turkish;
    }
}

/// <summary>
/// Deneme karelerinin ölçüleri (Mac <c>DemoFrames</c> ile aynı). Kareyi Windows'ta uygulama katmanı çizer (WPF,
/// <c>DemoFrameRenderer</c>): düz bir kıyı sahnesi, sol üstte görev yazısı, altta İngilizce altyazı.
/// </summary>
public static class DemoFrames
{
    public const int Width = 1280;
    public const int Height = 720;
    /// <summary>Altyazının karede durduğu yer (üstten oran); varsayılan altyazı bölgesinin (0.62–0.97) içindedir.</summary>
    public const double SubtitleBaseline = 0.86;

    /// <summary>Çizici yokken (sınamalar, arayüzsüz çalışma) verilen yazısız, düz kare.</summary>
    public static Frame? Plain(int? line, int scene) => Frame.Blank(Width, Height);
}

/// <summary>
/// Konsol akışının yerine deneme karelerini saniyede birkaç kez verir. Her satır <c>lineSeconds</c> boyunca görünür,
/// ardından <c>gapSeconds</c> altyazısız kare gelir (satırlar ayrı ayrı okunsun); satırlar döngüde sürer.
/// <c>render</c>: (satırın sırası ya da altyazısız karede null, arka planın tonu) → kare.
/// </summary>
public sealed class DemoFrameSource(Func<int?, int, Frame?> render, double lineSeconds = 3.6, double gapSeconds = 0.9, double framesPerSecond = 5)
{
    /// <summary>Kaynağın kendi iş parçacığında çağrılır.</summary>
    public event Action<Frame>? FrameReady;
    public double LineSeconds { get; } = lineSeconds;
    public double GapSeconds { get; } = gapSeconds;
    public double FramesPerSecond { get; } = framesPerSecond;
    private CancellationTokenSource? running;

    public bool IsRunning => running is not null;

    /// <summary>
    /// Başlangıçtan <paramref name="elapsed"/> saniye sonra gösterilen satırın sırası (altyazısız aralıkta null). İlk satır
    /// kısa bir boş karenin ardından gelir.
    /// </summary>
    public int? LineIndex(double elapsed)
    {
        var shifted = elapsed - GapSeconds;
        if (shifted < 0) return null;
        var cycle = LineSeconds + GapSeconds;
        if (shifted % cycle >= LineSeconds) return null;
        return (int)(shifted / cycle) % DemoScript.Lines.Count;
    }

    public void Start()
    {
        Stop();
        var cancel = new CancellationTokenSource();
        running = cancel;
        var token = cancel.Token;
        var interval = TimeSpan.FromSeconds(1 / Math.Max(1, FramesPerSecond));
        _ = Task.Run(async () =>
        {
            var clock = Stopwatch.StartNew();
            var drawn = false;
            int? shown = null;
            Frame? frame = null;
            while (!token.IsCancellationRequested)
            {
                var line = LineIndex(clock.Elapsed.TotalSeconds);
                if (!drawn || shown != line)
                {
                    // Çizim tek bir karede başarısız olsa da akış sürer; önceki kare gösterilmeye devam eder.
                    try { frame = render(line, (line ?? 0) / 4) ?? frame; }
                    catch (Exception) when (!token.IsCancellationRequested) { }
                    (drawn, shown) = (true, line);
                }
                if (frame is not null && !token.IsCancellationRequested) FrameReady?.Invoke(frame);
                try { await Task.Delay(interval, token).ConfigureAwait(false); }
                catch (OperationCanceledException) { return; }
            }
        }, CancellationToken.None);
    }

    public void Stop()
    {
        running?.Cancel();
        running?.Dispose();
        running = null;
    }
}

/// <summary>
/// Deneme modunun çevirmeni: seçili motor (varsayılanı cihazdaki ücretsiz çeviri) çevirir; motor çeviremezse (model
/// indirilmemiş, ağ ya da anahtar yok) örnek satırların gömülü hazır çevirisi gösterilir. Böylece deneme modu internet
/// ve anahtar olmadan da baştan sona çalışır.
/// </summary>
public sealed class DemoTranslator(ITextTranslator? inner) : ITextTranslator
{
    public async Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        if (inner is not null)
        {
            try
            {
                var result = await inner.TranslateAsync(text, cancellationToken).ConfigureAwait(false);
                if (!string.IsNullOrWhiteSpace(result)) return result;
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception) { /* hazır çeviriye düşülür */ }
        }
        return DemoScript.Translation(text) ?? text;
    }

    public async Task<IReadOnlyList<string>> TranslateAllAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default)
    {
        if (inner is not null)
        {
            try
            {
                var results = await inner.TranslateAllAsync(texts, cancellationToken).ConfigureAwait(false);
                if (results.Count == texts.Count) return results;
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception) { /* hazır çeviriye düşülür */ }
        }
        return [.. texts.Select(text => DemoScript.Translation(text) ?? text)];
    }

    public IReadOnlyList<SpokenLine> SpokenLines(string text) => inner?.SpokenLines(text) ?? [];
    public bool Prefetches => inner?.Prefetches ?? false;
    public void Prefetch(string text) => inner?.Prefetch(text);
    public bool TranslatesTogether => inner?.TranslatesTogether ?? false;
    public string? CachedTranslation(string text) => inner?.CachedTranslation(text);
    public void NoteSpeaker(string name) => inner?.NoteSpeaker(name);
}
