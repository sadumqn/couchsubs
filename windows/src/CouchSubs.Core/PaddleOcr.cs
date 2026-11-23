// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Gelişmiş yazı tanıma: PaddleOCR'ın PP-OCRv6 small modelleri (Baidu / PaddlePaddle, Apache-2.0). Yazı bulma modeli
/// (DB) her piksel için "yazı" olasılığı verir; bu haritadan satır kutuları çıkar. Okuma modeli 48 piksel yüksekliğe
/// getirilen her satırı karakter olasılıklarına çevirir (CTC). Bu sınıf modeli çalıştırmaz: model girdisini hazırlar
/// ve çıktısını yorumlar; çalıştırma uygulamadadır (Windows: ONNX Runtime). Ayarlar RapidOCR'ın PP-OCRv6 varsayılanlarıdır
/// (eşik 0,3, kutu eşiği 0,5, genişletme 1,6); altyazı alanı için yazı bulmada en uzun kenar 960 pikselle sınırlıdır.
/// </summary>
public static class PaddleOcr
{
    /// <summary>İndirilen bir model dosyası: yerel adı, kaynağı, boyutu ve SHA-256 özeti.</summary>
    public sealed record ModelFile(string Name, Uri Url, long Bytes, string Sha256);

    public const string DetectionFile = "det.onnx";
    public const string RecognitionFile = "rec.onnx";
    /// <summary>Okuma modelinin ayarları; karakter sözlüğü buradadır.</summary>
    public const string RecognitionConfigFile = "rec.yml";

    // Resmî PaddlePaddle depoları, belirli sürüme sabit: dosya değişirse özet de tutmaz.
    private const string DetectionRevision = "28fe5895c24fd108c19eb3e8479f4ab385fbfc62";
    private const string RecognitionRevision = "b8f84f0b80c529de40b4fbb3544b84fa7233a513";
    /// <summary>Modellerin kurulduğu klasörün adı; model değişince eskisi silinebilsin diye sürüm taşır.</summary>
    public const string Version = "pp-ocrv6-small";

    public static IReadOnlyList<ModelFile> Files { get; } =
    [
        new(DetectionFile, Hub("PP-OCRv6_small_det_onnx", DetectionRevision, "inference.onnx"), 9_880_512,
            "d73e0058b7a8086bbd57f3d10b8bcd4ff95363f67e06e2762b5e814fe9c9410e"),
        new(RecognitionFile, Hub("PP-OCRv6_small_rec_onnx", RecognitionRevision, "inference.onnx"), 21_159_378,
            "5435fd747c9e0efe15a96d0b378d5bd157e9492ed8fd80edf08f30d02fa24634"),
        new(RecognitionConfigFile, Hub("PP-OCRv6_small_rec_onnx", RecognitionRevision, "inference.yml"), 150_579,
            "ab078671bb49f06228eadccd34f1bb501e157f7a047095ffb943ba81512c77d1"),
    ];

    public static long TotalBytes => Files.Sum(file => file.Bytes);

    private static Uri Hub(string repository, string revision, string name) =>
        new($"https://huggingface.co/PaddlePaddle/{repository}/resolve/{revision}/{name}");

    /// <summary>Yazı bulmada görüntünün en uzun kenarı en çok bu (altyazı alanı).</summary>
    public const int DetectionLimit = 960;
    /// <summary>Büyük görüntüde (bütün ekran, 1080p'de altyazı alanı) küçük yazı kaybolmasın diye sınır.</summary>
    public const int LargeDetectionLimit = 1280;

    /// <summary>Görüntünün boyutuna göre yazı bulma sınırı.</summary>
    public static int DetectionLimitFor(int width, int height) => Math.Max(width, height) > 1100 ? LargeDetectionLimit : DetectionLimit;
    public const float Threshold = 0.3f;
    public const float BoxThreshold = 0.5f;
    public const double UnclipRatio = 1.6;
    public const int MaxCandidates = 1000;
    public const int RecognitionHeight = 48;
    /// <summary>Okuma modeline birlikte giden satır sayısı.</summary>
    public const int RecognitionBatch = 6;
    /// <summary>Bundan düşük güvenle okunan satır atılır (RapidOCR'ın varsayılanı 0,5; altyazıda biraz daha sıkı).</summary>
    public const double MinConfidence = 0.55;

    private static readonly float[] DetectionMean = [0.485f, 0.456f, 0.406f];
    private static readonly float[] DetectionStd = [0.229f, 0.224f, 0.225f];

