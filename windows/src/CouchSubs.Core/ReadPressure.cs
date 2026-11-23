// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Altyazı okuması her zaman önce gelir: ek alanların ve kendiliğinden bulunan ekran yazılarının okuması altyazı okumasını
/// geciktiriyorsa kendini kısar (#679; Mac ve iPhone: ReadQueue.backgroundSlowdown, Android: ReadPressure).
/// </summary>
public static class ReadPressure
{
    /// <summary>Son altyazı okuması bundan uzun sürdüyse ek alan turları iki kat seyrekleşir.</summary>
    public const int SlowReadMs = 700;
    /// <summary>Bundan uzun sürdüyse (ya da süren okuma bu kadardır bitmediyse) dört kat.</summary>
    public const int VerySlowReadMs = 1500;

    /// <summary>
    /// Ek alan tur aralığının çarpanı (1, 2 ya da 4). <paramref name="lastReadMs"/>: son altyazı okumasının süresi;
    /// <paramref name="busyMs"/>: şu an süren altyazı okumasının ne kadardır sürdüğü (sürmüyorsa 0).
    /// </summary>
    public static int Slowdown(int? lastReadMs, long busyMs)
    {
        var worst = Math.Max(lastReadMs ?? 0, busyMs);
        return worst >= VerySlowReadMs ? 4 : worst >= SlowReadMs ? 2 : 1;
    }
}
