// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;

namespace CouchSubs.Shell;

/// <summary>Açılır reklamın gösterilebileceği an.</summary>
public enum PopupAdMoment { AppLaunch, TranslationStopped }

/// <summary>reklamlar.json › popups içindeki bir açılır reklam: reklam/ altındaki görsel dosyası ve tıklanınca açılacak bağlantı.</summary>
public sealed record PopupAdEntry(string Id, string Image, Uri Link);

/// <summary>
/// Açılır reklam kuralları (design/yeni-arayuz/METINLER.md › Reklam kuralları; Mac ile aynı): günde en fazla bir kez;
/// yalnız uygulama açılışında ya da çeviri durunca; çeviri sürerken, kurulumda, görüntü (yayın) penceresi açıkken asla;
/// gösterilecek görsel yoksa hiç (yer tutucu ya da logo asla).
/// </summary>
public static class PopupAdPolicy
{
    public static bool ShouldShow(PopupAdMoment moment, DateTime now, DateTime? lastShown, bool running, bool setupDone, bool streamWindowOpen, bool hasAd)
    {
        if (!hasAd || running || !setupDone || streamWindowOpen) return false;
        _ = moment;
        return lastShown is not { } last || last.ToLocalTime().Date != now.ToLocalTime().Date;
    }

    /// <summary>
    /// reklamlar.json'daki açılır reklamlar (Mac aynı dosyayı okur). Görsel adı boş ya da bağlantısı https değilse reklam
    /// atlanır; dosya yoksa ya da bozuksa liste boş (açılır reklam açılmaz).
    /// </summary>
    public static IReadOnlyList<PopupAdEntry> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Object || !document.RootElement.TryGetProperty("popups", out var popups)
                || popups.ValueKind != JsonValueKind.Array)
                return [];
            var list = new List<PopupAdEntry>();
            foreach (var popup in popups.EnumerateArray())
            {
                if (popup.ValueKind != JsonValueKind.Object) continue;
                string? Text(string name) => popup.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
                var image = Text("image");
                if (string.IsNullOrWhiteSpace(image) || !Uri.TryCreate(Text("link"), UriKind.Absolute, out var link) || link.Scheme != Uri.UriSchemeHttps)
                    continue;
                list.Add(new PopupAdEntry(Text("id") ?? image, image, link));
            }
            return list;
        }
        catch (JsonException)
        {
            return [];
        }
    }

    /// <summary>O günün reklamı (birden çok varsa gün sırasıyla); liste boşsa null.</summary>
    public static T? Pick<T>(IReadOnlyList<T> ads, DateTime now) where T : class =>
        ads.Count == 0 ? null : ads[now.DayOfYear % ads.Count];
}
