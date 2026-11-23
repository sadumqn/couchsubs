// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Altyazı ekran yazısı olarak ikinci kez çizilmez (kullanıcı bildirimi, beta.65/66: çeviri hem seçilen altyazı konumunda
/// hem oyunun altyazısının üstünde görünüyordu). Mac: SubtitleEchoTests.swift, Android: SubtitleEchoTest.kt.
/// </summary>
public class SubtitleEchoTests
{
    private long time;
    private readonly SubtitleEcho echo;
    /// <summary>Varsayılan altyazı alanı (0,14–0,86 x 0,62–0,97).</summary>
    private static readonly CropRegion Region = new();

    public SubtitleEchoTests() => echo = new SubtitleEcho(() => time);

    /// <summary>Altyazı alanına oranla kutu: karedeki yerden.</summary>
    private static TextLine InRegion(string text, double left, double top, double right, double bottom)
    {
        double w = Region.Right - Region.Left, h = Region.Bottom - Region.Top;
        return new(text, new TextBox((left - Region.Left) / w, (top - Region.Top) / h, (right - Region.Left) / w, (bottom - Region.Top) / h));
    }

    private static TextLine At(string text, double left, double top, double right, double bottom) =>
        new(text, new TextBox(left, top, right, bottom));

    [Fact]
    public void LinesInTheSubtitleAreaAreNotScreenText()
    {
        echo.Record(new Reading([InRegion("Thought I was flying solo. Come on.", 0.30, 0.80, 0.70, 0.84)]), Region);
        // Altyazının yerine düşen satır (aynı altyazının bozuk okunuşu ya da yeni altyazı) metin tutmasa da atılır.
        var reading = new Reading([At("Thought I was fiying soio. C0me on.", 0.31, 0.80, 0.69, 0.84),
                                   At("Okay, let's go then, right now.", 0.28, 0.80, 0.72, 0.845),
                                   At("Press up to open the phone", 0.02, 0.05, 0.30, 0.09)]);
        Assert.Equal(["Press up to open the phone"], echo.Filter(reading).Lines.Select(line => line.Text));
    }

    /// <summary>
    /// Kullanıcı bildirimi (X, beta.69, GTA 6): "Ekranı çevir" altyazıyı çeviriyor, telefon mesajlarını çevirmiyordu. Sağ
    /// alttaki telefon kartı (0,72–0,99 x 0,45–0,80) varsayılan altyazı alanıyla kesişiyor; altyazı okunurken kartın
    /// 0,62'nin altındaki satırlarının merkezi alanın içinde kaldığı için hepsi atılıyordu.
    /// </summary>
    [Fact]
    public void PhoneMessagesInsideTheSubtitleAreaAreScreenText()
    {
        echo.Record(new Reading([InRegion("Yeah, I'll stop by.", 0.42, 0.86, 0.58, 0.90)]), Region);
        Assert.True(echo.HasRecent);
        var phone = new[]
        {
            At("Jason", 0.76, 0.47, 0.84, 0.50),
            At("Where are you? We need to talk.", 0.74, 0.55, 0.95, 0.58),
            At("Come to the marina after dark", 0.74, 0.64, 0.94, 0.67),
            At("Bring the cash", 0.74, 0.70, 0.84, 0.73),
            At("Don't be late this time", 0.80, 0.76, 0.97, 0.79),
        };
        var reading = new Reading([.. phone, At("Yeah, I'll stop by.", 0.42, 0.86, 0.58, 0.90)]);
        Assert.Equal(phone.Select(line => line.Text), echo.Filter(reading).Lines.Select(line => line.Text));
        // Geniş altyazıyla aynı sıradaki mesaj satırı da kalır (yalnız ucu örtüşür); altyazının alana düşen parçası atılır.
        echo.Record(new Reading([InRegion("You better get to the docks before the cops do", 0.15, 0.76, 0.85, 0.80)]), Region);
        var wide = new Reading([At("Don't be late this time", 0.80, 0.76, 0.97, 0.79), At("before the cops do", 0.73, 0.76, 0.85, 0.80)]);
        Assert.Equal(["Don't be late this time"], echo.Filter(wide).Lines.Select(line => line.Text));
    }

    /// <summary>
    /// İki satırlı altyazının üst satırı alanın dışında: altyazı hattı yalnız alt satırı okur, üst satır bitişik ve aynı
    /// boyda olduğu için o da altyazıdır.
    /// </summary>
    [Fact]
    public void SubtitleLineOverflowingTheAreaEdgeIsNotScreenText()
    {
        echo.Record(new Reading([InRegion("and you still owe me for the boat.", 0.32, 0.63, 0.68, 0.67)]), Region);
        var reading = new Reading([At("Lucia, I told you twice already", 0.30, 0.585, 0.70, 0.625),
                                   At("Find a vehicle", 0.80, 0.30, 0.95, 0.34)]);
        Assert.Equal(["Find a vehicle"], echo.Filter(reading).Lines.Select(line => line.Text));
        // Altyazı kalkınca bitişik satır kuralı da kalkar.
        time += SubtitleEcho.AdjacentMs + 1;
        Assert.Equal(2, echo.Filter(reading).Lines.Count);
    }

