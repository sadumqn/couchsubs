// SPDX-License-Identifier: AGPL-3.0-only
using CouchSubs.Core.Dubbing;

namespace CouchSubs.Core.Tests;

public class PackedRereadTests
{
    private static readonly Frame Image = Frame.Blank(64, 64);

    [Theory]
    [InlineData("I'm king of the world.", "world.")]
    [InlineData("That he fucking passed out.", "passed")]
    [InlineData("Yo Jason, get in, get in!", "get in!")]
    public async Task PackedFragmentDoesNotReplaceInFlightFullLine(string full, string fragment)
    {
        long clock = 0;
        var translator = new GatedTranslator();
        var sender = new FakeSender();
        var reading = new FakeReader(Enumerable.Repeat(full, 4).Concat(Enumerable.Repeat(fragment, 4)).ToArray());
        var pipeline = new SubtitlePipeline(reading, translator, sender, clock: () => clock)
        {
            PackLookup = text => text == fragment ? new PackMatch("Paket parçası", [new SpokenLine(fragment, "Paket parçası")]) : null,
            ReadingScore = text => text.Length, LooksMisread = _ => false, PackWait = 0, CleanWait = 0,
        };
        try
        {
            for (var i = 0; i < 8; i++) { await pipeline.ProcessAsync(Image, new CropRegion()); clock += 100; }
            Assert.Empty(sender.Sent);
        }
        finally { clock += 3000; translator.Open(); await pipeline.WaitForTranslationsAsync(); }
        Assert.Equal(["TR: " + full], sender.Sent);
        Assert.Equal([full], translator.Requested);
        Assert.Equal(0, pipeline.PackHits);
    }

    [Fact]
    public async Task PackedFragmentDoesNotReplaceHeldFullLineOrExtendItsDeadline()
    {
        const string full = "I'm king of the world.";
        long clock = 0;
        var translator = new FakeTranslator();
        var sender = new FakeSender();
        var frames = Enumerable.Repeat(full, 4).Concat(Enumerable.Repeat("world.", 8)).ToArray();
        var pipeline = new SubtitlePipeline(new FakeReader(frames), translator, sender, clock: () => clock)
        {
            PackLookup = text => text == "world." ? new PackMatch("Dünya", []) : null,
            ReadingScore = text => text.Length, LooksMisread = text => text == full,
        };
        for (var i = 0; i < frames.Length; i++)
        {
            await pipeline.ProcessAsync(Image, new CropRegion()); await pipeline.WaitForTranslationsAsync();
            if (i == 9) Assert.Contains(full, translator.Requested); // 100 + 800 ms; süre yeniden başlamaz.
            clock += 100;
        }
        Assert.Equal([full], translator.Requested);
        Assert.Equal(["TR: " + full], sender.Sent);
    }

    [Theory]
    [InlineData("I swear to God, you kill me!", "You kill me!", false)]
    [InlineData("I'm king of the world.", "world.", true)]
    [InlineData("That he fucking passed out.", "Get down!", false)]
    [InlineData("I have five bullets.", "I have one bullet.", false)]
    public async Task GenuinePackedLineStillAppearsImmediately(string full, string next, bool blank)
    {
        long clock = 0;
        var frames = Enumerable.Repeat(full, 4)
            .Concat(blank ? Enumerable.Repeat("", 12) : [])
            .Concat(Enumerable.Repeat(next, 4)).ToArray();
        var sender = new FakeSender();
        var translator = new FakeTranslator();
        var pipeline = new SubtitlePipeline(new FakeReader(frames), translator, sender, clock: () => clock)
        {
            PackLookup = text => text == next ? new PackMatch("Yeni replik", [new SpokenLine(next, "Yeni replik")]) : null,
            ReadingScore = text => text.Length, LooksMisread = _ => false,
        };
        for (var i = 0; i < frames.Length; i++)
        {
            await pipeline.ProcessAsync(Image, new CropRegion());
            await pipeline.WaitForTranslationsAsync();
            if (i == frames.Length - 3) Assert.Contains("Yeni replik", sender.Sent);
            clock += 100;
        }
        Assert.Equal("Yeni replik", sender.Sent.Last());
        Assert.DoesNotContain(next, translator.Requested);
    }

    /// <summary>
    /// Temiz ama yarım görünen satır bekletilirken gelen bozuk okumalı yeni satır yok sayılıyordu; kararlayıcı onu
    /// gönderilmiş saydığı için ekranda kaldığı sürece bir daha hiç çevrilmiyordu. Bekleme bitince o da çevrilmeli.
    /// </summary>
    [Fact]
    public async Task MisreadLineArrivingDuringCleanHoldIsTranslatedLater()
    {
        const string held = "I told you to stay close", next = "Where is the bóat?";
        long clock = 0;
        var translator = new FakeTranslator();
        var sender = new FakeSender();
        var frames = Enumerable.Repeat(held, 2).Concat(Enumerable.Repeat(next, 20)).ToArray();
        var pipeline = new SubtitlePipeline(new FakeReader(frames), translator, sender, clock: () => clock)
        {
            PackLookup = _ => null, LooksMisread = text => text.Contains('ó'), ReadingScore = text => text.Length,
        };
        foreach (var _ in frames)
        {
            await pipeline.ProcessAsync(Image, new CropRegion());
            await pipeline.WaitForTranslationsAsync();
            clock += 100;
        }
        Assert.Equal([held, next], translator.Requested);
        Assert.Equal("TR: " + next, sender.Sent.Last());
    }
}
