// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public class GamePhonePaletteTests
{
    [Theory]
    [InlineData(224, 232, 224, 24)]
    [InlineData(32, 64, 120, 248)]
    public void ReadsTheSurfaceAndInkOnlyInsideTheTextBox(byte red, byte green, byte blue, byte ink)
    {
        var frame = Frame.Blank(120, 50);
        for (int y = 0; y < frame.Height; y++)
            for (int x = 0; x < frame.Width; x++)
            {
                bool inside = x is >= 15 and < 105 && y is >= 10 and < 40;
                var color = !inside ? (R: (byte)255, G: (byte)0, B: (byte)196)
                    : x % 13 < 3 ? (R: ink, G: ink, B: ink) : (R: red, G: green, B: blue);
                Set(frame, x, y, color.R, color.G, color.B);
            }
        var box = new TextBox(.125, .2, .875, .8);
        var style = GamePhonePalette.Sample(frame, box);
        Assert.Equal($"#{red:X2}{green:X2}{blue:X2}", style.Background);
        Assert.Equal($"#{ink:X2}{ink:X2}{ink:X2}", style.Foreground);
        Assert.True(DesignTokens.Contrast(style.Background, style.Foreground) >= 4.5);

        var reading = new Reading([new TextLine("Meet us at the station.", box)]);
        var crop = new CropRegion(0, 1, 0, 1);
        var phone = RegionWatcher.MakeCandidate(reading, crop, frame, phone: true);
        Assert.Equal(style, Assert.Single(phone.Blocks!).Style);
        var ordinary = RegionWatcher.MakeCandidate(reading, crop, frame);
        Assert.All(ordinary.Blocks ?? [], b => Assert.Null(b.Style));
    }

    [Fact]
    public void BorderlineBlueBubbleKeepsLightInkAndReadableContrast()
    {
        var frame = Frame.Blank(90, 30);
        for (int y = 0; y < frame.Height; y++)
            for (int x = 0; x < frame.Width; x++)
                if (x % 13 < 3) Set(frame, x, y, 230, 239, 246);
                else Set(frame, x, y, 88, 120, 192);
        var style = GamePhonePalette.Sample(frame, new TextBox(0, 0, 1, 1));
        Assert.Equal("#5070B8", style.Background);
        Assert.Equal("#FFFFFF", style.Foreground);
        Assert.True(DesignTokens.Contrast(style.Background, style.Foreground) >= 4.5);
    }
    [Fact]
    public void PhotoUsesOneNeutralReadablePairAcrossChangingFrames()
    {
        var frame = Frame.Blank(96, 54);
        var box = new TextBox(0, 0, 1, 1);
        for (int step = 0; step < 2; step++)
        {
            for (int y = 0; y < frame.Height; y++)
                for (int x = 0; x < frame.Width; x++)
                    Set(frame, x, y, (byte)((x * 3 + step * 80) % 256), (byte)(y * 4), (byte)((x + y) * 3));
            Assert.Equal(GamePhonePalette.Neutral, GamePhonePalette.Sample(frame, box));
        }
        Assert.True(DesignTokens.Contrast(GamePhonePalette.Neutral.Background, GamePhonePalette.Neutral.Foreground) >= 4.5);
    }

    private static void Set(Frame frame, int x, int y, byte r, byte g, byte b)
    {
        int p = y * frame.Stride + x * 4;
        frame.Pixels[p] = b;
        frame.Pixels[p + 1] = g;
        frame.Pixels[p + 2] = r;
    }
}