    /// <summary>
    /// Okuma modelinin karakterleri: <c>inference.yml</c>'deki <c>PostProcess.character_dict</c> listesi. Model çıktısının
    /// 0. sınıfı boşluk-yok (CTC "blank"), son sınıfı boşluk karakteridir; aradakiler bu sırayla sözlüktür.
    /// </summary>
    public static string[] ParseCharacters(string yaml)
    {
        var lines = yaml.Replace("\r\n", "\n").Split('\n');
        var start = Array.FindIndex(lines, line => line.TrimEnd() == "  character_dict:");
        if (start < 0) throw new InvalidDataException("character_dict not found");
        var characters = new List<string>();
        for (var i = start + 1; i < lines.Length && lines[i].StartsWith("  - ", StringComparison.Ordinal); i++)
        {
            var value = lines[i][4..];
            if (value.Length >= 2 && value[0] == '\'' && value[^1] == '\'') value = value[1..^1].Replace("''", "'");
            else if (value.Length >= 2 && value[0] == '"' && value[^1] == '"') value = System.Text.Json.JsonSerializer.Deserialize<string>(value)!;
            characters.Add(value);
        }
        if (characters.Count == 0) throw new InvalidDataException("character_dict is empty");
        return ["", .. characters, " "];
    }

    /// <summary>Yazı bulma modelinin girdisi: NCHW, BGR sırasıyla normalleştirilmiş; boyutlar 32'nin katı.</summary>
    public sealed record DetectionInput(float[] Data, int Width, int Height);

