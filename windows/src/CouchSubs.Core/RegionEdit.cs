// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Alan çerçevesinin fareyle/parmakla düzenlenmesi (Ayarlar › Alan önizlemesi): hangi tutamacın tutulduğu, taşıma ve
/// boyutlandırma. Çerçevenin sekiz tutamacı vardır (köşeler ve kenar ortaları). Altyazı alanında "Ortada tut" açıksa
/// (varsayılan) yatay boyut ortadan değişir: sağ kenar çekilince sol kenar da aynı kadar açılır, alan ortalı kalır
/// (oyunların çoğu altyazıyı ortalar). Kapalıysa (sola yaslı ya da köşedeki altyazı) ve ek alanlarda kenarlar serbesttir:
/// yalnız tutulan kenar oynar. Mac ve iPhone'daki RegionEdit.swift ve Android'deki RegionEdit.kt ile aynı kurallar.
/// </summary>
public static class RegionEdit
{
    [Flags]
    public enum Handle { None = 0, Left = 1, Top = 2, Right = 4, Bottom = 8 }

    /// <summary>
    /// Çerçeve düzenlenirken bir kenarın en küçük boyu (kenara oranla). Tek satırlık küçük HUD yazıları için kaydırıcıların
    /// sınırından (<see cref="AreaPresets.MinimumSize"/>) küçüktür; Windows seçicisi bu sınırı önceden de kullanıyordu.
    /// </summary>
    public const double MinimumSize = 0.03;

    /// <summary>
    /// Önizlemedeki nokta (0–1) hangi tutamaçta: kenar ya da köşe; çerçevenin içinde ve kenarlardan uzaktaysa
    /// <see cref="Handle.None"/> (taşıma); çerçevenin dışındaysa null. <paramref name="grabX"/>/<paramref name="grabY"/>:
    /// tutma payı (kenara oranla).
    /// </summary>
    public static Handle? HandleAt(CropRegion region, double x, double y, double grabX, double grabY)
    {
        if (x < region.Left - grabX || x > region.Right + grabX || y < region.Top - grabY || y > region.Bottom + grabY) return null;
        var handle = Handle.None;
        // Çok küçük bir çerçevede iki kenar üst üste gelirse daha yakın olan tutulur.
        var (left, right) = (Math.Abs(x - region.Left), Math.Abs(x - region.Right));
        if (Math.Min(left, right) <= grabX) handle |= left <= right ? Handle.Left : Handle.Right;
        var (top, bottom) = (Math.Abs(y - region.Top), Math.Abs(y - region.Bottom));
        if (Math.Min(top, bottom) <= grabY) handle |= top <= bottom ? Handle.Top : Handle.Bottom;
        if (handle == Handle.None && (x < region.Left || x > region.Right || y < region.Top || y > region.Bottom)) return null;
        return handle;
    }

    /// <summary>
    /// <paramref name="start"/> çerçevesi <paramref name="handle"/>'dan (dx, dy) kadar sürüklendi. <see cref="Handle.None"/>
    /// taşır; kenarlar boyutlandırır. <paramref name="centered"/>: yatay boyut ortadan değişir. Çerçeve karenin dışına
    /// taşmaz ve her kenarda en az <see cref="MinimumSize"/> kalır.
    /// </summary>
    public static CropRegion Dragged(CropRegion start, Handle handle, double dx, double dy, bool centered)
    {
        if (handle == Handle.None)
        {
            var width = start.Right - start.Left;
            var height = start.Bottom - start.Top;
            var left = Math.Clamp(start.Left + dx, 0, 1 - width);
            var top = Math.Clamp(start.Top + dy, 0, 1 - height);
            return new CropRegion(top, top + height, left, left + width);
        }
        var (t, b, l, r) = (start.Top, start.Bottom, start.Left, start.Right);
        if (handle.HasFlag(Handle.Top)) t = Math.Clamp(start.Top + dy, 0, start.Bottom - MinimumSize);
        if (handle.HasFlag(Handle.Bottom)) b = Math.Clamp(start.Bottom + dy, start.Top + MinimumSize, 1);
        if (centered && (handle.HasFlag(Handle.Left) || handle.HasFlag(Handle.Right)))
        {
            var center = (start.Left + start.Right) / 2;
            var half = handle.HasFlag(Handle.Right) ? start.Right + dx - center : center - (start.Left + dx);
            half = Math.Clamp(half, MinimumSize / 2, Math.Max(MinimumSize / 2, Math.Min(center, 1 - center)));
            (l, r) = (Math.Max(0, center - half), Math.Min(1, center + half));
        }
        else
        {
            if (handle.HasFlag(Handle.Left)) l = Math.Clamp(start.Left + dx, 0, start.Right - MinimumSize);
            if (handle.HasFlag(Handle.Right)) r = Math.Clamp(start.Right + dx, start.Left + MinimumSize, 1);
        }
        return new CropRegion(t, b, l, r);
    }

    /// <summary>Sekiz tutamacın yeri (0–1): köşeler ve kenar ortaları, saat yönünde sol üstten.</summary>
    public static IReadOnlyList<(double X, double Y)> Handles(CropRegion region)
    {
        var (midX, midY) = ((region.Left + region.Right) / 2, (region.Top + region.Bottom) / 2);
        return
        [
            (region.Left, region.Top), (midX, region.Top), (region.Right, region.Top), (region.Right, midY),
            (region.Right, region.Bottom), (midX, region.Bottom), (region.Left, region.Bottom), (region.Left, midY),
        ];
    }
}
