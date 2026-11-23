// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

[Collection(nameof(SubtitleLog))]
public class FallbackTextReaderTests
{
    private static readonly Frame Image = new(new byte[16 * 16 * 4], 16, 16, 16 * 4);

    /// <summary>Sıradaki sonuç: metin ya da null (hata verir).</summary>
    private sealed class ScriptedReader(params string?[] results) : ITextReader
    {
        private readonly Queue<string?> results = new(results);
        public int Reads { get; private set; }
        public string Read(Frame image) => ReadLines(image, deep: true).Text;
        public Reading ReadLines(Frame image, bool deep)
        {
            Reads++;
            var next = results.Count > 0 ? results.Dequeue() : "";
            return next is null ? throw new InvalidOperationException("device removed") : Reading.FromText(next);
        }
    }

    [Fact]
    public void Primary_reads_while_it_works()
    {
        var primary = new ScriptedReader("Hello", "There");
        var fallback = new ScriptedReader("windows");
        var reader = new FallbackTextReader(primary, fallback);
        Assert.Equal("Hello", reader.ReadLines(Image, deep: false).Text);
        Assert.Equal("There", reader.Read(Image));
        Assert.Equal(0, fallback.Reads);
        Assert.False(reader.FellBack);
    }

    [Fact]
    public void A_failed_frame_is_read_by_the_fallback_and_a_success_resets_the_count()
    {
        var primary = new ScriptedReader(null, null, "ok", null, null, "ok2");
        var fallback = new ScriptedReader("w1", "w2", "w3", "w4");
        var released = 0;
        var reader = new FallbackTextReader(primary, fallback, () => released++);
        Assert.Equal("w1", reader.Read(Image));
        Assert.Equal("w2", reader.Read(Image));
        Assert.Equal("ok", reader.Read(Image));
        Assert.Equal("w3", reader.Read(Image));
        Assert.Equal("w4", reader.Read(Image));
        Assert.Equal("ok2", reader.Read(Image));
        Assert.False(reader.FellBack);
        Assert.Equal(0, released);
    }

    [Fact]
    public void Consecutive_failures_release_the_primary_once_and_switch_for_good()
    {
        var primary = new ScriptedReader(null, null, null, "never");
        var fallback = new ScriptedReader("w1", "w2", "w3", "w4", "w5");
        var released = 0;
        var reader = new FallbackTextReader(primary, fallback, () => released++);
        for (var i = 1; i <= FallbackTextReader.Threshold; i++) Assert.Equal($"w{i}", reader.Read(Image));
        Assert.True(reader.FellBack);
        Assert.Equal(1, released);

        Assert.Equal("w4", reader.Read(Image));
        Assert.Equal("w5", reader.ReadLines(Image, deep: true).Text);
        Assert.Equal(FallbackTextReader.Threshold, primary.Reads);
        Assert.Equal(1, released);
    }

    [Fact]
    public void Without_a_fallback_failures_read_nothing_instead_of_throwing()
    {
        var reader = new FallbackTextReader(new ScriptedReader(null, null, null), fallback: null);
        for (var i = 0; i < FallbackTextReader.Threshold + 1; i++) Assert.Same(Reading.Empty, reader.ReadLines(Image, deep: true));
        Assert.True(reader.FellBack);
    }

    [Fact]
    public void A_failing_release_still_switches_to_the_fallback()
    {
        var reader = new FallbackTextReader(new ScriptedReader(null, null, null), new ScriptedReader("a", "b", "c", "d"),
            () => throw new ObjectDisposedException("engine"));
        for (var i = 0; i < FallbackTextReader.Threshold; i++) reader.Read(Image);
        Assert.True(reader.FellBack);
        Assert.Equal("d", reader.Read(Image));
    }

    [Fact]
    public void Failures_and_the_switch_are_written_to_the_subtitle_log()
    {
        var folder = Path.Combine(Path.GetTempPath(), "altyazi-log-" + Guid.NewGuid());
        var file = Path.Combine(folder, "altyazi.log");
        try
        {
            SubtitleLog.Enable(file);
            var reader = new FallbackTextReader(new ScriptedReader(null, null, null), new ScriptedReader());
            for (var i = 0; i < FallbackTextReader.Threshold; i++) reader.Read(Image);
            SubtitleLog.Disable();
            var text = File.ReadAllText(file);
            Assert.Contains("gelişmiş yazı tanıma hata verdi (1/3)", text);
            Assert.Contains("gelişmiş yazı tanıma 3 kez art arda hata verdi, bırakıldı; bu oturumun geri kalanında Windows'un yazı tanıması okuyor", text);
            Assert.Contains("InvalidOperationException: \"device removed\"", text);
        }
        finally
        {
            SubtitleLog.Disable();
            if (Directory.Exists(folder)) Directory.Delete(folder, recursive: true);
        }
    }
}
