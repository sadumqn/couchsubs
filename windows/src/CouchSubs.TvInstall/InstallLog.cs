// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.TvInstall;

/// <summary>
/// TV kurulum günlüğü (Windows: %LOCALAPPDATA%\CouchSubs\tvinstall.log, Mac: ~/Library/Logs/CouchSubs/tvinstall.log).
/// Kurulum olmazsa kullanıcı bu dosyayı gönderir: her adım, TV'nin ve Samsung'un yanıtları burada. Samsung hesabının
/// jetonu ve parolalar yazılmaz. Dosya 1 MB'yi geçince eski yarısı silinir; yazılamazsa kurulum yine sürer.
/// </summary>
public sealed class InstallLog(string? path)
{
    internal const long MaxBytes = 1 << 20;
    private static readonly object Gate = new();

    /// <summary>Yol yoksa (testler) hiçbir şey yazılmaz.</summary>
    public string? Path { get; } = path;

    public void Write(string message)
    {
        if (Path is null) return;
        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message.TrimEnd()}\n";
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
                if (File.Exists(Path) && new FileInfo(Path).Length > MaxBytes)
                {
                    var old = File.ReadAllText(Path);
                    // Eski yarı silinir; kalan kısım satır başından başlar.
                    var start = old.IndexOf('\n', old.Length / 2);
                    File.WriteAllText(Path, start < 0 ? "" : old[(start + 1)..]);
                }
                File.AppendAllText(Path, line);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // Günlük yazılamasa da kurulum sürer.
            }
        }
    }
}
