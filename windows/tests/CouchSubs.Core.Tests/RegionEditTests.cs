// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using Xunit;
using static CouchSubs.Core.RegionEdit;

namespace CouchSubs.Core.Tests;

/// <summary>Alan çerçevesinin tutamaçları, taşınması ve boyutlandırılması (Mac/iPhone RegionEditTests ve Android ile aynı örnekler).</summary>
public class RegionEditTests
{
    private static readonly CropRegion Area = new(0.60, 0.90, 0.20, 0.80);
    private const double Grab = 0.02;

    private static void Close(CropRegion expected, CropRegion actual) =>
        Assert.True(expected.IsClose(actual, 1e-9), $"{expected} != {actual}");

    [Theory]
    [InlineData(0.20, 0.60, Handle.Left | Handle.Top)]
    [InlineData(0.50, 0.60, Handle.Top)]
    [InlineData(0.80, 0.75, Handle.Right)]
    [InlineData(0.81, 0.91, Handle.Right | Handle.Bottom)]
    [InlineData(0.50, 0.75, Handle.None)]
    public void HandlesAreTheCornersAndEdgeMiddles(double x, double y, Handle handle) =>
        Assert.Equal(handle, HandleAt(Area, x, y, Grab, Grab));

    [Fact]
    public void FarOutsideIsNoHandle()
    {
        Assert.Null(HandleAt(Area, 0.10, 0.75, Grab, Grab));
        Assert.Null(HandleAt(Area, 0.50, 0.30, Grab, Grab));
    }

    [Fact]
    public void ATinyFrameTakesTheNearerEdge() =>
        Assert.Equal(Handle.Right, HandleAt(new CropRegion(0.50, 0.90, 0.50, 0.51), 0.512, 0.70, Grab, Grab));

    [Fact]
    public void EightHandlesSitOnTheCornersAndEdgeMiddles()
    {
        var handles = Handles(Area);
        Assert.Equal(8, handles.Count);
        Assert.Contains((0.50, 0.60), handles);
        Assert.Contains((0.80, 0.75), handles);
        Assert.Contains((0.20, 0.90), handles);
    }

    [Fact]
    public void MovingKeepsTheSizeAndStaysInTheFrame()
    {
        Close(new CropRegion(0.65, 0.95, 0.10, 0.70), Dragged(Area, Handle.None, -0.10, 0.05, centered: true));
        Close(new CropRegion(0.70, 1.00, 0.40, 1.00), Dragged(Area, Handle.None, 0.50, 0.50, centered: false));
    }

    [Fact]
    public void TheSubtitleAreaWidensFromTheMiddle()
    {
        // Sağ kenar 0.1 dışarı: sol kenar da 0.1 açılır, orta (0.5) yerinde kalır.
        Close(new CropRegion(0.60, 0.90, 0.10, 0.90), Dragged(Area, Handle.Right, 0.10, 0, centered: true));
        // Sol kenar içeri: iki yandan daralır.
        Close(new CropRegion(0.60, 0.90, 0.30, 0.70), Dragged(Area, Handle.Left, 0.10, 0, centered: true));
        // Karenin kenarına dayanınca durur; ortası kaymaz.
        Close(new CropRegion(0.60, 0.90, 0.00, 1.00), Dragged(Area, Handle.Right, 0.50, 0, centered: true));
        // Köşe: yatay ortadan, dikey yalnız o kenar.
        Close(new CropRegion(0.60, 0.95, 0.15, 0.85), Dragged(Area, Handle.Right | Handle.Bottom, 0.05, 0.05, centered: true));
    }

    [Fact]
    public void ExtraAreasResizeFromTheDraggedEdgeOnly()
    {
        Close(new CropRegion(0.60, 0.90, 0.20, 0.90), Dragged(Area, Handle.Right, 0.10, 0, centered: false));
        Close(new CropRegion(0.50, 0.90, 0.10, 0.80), Dragged(Area, Handle.Left | Handle.Top, -0.10, -0.10, centered: false));
    }

    [Fact]
    public void WithoutKeepCenteredALeftAlignedSubtitleAreaKeepsItsLeftEdge()
    {
        // Sola yaslı altyazı: "Ortada tut" kapalıyken sağ kenar çekilince sol kenar yerinde kalır.
        var left = new CropRegion(0.80, 0.95, 0.05, 0.45);
        Close(new CropRegion(0.80, 0.95, 0.05, 0.55), Dragged(left, Handle.Right, 0.10, 0, centered: false));
        Close(new CropRegion(0.70, 0.95, 0.00, 0.45), Dragged(left, Handle.Left | Handle.Top, -0.05, -0.10, centered: false));
        // Açıkken aynı sürükleme sol kenarı da oynatır ve karenin kenarına dayar.
        Close(new CropRegion(0.80, 0.95, 0.00, 0.50), Dragged(left, Handle.Right, 0.10, 0, centered: true));
    }

    [Fact]
    public void AFrameNeverGetsSmallerThanTheMinimumOrFlips()
    {
        var narrow = Dragged(Area, Handle.Left, 0.90, 0, centered: false);
        Assert.Equal(Area.Right - MinimumSize, narrow.Left, 9);
        var flat = Dragged(Area, Handle.Top, 0, 0.90, centered: false);
        Assert.Equal(Area.Bottom - MinimumSize, flat.Top, 9);
        var centered = Dragged(Area, Handle.Right, -0.90, 0, centered: true);
        Assert.Equal(MinimumSize, centered.Right - centered.Left, 9);
        Assert.Equal(0.50, (centered.Left + centered.Right) / 2, 9);
    }
}
