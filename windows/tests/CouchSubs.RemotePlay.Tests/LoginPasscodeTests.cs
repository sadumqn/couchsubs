// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.RemotePlay.Tests;

/// <summary>PS5 giriş şifresi: kayıtlıysa ilk istekte gönderilir; yoksa ya da yanlışsa oturum kapanır (Mac ile aynı).</summary>
public class LoginPasscodeTests
{
    [Theory]
    [InlineData(" 1234 ", "1234")]
    [InlineData("0007", "0007")]
    [InlineData(null, null)]
    [InlineData("", null)]
    [InlineData("123", null)]
    [InlineData("12345", null)]
    [InlineData("12a4", null)]
    [InlineData("١٢٣٤", null)]
    public void OnlyFourDigitsAreKept(string? value, string? expected) => Assert.Equal(expected, LoginPasscode.Normalized(value));

    [Fact]
    public void SavedPasscodeIsSentAsAsciiOnFirstRequest()
    {
        var (pin, stop) = LoginPasscode.Reply("1234", incorrect: false);
        Assert.Equal(new byte[] { 0x31, 0x32, 0x33, 0x34 }, pin);
        Assert.Null(stop);
    }

    [Fact]
    public void MissingPasscodeStopsTheSession()
    {
        Assert.Equal(DisconnectKind.LoginPasscode, StopOf(LoginPasscode.Reply(null, incorrect: false)));
        Assert.Equal(DisconnectKind.LoginPasscode, StopOf(LoginPasscode.Reply("12", incorrect: false)));
    }

    /// <summary>PS5 şifreyi yeniden istiyorsa önceki yanlıştı: aynı şifre tekrar gönderilmez.</summary>
    [Fact]
    public void IncorrectPasscodeIsNotResent() =>
        Assert.Equal(DisconnectKind.LoginPasscodeIncorrect, StopOf(LoginPasscode.Reply("1234", incorrect: true)));

    /// <summary>Oturum kapanıyorsa gönderilecek şifre yoktur.</summary>
    private static DisconnectKind? StopOf((byte[]? Pin, DisconnectKind? Stop) reply)
    {
        Assert.Null(reply.Pin);
        return reply.Stop;
    }
}
