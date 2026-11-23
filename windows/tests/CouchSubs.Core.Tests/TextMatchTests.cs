// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public class TextMatchTests
{
    [Fact]
    public void NormalizeStripsPunctuationAndCase() =>
        Assert.Equal("kratos we do not have time boy", TextMatch.Normalize("Kratos: We do NOT have time, boy."));

    [Fact]
    public void SimilarToleratesOcrNoise() => Assert.True(TextMatch.IsSimilar("the gate will not hold", "the gale will not hold"));

    [Fact]
    public void DifferentLinesAreNotSimilar() => Assert.False(TextMatch.IsSimilar("we do not have time", "the gate will not hold"));

    [Fact]
    public void EmptyIsNeverSimilarToText() => Assert.False(TextMatch.IsSimilar("", "abc"));

    [Fact]
    public void SameSubtitleIgnoresGarbledWords()
    {
        var sent = TextMatch.Normalize("Across the deep waters, Pbo ou$3e went, hoping a boat would carry him home.");
        var wordSwap = TextMatch.Normalize("Across the deep waters, 2aljd Pbo went, Hoping 3e boat would carry him home now.");
        Assert.False(TextMatch.IsSimilar(wordSwap, sent));
        Assert.True(TextMatch.IsSameSubtitle(wordSwap, sent));
    }

    /// İki satırlık altyazı solarken alt satır kaçırıldı: yeni satır değil. Uzayan metin ise yenidir.
    [Fact]
    public void RereadMissingALineIsSameSubtitle()
    {
        const string twoRows = "Across the deep waters, Pbo went,\nhoping a boat would carry him home.";
        var sent = TextMatch.NormalizeRows(twoRows);
        Assert.True(TextMatch.IsSameSubtitle(TextMatch.Normalize(OcrNoise.Clean("Across the deep waters2aljd O went,")), sent));
        Assert.True(TextMatch.IsSameSubtitle(TextMatch.Normalize("Across the deep waters, Pbo went,"), sent));
        Assert.True(TextMatch.IsSameSubtitle(TextMatch.Normalize("hoping a boat would carry him home."), sent));
        Assert.False(TextMatch.IsSameSubtitle(TextMatch.Normalize(twoRows), TextMatch.Normalize("Across the deep waters, Pbo went,")));
    }

    /// İki konuşmacı aynı sözlerle konuşuyor: sözcüklerin çoğu ortak olsa da ikisi de ayrı çevrilmeli.
    [Theory]
    [InlineData("Where are you going?", "Where are you going, boy?")]
    [InlineData("Where are you going, boy?", "Where are you going?")]
    [InlineData("We need to leave this place before the sun goes down, boy.", "We need to leave this place before the sun goes down.")]
    [InlineData("Boy, we need to leave this place before the sun goes down.", "We need to leave this place before the sun goes down.")]
    public void LineSharingMostWordsIsANewSubtitle(string reread, string sent) =>
        Assert.False(TextMatch.IsSameSubtitle(TextMatch.Normalize(reread), TextMatch.NormalizeRows(sent)));

    /// Tek satırlık altyazının başı kesildiyse satır kaçırılmış sayılmaz; tam satırlar eksikse sayılır.
    [Fact]
    public void ShortenedSingleRowIsNotAMissingRow()
    {
        Assert.False(TextMatch.IsSameSubtitle("we have to cross the river", TextMatch.NormalizeRows("We have to cross the river before the sun goes down")));
        Assert.True(TextMatch.IsSameSubtitle("we have to cross the river", TextMatch.NormalizeRows("We have to cross the river\nbefore the sun goes down")));
    }

    [Theory]
    [InlineData("we do not have time", "the gate will not hold")]
    [InlineData("we do not have time for this boy and you know it", "we do not have time")]
    [InlineData("where is the boy", "where is the ship")]
    [InlineData("you should not be here", "i told you to stay with your mother")]
    [InlineData("we have to cross the river before the sun goes down", "the river is too deep for us to cross today")]
    public void SameSubtitleKeepsDistinctLinesApart(string reread, string sent) =>
        Assert.False(TextMatch.IsSameSubtitle(reread, sent));

    /// Uzayan, yarım ya da bir iki sözcüğü başka okunan aynı cümle: TV'de öncekinin yerine geçer (Mac: TextMatchTests).
    [Theory]
    [InlineData("We do not have time for this.", "We do not have")]
    [InlineData("We do not have", "We do not have time for this.")]
    [InlineData("have time for this, boy.", "We do not have time for this, boy.")]
    [InlineData("The gate will not hold!", "The gale will not hold")]
    [InlineData("Across the deep waters he went, hoping a boat would carry him home.", "Across the deep waters O went, Hoping a boal would carry him home")]
    public void RevisionsOfTheSameSentence(string newText, string oldText) =>
        Assert.True(TextMatch.IsRevision(newText, oldText));

    [Theory]
    [InlineData("Run to the boat!", "We do not have time for this.")]
    [InlineData("Where is the ship?", "Where is the boy?")]
    [InlineData("No.", "Yes.")]
    [InlineData("I told you to stay with your mother.", "You should not be here.")]
    public void DifferentSentencesAreNotRevisions(string newText, string oldText) =>
        Assert.False(TextMatch.IsRevision(newText, oldText));

    [Fact]
    public void GrowthOnlyCountsAddedWords()
    {
        Assert.True(TextMatch.IsGrowth("We do not have time.", "We do not"));
        Assert.False(TextMatch.IsGrowth("We do not", "We do not have time."));
        Assert.False(TextMatch.IsGrowth("We do not have time.", "We do not have time."));
        Assert.True(TextMatch.IsGrowth("Then we go home.", "Then"));
        // Başı okunmamış satır: sondaki tek sözcük yetmez, iki sözcük yeter.
        Assert.False(TextMatch.IsGrowth("Then we go home.", "home"));
        Assert.True(TextMatch.IsGrowth("Then we go home.", "go home"));
    }

    /// Olumsuzluk ya da sayı farkı karakterce küçüktür ama anlamı tersine çevirir: yeniden okuma sayılmamalı.
    /// Uzun cümlede tek sözcük %85 benzerlik sınırının üstünde kalıyor ("never": 0.86, "5"/"6": 0.92). Kısaltmanın
    /// "t"si (can't → "can t") tek harf olduğu için sözcük karşılaştırmasına hiç girmiyor.
    [Theory]
    [InlineData("I can't do that for you right now.", "I can do that for you right now.")]
    [InlineData("I said that I would never help you with this.", "I said that I would help you with this.")]
    [InlineData("He is not coming back tonight.", "He is coming back tonight.")]
    [InlineData("Meet me at the docks at 6.", "Meet me at the docks at 5.")]
    public void MeaningChangingRereadIsNotSameSubtitle(string reread, string sent) =>
        Assert.False(TextMatch.IsSameSubtitle(TextMatch.Normalize(reread), TextMatch.NormalizeRows(sent)));

    /// Olumsuzluk korunurken yalnız yazımı farklı okunan satır yine aynı altyazıdır (düzeltme bunu bozmamalı).
    [Theory]
    [InlineData("I can’t do that for you right now.", "I can't do that for you right now.")]
    [InlineData("I dont know what to do.", "I don't know what to do.")]
    [InlineData("He is n0t coming back tonight.", "He is not coming back tonight.")]
    public void SpellingNoiseKeepsNegatedLineSame(string reread, string sent) =>
        Assert.True(TextMatch.IsSameSubtitle(TextMatch.Normalize(reread), TextMatch.NormalizeRows(sent)));

    /// Yalnız eklenen işaret sayılır: düşen olumsuzluk ya da sayı çoğu zaman OCR kaybıdır. Kesmenin "t"si yalnız
    /// bilinen olumsuz kısaltmayı tamamlar ("cotton t shirt" değil).
    [Theory]
    [InlineData("I can't do that.", "I can do that.", true)]
    [InlineData("I can do that.", "I can't do that.", false)]
    [InlineData("Meet me at 6.", "Meet me at 5.", true)]
    [InlineData("Meet me at", "Meet me at 5.", false)]
    [InlineData("He is n0t here.", "He is here.", true)]
    [InlineData("I dont know.", "I don't know.", false)]
    [InlineData("Buy a t shirt.", "Buy a shirt.", false)]
    [InlineData("Buy a cotton t shirt.", "Buy a cotton shirt.", false)]
    [InlineData("I won t go.", "I will go.", true)]
    [InlineData("We haven t left.", "We have left.", true)]
    [InlineData("Bring 5 and 5.", "Bring 5.", true)]
    [InlineData("Bring 5.", "Bring 5 and 5.", false)]
    [InlineData("It costs $500 now.", "It costs $500.", false)]
    [InlineData("1 can do that.", "I can do that.", false)]
    public void AddsMeaningCountsOnlyAddedMarks(string reread, string sent, bool expected) =>
        Assert.Equal(expected, TextMatch.AddsMeaning(reread, sent));
}
