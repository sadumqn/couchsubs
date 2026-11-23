// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell;

/// <summary>Üst çubuktaki durum hapının durumu (design/yeni-arayuz/METINLER.md › Pencere kabuğu; Mac ile aynı).</summary>
public enum ShellStatusKind { Ready, TranslationOn, Connecting, NeedsAttention, SetupIncomplete, Demo }

public static class ShellStatus
{
    /// <summary>
    /// Deneme modu her şeyden önce gelir; kurulum bitmediyse "Kurulum Eksik". Çeviri sürerken konsol ya da TV uyarıdaysa
    /// "Sorun Var", konsol henüz bağlanmadıysa "Bağlanıyor…", bağlıysa "Çeviri Açık". Başlatılırken "Bağlanıyor…",
    /// yoksa "Hazır". <paramref name="tv"/>: altyazı TV'ye gitmiyorsa <see cref="StatusTone.Good"/> verilir.
    /// </summary>
    public static ShellStatusKind For(bool demo, bool setupDone, bool running, bool starting, StatusTone console, StatusTone tv)
    {
        if (demo) return ShellStatusKind.Demo;
        if (!setupDone) return ShellStatusKind.SetupIncomplete;
        if (running)
        {
            if (console == StatusTone.Warning || tv == StatusTone.Warning) return ShellStatusKind.NeedsAttention;
            return console == StatusTone.Good ? ShellStatusKind.TranslationOn : ShellStatusKind.Connecting;
        }
        return starting ? ShellStatusKind.Connecting : ShellStatusKind.Ready;
    }
}
