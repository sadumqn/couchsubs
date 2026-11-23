// SPDX-License-Identifier: AGPL-3.0-only

using System.Runtime.InteropServices;

namespace CouchSubs.Core.Dubbing;

/// <summary>
/// pocket-tts içindeki sentencepiece (C++) Windows'ta dosya yolunu ANSI kod sayfasıyla açar: "C:\Users\Şafak\..." gibi
/// ASCII dışı harfli yolda sözlüğü bulamaz. Yol önce 8.3 kısa adıyla ASCII'ye çevrilir; sürücüde kısa adlar kapalıysa
/// sözlük ASCII bir klasöre (%ProgramData%, sonra C:\Users\Public) kopyalanır. macOS yolları UTF-8 açtığı için orada gerekmez.
/// </summary>
public static partial class NativeToolPath
{
    public static bool IsAscii(string path) => path.All(c => c < 128);

    /// <summary>Yol ASCII ise kendisi, değilse ASCII çıkan kısa adı; ikisi de olmazsa null.</summary>
    public static string? Resolve(string path, Func<string, string?> shortPath)
    {
        if (IsAscii(path)) return path;
        var shortened = shortPath(path);
        return shortened is not null && IsAscii(shortened) ? shortened : null;
    }

    /// <summary>
    /// Sözlük dosyasının pocket-tts'e verilecek yolu. Kısa ad işe yaramazsa dosya ASCII köklerden ilk yazılabilir olana
    /// kopyalanır; hiçbiri olmazsa özgün yol döner (hata mesajı yine görünür).
    /// </summary>
    public static string Tokenizer(string file, Func<string, string?> shortPath, IEnumerable<string?> fallbackRoots,
                                   Action<string, string> copy)
    {
        if (Resolve(file, shortPath) is { } resolved) return resolved;
        foreach (var root in fallbackRoots)
        {
            if (string.IsNullOrEmpty(root) || !IsAscii(root)) continue;
            var target = Path.Combine(root, "CouchSubs", "models", "tts-tr", DubbingModel.Revision, "tokenizer.model");
            try
            {
                copy(file, target);
                return target;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
        return file;
    }

    /// <summary>Bu bilgisayarda çalışan sürüm: Windows kısa adı, %ProgramData% ve Public klasörü.</summary>
    public static string ForTokenizer(string file)
    {
        if (!OperatingSystem.IsWindows()) return file;
        return Tokenizer(file, ShortPath,
            [Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), Environment.GetEnvironmentVariable("PUBLIC")],
            CopyIfChanged);
    }

    private static unsafe string? ShortPath(string path)
    {
        const int capacity = 1024;
        var buffer = stackalloc char[capacity];
        var length = GetShortPathName(path, buffer, capacity);
        return length is 0 or >= capacity ? null : new string(buffer, 0, (int)length);
    }

    /// <summary>Aynı içerik zaten oradaysa (başka kullanıcının kopyası da olabilir) dokunulmaz.</summary>
    private static void CopyIfChanged(string source, string target)
    {
        if (File.Exists(target) && File.ReadAllBytes(target).AsSpan().SequenceEqual(File.ReadAllBytes(source))) return;
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.Copy(source, target, overwrite: true);
    }

    [LibraryImport("kernel32.dll", EntryPoint = "GetShortPathNameW", StringMarshalling = StringMarshalling.Utf16)]
    private static unsafe partial uint GetShortPathName(string longPath, char* shortPath, uint length);
}
