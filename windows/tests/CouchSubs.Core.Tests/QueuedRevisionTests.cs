// SPDX-License-Identifier: AGPL-3.0-only
namespace CouchSubs.Core.Tests;

public class QueuedRevisionTests
{
    private sealed class Translator : ITextTranslator
    {
        private readonly GatedTranslator gate = new();
        public List<string> Requested => gate.Requested;
        public void Open() => gate.Open();
        public static string Result(string text) => text == Full ? "Bu gerçekten çılgınca." : text == Short ? "Kuşlar gibi uçmak mı?" : "Kapıyı tut.";
        public async Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
        { await gate.TranslateAsync(text, cancellationToken); return Result(text); }
    }

    private const string Full = "Huh? Jumping out of airplanes, flying like birds? Fuck, that is crazy.";
    private const string Short = "Huh? Jumping out of airplanes, flying like birds?";

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ShorterReadingDoesNotEraseQueuedFullLine(bool returns)
    {
        long clock = 0;
        var translator = new Translator();
        var sender = new FakeSender();
        var log = new List<string>();
        var texts = new[] { "Hold the gate.", Full, Short }.Concat(returns ? new[] { Full } : []).ToArray();
        var pipeline = new SubtitlePipeline(new FakeReader(texts), translator, sender, clock: () => clock)
        { HoldWithoutPacks = true, PackWait = 0, CleanWait = 0, Log = log.Add };
        try
        {
            foreach (var _ in texts) { await pipeline.ProcessAsync(Frame.Blank(64, 64), new CropRegion()); clock += 100; }
        }
        finally { translator.Open(); await pipeline.WaitForTranslationsAsync(); }
        Assert.True(translator.Requested.Contains(Full), string.Join("\n", log));
        Assert.Contains(Translator.Result(Full), sender.Sent);
        if (returns) Assert.Equal(new[] { "Hold the gate.", Full }, translator.Requested);
    }
    [Theory]
    [InlineData("Run! Wait here.", "Run!")]
    [InlineData("I swear to God, you kill me!", "You kill me!")]
    [InlineData("Hold your fire until I return.", "Get down!")]
    public async Task GenuineShortLineKeepsBothQueuedUtterances(string full, string next)
    {
        var requested = await Replay(full, next);
        Assert.Equal(new[] { "Hold the gate.", full, next }, requested);
    }

    [Theory]
    [InlineData("We have 5 minutes left.", "We have 1 minute left.")]
    [InlineData("Meet me at 06:40.", "Meet me at 06:50.")]
    [InlineData("I can do that for you right now.", "I can't do that for you right now.")]
    [InlineData("We have time to wait.", "We have no time to wait.")]
    [InlineData("We do not have...", "We do not have time.")]
    public async Task CorrectedReadingReplacesOlderQueuedReading(string old, string corrected)
    {
        var requested = await Replay(old, corrected);
        Assert.Equal(new[] { "Hold the gate.", corrected }, requested);
    }

    [Fact]
    public async Task FullReadingReturningAfterRestoreWindowStillCoalescesTheQueue()
    {
        var readings = new[] { Full }.Concat(Enumerable.Repeat(Short, 18)).Append(Full).ToArray();
        Assert.Equal(new[] { "Hold the gate.", Full }, await Replay(readings));
    }

    [Fact]
    public async Task ConfirmedBlankKeepsTheInterveningShortUtterance()
    {
        var readings = new[] { Full, Short }.Concat(Enumerable.Repeat("", 12)).Append(Full).ToArray();
        Assert.Equal(new[] { "Hold the gate.", Full, Short }, await Replay(readings));
    }

    private static async Task<List<string>> Replay(params string[] readings)
    {
        long clock = 0;
        var translator = new Translator();
        var texts = new[] { "Hold the gate." }.Concat(readings).ToArray();
        var pipeline = new SubtitlePipeline(new FakeReader(texts), translator, new FakeSender(), clock: () => clock)
        { HoldWithoutPacks = true, PackWait = 0, CleanWait = 0 };
        try
        {
            foreach (var _ in texts) { await pipeline.ProcessAsync(Frame.Blank(64, 64), new CropRegion()); clock += 100; }
        }
        finally { translator.Open(); await pipeline.WaitForTranslationsAsync(); }
        return translator.Requested;
    }

}
