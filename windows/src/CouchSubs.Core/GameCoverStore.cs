// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// User-supplied cover art for game-pack tiles. Artwork is stored only in the user's
/// application-data directory; no third-party images are bundled or fetched.
/// </summary>
public static class GameCoverStore
{
    /// <summary>Each 128px PNG thumbnail is capped at 2 MiB.</summary>
    public const int MaxCoverBytes = 2 * 1024 * 1024;

    public static string DefaultDirectory { get; } = Path.Combine(AppDataPaths.Root, "covers");

    /// <summary>An unsafe or missing pack ID never becomes a file-system path.</summary>
    public static string? PathFor(string? packId, string? directory = null)
    {
        if (string.IsNullOrEmpty(packId) || packId.Length > 120 || packId[0] == '-'
            || packId.Any(c => c is not (>= 'a' and <= 'z') and not (>= '0' and <= '9') and not '-'))
            return null;
        return Path.Combine(directory ?? DefaultDirectory, packId + ".png");
    }

    /// <summary>Atomically publish a validated PNG thumbnail; failed input cannot replace an existing cover.</summary>
    public static void Save(string packId, byte[] png, string? directory = null)
    {
        var destination = PathFor(packId, directory)
            ?? throw new ArgumentException("Invalid game pack ID.", nameof(packId));
        ReadOnlySpan<byte> signature = [137, 80, 78, 71, 13, 10, 26, 10];
        if (png.Length <= signature.Length || png.Length > MaxCoverBytes
            || !png.AsSpan(0, signature.Length).SequenceEqual(signature))
            throw new InvalidDataException("A small PNG cover is required.");

        var folder = Path.GetDirectoryName(destination)!;
        Directory.CreateDirectory(folder);
        var temporary = Path.Combine(folder, "." + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            File.WriteAllBytes(temporary, png);
            File.Move(temporary, destination, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public static bool Remove(string packId, string? directory = null)
    {
        var path = PathFor(packId, directory);
        if (path is null || !File.Exists(path)) return false;
        File.Delete(path);
        return true;
    }
}
