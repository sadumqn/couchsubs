// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core.Dubbing;
using Xunit;

namespace CouchSubs.Core.Tests;

public class SpeechTextTests
{
    [Fact]
    public void EmotionComesFromTheEnglishLine()
    {
        Assert.Equal(SpeechEmotion.Angry, SpeechEmotions.Guess("Get back! This is not your fight."));
        Assert.Equal(SpeechEmotion.Surprised, SpeechEmotions.Guess("What?! The door opened by itself!"));
        Assert.Equal(SpeechEmotion.Sad, SpeechEmotions.Guess("I'm sorry. I couldn't save her."));
        Assert.Equal(SpeechEmotion.Happy, SpeechEmotions.Guess("We did it! We're going home."));
        Assert.Equal(SpeechEmotion.Calm, SpeechEmotions.Guess("Breathe, boy. Take your time."));
        Assert.Null(SpeechEmotions.Guess("We need to cross the river."));
    }

    [Fact]
    public void EverySentenceStartsLowercaseWithTheTagFirst()
    {
        Assert.Equal("[kızgın] geri çekil!", SpeechText.Prepare("Geri çekil!", SpeechEmotion.Angry));
        Assert.Equal("ileri gidelim. hemen...", SpeechText.Prepare("İleri gidelim.  Hemen…"));
        Assert.Equal("ışığı kapat.", SpeechText.Prepare("Işığı kapat."));
        Assert.Equal("ne? kapı açıldı!", SpeechText.Prepare("Ne?! Kapı açıldı!!"));
    }

    /// <summary>Hızlı dublajda (Windows'un kendi sesi) duygu etiketi okunmaz.</summary>
    [Fact]
    public void SystemVoiceDoesNotReadTheEmotionTag()
    {
        Assert.Equal("geri çekil!", SpeechText.WithoutEmotion(SpeechText.Prepare("Geri çekil!", SpeechEmotion.Angry)));
        Assert.Equal("[not] bir etiket", SpeechText.WithoutEmotion("[not] bir etiket"));
        Assert.Equal("düz cümle.", SpeechText.WithoutEmotion("düz cümle."));
    }

    [Fact]
    public void NumbersAreSpelledOut()
    {
        Assert.Equal("bin iki yüz elli", TurkishNumbers.Words(1250));
        Assert.Equal("iki milyon yüz beş", TurkishNumbers.Words(2_000_105));
        Assert.Equal("yüz", TurkishNumbers.Words(100));
        Assert.Equal("üç kapı, yüzde yirmi şans, saat on dört otuz, üç virgül beş metre, bin beş yüz altın",
            TurkishNumbers.SpellOut("3 kapı, %20 şans, saat 14:30, 3,5 metre, 1.500 altın"));
        Assert.Equal("dokuz sıfır beş", TurkishNumbers.SpellOut("09:05"));
    }
}

public class VoiceCastTests
{
    [Fact]
    public void EachCharacterKeepsItsVoice()
    {
        var cast = new VoiceCast();
        var kratos = cast.VoiceFor(new SpokenLine("", "", "KRATOS"), out var assigned);
        Assert.True(assigned);
        var freya = cast.VoiceFor(new SpokenLine("", "", "Freya"), out _);
        var atreus = cast.VoiceFor(new SpokenLine("", "", "ATREUS"), out _);
        Assert.Equal(VoiceGender.Male, kratos.Gender());
        Assert.Equal(VoiceGender.Female, freya.Gender());
        Assert.Equal(VoiceGender.Male, atreus.Gender());
        Assert.NotEqual(kratos, atreus);
        Assert.NotEqual(cast.Narrator, kratos);
        Assert.Equal(kratos, cast.VoiceFor(new SpokenLine("", "", "Kratos"), out assigned));
        Assert.False(assigned);
    }

    [Fact]
    public void DashedTurnsAlternateVoices()
    {
        var cast = new VoiceCast();
        var first = cast.VoiceFor(new SpokenLine("", "", NewTurn: true), out _);
        var second = cast.VoiceFor(new SpokenLine("", "", NewTurn: true), out _);
        Assert.NotEqual(first, second);
        Assert.Equal(second, cast.VoiceFor(new SpokenLine("", ""), out _));
    }

    [Fact]
    public void ManualChoiceIsSaved()
    {
        var cast = new VoiceCast();
        cast.Assign(DubbingVoice.Female3, "Mimir");
        var restored = JsonSerializer.Deserialize<VoiceCast>(JsonSerializer.Serialize(cast))!;
        Assert.Equal(DubbingVoice.Female3, restored.VoiceFor(new SpokenLine("", "", "MIMIR"), out _));
        Assert.Contains("\"Female3\"", JsonSerializer.Serialize(cast));
    }
}

public class SpeechAudioTests
{
    private static float[] Tone(double seconds) =>
        Enumerable.Range(0, (int)(seconds * 24000)).Select(i => MathF.Sin(i * 0.1f) * 0.5f).ToArray();

    private static float[] Silence(double seconds) => new float[(int)(seconds * 24000)];

    [Fact]
    public void LongPausesAreShortenedTo200Ms()
    {
        var audio = new SpeechAudio([.. Silence(0.2), .. Tone(0.3), .. Silence(0.4), .. Tone(0.3), .. Silence(0.5)], 24000);
        Assert.Equal(0.91, audio.Tightened().Duration, 0.03);
    }

