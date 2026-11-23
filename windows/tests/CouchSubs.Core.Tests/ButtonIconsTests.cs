// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Oyun ipuçlarındaki kumanda simgeleri ("Hold △ to sprint"): yazı tanıma simgeyi harf sanıyor ("A", "Ä"), çeviri
/// simgeyi örtüyor ve Türkçede neye basılacağı kalmıyordu. Sözcük yerleri Windows yazı tanımasının 1280×200'lük gerçek
/// okumalarından alındı (simgeli ipucu görüntüleri).
/// </summary>
public class ButtonIconsTests
{
    private const int Width = 1280, Height = 200;
    private const char M = ButtonIcons.Marker;

    private static TextWord Word(string text, double x, double w, double y, double h) =>
        new(text, new TextBox(x / Width, y / Height, (x + w) / Width, (y + h) / Height));

    private static TextLine Line(params TextWord[] words)
    {
        var box = words.Skip(1).Aggregate(words[0].Box, (a, b) => a.Union(b.Box));
        return new TextLine(string.Join(' ', words.Select(word => word.Text)), box, Words: words);
    }

    // "Hold △ to sprint.": △ "A" okundu.
    private static readonly TextLine Hold = Line(Word("Hold", 48, 75, 89, 31), Word("A", 138, 29, 90, 27),
                                                 Word("to", 202, 34, 91, 25), Word("sprint.", 249, 99, 84, 39));

    /// <summary>Koyu zeminde beyaz "yazı" blokları ve (135–182, 79–126) arasında yuvarlak bir simge.</summary>
    private static Frame HoldFrame()
    {
        var frame = Frame.Blank(Width, Height);
        Fill(frame, 0, 0, Width, Height, (52, 44, 40));
        Fill(frame, 48, 89, 123, 120, (255, 255, 255)); // Hold
        Fill(frame, 202, 91, 236, 116, (255, 255, 255)); // to
        Fill(frame, 249, 84, 348, 123, (255, 255, 255)); // sprint.
        for (var y = 79; y < 126; y++)
            for (var x = 135; x < 182; x++)
                if (Math.Pow(x - 158.5, 2) + Math.Pow(y - 102.5, 2) <= 23.5 * 23.5) Set(frame, x, y, (0, 0, 0));
        return frame;
    }

    private static void Fill(Frame frame, int x0, int y0, int x1, int y1, (byte B, byte G, byte R) color)
    {
        for (var y = y0; y < y1; y++)
            for (var x = x0; x < x1; x++) Set(frame, x, y, color);
    }

    private static void Set(Frame frame, int x, int y, (byte B, byte G, byte R) color)
    {
        var i = (y * frame.Stride) + (x * 4);
        (frame.Pixels[i], frame.Pixels[i + 1], frame.Pixels[i + 2], frame.Pixels[i + 3]) = (color.B, color.G, color.R, 255);
    }