    public static DetectionInput PrepareDetection(Frame image, int limit = DetectionLimit)
    {
        var ratio = Math.Max(image.Width, image.Height) > limit ? (double)limit / Math.Max(image.Width, image.Height) : 1.0;
        var width = Math.Max(32, (int)Math.Round((int)(image.Width * ratio) / 32.0) * 32);
        var height = Math.Max(32, (int)Math.Round((int)(image.Height * ratio) / 32.0) * 32);
        var resized = width == image.Width && height == image.Height ? image : image.Resized(width, height);
        var plane = width * height;
        var data = new float[3 * plane];
        for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++)
            {
                var p = (y * resized.Stride) + (x * 4);
                var i = (y * width) + x;
                for (var c = 0; c < 3; c++)
                    data[(c * plane) + i] = ((resized.Pixels[p + c] / 255f) - DetectionMean[c]) / DetectionStd[c];
            }
        return new DetectionInput(data, width, height);
    }

    /// <summary>Bulunan bir satır kutusu, özgün görüntünün pikselleriyle.</summary>
    public readonly record struct Box(double Left, double Top, double Right, double Bottom);

    /// <summary>
    /// Yazı olasılık haritasından satır kutuları (DB son işlemi). Altyazı yatay olduğundan kutular eksene paraleldir:
    /// eşiği geçen pikseller 2×2 genişletilir, birbirine değen parçalar bir aday olur, adayın kutusundaki ortalama
    /// olasılık kutu eşiğini geçmeli ve kutu, alanı × oran / çevresi kadar dışa genişletilir. Sonuç yukarıdan aşağı,
    /// aynı satırda soldan sağa sıralıdır.
    /// </summary>
    public static List<Box> FindBoxes(ReadOnlySpan<float> map, int width, int height, int sourceWidth, int sourceHeight)
    {
        var on = new bool[width * height];
        for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++)
            {
                // cv2.dilate, 2×2 çekirdek: piksel, kendisi ya da sol/üst komşularından biri eşiği geçiyorsa açık.
                var any = false;
                for (var dy = 0; dy <= 1 && !any; dy++)
                    for (var dx = 0; dx <= 1 && !any; dx++)
                    {
                        int sx = x - dx, sy = y - dy;
                        if (sx >= 0 && sy >= 0 && map[(sy * width) + sx] > Threshold) any = true;
                    }
                on[(y * width) + x] = any;
            }

        var seen = new bool[on.Length];
        var stack = new Stack<int>();
        var boxes = new List<Box>();
        for (var start = 0; start < on.Length && boxes.Count < MaxCandidates; start++)
        {
            if (!on[start] || seen[start]) continue;
            int x0 = width, y0 = height, x1 = -1, y1 = -1;
            seen[start] = true;
            stack.Push(start);
            while (stack.Count > 0)
            {
                var i = stack.Pop();
                int x = i % width, y = i / width;
                x0 = Math.Min(x0, x); x1 = Math.Max(x1, x);
                y0 = Math.Min(y0, y); y1 = Math.Max(y1, y);
                for (var dy = -1; dy <= 1; dy++)
                    for (var dx = -1; dx <= 1; dx++)
                    {
                        int nx = x + dx, ny = y + dy;
                        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
                        var n = (ny * width) + nx;
                        if (on[n] && !seen[n]) { seen[n] = true; stack.Push(n); }
                    }
            }
            // Kenar noktaları piksel ortalarıdır (cv2.minAreaRect): kutu x1 - x0 geniştir.
            double w = x1 - x0, h = y1 - y0;
            if (Math.Min(w, h) < 3) continue;
            var sum = 0.0;
            for (var y = y0; y <= y1; y++)
                for (var x = x0; x <= x1; x++)
                    sum += map[(y * width) + x];
            if (sum / ((w + 1) * (h + 1)) < BoxThreshold) continue;
            var distance = w * h * UnclipRatio / (2 * (w + h));
            double left = x0 - distance, top = y0 - distance, right = x1 + distance, bottom = y1 + distance;
            if (Math.Min(right - left, bottom - top) < 5) continue;
            boxes.Add(new Box(
                Math.Clamp(Math.Round(left / width * sourceWidth), 0, sourceWidth),
                Math.Clamp(Math.Round(top / height * sourceHeight), 0, sourceHeight),
                Math.Clamp(Math.Round(right / width * sourceWidth), 0, sourceWidth),
                Math.Clamp(Math.Round(bottom / height * sourceHeight), 0, sourceHeight)));
        }
        // RapidOCR'ın sıralaması: yukarıdan aşağı; üstleri 10 pikselden yakın olanlar soldan sağa.
        boxes.Sort((a, b) => a.Top != b.Top ? a.Top.CompareTo(b.Top) : a.Left.CompareTo(b.Left));
        for (var i = 0; i < boxes.Count - 1; i++)
            for (var j = i; j >= 0; j--)
            {
                if (Math.Abs(boxes[j + 1].Top - boxes[j].Top) < 10 && boxes[j + 1].Left < boxes[j].Left)
                    (boxes[j], boxes[j + 1]) = (boxes[j + 1], boxes[j]);
                else break;
            }
        return boxes;
    }

    /// <summary>Kutunun kesiti; okuma modeline gidecek satır görüntüsü.</summary>
    public static Frame CropBox(Frame image, Box box)
    {
        var left = (int)box.Left;
        var top = (int)box.Top;
        return image.Crop(left, top, Math.Max(1, (int)(box.Right - box.Left)), Math.Max(1, (int)(box.Bottom - box.Top)));
    }

    /// <summary>
    /// Okuma modelinin bir toplu girdisi: satırlar 48 piksel yüksekliğe ölçeklenir, en geniş olanın genişliğine (en az
    /// 320) sağdan sıfırla doldurulur; değerler (x/255 − 0,5) / 0,5, BGR sırası.
    /// </summary>
    public static (float[] Data, int Width) PrepareRecognition(IReadOnlyList<Frame> lines)
    {
        const int h = RecognitionHeight;
        var maxRatio = 320.0 / h;
        foreach (var line in lines) maxRatio = Math.Max(maxRatio, (double)line.Width / Math.Max(1, line.Height));
        var width = (int)(h * maxRatio);
        var plane = h * width;
        var data = new float[lines.Count * 3 * plane];
        for (var n = 0; n < lines.Count; n++)
        {
            var line = lines[n];
            var resizedWidth = Math.Min(width, (int)Math.Ceiling(h * ((double)line.Width / Math.Max(1, line.Height))));
            var resized = line.Resized(Math.Max(1, resizedWidth), h);
            var offset = n * 3 * plane;
            for (var y = 0; y < h; y++)
                for (var x = 0; x < resized.Width; x++)
                {
                    var p = (y * resized.Stride) + (x * 4);
                    for (var c = 0; c < 3; c++)
                        data[offset + (c * plane) + (y * width) + x] = ((resized.Pixels[p + c] / 255f) - 0.5f) / 0.5f;
                }
        }
        return (data, width);
    }

    /// <summary>Latin alfabesiyle yazılan diller (oyun dili bunlardansa Çince/Japonca/Korece karakterler okuma hatasıdır).</summary>
    public static bool IsLatinLanguage(string language) =>
        language.Split('-', '_')[0].ToLowerInvariant() is "en" or "tr" or "de" or "fr" or "es" or "it" or "pt" or "nl" or "pl"
            or "sv" or "da" or "no" or "nb" or "fi" or "cs" or "sk" or "hu" or "ro" or "hr" or "sl" or "id" or "ms" or "vi";

    /// <summary>
    /// Latin alfabeli dilde okunan satırdan Çince, Japonca ve Korece karakterler çıkar: model çok dillidir, karışık
    /// zeminde tek tük bu karakterleri "görür" ("一 0"). Geriye harf kalmazsa satır boştur.
    /// </summary>
    public static string LatinOnly(string text)
    {
        var builder = new System.Text.StringBuilder(text.Length);
        foreach (var c in text)
            if (!IsCjk(c)) builder.Append(c);
        var kept = string.Join(' ', builder.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
        return kept.Any(char.IsLetter) ? kept : "";
    }

    private static bool IsCjk(char c) =>
        c is (>= '\u2E80' and <= '\u9FFF') or (>= '\uAC00' and <= '\uD7AF') or (>= '\uF900' and <= '\uFAFF') or (>= '\uFF00' and <= '\uFFEF')
            or (>= '\u1100' and <= '\u11FF') or (>= '\u3130' and <= '\u318F');

    /// <summary>
    /// Bir satırın karakter olasılıklarından (zaman adımı × sınıf) metin ve güven: her adımda en olası sınıf alınır,
    /// art arda aynı sınıf ve boş sınıf atlanır; güven, kalan adımların olasılıklarının ortalamasıdır.
    /// </summary>
    public static (string Text, double Confidence) Decode(ReadOnlySpan<float> probabilities, int steps, string[] characters)
    {
        var (text, confidence, _) = DecodeWithPlaces(probabilities, steps, characters);
        return (text, confidence);
    }

    /// <summary>
    /// <see cref="Decode"/> gibi; ayrıca her okunan karakterin satırdaki yeri (ortası, zaman adımı biriminde). Sözcük
    /// yerlerini çıkarmaya yarar (<see cref="Words"/>): yazının içindeki kumanda simgesi böyle bulunur.
    /// </summary>
    public static (string Text, double Confidence, IReadOnlyList<(string Character, double Center)> Places) DecodeWithPlaces(
        ReadOnlySpan<float> probabilities, int steps, string[] characters)
    {
        var classes = characters.Length;
        var text = new System.Text.StringBuilder();
        var places = new List<(string, double)>();
        var total = 0.0;
        var count = 0;
        var previous = -1;
        var start = 0;
        for (var t = 0; t <= steps; t++)
        {
            var best = 0;
            if (t < steps)
            {
                var row = probabilities.Slice(t * classes, classes);
                for (var c = 1; c < classes; c++)
                    if (row[c] > row[best]) best = c;
                if (best != 0 && best != previous)
                {
                    text.Append(characters[best]);
                    total += row[best];
                    count++;
                }
            }
            // Aynı karakterin art arda adımları bitti: yeri o adımların ortası.
            if (previous > 0 && best != previous) places.Add((characters[previous], (start + t) / 2.0));
            if (best != previous) start = t;
            previous = best;
        }
        return count == 0 ? ("", 0, []) : (text.ToString(), total / count, places);
    }

    /// <summary>
    /// Karakter yerlerinden sözcükler: boşluk karakteri sözcükleri ayırır; her sözcük ilk ve son harfinin ortasından
    /// yarım harf aralığı dışarı taşar (aralık, sözcüklerin içindeki harflerin ortalama uzaklığıdır). Birim zaman adımıdır.
    /// </summary>
    public static IReadOnlyList<(string Text, double Left, double Right)> Words(IReadOnlyList<(string Character, double Center)> places)
    {
        var words = new List<List<(string Character, double Center)>>();
        var current = new List<(string, double)>();
        foreach (var place in places)
        {
            if (string.IsNullOrWhiteSpace(place.Character))
            {
                if (current.Count > 0) words.Add(current);
                current = [];
            }
            else current.Add(place);
        }
        if (current.Count > 0) words.Add(current);
        var gaps = words.SelectMany(word => word.Skip(1).Select((place, i) => place.Center - word[i].Center)).Order().ToList();
        var pitch = gaps.Count > 0 ? gaps[gaps.Count / 2] : 2.0;
        return [.. words.Select(word => (string.Concat(word.Select(place => place.Character)),
                                         word[0].Center - (pitch / 2), word[^1].Center + (pitch / 2)))];
    }

    /// <summary>Çince, Japonca ve Korece karakterleri atar (<see cref="LatinOnly"/>'nin sözcük karşılığı; harfsiz sözcük kalır).</summary>
    public static string WithoutCjk(string text) => new([.. text.Where(c => !IsCjk(c))]);
}
