// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Deneme modu (Mac/iPhone DemoModeTests.swift ile aynı vektörler): senaryo, zamanlama, hazır çeviri, hat.</summary>
public class DemoModeTests
{
    /// <summary>Yazı tanıma yerine: hep aynı satırı "okur".</summary>
    private sealed class SameLineReader(string text) : ITextReader
    {
        public string Read(Frame image) => text;
    }

    /// <summary>Modeli indirilmemiş ücretsiz çeviri gibi davranır.</summary>
    private sealed class MissingModelTranslator : ITextTranslator
    {
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
            throw new TranslatorException(TranslatorStatus.NeedsDownload);
    }

    private sealed class EchoTranslator : ITextTranslator
    {
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) => Task.FromResult("motor: " + text);
    }

    private sealed class EmptyTranslator : ITextTranslator
    {
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) => Task.FromResult("  ");
    }

    [Fact]
    public void ScriptHasEnoughLinesWithTurkish()
    {
        Assert.InRange(DemoScript.Lines.Count, 10, 15);
        foreach (var line in DemoScript.Lines.Append(DemoScript.Objective))
        {
            Assert.NotEmpty(line.Turkish);
            foreach (var brand in new[] { "PS5", "PlayStation", "Sony", "Xbox" }) Assert.DoesNotContain(brand, line.English);
        }
    }

    /// <summary>Satırlar ve Türkçeleri core (Demo/DemoMode.swift) ve Android (DemoScript.kt) ile birebir aynıdır.</summary>
    [Fact]
    public void ScriptMatchesTheSharedLines()
    {
        Assert.Equal(12, DemoScript.Lines.Count);
        Assert.Equal(new DemoScript.Line("We should reach the lighthouse before dark.", "Hava kararmadan deniz fenerine varmalıyız."), DemoScript.Lines[0]);
        Assert.Equal(new DemoScript.Line("I found a map in the old captain's cabin.", "Yaşlı kaptanın kamarasında bir harita buldum."), DemoScript.Lines[3]);
        Assert.Equal(new DemoScript.Line("Rest now. Tomorrow will be a long day.", "Şimdi dinlen. Yarın uzun bir gün olacak."), DemoScript.Lines[11]);
        Assert.Equal(new DemoScript.Line("Objective: Reach the lighthouse", "Görev: Deniz fenerine ulaş"), DemoScript.Objective);
        Assert.Equal((1280, 720, 0.86), (DemoFrames.Width, DemoFrames.Height, DemoFrames.SubtitleBaseline));
    }

    /// <summary>core'daki Swift kaynağıyla satır satır karşılaştırır (depo içinde çalışırken); satır eklenip unutulmasın.</summary>
    [Fact]
    public void ScriptIsTheSameAsTheSwiftSource()
    {
        var folder = AppContext.BaseDirectory;
        string? source = null;
        for (var up = 0; up < 10 && folder is not null; up++, folder = Path.GetDirectoryName(folder))
        {
            var candidate = Path.Combine(folder, "core", "Sources", "CouchSubsCore", "Demo", "DemoMode.swift");
            if (File.Exists(candidate)) { source = File.ReadAllText(candidate); break; }
        }
        if (source is null) return;
        var pairs = System.Text.RegularExpressions.Regex.Matches(source, "Line\\(english: \"([^\"]+)\", turkish: \"([^\"]+)\"\\)")
            .Select(match => new DemoScript.Line(match.Groups[1].Value, match.Groups[2].Value)).ToList();
        Assert.Equal(DemoScript.Lines.Append(DemoScript.Objective).ToList(), pairs);
        var defaults = new DemoFrameSource(DemoFrames.Plain);
        Assert.Contains($"lineSeconds: Double = {defaults.LineSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture)}", source);
        Assert.Contains($"gapSeconds: Double = {defaults.GapSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture)}", source);
        Assert.Contains($"framesPerSecond: Double = {defaults.FramesPerSecond.ToString(System.Globalization.CultureInfo.InvariantCulture)}", source);
    }

    [Fact]
    public void ScheduleShowsLinesInTurnWithGaps()
    {
        var source = new DemoFrameSource(DemoFrames.Plain, lineSeconds: 3, gapSeconds: 1);
        Assert.Null(source.LineIndex(0.5));
        Assert.Equal(0, source.LineIndex(1.5));
        Assert.Null(source.LineIndex(4.5));
        Assert.Equal(1, source.LineIndex(5.5));
        Assert.Equal(0, source.LineIndex(1 + (4 * DemoScript.Lines.Count) + 0.5));
    }

    [Fact]
    public async Task SourceDeliversFramesAndAsksForEachLineOnce()
    {
        var asked = new List<(int? Line, int Scene)>();
        var source = new DemoFrameSource((line, scene) =>
        {
            lock (asked) asked.Add((line, scene));
            return Frame.Blank(DemoFrames.Width, DemoFrames.Height);
        }, lineSeconds: 0.2, gapSeconds: 0.05, framesPerSecond: 40);
        var got = new TaskCompletionSource<Frame>(TaskCreationOptions.RunContinuationsAsynchronously);
        var frames = 0;
        source.FrameReady += frame =>
        {
            // Birkaç kare aynı satırı gösterir; çizim satır başına bir kez istenir.
            if (Interlocked.Increment(ref frames) >= 12) got.TrySetResult(frame);
        };
        source.Start();
        Assert.True(source.IsRunning);
        var frame = await got.Task.WaitAsync(TimeSpan.FromSeconds(5));
        source.Stop();
        Assert.False(source.IsRunning);
        Assert.Equal(DemoFrames.Width, frame.Width);
        lock (asked)
        {
            // İlk kare altyazısızdır, ardından ilk satır gelir; aynı satır art arda yeniden çizilmez.
            Assert.Equal(((int?)null, 0), asked[0]);
            Assert.Equal(((int?)0, 0), asked[1]);
            Assert.True(asked.Count < frames);
            for (var i = 1; i < asked.Count; i++) Assert.NotEqual(asked[i - 1].Line, asked[i].Line);
        }
    }

    [Fact]
    public async Task SourceKeepsTheLastFrameWhenDrawingFails()
    {
        var calls = 0;
        var good = Frame.Blank(8, 8);
        var source = new DemoFrameSource((_, _) => Interlocked.Increment(ref calls) == 1 ? good : throw new InvalidOperationException(),
            lineSeconds: 0.05, gapSeconds: 0.05, framesPerSecond: 50);
        var got = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var wrong = false;
        source.FrameReady += frame =>
        {
            if (!ReferenceEquals(frame, good)) wrong = true;
            if (Volatile.Read(ref calls) >= 3) got.TrySetResult();
        };
        source.Start();
        await got.Task.WaitAsync(TimeSpan.FromSeconds(5));
        source.Stop();
        Assert.False(wrong);
    }

    [Fact]
    public void TableTranslatesReadingsWithOcrSlips()
    {
        Assert.Equal(DemoScript.Lines[0].Turkish, DemoScript.Translation(DemoScript.Lines[0].English));
        Assert.Equal(DemoScript.Lines[0].Turkish, DemoScript.Translation("We should reach the lighthouse before dark"));
        Assert.Equal(DemoScript.Lines[0].Turkish, DemoScript.Translation("We shou1d reach the lighthouse before dark."));
        Assert.Equal(DemoScript.Objective.Turkish, DemoScript.Translation(DemoScript.Objective.English));
        Assert.Null(DemoScript.Translation("Completely different text"));
        Assert.Null(DemoScript.Translation("  "));
    }

    [Fact]
    public async Task TranslatorUsesEngineAndFallsBackToTable()
    {
        var line = DemoScript.Lines[3];
        Assert.Equal("motor: " + line.English, await new DemoTranslator(new EchoTranslator()).TranslateAsync(line.English));
        Assert.Equal(line.Turkish, await new DemoTranslator(new MissingModelTranslator()).TranslateAsync(line.English));
        Assert.Equal(line.Turkish, await new DemoTranslator(new EmptyTranslator()).TranslateAsync(line.English));
        Assert.Equal(line.Turkish, await new DemoTranslator(null).TranslateAsync(line.English));
        Assert.Equal("Unknown line", await new DemoTranslator(null).TranslateAsync("Unknown line"));
        Assert.Equal(new[] { DemoScript.Objective.Turkish },
            await new DemoTranslator(new MissingModelTranslator()).TranslateAllAsync([DemoScript.Objective.English]));
        Assert.Equal(new[] { "motor: a", "motor: b" }, await new DemoTranslator(new EchoTranslator()).TranslateAllAsync(["a", "b"]));
    }

    [Fact]
    public async Task TranslatorDoesNotSwallowCancellation()
    {
        using var cancel = new CancellationTokenSource();
        cancel.Cancel();
        var translator = new DemoTranslator(new GatedTranslator());
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => translator.TranslateAsync(DemoScript.Lines[0].English, cancel.Token));
    }

    /// <summary>Deneme karesi gerçek hattan geçer: okunan satır çevrilip TV'ye gider (model inmemiş olsa da).</summary>
    [Fact]
    public async Task PipelineTranslatesAndShowsADemoLine()
    {
        var clock = new TestClock();
        var line = DemoScript.Lines[1];
        var sender = new FakeSender();
        var pipeline = new SubtitlePipeline(new SameLineReader(line.English), new DemoTranslator(new MissingModelTranslator()), sender,
            clock: () => clock.Now) { PackWait = 0, CleanWait = 0 };
        var frame = Frame.Blank(DemoFrames.Width, DemoFrames.Height);
        for (var i = 0; i < 8; i++)
        {
            await pipeline.ProcessAsync(frame, new CropRegion());
            clock.Now += 200;
        }
        await pipeline.WaitForTranslationsAsync();
        Assert.Contains(sender.Sent, text => text.Contains(line.Turkish));
        Assert.Equal(line.Turkish, pipeline.LastPair?.Translation);
    }
}
