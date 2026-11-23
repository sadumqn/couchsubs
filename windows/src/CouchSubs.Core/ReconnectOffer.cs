// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Çeviri sürerken ana ekranda "Yeniden bağlan" düğmesi ne zaman görünür (Mac/iPhone: core ReconnectOffer.swift, Android:
/// ReconnectOffer.kt; aynı kural, aynı test durumları).
///
/// Konsol bağlantısı koparsa oturum kendiliğinden kademeli olarak yeniden bağlanır. Ama oturum yeniden denemeyi bırakabilir
/// (PS5'te Uzaktan Oynatma çöktü, kayıt ya da giriş şifresi geçersiz, Xbox denemeleri bitti) ya da uzun süre bağlanamayabilir.
/// Eskiden ekranda yalnız "Yeniden bağlanılıyor…" ya da "yeniden başlatın" yazıyordu; kullanıcılar uygulamayı kapatıp
/// açıyordu. Düğme, bırakılan oturumda hemen, süren denemelerde <see cref="After"/> sonra görünür.
/// </summary>
public sealed class ReconnectOffer
{
    /// <summary>Bu kadar süredir bağlı değilse (bağlanıyor ya da kopmuş) düğme görünür.</summary>
    public static readonly TimeSpan After = TimeSpan.FromSeconds(45);

    /// <summary>Bağlantının gittiği an; bağlıyken null.</summary>
    public DateTime? NotLiveSince { get; private set; }

    /// <summary>Oturum durumu değişti. <paramref name="live"/>: görüntü akıyor. Ara durumlar (bağlanıyor ↔ koptu) süreyi
    /// baştan başlatmaz.</summary>
    public void Update(bool live, DateTime now)
    {
        if (live) NotLiveSince = null;
        else NotLiveSince ??= now;
    }

    /// <summary>Çeviri durdu ya da yeni oturum açıldı: süre <paramref name="now"/>'dan (null: hiç) sayılır.</summary>
    public void Reset(DateTime? now = null) => NotLiveSince = now;

    /// <param name="gaveUp">Oturum yeniden denemeyi bıraktı.</param>
    public bool Shows(bool gaveUp, DateTime now) =>
        gaveUp || (NotLiveSince is { } since && now - since >= After);
}
