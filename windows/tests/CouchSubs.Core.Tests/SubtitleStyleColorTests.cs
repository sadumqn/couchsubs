// SPDX-License-Identifier: AGPL-3.0-only

using System.Net.Http;
using System.Text.Json;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Yeni arayüzün altyazı biçimi alanları (design/yeni-arayuz/METINLER.md; Mac SubtitleStyle ile aynı): zemin ve yazı
/// rengi, karakter adı rengi, yalnız adı boya, TV girişi. Eski kayıt eksik alanlarla açılır; TV'ye geriye uyumlu gider.
/// </summary>
public class SubtitleStyleColorTests
{
    private static readonly HttpClient Http = new();

    [Fact]
    public void OldSettingsGetDefaults()
    {
        var old = JsonSerializer.Deserialize<SubtitleStyle>("{\"FontSize\":58}")!;
        Assert.Equal("#101014", old.BackgroundColor);
        Assert.Null(old.TextHex);
        Assert.Equal(NameColorMode.Speaker, old.NameColorMode);
        Assert.False(old.NameOnly);
        Assert.Null(old.HdmiInput);
    }

    [Fact]
    public void NewFieldsRoundTrip()
    {
        var style = new SubtitleStyle() with
        {
            BackgroundColor = "#0E1A30", TextHex = "#FFE066", NameColorMode = NameColorMode.Single, NameHex = "#4FD1C5",
            CharacterColors = new Dictionary<string, string> { ["jason"] = "#F5B83D" }, NameOnly = true, HdmiInput = 2,
        };
        var back = JsonSerializer.Deserialize<SubtitleStyle>(JsonSerializer.Serialize(style))!;
        Assert.Equal("#0E1A30", back.BackgroundColor);
        Assert.Equal("#FFE066", back.TextHex);
        Assert.Equal(NameColorMode.Single, back.NameColorMode);
        Assert.Equal("#4FD1C5", back.NameHex);
        Assert.Equal("#F5B83D", back.CharacterColors!["jason"]);
        Assert.True(back.NameOnly);
        Assert.Equal(2, back.HdmiInput);
        Assert.Contains("\"single\"", JsonSerializer.Serialize(style));
    }

    [Fact]
    public void HexIsValidatedAndUppercased()
    {
        Assert.Equal("#ABCDEF", SubtitleStyle.Hex("#abcdef"));
        Assert.Null(SubtitleStyle.Hex("#12345"));
        Assert.Null(SubtitleStyle.Hex("red"));
        Assert.Equal("#FFE135", new SubtitleStyle(TextColor: SubtitleTextColor.Yellow).TextRgb);
        Assert.Equal("#BFE3FF", new SubtitleStyle(TextHex: "#bfe3ff").TextRgb);
    }

    [Fact]
    public async Task TvGetsTheNewFields()
    {
        using var server = new SubtitleServer(0);
        var port = await server.StartAsync();
        server.SendStyle(new SubtitleStyle(BackgroundColor: "#2B2D33", TextHex: "#BFE3FF", NameOnly: true, HdmiInput: 3));
        using var response = await Http.GetAsync($"http://127.0.0.1:{port}/events", HttpCompletionOption.ResponseHeadersRead);
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        string? data = null;
        while (await reader.ReadLineAsync() is { } line)
            if (line.StartsWith("data:")) { data = line; break; }
        Assert.Contains("\"backgroundColor\":\"#2B2D33\"", data);
        Assert.Contains("\"textHex\":\"#BFE3FF\"", data);
        Assert.Contains("\"nameOnly\":true", data);
        Assert.Contains("\"hdmiInput\":3", data);
        // Eski TV için beyaz/sarı da gider.
        Assert.Contains("\"textColor\":\"white\"", data);
    }

    [Fact]
    public void SingleColorAndChosenCharacterColors()
    {
        var book = new SpeakerColorBook();
        book.Configure("#4FD1C5", new Dictionary<string, string>());
        Assert.Equal("#4FD1C5", book.Color("Jason"));
        Assert.Equal("#4FD1C5", book.Color("Lucia"));

        var chosen = new SpeakerColorBook();
        chosen.Configure(null, new Dictionary<string, string> { ["Jason"] = "#F5B83D" });
        Assert.Equal("#F5B83D", chosen.Color("JASON"));
        // Yazı tanımanın yakın okuması aynı kişi.
        Assert.Equal("#F5B83D", chosen.Color("Jasom"));
        Assert.NotEqual("#F5B83D", chosen.Color("Lucia"));
    }
}
