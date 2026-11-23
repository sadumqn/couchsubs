// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Core.Dubbing;

namespace CouchSubs.Core.Tests;

/// <summary>Mac SpeakerPrefixTests ve Android SpeakerPrefixTest ile aynı örnekler.</summary>
public class SpeakerPrefixTests
{
    [Fact]
    public void NameIsSplitFromTheSentence()
    {
        Assert.Equal(new SpeakerPrefix.Split("ARTHUR", "We need to go."), SpeakerPrefix.Parse("ARTHUR: We need to go."));
        Assert.Equal(new SpeakerPrefix.Split("Dutch", "I have a plan."), SpeakerPrefix.Parse("Dutch: I have a plan."));
        Assert.Equal(new SpeakerPrefix.Split("Mrs. Adler", "Leave me."), SpeakerPrefix.Parse("Mrs. Adler：Leave me."));
        Assert.Equal("OLD MAN", SpeakerPrefix.Parse("OLD MAN : Hm.")?.Name);
        Assert.Equal("We go.", SpeakerPrefix.Parse("ARTHUR:We go.")?.Body);
        Assert.Equal("We need to go.", SpeakerPrefix.Parse("Arthur:\nWe need to go.")?.Body);
    }

    [Theory]
    [InlineData("10:30 at the station.")]
    [InlineData("Meet me at 10:30.")]
    [InlineData("HTTPS://example.com")]
    [InlineData("Ratio 16:9")]
    [InlineData("Note: the gate is shut.")]
    [InlineData("I told you: get out!")]
    [InlineData("Very Long Name Of Four: words")]
    [InlineData("Bartholomew Montgomeryson: Hi.")]
    [InlineData("ARTHUR:")]
    public void FalseMatchesAreLeftAlone(string text) => Assert.Null(SpeakerPrefix.Parse(text));

    [Fact]
    public void PresentAddsOrHidesTheName()
    {
        const string source = "ARTHUR: We need to go.";
        Assert.Equal("ARTHUR: Gitmeliyiz.", SpeakerPrefix.Present("Gitmeliyiz.", source, true));
        Assert.Equal("Gitmeliyiz.", SpeakerPrefix.Present("Gitmeliyiz.", source, false));
        Assert.Equal("ARTHUR: Gitmeliyiz.", SpeakerPrefix.Present("ARTHUR: Gitmeliyiz.", source, true));
        Assert.Equal("Evet.\nHayır.", SpeakerPrefix.Present("ARTHUR: Evet.\nDUTCH: Hayır.", "ARTHUR: Yes.\nDUTCH: No.", false));
        Assert.Equal("Hedef: Kampa dön.", SpeakerPrefix.Present("Hedef: Kampa dön.", "Objective: Return to camp.", false));
    }

    [Fact]
    public void VoicedLinesGetTheSpeaker()
    {
        var lines = SpeakerPrefix.Voiced([new SpokenLine("We go.", "Gidiyoruz.")], new SpeakerPrefix.Split("ARTHUR", "We go."));
        Assert.Equal("ARTHUR", Assert.Single(lines).Speaker);
    }

    /// <summary>Renkli ad cümleden ayrı okunsa da satır soldan sağa birleşir; ad sona düşmez.</summary>
    [Fact]
    public void NameReadApartJoinsItsRow()
    {
        var reading = new Reading([
            new TextLine("We need to go.", new TextBox(0.40, 0.501, 0.70, 0.60)),
            new TextLine("ARTHUR:", new TextBox(0.30, 0.50, 0.385, 0.60)),
            new TextLine("9", new TextBox(0.95, 0.50, 0.97, 0.60)),
        ]).JoiningRows();
        Assert.Equal(new[] { "9", "ARTHUR: We need to go." }, reading.Lines.Select(line => line.Text).Order());
    }
}
