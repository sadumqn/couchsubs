// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell.Tests;

/// <summary>Bilgisayar ekranındaki altyazı penceresinin yeri: bozuk ya da eski kayıt pencereyi ekran dışına ya da sıfır boya koymaz.</summary>
public class OverlayPlacementTests
{
    /// <summary>1920×1080 tek ekran, altta 48 birimlik görev çubuğu.</summary>
    private static readonly ScreenArea Screen = new(0, 0, 1920, 1080);
    private static readonly ScreenArea Work = new(0, 0, 1920, 1032);
    private const double Height = 500;

    private static void AssertDefault(OverlayBounds placed)
    {
        Assert.Equal(1344, placed.Width);
        Assert.Equal((1920 - 1344) / 2.0, placed.Left);
        Assert.Equal(1032 - 1032 * 0.04 - Height, placed.Top, 6);
    }

    [Fact]
    public void NothingSavedOpensAtBottomCenter() => AssertDefault(OverlayPlacement.Place(null, Screen, Work, Height));

    [Fact]
    public void SavedPlaceOnScreenIsKept()
    {
        var placed = OverlayPlacement.Place(new OverlayBounds(100, 400, 1000), Screen, Work, Height);
        Assert.Equal(new OverlayBounds(100, 400, 1000), placed);
    }

    [Theory]
    [InlineData(double.NaN, 400, 1000)]
    [InlineData(100, double.PositiveInfinity, 1000)]
    [InlineData(100, 400, 0)]
    [InlineData(100, 400, -50)]
    [InlineData(100, 400, double.NaN)]
    public void BrokenSaveFallsBackToDefault(double left, double top, double width) =>
        AssertDefault(OverlayPlacement.Place(new OverlayBounds(left, top, width), Screen, Work, Height));

    /// <summary>Sağdaki ikinci ekran çıkarıldı: kayıtlı yer artık hiçbir ekranda değil.</summary>
    [Theory]
    [InlineData(2100, 400)]
    [InlineData(-3000, 400)]
    [InlineData(100, 1060)]
    [InlineData(100, -480)]
    public void OffScreenSaveFallsBackToDefault(double left, double top) =>
        AssertDefault(OverlayPlacement.Place(new OverlayBounds(left, top, 1000), Screen, Work, Height));

    [Fact]
    public void SecondScreenOnTheLeftIsKept()
    {
        var both = new ScreenArea(-1920, 0, 3840, 1080);
        var placed = OverlayPlacement.Place(new OverlayBounds(-1600, 500, 1200), both, Work, Height);
        Assert.Equal(new OverlayBounds(-1600, 500, 1200), placed);
    }

    [Fact]
    public void WidthIsClampedToScreens()
    {
        Assert.Equal(1920, OverlayPlacement.Place(new OverlayBounds(0, 400, 99999), Screen, Work, Height).Width);
        Assert.Equal(OverlayPlacement.SmallestWidth, OverlayPlacement.Place(new OverlayBounds(0, 400, 10), Screen, Work, Height).Width);
    }

    /// <summary>Ekran bilgisi okunamadıysa (sıfır ya da NaN) pencere yine geçerli bir yerde ve boyda açılır.</summary>
    [Fact]
    public void UnreadableScreensStillGiveAValidPlace()
    {
        var empty = new ScreenArea(0, 0, 0, 0);
        var broken = new ScreenArea(double.NaN, 0, double.NaN, 1080);
        foreach (var placed in new[]
                 {
                     OverlayPlacement.Place(null, empty, empty, Height),
                     OverlayPlacement.Place(new OverlayBounds(100, 100, 800), broken, broken, double.NaN),
                     OverlayPlacement.Place(null, Screen, empty, 0),
                 })
        {
            Assert.True(double.IsFinite(placed.Left) && double.IsFinite(placed.Top) && double.IsFinite(placed.Width));
            Assert.True(placed.Width >= OverlayPlacement.SmallestWidth);
        }
    }

    [Fact]
    public void ClampWidthNeverThrows()
    {
        // Math.Clamp(x, 320, 200) hata verirdi (ekranlar dar okunduysa).
        Assert.Equal(OverlayPlacement.SmallestWidth, OverlayPlacement.ClampWidth(1000, 200));
        Assert.Equal(OverlayPlacement.SmallestWidth, OverlayPlacement.ClampWidth(double.NaN, 1920));
        Assert.Equal(1920, OverlayPlacement.ClampWidth(5000, 1920));
        Assert.Equal(900, OverlayPlacement.ClampWidth(900, double.NaN));
    }

    [Fact]
    public void NonFiniteBoundsAreNotSaved()
    {
        Assert.Null(OverlayPlacement.ToSave(double.NaN, 10, 800));
        Assert.Null(OverlayPlacement.ToSave(10, double.NegativeInfinity, 800));
        Assert.Null(OverlayPlacement.ToSave(10, 10, 0));
        Assert.Equal(new OverlayBounds(10, 21, 800), OverlayPlacement.ToSave(10.2, 20.6, 799.7));
    }

    [Fact]
    public void HeightAndScaleStayPositive()
    {
        Assert.Equal(1, OverlayPlacement.Scale(0));
        Assert.Equal(1, OverlayPlacement.Scale(double.NaN));
        Assert.Equal(2, OverlayPlacement.Scale(2160));
        Assert.Equal(OverlayPlacement.Height(46, 1), OverlayPlacement.Height(0, 1));
        Assert.Equal(OverlayPlacement.Height(46, 1), OverlayPlacement.Height(-5, 1));
        Assert.True(OverlayPlacement.Height(36, 0.5) > 0);
    }
}
