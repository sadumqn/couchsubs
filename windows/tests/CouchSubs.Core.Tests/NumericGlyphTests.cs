// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public class NumericGlyphTests
{
    [Theory]
    [InlineData("I have 1 bullet left.", "I have 5 bullets left.")]
    [InlineData("I have 1 bullet left.", "I have 5 bullet left.")]
    [InlineData("1 have 1 bullet left.", "I have 5 bullets left.")]
    [InlineData("I need 1 more key.", "I need more keys.")]
    [InlineData("I have 1 and 1 left.", "I have 1 left.")]
    [InlineData("I have 1 and 1 left.", "I have 1 and 5 left.")]
    [InlineData("O, we have 0 keys left.", "O, we have 5 keys left.")]
    [InlineData("I have 10 keys left.", "I have 5 keys left.")]
    [InlineData("I have 1 key left.", "I have\n5 keys left.")]
    public void NumberChangesAreNotHiddenByLettersElsewhere(string reread, string sent)
    {
        Assert.True(TextMatch.AddsMeaning(reread, sent));
        Assert.False(TextMatch.IsSameSubtitle(TextMatch.Normalize(reread), TextMatch.NormalizeRows(sent)));
        Assert.False(TextMatch.IsWorseReread(reread, sent));
    }

    [Theory]
    [InlineData("1 can do that.", "I can do that.")]
    [InlineData("0, we should leave now.", "O, we should leave now.")]
    [InlineData("Now 1 can do that.", "Now I can do that.")]
    [InlineData("Ycs 1 can do thal.", "Yes I can do that.")]
    [InlineData("Yes 1 can do that.", "Well I can do that.")]
    [InlineData("1 can do that now.", "I can do that.")]
    [InlineData("Now 1 can do that.", "I can do that.")]
    [InlineData("1 have 1 key left.", "I have 1 key left.")]
    [InlineData("1 said 1 can do that.", "I said I can do that.")]
    [InlineData("1 have 5 keys left.", "I have 5 keys left.")]
    public void AlignedLetterDigitNoiseDoesNotAddANumber(string reread, string sent) =>
        Assert.False(TextMatch.AddsMeaning(reread, sent));

    [Fact]
    public void StabilizerSendsNumericCorrectionButNotLetterNoise()
    {
        var s = new SubtitleStabilizer();
        const string first = "I have 5 bullets left.";
        const string corrected = "I have 1 bullet left.";
        Assert.Equal(StabilizerAction.Translate(first), s.Feed(first));
        Assert.Equal(StabilizerAction.None, s.Feed("1 have 5 bullets left."));
        Assert.Equal(StabilizerAction.Translate(corrected), s.Feed(corrected));
        Assert.Equal(StabilizerAction.None, s.Feed("1 have 1 bullet left."));
    }
}
