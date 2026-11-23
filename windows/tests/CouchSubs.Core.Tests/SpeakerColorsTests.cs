// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Mac SpeakerColorsTests, Android SpeakerColorsTest ve TV uygulamasıyla aynı renkler.</summary>
public class SpeakerColorsTests
{
    [Theory]
    [InlineData("Mattia", "#90CAF9")]
    [InlineData("MATTIA", "#90CAF9")]
    [InlineData(" mattia ", "#90CAF9")]
    [InlineData("Lucia", "#F06292")]
    [InlineData("Jason", "#4DD0E1")]
    [InlineData("Cal", "#4FC3F7")]
    public void ColorComesFromTheName(string name, string color) => Assert.Equal(color, SpeakerColors.Color(name));

    [Fact]
    public void PaletteHasTenDistinctColorsWithoutWhite()
    {
        Assert.Equal(10, SpeakerColors.Palette.Distinct().Count());
        Assert.DoesNotContain("#FFFFFF", SpeakerColors.Palette);
    }

    [Fact]
    public void SpeakersAreLineStartNamesInOrderWithoutRepeats()
    {
        Assert.Equal(["Mattia", "Lucia"], SpeakerColors.Speakers("Mattia: Gel.\nLucia: Hayır.\nMattia: Lütfen."));
        Assert.Empty(SpeakerColors.Speakers("Saat 10:30'da buluşalım."));
        Assert.Empty(SpeakerColors.Speakers("Note: Keep going."));
    }

    [Fact]
    public void OnlyTheSpeakerNameIsColored()
    {
        // Sarılmış metin: yalnız "Ad:" konuşanın renginde; cümle ve devam satırı renksiz (kullanıcının Yazı rengi).
        var text = "Mattia: Bunu yarın\nkonuşuruz.\nLucia : Tamam.";
        var segments = SpeakerColors.Segments(text, SpeakerColors.Speakers("Mattia: Bunu yarın konuşuruz.\nLucia : Tamam."));
        Assert.Equal(
            [
                new SpeakerColors.Segment("Mattia:", "#90CAF9"), new SpeakerColors.Segment(" Bunu yarın\nkonuşuruz.\n", null),
                new SpeakerColors.Segment("Lucia :", "#F06292"), new SpeakerColors.Segment(" Tamam.", null),
            ],
            segments);
        Assert.Equal(text, string.Concat(segments.Select(segment => segment.Text)));
    }

    [Fact]
    public void TextBeforeTheFirstNameStaysUncolored()
    {
        var segments = SpeakerColors.Segments("Kapıyı aç.\nJason: Geldim.", ["Jason"]);
        Assert.Equal(
            [new SpeakerColors.Segment("Kapıyı aç.\n", null), new SpeakerColors.Segment("Jason:", "#4DD0E1"), new SpeakerColors.Segment(" Geldim.", null)],
            segments);
        Assert.Equal([new SpeakerColors.Segment("Düz metin", null)], SpeakerColors.Segments("Düz metin", []));
    }
}