    /// <summary>Alandan geniş altyazının ucu ya da hazır mesaj alanına düşen parçası metinle tanınır.</summary>
    [Fact]
    public void TextReadByTheSubtitleLineIsNotScreenTextAnywhere()
    {
        echo.Record(new Reading([InRegion("You better get to the docks before the cops do", 0.15, 0.80, 0.85, 0.84)]), Region);
        Assert.True(echo.IsEcho("YOU BETTER GET TO THE DOCKS BEFORE THE COPS DO"));
        Assert.True(echo.IsEcho("the docks before the cops do")); // parça
        Assert.False(echo.IsEcho("Get to the docks")); // kısa ve farklı görev yazısı
        // Görev alanında (yer kuralı kapalı) da metinle atılır.
        var mission = new Reading([At("You better get to the docks before the cops do", 0.2, 0.2, 0.8, 0.6)]);
        Assert.Empty(echo.Filter(mission, geometry: false).Lines);
        time += SubtitleEcho.WindowMs + 1;
        Assert.False(echo.IsEcho("You better get to the docks before the cops do"));
    }

    [Fact]
    public void FullScreenSubtitleAreaDoesNotHideEverything()
    {
        echo.Record(Reading.Empty, new CropRegion(0, 1, 0, 1));
        var reading = new Reading([At("Press up to open the phone", 0.4, 0.5, 0.6, 0.55)]);
        Assert.Single(echo.Filter(reading).Lines);
    }

    // RegionWatcher

    private sealed class Reader : ITextReader
    {
        public List<TextLine> Lines { get; set; } = [];
        public string Read(Frame image) => "";
        public Reading ReadLines(Frame image, bool deep) => new(Lines);
    }

    private sealed class Translator : ITextTranslator
    {
        public List<string> Calls { get; } = [];
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
        {
            lock (Calls) Calls.Add(text);
            return Task.FromResult($"çeviri {text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Count(word => word.Any(char.IsLetter))}");
        }
    }

    private sealed class Server : IRegionSender
    {
        public List<string> Sent { get; } = [];
        public void SendRegion(string id, string text, TextBox? box, double? lineHeight = null)
        {
            lock (Sent) Sent.Add(text);
        }
        public void SendRegion(string id, string text, TextBox? box, double? lineHeight, IReadOnlyList<IconPlacement>? icons,
                               IReadOnlyList<ScreenTranslation.Item>? blocks) => SendRegion(id, text, box, lineHeight);
        public void ClearRegions() { }
    }

    /// <summary>Koyu düz panelde açık yazı benzeri çizgiler (hazır alanın arayüz kutusu kanıtı için).</summary>
    private static Frame Panel()
    {
        var frame = Frame.Blank(320, 180);
        for (var y = 0; y < frame.Height; y++)
            for (var x = 0; x < frame.Width; x++)
            {
                var p = y * frame.Stride + x * 4;
                var value = (byte)((y / 3) % 4 == 0 && (x / 4) % 3 == 0 ? 230 : 30);
                (frame.Pixels[p], frame.Pixels[p + 1], frame.Pixels[p + 2], frame.Pixels[p + 3]) = (value, value, value, 255);
            }
        return frame;
    }

    /// <summary>Dedektörün altyazı alanının kenarında bulduğu (yarım karo genişletilmiş) otomatik alan altyazıyı okur: çizilmez.</summary>
    [Fact]
    public async Task AutoAreaReadingTheSubtitleSendsNothing()
    {
        echo.Record(new Reading([InRegion("and you still owe me for the boat.", 0.32, 0.63, 0.68, 0.67)]), Region);
        var reader = new Reader();
        var server = new Server();
        var watcher = new RegionWatcher(reader, new Translator(), server, clock: () => time) { SubtitleEcho = echo };
        // Alan 0,25–0,75 x 0,55–0,70: üst satır alanın dışında, alt satır içinde.
        var area = new WatchedArea("auto-1", ScreenTextDetector.AreaName, new CropRegion(0.55, 0.70, 0.25, 0.75)) { Auto = true };
        static TextLine Local(string text, double top, double bottom) =>
            new(text, new TextBox(0.1, (top - 0.55) / 0.15, 0.9, (bottom - 0.55) / 0.15));
        reader.Lines = [Local("Lucia, I told you twice already", 0.585, 0.625), Local("and you still owe me for the boat.", 0.63, 0.67)];
        await watcher.PassAsync(Panel(), [area]);
        await watcher.PassAsync(Panel(), [area]);
        Assert.All(server.Sent, text => Assert.Empty(text));
    }

