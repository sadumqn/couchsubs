// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// Tasarım değerleri design/tokens.json'dan gelir (Mac sürümü de aynı dosyayı kullanır).
/// Bu testler yazıların her iki görünümde de rahat okunmasını güvenceye alır.
public class DesignTokensTests
{
    private readonly DesignTokens tokens = DesignTokens.Shared;

    private void AssertContrast(string text, string background, double minimum)
    {
        foreach (var dark in new[] { false, true })
        {
            var foreground = tokens.Color[text].For(dark);
            var back = tokens.Color[background].For(dark);
            var ratio = DesignTokens.Contrast(foreground, back);
            Assert.True(ratio >= minimum, $"{text} / {background} ({foreground} – {back}): {ratio}");
        }
    }

    [Fact]
    public void TokensAreBundled()
    {
        Assert.Equal("CouchSubs", tokens.Name);
        foreach (var (name, pair) in tokens.Color)
        {
            Assert.True(DesignTokens.Rgb(pair.Light) is not null, name);
            Assert.True(DesignTokens.Rgb(pair.Dark) is not null, name);
        }
    }

    [Fact]
    public void ContrastFormulaMatchesWcag()
    {
        Assert.Equal(21, DesignTokens.Contrast("#000000", "#FFFFFF"), 2);
        Assert.Equal(4.48, DesignTokens.Contrast("#777777", "#FFFFFF"), 2);
    }

    [Fact]
    public void MainTextIsHighlyReadable()
    {
        AssertContrast("textPrimary", "background", 7);
        AssertContrast("textPrimary", "surface", 7);
    }

    [Fact]
    public void SecondaryAndColoredTextIsReadable()
    {
        foreach (var text in new[] { "textSecondary", "accentText", "success", "warning", "danger" })
        {
            AssertContrast(text, "background", 4.5);
            AssertContrast(text, "surface", 4.5);
        }
        AssertContrast("accentText", "accentSoft", 4.5);
    }

    /// <summary>Bento renkleri: Pro moru, tonlu zeminler ve yüzey-2 üstündeki yazılar.</summary>
    [Fact]
    public void BentoColorsAreReadable()
    {
        foreach (var background in new[] { "background", "surface", "proSoft" }) AssertContrast("pro", background, 4.5);
        AssertContrast("danger", "dangerSoft", 4.5);
        AssertContrast("success", "successSoft", 4.5);
        AssertContrast("textPrimary", "surface2", 7);
        AssertContrast("textSecondary", "surface2", 4.5);
    }

    [Fact]
    public void GlowsUseValidColors()
    {
        Assert.NotEmpty(tokens.Glow);
        foreach (var (name, glow) in tokens.Glow)
        {
            Assert.True(DesignTokens.Rgb(glow.Color) is not null, name);
            Assert.InRange(glow.Opacity, 0, 1);
        }
    }

    [Fact]
    public void ButtonTextIsReadable()
    {
        AssertContrast("onAccent", "accent", 4.5);
        AssertContrast("onDanger", "danger", 4.5);
    }

    [Fact]
    public void TextIsLargerThanSystemDefault()
    {
        Assert.True(tokens.Font["body"].Size >= 15);
        Assert.True(tokens.Font["caption"].Size >= 12);
    }
}
