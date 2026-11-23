// SPDX-License-Identifier: AGPL-3.0-only

using System.Security.Cryptography;
using CouchSubs.Core.LgTv;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Gerçek SSH sunucusuyla denemeler için COUCHSUBS_TEST_SSH="host:port:kullanıcı:anahtar-dosyası" verilir; sunucu LG
/// geliştirici modu gibi yalnız ssh-rsa kabul edecek biçimde kurulabilir. Verilmezse yalnız bağlantısız denemeler çalışır.
/// </summary>
public class SshNetShellTests
{
    private static (string Host, int Port, string User, string Key)? Server =>
        Environment.GetEnvironmentVariable("COUCHSUBS_TEST_SSH")?.Split(':', 4) is [var host, var port, var user, var key]
            ? (host, int.Parse(port), user, key)
            : null;

    private static string RandomKeyFile()
    {
        using var rsa = RSA.Create(2048);
        var file = Path.GetTempFileName();
        File.WriteAllText(file, rsa.ExportRSAPrivateKeyPem());
        return file;
    }

    [Fact]
    public async Task ClosedPortIsUnreachable()
    {
        var key = RandomKeyFile();
        try
        {
            var shell = new SshNetShell("127.0.0.1", 1, key) { ConnectTimeout = TimeSpan.FromSeconds(2), KeyServerPort = 1 };
            var error = await Assert.ThrowsAsync<DevModeException>(() => shell.RunAsync("true"));
            Assert.Equal(DevModeError.Unreachable, error.Error);
        }
        finally
        {
            File.Delete(key);
        }
    }

    /// <summary>#200, #1116: Key Server anahtarı verdi ama SSH reddediyor (webOS Hub'lı TV): "TV yanıt vermedi" denmez.</summary>
    [Fact]
    public async Task ClosedSshWhileKeyServerAnswersIsAClosedDeveloperConnection()
    {
        var key = RandomKeyFile();
        var keyServer = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        keyServer.Start();
        try
        {
            var port = ((System.Net.IPEndPoint)keyServer.LocalEndpoint).Port;
            var shell = new SshNetShell("127.0.0.1", 1, key) { ConnectTimeout = TimeSpan.FromSeconds(2), KeyServerPort = port };
            var error = await Assert.ThrowsAsync<DevModeException>(() => shell.RunAsync("true"));
            Assert.Equal(DevModeError.DevConnectionClosed, error.Error);
        }
        finally
        {
            keyServer.Stop();
            File.Delete(key);
        }
    }

    [Fact]
    public async Task UnreadableKeyIsRefused()
    {
        var key = Path.GetTempFileName();
        await File.WriteAllTextAsync(key, "anahtar değil");
        try
        {
            var error = await Assert.ThrowsAsync<DevModeException>(() => new SshNetShell("127.0.0.1", 1, key).RunAsync("true"));
            Assert.Equal(DevModeError.KeyRefused, error.Error);
        }
        finally
        {
            File.Delete(key);
        }
    }

    [Fact]
    public async Task CommandOutputAndExitStatusAreRead()
    {
        if (Server is not var (host, port, user, key)) return;
        var result = await new SshNetShell(host, port, key, user).RunAsync("echo merhaba; echo uyarı >&2; exit 3");
        Assert.Equal(3, result.Status);
        Assert.Equal("merhaba\nuyarı\n", result.Output);
    }

    [Fact]
    public async Task InputFileReachesTheCommandWhole()
    {
        if (Server is not var (host, port, user, key)) return;
        var package = Path.GetTempFileName();
        await File.WriteAllBytesAsync(package, RandomNumberGenerator.GetBytes(300_000));
        var remote = $"/tmp/couchsubs-test-{Guid.NewGuid():N}";
        try
        {
            var shell = new SshNetShell(host, port, key, user);
            var upload = await shell.RunAsync($"cat > {remote}", package);
            Assert.Equal(0, upload.Status);
            var size = await shell.RunAsync($"wc -c < {remote}; rm -f {remote}");
            Assert.Equal("300000", size.Output.Trim());
        }
        finally
        {
            File.Delete(package);
        }
    }

    [Fact]
    public async Task UnknownKeyIsRefused()
    {
        if (Server is not var (host, port, user, _)) return;
        var key = RandomKeyFile();
        try
        {
            var error = await Assert.ThrowsAsync<DevModeException>(() => new SshNetShell(host, port, key, user).RunAsync("true"));
            Assert.Equal(DevModeError.KeyRefused, error.Error);
        }
        finally
        {
            File.Delete(key);
        }
    }
}
