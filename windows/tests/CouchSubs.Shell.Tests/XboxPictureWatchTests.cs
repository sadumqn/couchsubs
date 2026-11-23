// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell.Tests;

/// <summary>
/// İlk kareden sonra Xbox görüntüsü kesilince uyarı ve yeniden kurma. Sahte saat: anlar ms olarak verilir.
/// CouchSubsCore XboxPictureWatchTests ve Android'deki XboxPictureWatchTest ile aynı durumlar.
/// </summary>
public class XboxPictureWatchTests
{
    [Fact]
    public void NothingIsDecidedBeforeTheFirstFrame()
    {
        var watch = new XboxPictureWatch();
        watch.IceChanged(XboxPictureWatch.Ice.Disconnected, 0);
        Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(60_000));
    }

    [Fact]
    public void FlowingPictureIsFine()
    {
        var watch = new XboxPictureWatch();
        for (long second = 0; second < 120; second++)
        {
            watch.FrameArrived(second * 1000);
            Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(second * 1000 + 500));
        }
    }

    [Fact]
    public void WarnsOnceThenReconnectsWhenFramesStopWhileTheConnectionLooksOpen()
    {
        var watch = new XboxPictureWatch();
        watch.FrameArrived(0);
        watch.FrameArrived(40_000);
        Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(44_000));
        Assert.Equal(XboxPictureVerdict.Warn, watch.Tick(45_000));
        Assert.True(watch.Warned);
        Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(46_000));
        Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(51_000));
        Assert.Equal(XboxPictureVerdict.Stalled("Xbox'tan 12 sn'dir görüntü gelmiyor (bağlantı açık görünüyor)"), watch.Tick(52_000));
    }

    /// <summary>Yayının ilk 30 sn'sinde kare boşluğu oturumu kapatmaz (yalnız uyarı); sınırdan sonra kapatır.</summary>
    [Fact]
    public void GapsInTheFirstThirtySecondsDoNotEndTheSession()
    {
        var watch = new XboxPictureWatch();
        watch.FrameArrived(1000);
        Assert.Equal(XboxPictureVerdict.Warn, watch.Tick(6000));
        for (long at = 7000; at <= 30_000; at += 1000) Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(at));
        Assert.Equal(XboxPictureVerdict.Stalled("Xbox'tan 30 sn'dir görüntü gelmiyor (bağlantı açık görünüyor)"), watch.Tick(31_000));
    }

    [Fact]
    public void FlowingMeansARecentFrame()
    {
        var watch = new XboxPictureWatch();
        Assert.False(watch.IsFlowing(0));
        watch.FrameArrived(1000);
        Assert.True(watch.IsFlowing(5999));
        Assert.False(watch.IsFlowing(6000));
    }

    /// <summary>
    /// Sahte Xbox oturumu (bekçiler XboxStreamSession'daki gibi saniyede bir; canlı tutma 30 sn'de bir). Play'deki bildirim
    /// (Android beta.85): "uzaktan yürütme başlatıldı, hemen ardından durdu, tekrar başladı/durdu". Yayın başında görüntü
    /// birkaç saniye bekliyor, canlı tutma 404 dönüyor: ilk 30 sn'de (ve görüntü akarken sonrasında da) oturum kapatılmıyor,
    /// yeniden açılmıyor. Sonra gerçek kopma: en çok bir kez, 5 sn sonra yeniden bağlanılıyor. CouchSubsCore ve Android'deki
    /// aynı adlı testle aynı senaryo.
    /// </summary>
    [Fact]
    public void FakeXboxSessionDoesNotLoopAndReconnectsAtMostOnce()
    {
        var session = new FakeXboxSession();
        session.Connect();
        session.Frames(1000, 3000);
        // 3–20 sn: Xbox görüntüyü bekletiyor (yükleme, bildirim); 20 sn'den sonra yine akıyor.
        session.Frames(20_000, 70_000);
        session.KeepaliveFails = "Xbox service HTTP 404: ";
        for (long at = 0; at <= 70_000; at += 1000) session.Tick(at);
        Assert.Empty(session.Ends);
        Assert.Equal(1, session.Plays);

        // Gerçek kopma: Wi-Fi gitti, ICE disconnected, kare yok.
        session.IceLost(70_500);
        for (long at = 71_000; at <= 82_000; at += 1000) session.Tick(at);
        Assert.Single(session.Ends);
        Assert.Equal(new int?[] { 5000 }, session.Retries);
        Assert.Equal(2, session.Plays);
        // Yeniden bağlanma da kısa sürede kopuyor: ikinci deneme yok, yayın durur ("Yeniden bağlan" düğmesi).
        session.Frames(96_000, 100_000);
        session.IceLost(100_500);
        for (long at = 96_000; at <= 160_000; at += 1000) session.Tick(at);
        Assert.Equal(new int?[] { 5000, null }, session.Retries);
        Assert.Equal(2, session.Plays);
    }

    /// <summary>XboxStreamSession'ın bekçi döngüsünün ağsız kopyası (yeniden deneme planı, görüntü bekçisi, canlı tutma).</summary>
    private sealed class FakeXboxSession
    {
        private long now;
        private readonly XboxRetryPlan retries = new();
        private XboxPictureWatch watch = new();
        private XboxKeepalive keepalive = new();
        private readonly SortedSet<long> frameTimes = [];
        private long connectedAt;
        private long streamingSince;
        private bool stopped;
        public string? KeepaliveFails;
        public int Plays;
        public readonly List<string> Ends = [];
        public readonly List<int?> Retries = [];

        public void Connect()
        {
            Plays++;
            connectedAt = now;
            streamingSince = 0;
            watch = new XboxPictureWatch();
            keepalive = new XboxKeepalive();
        }

        /// <summary>Xbox bu aralıkta ~60 kare/sn gönderir.</summary>
        public void Frames(long from, long to)
        {
            for (var at = from; at <= to; at += 16) frameTimes.Add(at);
        }

        public void IceLost(long at)
        {
            frameTimes.RemoveWhere(t => t >= at);
            watch.IceChanged(XboxPictureWatch.Ice.Disconnected, at);
        }

        public void Tick(long at)
        {
            if (stopped) return;
            now = at;
            foreach (var frame in frameTimes.GetViewBetween(at - 999, at))
            {
                if (streamingSince == 0)
                {
                    streamingSince = frame;
                    retries.PictureArrived();
                }
                watch.FrameArrived(frame);
            }
            var since = at - connectedAt;
            if (since > 0 && since % (long)XboxKeepalive.Interval.TotalMilliseconds == 0 && KeepaliveFails is { } error
                && XboxKeepalive.ShouldEnd(XboxKeepalive.SessionGone(error), keepalive.Failed(), watch.IsFlowing(at)))
            {
                End("canlı tutma");
                return;
            }
            if (watch.Tick(at) is { Kind: XboxPictureVerdictKind.Stalled } verdict) End(verdict.Reason!);
        }

        private void End(string reason)
        {
            Ends.Add(reason);
            var delay = retries.Failed(false, streamingSince == 0, streamingSince == 0 ? null : now - streamingSince, reason);
            Retries.Add(delay);
            if (delay is null)
            {
                stopped = true;
                return;
            }
            now += delay.Value;
            Connect();
        }
    }

    [Fact]
    public void RecoversWhenFramesComeBackBeforeTheLimit()
    {
        var watch = new XboxPictureWatch();
        watch.FrameArrived(0);
        Assert.Equal(XboxPictureVerdict.Warn, watch.Tick(6000));
        watch.FrameArrived(8000);
        Assert.Equal(XboxPictureVerdict.Recovered, watch.Tick(8500));
        Assert.False(watch.Warned);
        Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(9500));
    }

    [Fact]
    public void IceDisconnectedWarnsAfterOneSecondWithoutFrames()
    {
        var watch = new XboxPictureWatch();
        watch.FrameArrived(0);
        watch.IceChanged(XboxPictureWatch.IceFrom("disconnected"), 200);
        Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(500));
        Assert.Equal(XboxPictureVerdict.Warn, watch.Tick(1200));
        watch.IceChanged(XboxPictureWatch.IceFrom("connected"), 3000);
        watch.FrameArrived(3100);
        Assert.Equal(XboxPictureVerdict.Recovered, watch.Tick(3500));
    }

    [Fact]
    public void IceStuckInDisconnectedEndsTheSessionAtTheLimit()
    {
        var watch = new XboxPictureWatch();
        watch.FrameArrived(0);
        watch.FrameArrived(40_000);
        watch.IceChanged(XboxPictureWatch.Ice.Disconnected, 40_100);
        Assert.Equal(XboxPictureVerdict.Warn, watch.Tick(41_000));
        Assert.Equal(XboxPictureVerdict.Stalled("Xbox'tan 12 sn'dir görüntü gelmiyor (ICE disconnected)"), watch.Tick(52_000));
    }

    [Fact]
    public void IceFailedEndsTheSessionAtOnce()
    {
        var watch = new XboxPictureWatch();
        watch.FrameArrived(0);
        watch.IceChanged(XboxPictureWatch.IceFrom("failed"), 500);
        Assert.Equal(XboxPictureVerdict.Stalled("Xbox ICE bağlantısı koptu (failed)"), watch.Tick(600));
    }

    [Fact]
    public void FramesWhileIceSaysDisconnectedDoNotWarn()
    {
        var watch = new XboxPictureWatch();
        watch.IceChanged(XboxPictureWatch.Ice.Disconnected, 0);
        for (long second = 0; second < 20; second++)
        {
            watch.FrameArrived(second * 1000);
            Assert.Equal(XboxPictureVerdict.Fine, watch.Tick(second * 1000 + 300));
        }
    }

    [Fact]
    public void UnknownStatesAreIgnored()
    {
        Assert.Equal(XboxPictureWatch.Ice.Other, XboxPictureWatch.IceFrom("checking"));
        Assert.Equal(XboxPictureWatch.Ice.Other, XboxPictureWatch.IceFrom(null));
    }
}