    private static (int Width, int Height) PngSize(string dataUri)
    {
        var bytes = Convert.FromBase64String(dataUri["data:image/png;base64,".Length..]);
        static int Read(byte[] b, int at) => (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
        return (Read(bytes, 16), Read(bytes, 20));
    }

    [Fact]
    public void IconReadAsALetterAfterAVerbIsMarked()
    {
        var marked = ButtonIcons.Mark(Hold);
        Assert.Equal($"Hold {M} to sprint.", marked.Text);
        var icon = Assert.Single(marked.Icons!);
        Assert.Equal("A", icon.Text);
        // Kutu simgenin tamamını içine alır (komşu sözcüklerle arasındaki boşlukların ortasına kadar).
        Assert.True(icon.Box.Left * Width <= 135 && icon.Box.Right * Width >= 182);
        Assert.True(icon.Box.Top * Height <= 79 && icon.Box.Bottom * Height >= 126);
    }

    [Fact]
    public void IconGluedToTheVerbIsSplitOff()
    {
        // "Press [R2] to open the weapon wheel." → "PressÄ"
        var line = Line(Word("PressÄ", 49, 148, 71, 41), Word("to", 223, 33, 80, 24), Word("open", 269, 80, 85, 28),
                        Word("the", 362, 52, 76, 28), Word("weapon", 425, 127, 85, 28), Word("wheel.", 565, 101, 76, 28));
        var marked = ButtonIcons.Mark(line);
        Assert.Equal($"Press {M} to open the weapon wheel.", marked.Text);
        Assert.Equal("Ä", Assert.Single(marked.Icons!).Text);
    }

    [Fact]
    public void SeveralIconsInOneHintAreMarked()
    {
        // "Use [stick] to move the camera and [△] to interact." → "Useo ... and A to interact."
        var line = Line(Word("Useo", 48, 94, 69, 41), Word("to", 164, 27, 80, 21), Word("move", 204, 76, 85, 16),
                        Word("the", 291, 44, 77, 24), Word("camera", 346, 100, 85, 16), Word("and", 458, 50, 77, 24),
                        Word("A", 527, 26, 76, 24), Word("to", 582, 29, 80, 21), Word("interact.", 623, 110, 78, 23));
        var marked = ButtonIcons.Mark(line);
        Assert.Equal($"Use {M} to move the camera and {M} to interact.", marked.Text);
        Assert.Equal(["o", "A"], marked.Icons!.Select(icon => icon.Text));
    }

    [Fact]
    public void UnreadIconLeavesAGapAfterTheVerb()
    {
        // Beyaz yazı süzgecinde simge kaybolur: "Hold" ile "to" arasında birkaç harflik boşluk kalır.
        var line = Line(Word("Hold", 48, 75, 89, 31), Word("to", 202, 34, 91, 25), Word("sprint.", 249, 99, 84, 39));
        var marked = ButtonIcons.Mark(line);
        Assert.Equal($"Hold {M} to sprint.", marked.Text);
        Assert.Equal("", Assert.Single(marked.Icons!).Text);
    }

    [Theory]
    [InlineData("I'll use a rope to climb down.")]
    [InlineData("Press the button to continue.")]
    [InlineData("Hold on, Arthur.")]
    [InlineData("He uses the map, and I follow.")]
    [InlineData("A New Quest")]
    [InlineData("Use it wisely.")]
    public void OrdinaryTextIsLeftAlone(string text)
    {
        // Sözcük yerleri bilinmiyor: harf sayısına göre kestirilir.
        var line = new TextLine(text, new TextBox(0.1, 0.4, 0.6, 0.45));
        Assert.Same(line, ButtonIcons.Mark(line));
    }

    [Fact]
    public void WithoutWordPositionsTheIconIsStillFoundByItsPlaceInTheText()
    {
        // Okuyucu yalnız satırın kutusunu veriyor.
        var marked = ButtonIcons.Mark(new TextLine("Hold A to sprint.", new TextBox(0.1, 0.4, 0.6, 0.45)));
        Assert.Equal($"Hold {M} to sprint.", marked.Text);
    }

    [Fact]
    public void IconRecognisedAsASymbolIsTranslatedInsteadOfDroppedAsAPrompt()
    {
        // PaddleOCR simgeyi tanıyor: "Hold △ to sprint." eskiden kumanda ipucu sayılıp hiç çevrilmiyordu.
        var line = new TextLine("Hold △ to sprint.", new TextBox(39.0 / Width, 0.4, 356.0 / Width, 0.62));
        var lines = new Reading([line]).WithButtonIcons().WithoutButtonPrompts().Lines;
        Assert.Equal($"Hold {M} to sprint.", Assert.Single(lines).Text);
    }

    [Theory]
    // #424'ün GTA 6 havuzundaki gerçek okumaları: fiil ile "to" arasındaki tuş kalıntıları simgedir.
    [InlineData("Press @ to open the map", "Press ￼ to open the map", new[] { "@" })]
    [InlineData("Hold I LI to open your loadout", "Hold ￼ to open your loadout", new[] { "I LI" })]
    [InlineData("Press RE to go back to your weapons and equipment", "Press ￼ to go back to your weapons and equipment", new[] { "RE" })]
    [InlineData("Press (9 0 to stop focusing", "Press ￼ to stop focusing", new[] { "(9 0" })]
    [InlineData("Release 2 and R2 to breathe out", "Release ￼ and ￼ to breathe out", new[] { "2", "R2" })]
    [InlineData("Press [RB] to take cover", "Press ￼ to take cover", new[] { "[RB]" })]
    public void IconRemnantsFromTheHintPoolBecomeIcons(string read, string marked, string[] icons)
    {
        var line = ButtonIcons.Mark(new TextLine(read, new TextBox(0.1, 0.4, 0.6, 0.45)));
        Assert.Equal(marked, line.Text);
        Assert.Equal(icons, line.Icons!.Select(icon => icon.Text));
    }

    [Fact]
    public void HintWhoseIconWasFoundIsTranslatedButOtherwiseStillDropped()
    {
        // Ekranı çevir/ek alan: simge bulunduysa satır kalır (simgesiyle çevrilir).
        var line = new TextLine("Press @ to open the map", new TextBox(0.1, 0.4, 0.6, 0.45));
        Assert.Single(new Reading([line]).WithButtonIcons().WithoutButtonPrompts().Lines);
        // Ana altyazı simge aramaz: #424'teki gibi ipucu atılır.
        Assert.Empty(new Reading([line]).WithoutButtonPrompts().Lines);
    }

    [Theory]
    // #424'ün koruduğu konuşmalar simge sanılmaz.
    [InlineData("Press the button, Jason!")]
    [InlineData("Hold on to something.")]
    [InlineData("HOLD ON TO IT")]
    [InlineData("Use it to open the door.")]
    [InlineData("Jason: Press to the left")]
    [InlineData("Hold to your course")]
    public void SpeechKeptByTheHintRuleIsNotMarked(string text)
    {
        var line = new TextLine(text, new TextBox(0.1, 0.4, 0.6, 0.45));
        Assert.Same(line, ButtonIcons.Mark(line));
    }

    [Fact]
    public void HintSplitAroundTheIconIsJoinedBack()
    {
        // PaddleOCR'ın gerçek okuması: "Press" | "R2" | "to open the weapon wheel." (x: 42-144, 125-179, 215-670).
        var reading = new Reading([
            new TextLine("Press", new TextBox(42.0 / Width, 70.0 / Height, 144.0 / Width, 114.0 / Height)),
            new TextLine("R2", new TextBox(125.0 / Width, 68.0 / Height, 179.0 / Width, 116.0 / Height)),
            new TextLine("to open the weapon wheel.", new TextBox(215.0 / Width, 72.0 / Height, 670.0 / Width, 112.0 / Height)),
        ]);
        var line = Assert.Single(reading.WithButtonIcons().Lines);
        Assert.Equal($"Press {M} to open the weapon wheel.", line.Text);
        Assert.Equal("R2", Assert.Single(line.Icons!).Text);
    }

    [Fact]
    public void SeparateLabelsOnOneRowAreNotJoined()
    {
        var reading = new Reading([
            new TextLine("Map", new TextBox(0.10, 0.9, 0.14, 0.93)),
            new TextLine("Inventory", new TextBox(0.16, 0.9, 0.24, 0.93)),
        ]);
        Assert.Same(reading, ButtonIcons.JoinHints(reading));
    }

    [Theory]
    [InlineData("△ Pick up")]
    [InlineData("L1 + R1 Spartan Rage")]
    [InlineData("PHOTO MODE L1 + R1")]
    public void ShortPromptsWithTheButtonAtAnEdgeStayUntranslated(string text)
    {
        // Bilerek çevrilmezler (ek alanda sürekli gelip giderler); örtülmedikleri için simge zaten görünür kalır.
        var line = new TextLine(text, new TextBox(0.1, 0.4, 0.4, 0.45));
        Assert.Empty(new Reading([line]).WithButtonIcons().WithoutButtonPrompts().Lines);
    }

    [Fact]
    public void ButtonAfterAVerbAtTheEndIsTranslatedWithTheVerb()
    {
        // "Hold △": yalnız "Hold" çevrilince "Tut" kalır; ad ile "△'yu basılı tut" olur.
        var marked = ButtonIcons.Mark(new TextLine("Hold △", new TextBox(0.1, 0.4, 0.3, 0.45)));
        Assert.Equal("Hold Feldor", IconText.Protect(marked.Text).Text);
    }

    [Fact]
    public void SingleLettersAtTheStartAreNotButtons()
    {
        // "A Pick up": "A" düğme de olabilir, tanım edatı da; tek harfe ancak fiilden sonra güvenilir.
        var line = new TextLine("A Pick up", new TextBox(0.1, 0.4, 0.3, 0.45));
        Assert.Same(line, ButtonIcons.Mark(line));
    }

    [Fact]
    public void PaddleCharacterPlacesGiveWordPositions()
    {
        // Zaman adımları: H(0-1) o(2) l(4) d(6) boşluk(8) ... boşluk t(20) o(22). "Hold" ile "to" arası simge.
        string[] characters = ["", "H", "o", "l", "d", "t", " "];
        var steps = new[] { 1, 1, 0, 2, 0, 3, 0, 4, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 5, 0, 2, 0 };
        var probabilities = steps.SelectMany(best => Enumerable.Range(0, characters.Length).Select(c => c == best ? 0.9f : 0.01f)).ToArray();
        var (text, _, places) = PaddleOcr.DecodeWithPlaces(probabilities, steps.Length, characters);
        Assert.Equal("Hold  to", text);
        var words = PaddleOcr.Words(places);
        Assert.Equal(["Hold", "to"], words.Select(word => word.Text));
        // Harf aralığı 2 adım: sözcükler ilk/son harf ortasından bir adım taşar.
        Assert.Equal((0.0, 8.5), (words[0].Left, words[0].Right));
        Assert.Equal((19.5, 23.5), (words[1].Left, words[1].Right));
    }

    [Fact]
    public void OcrNoiseCleaningKeepsTheMarker()
    {
        var reading = new Reading([ButtonIcons.Mark(Hold)]).WithoutOcrNoise();
        Assert.Equal($"Hold {M} to sprint.", reading.Lines[0].Text);
        Assert.Single(reading.Lines[0].Icons!);
    }

    [Fact]
    public void CropCutsTheIconTightlyOutOfTheFrame()
    {
        var icon = Assert.Single(ButtonIcons.Mark(Hold).Icons!);
        var image = ButtonIcons.Crop(HoldFrame(), icon.Box);
        Assert.NotNull(image);
        var (width, height) = PngSize(image!);
        // 47 piksellik simge + iki yanda 2 piksel pay; komşu sözcükler girmez.
        Assert.InRange(width, 47, 53);
        Assert.InRange(height, 47, 53);
    }

    [Fact]
    public void CropOfAnEmptyPlaceGivesNothing()
    {
        var frame = Frame.Blank(Width, Height);
        Fill(frame, 0, 0, Width, Height, (52, 44, 40));
        Assert.Null(ButtonIcons.Crop(frame, new TextBox(0.1, 0.3, 0.15, 0.6)));
    }

    [Fact]
    public void IconKeepsItsPlaceThroughTranslation()
    {
        var (text, names) = IconText.Protect($"Hold {M} to sprint.");
        Assert.Equal("Hold Feldor to sprint.", text);
        // Çevirmen ada Türkçe ek koyar; ek gerçek düğmenin adına uymayacağı için atılır.
        var restored = IconText.Restore("Koşmak için Feldor'u basılı tutun.", names, 0);
        var (plain, icons) = IconText.Render(restored, [new IconSlot(default, "A", "data:image/png;base64,AAAA")]);
        Assert.Equal("Koşmak için basılı tutun.", plain);
        Assert.Equal(12, Assert.Single(icons).At);
    }

    [Fact]
    public void TwoIconsKeepTheirOwnPlacesAndPunctuationStaysAttached()
    {
        var (text, names) = IconText.Protect($"Use {M} to move the camera and {M} to interact.");
        Assert.Equal("Use Feldor to move the camera and Halvor to interact.", text);
        // Türkçede sıra değişir; her ad kendi simgesine döner.
        var restored = IconText.Restore("Etkileşim için Halvor'u, kamerayı oynatmak için Feldor'u kullanın.", names, 0);
        IconSlot[] slots = [new(default, "o", "data:image/png;base64,STICK"), new(default, "A", "data:image/png;base64,TRI")];
        var (plain, icons) = IconText.Render(restored, slots);
        Assert.Equal("Etkileşim için, kamerayı oynatmak için kullanın.", plain);
        Assert.Equal([(14, "data:image/png;base64,TRI"), (39, "data:image/png;base64,STICK")], icons.Select(i => (i.At, i.Image)));
    }

    [Fact]
    public void CropIgnoresANeighbouringLetterThatFallsIntoTheBox()
    {
        var frame = HoldFrame();
        Fill(frame, 126, 96, 132, 118, (255, 255, 255)); // simgeye yakın bir harf
        var image = ButtonIcons.Crop(frame, new TextBox(120.0 / Width, 70.0 / Height, 186.0 / Width, 135.0 / Height));
        var (width, _) = PngSize(image!);
        Assert.InRange(width, 47, 53);
    }

    [Fact]
    public void DroppedPlaceholderPutsTheIconInFront()
    {
        var (_, names) = IconText.Protect($"Hold {M} to sprint.");
        var restored = IconText.Restore("Koşmak için basılı tutun.", names, 0);
        var (plain, icons) = IconText.Render(restored, [new IconSlot(default, "A", "data:image/png;base64,AAAA")]);
        Assert.Equal("Koşmak için basılı tutun.", plain);
        Assert.Equal(0, Assert.Single(icons).At);
    }

    [Fact]
    public void IconThatCouldNotBeCutFallsBackToTheReadText()
    {
        var restored = IconText.Restore("Koşmak için Feldor'u basılı tutun.", ["Feldor"], 0);
        var (plain, icons) = IconText.Render(restored, [new IconSlot(default, "A")]);
        Assert.Equal("Koşmak için A basılı tutun.", plain);
        Assert.Empty(icons);
    }

    private sealed class Translator(Func<string, string> translate) : ITextTranslator
    {
        public List<string> Calls { get; } = [];
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
        {
            lock (Calls) Calls.Add(text);
            return Task.FromResult(translate(text));
        }
    }

    [Fact]
    public async Task ScreenTranslationShowsTheButtonInsideTheTranslation()
    {
        var translator = new Translator(text => text == "Hold Feldor to sprint." ? "Koşmak için Feldor'u basılı tutun." : text);
        var items = await ScreenTranslation.TranslateAsync(new Reading([Hold]), translator, frame: HoldFrame());
        Assert.Equal(["Hold Feldor to sprint."], translator.Calls);
        var item = Assert.Single(items);
        Assert.Equal("Koşmak için basılı tutun.", item.Translation);
        Assert.Equal("Hold to sprint.", item.Source);
        var icon = Assert.Single(item.Icons!);
        Assert.Equal(12, icon.At);
        Assert.StartsWith("data:image/png;base64,", icon.Image);
    }

    private sealed class Reader(TextLine line) : ITextReader
    {
        public string Read(Frame image) => line.Text;
        public Reading ReadLines(Frame image, bool deep) => new([line]);
    }

    private sealed class Server : IRegionSender
    {
        public List<(string Text, IReadOnlyList<IconPlacement>? Icons)> Sent { get; } = [];
        public void SendRegion(string id, string text, TextBox? box, double? lineHeight = null) => Sent.Add((text, null));
        public void SendRegion(string id, string text, TextBox? box, double? lineHeight, IReadOnlyList<IconPlacement>? icons) =>
            Sent.Add((text, icons));
        public void ClearRegions() { }
    }

    [Fact]
    public async Task ExtraAreaShowsTheButtonInsideTheTranslation()
    {
        // Alan karenin tamamı: okunan alanın kutuları kareyle aynı.
        var area = new WatchedArea("tip", "Tip", new CropRegion(Top: 0, Bottom: 1, Left: 0, Right: 1));
        var server = new Server();
        var translator = new Translator(text => text == "Hold Feldor to sprint." ? "Koşmak için Feldor'u basılı tutun." : text);
        var watcher = new RegionWatcher(new Reader(Hold), translator, server);
        var frame = HoldFrame();
        await watcher.PassAsync(frame, [area]);
        await watcher.PassAsync(frame, [area]);
        var (text, icons) = Assert.Single(server.Sent);
        Assert.Equal("Koşmak için basılı tutun.", text);
        Assert.Equal(12, Assert.Single(icons!).At);
    }
}