    /// <summary>Hazır mesaj alanı altyazı alanıyla kesişir: kesişen yerdeki altyazı parçası çizilmez, mesaj kartı çizilir.</summary>
    [Fact]
    public async Task PresetAreaDropsTheSubtitlePartButKeepsItsOwnText()
    {
        var reader = new Reader();
        var server = new Server();
        var translator = new Translator();
        var watcher = new RegionWatcher(reader, translator, server, clock: () => time) { SubtitleEcho = echo };
        // Altyazı alanın sağ kenarına dek geniş: sağ ucu hazır mesaj alanına düşüyor.
        echo.Record(new Reading([InRegion("You better get to the docks before the cops do", 0.15, 0.76, 0.86, 0.795)]), Region);
        var messages = GameAreaPresets.Areas("GTA 6").First(area => area.Id == GameAreaPresets.PhoneId);
        var r = messages.Region;
        TextLine Local(string text, double top, double bottom) =>
            new(text, new TextBox(0.05, (top - r.Top) / (r.Bottom - r.Top), 0.5, (bottom - r.Top) / (r.Bottom - r.Top)));
        // Kartın altyazı alanına (0,62'den aşağısı) düşen mesaj satırı da kartın yazısıdır.
        reader.Lines = [Local("Meet me at the marina tonight, Jason", 0.50, 0.54), Local("Bring the boat keys", 0.66, 0.70),
                        Local("before the cops do", 0.76, 0.795)];
        await watcher.PassAsync(Panel(), [messages]);
        await watcher.PassAsync(Panel(), [messages]);
        // Yalnız mesaj kartı çevrilip çizilir; altyazı parçası metne katılmaz.
        Assert.Single(server.Sent, text => text.Length > 0);
        var call = string.Join(" / ", translator.Calls);
        Assert.Contains("marina", call);
        Assert.Contains("boat keys", call);
        Assert.DoesNotContain("cops", call);
    }

    /// <summary>
    /// "Ekranı çevir" GTA 6 telefonu açıkken (kullanıcı bildirimi, X, beta.69): altyazı çevrilmez (zaten kendi yerinde),
    /// telefon kartının bütün mesajları çevrilir; kartın altyazı alanına düşen alt yarısı da.
    /// </summary>
    [Fact]
    public async Task ScreenTranslationKeepsPhoneMessagesWhileSubtitlesRun()
    {
        echo.Record(new Reading([InRegion("Yeah, I'll stop by.", 0.42, 0.86, 0.58, 0.90)]), Region);
        var reader = new Reader
        {
            Lines = [At("Where are you? We need to talk.", 0.74, 0.55, 0.95, 0.58),
                     At("Come to the marina after dark", 0.74, 0.64, 0.94, 0.67),
                     At("Bring the cash with you", 0.74, 0.70, 0.90, 0.73),
                     At("Yeah, I'll stop by.", 0.42, 0.86, 0.58, 0.90)],
        };
        var items = await ScreenTranslation.TranslateAsync(Frame.Blank(1920, 1080), reader, new Translator(), echo);
        var sources = string.Join(" / ", items.Select(item => item.Source));
        Assert.Contains("We need to talk", sources);
        Assert.Contains("marina", sources);
        Assert.Contains("Bring the cash", sources);
        Assert.DoesNotContain("stop by", sources);
    }

    /// <summary>"Ekranı çevir": altyazı hattının okuduğu satır ekran çevirisine girmez, diğer yazılar girer.</summary>
    [Fact]
    public async Task ScreenTranslationLeavesTheSubtitleOut()
    {
        echo.Record(new Reading([InRegion("You better get to the docks before the cops do", 0.15, 0.80, 0.85, 0.84)]), Region);
        var reader = new Reader
        {
            Lines = [At("You better get to the docks before the cops do", 0.15, 0.80, 0.85, 0.84),
                     At("Press up to open the phone", 0.02, 0.05, 0.40, 0.09)],
        };
        var items = await ScreenTranslation.TranslateAsync(Frame.Blank(1920, 1080), reader, new Translator(), echo);
        var item = Assert.Single(items);
        Assert.Equal("Press up to open the phone", item.Source);
    }

    /// <summary>
    /// Altyazı hattı okuduğu bloğu kaydeder, sıfırlanınca unutur; menüde (altyazı gönderilmiyor) okunan blok kaydedilmez:
    /// menü satırlarının kendi çevirisi metin eşleşmesiyle atılmasın.
    /// </summary>
    [Fact]
    public async Task PipelineRecordsTheSubtitleBlockOnlyOutsideMenus()
    {
        var menu = false;
        var line = "You better get to the docks before the cops do";
        var pipeline = new SubtitlePipeline(new LinesReader(Reading.FromText(line)), new FakeTranslator(), new FakeSender())
        {
            Echo = echo,
            EchoPaused = () => menu,
        };
        menu = true;
        await pipeline.ProcessAsync(Frame.Blank(64, 64), Region);
        Assert.False(echo.IsEcho(line));
        menu = false;
        await pipeline.ProcessAsync(Frame.Blank(64, 64), Region);
        Assert.True(echo.IsEcho(line));
        pipeline.Reset();
        Assert.False(echo.HasRecent);
    }
}
