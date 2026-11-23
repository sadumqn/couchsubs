// SPDX-License-Identifier: AGPL-3.0-only

using System.Collections.Concurrent;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Otomatik ekran yazıları: dedektörün bulduğu kutu ek alan okuyucusuyla yerinde çevrilir.</summary>
public class ScreenTextReadingTests
{
    // Koyu zeminde sol üstte beyaz "yazı" çizgili kutu; altyazı alanının dışında.
    private static Frame BoxFrame()
    {
        var frame = Frame.Blank(640, 360);
        Array.Fill(frame.Pixels, (byte)90);
        for (var y = 20; y < 80; y++)
            for (var x = 20; x < 180; x++)
            {
                var p = y * frame.Stride + x * 4;
                var value = (byte)((y - 20) % 9 is 3 or 4 && (x - 20) % 7 < 4 ? 240 : 24);
                frame.Pixels[p] = frame.Pixels[p + 1] = frame.Pixels[p + 2] = value;
            }
        return frame;
    }

    [Theory]
    [InlineData(true, true)]
    [InlineData(false, true)]
    // Noktalamayla biten kısa tek cümle görev/hedef türüdür; Ayarlar'da Görev kapatılınca bulunan kutu çizilmez.
    [InlineData(true, false)]
    public async Task FoundTextBoxIsTranslatedInPlaceOnlyWhenEnabled(bool enabled, bool mission)
    {
        var services = new FakeServices { ReaderLines = Reading.FromText("Follow Paulie to the car.") };
        var settings = new MemorySettings();
        settings.Save(new UserSettings { FrameSource = FrameSource.RemotePlayWindow, Output = SubtitleOutput.Computer, AutoScreenText = enabled, AutoScreenTextReset = true,
                                        ScreenTextMission = mission });
        using var controller = AppControllerTests.Make(services, settings: settings);
        // Sahte okuyucu altyazıya ve alana aynı yazıyı verir; altyazı yinelemesi engeli burada sınanmıyor.
        controller.SubtitleEcho = null;
        var events = new ConcurrentQueue<SubtitleEvent>();
        controller.StreamEvent += events.Enqueue;
        await controller.StartAsync();
        var frame = BoxFrame();
        var until = DateTime.UtcNow + TimeSpan.FromSeconds(enabled && mission ? 6 : 2);
        bool Found() => events.Any(e => e.Kind == SubtitleEventKind.Region && e.Id?.StartsWith("auto-") == true && e.Text.Length > 0);
        while (DateTime.UtcNow < until && !Found())
        {
            services.Streams[0].Emit(frame);
            await Task.Delay(50);
        }
        Assert.Equal(enabled && mission, Found());
        controller.Stop();
    }

    /// <summary>
    /// Kullanıcı bildirimi (beta.65/66): otomatik ekran yazısı altyazıyı da okuyunca çeviri hem altyazı konumunda hem oyunun
    /// altyazısının üstünde görünüyordu. Kutunun yazısı altyazı hattının okuduğuyla aynı: yerinde çizilmez, altyazı gelir.
    /// </summary>
    [Fact]
    public async Task FoundBoxReadingTheSubtitleIsNotDrawnASecondTime()
    {
        var services = new FakeServices { ReaderLines = Reading.FromText("Follow Paulie to the car.") };
        var settings = new MemorySettings();
        settings.Save(new UserSettings { FrameSource = FrameSource.RemotePlayWindow, Output = SubtitleOutput.Computer, AutoScreenText = true, AutoScreenTextReset = true });
        using var controller = AppControllerTests.Make(services, settings: settings);
        var events = new ConcurrentQueue<SubtitleEvent>();
        controller.StreamEvent += events.Enqueue;
        await controller.StartAsync();
        var frame = BoxFrame();
        var until = DateTime.UtcNow + TimeSpan.FromSeconds(4);
        while (DateTime.UtcNow < until)
        {
            services.Streams[0].Emit(frame);
            await Task.Delay(50);
        }
        Assert.Contains(events, e => e.Kind == SubtitleEventKind.Subtitle && e.Text.Length > 0);
        Assert.DoesNotContain(events, e => e.Kind == SubtitleEventKind.Region && e.Id?.StartsWith("auto-") == true && e.Text.Length > 0);
        controller.Stop();
    }
}
