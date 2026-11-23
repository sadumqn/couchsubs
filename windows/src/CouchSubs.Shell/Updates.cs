// SPDX-License-Identifier: AGPL-3.0-only

using System.Reflection;
using System.Text.Json;

namespace CouchSubs.Shell;

/// <summary>Uygulama güncellemesi (gerçekte Velopack, GitHub sürümlerinden).</summary>
public interface IUpdater
{
    /// <summary>Kurulum dosyasıyla kurulduysa kendini günceller; zip'ten açıldıysa yalnız sürüm sayfasını gösteririz.</summary>
    bool CanUpdateItself { get; }
    /// <summary>Kurulum dosyasının indirildiği sayfa (sitemiz); zip kopyası ve uygulanamayan güncelleme buraya yönlenir.</summary>
    Uri DownloadPage { get; }
    /// <summary>Güncelleme denemelerinin kaydı; yoksa (testler, geliştirici derlemesi) null.</summary>
    UpdateAttemptJournal? Attempts => null;
    /// <summary>Velopack'in güncellemeyi uygularken yazdığı günlüğün yolu (velopack.log); bilinmiyorsa null.</summary>
    string? UpdateLogPath => null;
    /// <summary>Daha yeni sürüm varsa numarası, yoksa null.</summary>
    Task<string?> CheckAsync();
    Task<IReadOnlyList<ReleaseNoteRun>> ReleaseNotesAsync(string version);
    /// <summary>
    /// İndirir, kurar ve uygulamayı yeniden başlatır. <paramref name="beforeRestart"/> indirme bitince, uygulama
    /// kapanmadan hemen önce çağrılır (deneme kaydı).
    /// </summary>
    Task InstallAsync(IProgress<double> progress, Action? beforeRestart = null);
}

/// <summary>Uygulanmak üzere uygulamayı kapatan güncelleme: hangi sürümden hangisine, ne zaman.</summary>
public sealed record UpdateAttempt(string FromVersion, string TargetVersion, DateTimeOffset At);

/// <summary>
/// Güncelleme denemesinin kaydı. "Şimdi güncelle" uygulamayı kapatır, Velopack (Update.exe) kurulum klasörünü değiştirir
/// ve yeni sürümü açar; klasör kilitliyse (güvenlik yazılımı, kapanmayan bir süreç) eski sürüm yeniden açılır ve aynı
/// "yeni sürüm çıktı" şeridi sonsuza dek görünürdü. Kapanmadan önce hedef sürüm yazılır; sonraki açılışta sürüm hâlâ
/// hedefin gerisindeyse deneme başarısız sayılır. Hedefe ulaşılınca (ya da kurulum dosyasıyla kurulunca) kayıt silinir.
/// </summary>
public sealed class UpdateAttemptJournal(string path, string currentVersion, Func<DateTimeOffset>? clock = null)
{
    /// <summary>%LOCALAPPDATA%\CouchSubs\guncelleme-denemesi.json (Velopack'in kurulum klasörünün dışında).</summary>
    public static string DefaultPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CouchSubs", "guncelleme-denemesi.json");

    public string CurrentVersion => currentVersion;

    public void Record(string targetVersion)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var attempt = new UpdateAttempt(currentVersion, targetVersion, (clock ?? (() => DateTimeOffset.Now))());
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(attempt));
            File.Move(temporary, path, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    public UpdateAttempt? Read()
    {
        try
        {
            return File.Exists(path) ? JsonSerializer.Deserialize<UpdateAttempt>(File.ReadAllText(path)) : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or NotSupportedException)
        {
            return null;
        }
    }

    public void Clear()
    {
        try { File.Delete(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>Açılışta: önceki deneme bu sürüme ulaşamadıysa o deneme; ulaştıysa kayıt silinir ve null döner.</summary>
    public UpdateAttempt? FailedAttempt()
    {
        if (Read() is not { TargetVersion.Length: > 0 } attempt) return null;
        if (!AppVersion.IsNewer(attempt.TargetVersion, currentVersion))
        {
            Clear();
            return null;
        }
        return attempt;
    }
}

/// <summary>Sürüm numaraları: "0.1.0-beta.10" (anlamsal sürüm, ön sürüm parçaları sayıysa sayı olarak karşılaştırılır).</summary>
public static class AppVersion
{
    /// <summary>Derlemenin sürümü (CI etiketten verir: -p:Version=0.1.0-beta.10); "+commit" eki atılır.</summary>
    public static string Current(Assembly assembly) =>
        (assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0").Split('+')[0];

    public static bool IsNewer(string candidate, string current) => Compare(candidate, current) > 0;

    public static int Compare(string a, string b)
    {
        var (coreA, preA) = Split(a);
        var (coreB, preB) = Split(b);
        for (var i = 0; i < Math.Max(coreA.Length, coreB.Length); i++)
        {
            var x = i < coreA.Length ? coreA[i] : 0;
            var y = i < coreB.Length ? coreB[i] : 0;
            if (x != y) return x.CompareTo(y);
        }
        // Ön sürümü olmayan, ön sürümlüden yenidir (0.1.0 > 0.1.0-beta.9).
        if (preA.Length == 0 || preB.Length == 0) return preB.Length.CompareTo(preA.Length);
        for (var i = 0; i < Math.Max(preA.Length, preB.Length); i++)
        {
            if (i >= preA.Length) return -1;
            if (i >= preB.Length) return 1;
            var numberA = int.TryParse(preA[i], out var na);
            var numberB = int.TryParse(preB[i], out var nb);
            var result = numberA && numberB ? na.CompareTo(nb)
                : numberA ? -1 : numberB ? 1 : string.CompareOrdinal(preA[i], preB[i]);
            if (result != 0) return Math.Sign(result);
        }
        return 0;
    }

    private static (int[] Core, string[] Pre) Split(string version)
    {
        var text = version.Trim().TrimStart('v').Split('+')[0];
        var dash = text.IndexOf('-');
        var core = (dash < 0 ? text : text[..dash]).Split('.').Select(part => int.TryParse(part, out var n) ? n : 0).ToArray();
        var pre = dash < 0 ? [] : text[(dash + 1)..].Split('.');
        return (core, pre);
    }
}
