// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell;

/// <summary>Ana ekrandaki sessizlik nedeni kartı ("Sorun Var"; design/yeni-arayuz/METINLER.md › 09–10).</summary>
public enum HomeProblemKind { None, PictureStopped, MenuOpen, SubtitlesOff }

public static class HomeProblem
{
    /// <summary>Görüntü bu kadar süre gelmezse "Görüntü Durdu".</summary>
    public static readonly TimeSpan PictureTimeout = TimeSpan.FromSeconds(5);

    /// <summary>
    /// Yalnız çeviri sürerken (deneme modu dışında) ve görüntü bir kez gelmişken: görüntü 5 sn'dir gelmiyorsa
    /// "Görüntü Durdu"; oyunda menü açıksa "Menü Açık"; görüntü bir dakikadır geldiği hâlde tek satır okunmadıysa
    /// (<see cref="SubtitleOffTip"/>) "Oyunun Altyazısı Kapalı mı?". Hiçbiri yoksa kart görünmez, Durum kartı görünür.
    /// </summary>
    /// <param name="sinceFrame">Son karenin üstünden geçen süre; hiç kare gelmediyse null (bağlanıyor: sorun sayılmaz).</param>
    public static HomeProblemKind For(bool running, bool demo, TimeSpan? sinceFrame, bool menuOpen, bool subtitlesOffTip)
    {
        if (!running || demo || sinceFrame is not { } gap) return HomeProblemKind.None;
        if (gap >= PictureTimeout) return HomeProblemKind.PictureStopped;
        if (menuOpen) return HomeProblemKind.MenuOpen;
        return subtitlesOffTip ? HomeProblemKind.SubtitlesOff : HomeProblemKind.None;
    }

    /// <summary>Kaç saniyedir sessiz: son satırdan (yoksa çevirinin başlangıcından) bu yana; eksi olmaz.</summary>
    public static int SilentSeconds(DateTime now, DateTime? lastLine, DateTime started)
    {
        var since = lastLine is { } line && line > started ? line : started;
        return (int)Math.Max(0, Math.Floor((now - since).TotalSeconds));
    }
}
