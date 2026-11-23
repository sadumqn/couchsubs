// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// X (22 Kas, GTA 6 telefonu): "yazılar sürekli oynuyor okumak çok zor, balonların içinde de aynı hata var". Aynı balon küçük
/// oynamada yerinde kalır (<see cref="PhoneSteady.SteadyPositions"/>), panel el titremesiyle kaymaz
/// (<see cref="PhoneSteady.SteadyPose"/>), aynı görünen gönderi yinelenmez (<see cref="PhoneSteady.SamePicture"/>); gerçek
/// kaydırmada hepsi birlikte bir kerede geçer (Mac PhoneJitterTests.swift, Android PhoneJitterTest.kt ile aynı vektörler).
/// </summary>
public class PhoneJitterTests
{
    private static ScreenTranslation.Item Item(string text, TextBox box, double line = 0.03) =>
        new(text, "Çevrildi: " + text, box, line);

    [Fact]
    public void SmallJitterKeepsEachBubbleWhereItWasDrawn()
    {
        ScreenTranslation.Item[] before = [Item("Thx amigo! U find", new(0.62, 0.65, 0.75, 0.69)),
                                           Item("New message", new(0.64, 0.59, 0.75, 0.62))];
        ScreenTranslation.Item[] jiggled = [before[0] with { Source = "Thx amigo! U flnd", Box = new(0.623, 0.655, 0.753, 0.695) },
                                            before[1] with { Box = new(0.638, 0.586, 0.748, 0.616) }];
        var still = PhoneSteady.SteadyPositions(jiggled, before, 16.0 / 9);
        Assert.Equal(0.62, still[0].Box.Left, 9);
        Assert.Equal(0.65, still[0].Box.Top, 9);
        Assert.Equal(0.59, still[1].Box.Top, 9);
        Assert.Equal(0.03, still[1].Box.Bottom - still[1].Box.Top, 9);

        var scrolled = before.Select(item => item with { Box = item.Box with { Top = item.Box.Top - 0.02, Bottom = item.Box.Bottom - 0.02 } }).ToList();
        Assert.Equal(scrolled, PhoneSteady.SteadyPositions(scrolled, before, 16.0 / 9));

        ScreenTranslation.Item[] one = [jiggled[0] with { Box = jiggled[0].Box with { Top = 0.665, Bottom = 0.705 } }, jiggled[1]];
        var mixed = PhoneSteady.SteadyPositions(one, before, 16.0 / 9);
        Assert.Equal(0.665, mixed[0].Box.Top, 9);
        Assert.Equal(0.59, mixed[1].Box.Top, 9);

        ScreenTranslation.Item[] other = [jiggled[0], jiggled[1] with { Translation = "Başka" }];
        Assert.Equal(other[1].Box, PhoneSteady.SteadyPositions(other, before, 16.0 / 9)[1].Box);
    }

    [Fact]
    public void PanelAnchorIgnoresHandShakeAndFollowsARealMove()
    {
        var pose = new GamePhoneGeometry.Pose(0.70, 0.19, 0.70, 0.87);
        var shaken = new GamePhoneGeometry.Pose(0.704, 0.186, 0.703, 0.874);
        Assert.Equal(pose, PhoneSteady.SteadyPose(shaken, pose));
        var moved = new GamePhoneGeometry.Pose(0.66, 0.19, 0.66, 0.87);
        Assert.Equal(moved, PhoneSteady.SteadyPose(moved, pose));
        Assert.Equal(shaken, PhoneSteady.SteadyPose(shaken, null));
    }

    [Fact]
    public void PanelMessagesAreComparedByOrderAndTextNotByTheirFlowBoxes()
    {
        var card = Item("", new(0.2, 0.2, 0.5, 0.8)) with { Translation = ScreenPhoneCard.BackdropText, Panel = ScreenPhoneCard.PanelPart.Card };
        var message = Item("Hi", new(0.22, 0.3, 0.4, 0.34)) with { Panel = ScreenPhoneCard.PanelPart.Theirs };
        var nudged = message with { Box = message.Box with { Top = 0.304 } };
        Assert.True(PhoneSteady.SamePicture([card, message], [card, nudged]));
        Assert.False(PhoneSteady.SamePicture([card, message], [card, message with { Translation = "Selam" }]));
        Assert.False(PhoneSteady.SamePicture([card, message], [card with { Box = card.Box with { Left = 0.21 } }, message]));
        Assert.False(PhoneSteady.SamePicture([Item("Hi", message.Box)], [Item("Hi", nudged.Box)]));
    }

    [Fact]
    public void InkOnTheSameSideOfTheBubbleKeepsItsColor()
    {
        Assert.True(PhoneSteady.SameInk("#000000", "#584048", "#C8B0B8"));
        Assert.False(PhoneSteady.SameInk("#000000", "#FFFFFF", "#C8B0B8"));
        var before = Item("Casa De Donnie", new(0.65, 0.36, 0.77, 0.38)) with { Style = new("#C8B0B8", "#000000") };
        var grey = before with { Style = new("#C8B0B8", "#584048") };
        Assert.Equal(before.Style, Assert.Single(RegionWatcher.StablePhoneBlocks([grey], [before])).Style);
    }

    [Fact]
    public void SideOfABubbleStaysWithItsIdentity()
    {
        var spot = new TextBox(0.2, 0.2, 0.8, 0.3);
        var before = Item("Casa De Donnie", new(0.65, 0.36, 0.77, 0.38)) with { Phone = new(ScreenPhoneCard.Role.Incoming, spot) };
        var flipped = before with { Phone = new(ScreenPhoneCard.Role.Outgoing, spot) };
        Assert.Equal(ScreenPhoneCard.Role.Incoming, Assert.Single(RegionWatcher.StablePhoneBlocks([flipped], [before])).Phone?.Role);
    }

    [Fact]
    public void ShortMessageWithPunctuationNoiseKeepsItsTranslation()
    {
        var known = new Dictionary<string, string> { ["Ok."] = "Tamam.", ["Comprendo?"] = "Anladın mı?" };
        Assert.Equal("Tamam.", PhoneSteady.Translation("ok", known));
        Assert.Equal("Anladın mı?", PhoneSteady.Translation("Comprendo ?", known));
        Assert.Null(PhoneSteady.Translation("Ok?", known));
        Assert.Null(PhoneSteady.Translation("On", known));
        Assert.Equal("Yeni", PhoneSteady.Translation("New rnessage", new Dictionary<string, string> { ["New message"] = "Yeni" }));
    }
}