    [Fact]
    public void ShortPausesStay()
    {
        var audio = new SpeechAudio([.. Tone(0.3), .. Silence(0.1), .. Tone(0.3)], 24000);
        Assert.Equal(audio.Duration, audio.Tightened(lead: 0, tail: 0).Duration, 0.02);
    }

    [Fact]
    public void WavRoundTripAndStreamedSize()
    {
        var wav = new SpeechAudio([0f, 0.5f, -0.5f, 0.25f], 24000).ToWav();
        var decoded = SpeechAudio.FromWav(wav);
        Assert.Equal(24000, decoded.SampleRate);
        Assert.Equal(4, decoded.Samples.Length);
        Assert.Equal(0.5f, decoded.Samples[1], 0.001f);
        wav[40] = wav[41] = wav[42] = wav[43] = 0xFF;
        Assert.Equal(4, SpeechAudio.FromWav(wav).Samples.Length);
    }
}

public class DubbingModelTests
{
    [Fact]
    public void LocalConfigPointsAtDownloadedFiles()
    {
        const string original = "weights_path: hf://wite-tech/pocket-tts-turkish/model.safetensors\r\nflow_lm:\r\n  lookup_table:\r\n" +
                                "    tokenizer_path: hf://wite-tech/pocket-tts-turkish/tokenizer.model\r\n";
        var directory = Path.Combine("C:", "Users", "Ali's PC", "dubbing");
        var local = DubbingModel.LocalConfig(original, directory);
        Assert.Contains("weights_path: '" + Path.Combine(directory, "model.safetensors").Replace("'", "''") + "'", local);
        Assert.Contains("    tokenizer_path: '", local);
        Assert.EndsWith("capitalize_first_letter: false\n", local);
    }
}

public class PocketTtsExitTests
{
    [Fact]
    public void ExitMessageShowsTheLastErrorLine()
    {
        var message = PocketTtsServer.ExitMessage(1, new Queue<string>(["loading model", "Error: model.safetensors not found"]));
        Assert.Equal("pocket-tts kapandı (çıkış kodu 1): Error: model.safetensors not found", message);
    }

    [Fact]
    public void ExitMessageWithoutOutputKeepsTheExitCode()
    {
        Assert.Equal("pocket-tts kapandı (çıkış kodu 3)", PocketTtsServer.ExitMessage(3, new Queue<string>()));
    }
}

public class NativeToolPathTests
{
    private const string Tokenizer = @"C:\Users\Şafak\AppData\Local\CouchSubs\models\tts-tr\rev\tokenizer.model";
    private const string Short = @"C:\Users\AFAK~1\AppData\Local\CouchSubs\models\tts-tr\rev\TOKENI~1.MOD";

    [Fact]
    public void AsciiPathIsKept()
    {
        const string path = @"C:\Users\Ali\AppData\Local\CouchSubs\models\tts-tr\rev\tokenizer.model";
        Assert.Equal(path, NativeToolPath.Resolve(path, _ => throw new InvalidOperationException()));
    }

    [Fact]
    public void NonAsciiPathUsesTheShortName()
    {
        var copied = false;
        var result = NativeToolPath.Tokenizer(Tokenizer, _ => Short, [@"C:\ProgramData"], (_, _) => copied = true);
        Assert.Equal(Short, result);
        Assert.False(copied);
    }

    [Fact]
    public void WithoutShortNamesTheTokenizerIsCopiedToAnAsciiFolder()
    {
        // 8.3 adları kapalı sürücüde kısa ad uzun adla aynı döner.
        string? from = null, to = null;
        var result = NativeToolPath.Tokenizer(Tokenizer, path => path, [@"C:\ProgramData"],
            (source, target) => (from, to) = (source, target));
        var expected = Path.Combine(@"C:\ProgramData", "CouchSubs", "models", "tts-tr", DubbingModel.Revision, "tokenizer.model");
        Assert.Equal(expected, result);
        Assert.Equal(Tokenizer, from);
        Assert.Equal(expected, to);
        Assert.True(NativeToolPath.IsAscii(result));
    }

    [Fact]
    public void NonAsciiOrUnwritableRootsAreSkipped()
    {
        var result = NativeToolPath.Tokenizer(Tokenizer, _ => null, [null, @"D:\Veri\Şafak", @"C:\ProgramData", @"C:\Users\Public"],
            (_, target) =>
            {
                if (target.StartsWith(@"C:\ProgramData", StringComparison.Ordinal)) throw new UnauthorizedAccessException();
            });
        Assert.StartsWith(@"C:\Users\Public", result);
    }

    [Fact]
    public void WithNoUsableRootTheOriginalPathIsReturned()
    {
        Assert.Equal(Tokenizer, NativeToolPath.Tokenizer(Tokenizer, _ => null, [], (_, _) => { }));
    }

    [Fact]
    public void LocalConfigUsesTheGivenTokenizerPath()
    {
        const string original = "weights_path: x\nflow_lm:\n  lookup_table:\n    tokenizer_path: y\n";
        var local = DubbingModel.LocalConfig(original, @"C:\Users\Şafak\models", Short);
        Assert.Contains("    tokenizer_path: '" + Short + "'", local);
        Assert.Contains("Şafak", local);
    }
}
