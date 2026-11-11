// SPDX-License-Identifier: AGPL-3.0-only
// Hata kodlarının anlamları Apps2Samsung'un TizenInstallDiagnostics'inden (MIT, Patrick Stel):
// https://github.com/Jellyfin2Samsung/Samsung-Jellyfin-Installer

namespace CouchSubs.TvInstall.Samsung;

/// <summary><c>vd_appinstall</c> çıktısından anlaşılan sorun.</summary>
internal enum InstallProblem
{
    /// <summary>Çıktıda hata yok.</summary>
    None,
    /// <summary>Kurulum sırasında TV bağlantısı koptu.</summary>
    ConnectionLost,
    /// <summary>TV'de yer yok ([116]).</summary>
    NotEnoughSpace,
    /// <summary>TV'de aynı kimlikli, başka sertifikayla imzalı kopya var ([118, -12] same id / [118, -11] / [118012]).</summary>
    CertificateMismatch,
    /// <summary>TV sertifikanın kendisini reddetti (biçim, zincir ya da süresi geçmiş).</summary>
    CertificateRejected,
    /// <summary>TV'nin saati geride: sertifika "henüz geçerli değil".</summary>
    CertificateNotYetValid,
    /// <summary>TV'nin güvenlik yöneticisi paket kimliğini engelliyor ([118, -22] / [118022]).</summary>
    PackageBlocked,
    /// <summary>Paket bu TV'ye uygun değil ([118, -4], [118, -19]).</summary>
    Incompatible,
    /// <summary>Başka bir kurulum hatası.</summary>
    Other,
}

/// <summary>TV, kurulum başarısız olsa da komutu başarılı bitirir; ne olduğu çıktıdan anlaşılır.</summary>
internal static class SamsungInstallDiagnostics
{
    private const StringComparison IC = StringComparison.OrdinalIgnoreCase;

    /// <summary>
    /// Çıktı kurulumun başarısız olduğunu mu söylüyor? <c>install failed[…]</c>, <c>val[fail]</c>, yer ve bağlantı
    /// işaretleri. Yalın "failed" aranmaz; ilgisiz bir satır başarısızlık sanılmasın.
    /// </summary>
    public static bool Failed(string? log) =>
        Has(log, "install failed") || Has(log, "val[fail]") || Has(log, "not enough space") ||
        Has(log, "download failed[116]") || IsConnectionLost(log);

    public static InstallProblem Classify(string? log)
    {
        if (!Failed(log)) return InstallProblem.None;
        if (IsConnectionLost(log)) return InstallProblem.ConnectionLost;
        if (Has(log, "install failed[118, -4]") || Has(log, "install failed[118, -19]") || Has(log, "install failed[118019]"))
            return InstallProblem.Incompatible;
        if (Has(log, "download failed[116]") || Has(log, "not enough space")) return InstallProblem.NotEnoughSpace;
        var certificate = Has(log, "install failed[118, -12]") || Has(log, "install failed[118012]") ||
                          Has(log, "install failed[118, -11]") || Has(log, "install failed[118011]");
        // [118, -12] "Check certificate error" iki şey olabilir: TV'de başka sertifikalı kopya (kaldırınca düzelir) ya da
        // TV'nin sertifikayı reddetmesi (kaldırmak işe yaramaz; saat, internet ya da yeni sertifika gerekir).
        if (certificate && Has(log, "Check certificate error") && !Has(log, "same id and different certificate"))
        {
            if (Has(log, "not valid yet")) return InstallProblem.CertificateNotYetValid;
            return InstallProblem.CertificateRejected;
        }
        if (certificate || Has(log, "Author certificate not match")) return InstallProblem.CertificateMismatch;
        if (Has(log, "install failed[118, -22]") || Has(log, "install failed[118022]")) return InstallProblem.PackageBlocked;
        return InstallProblem.Other;
    }

    /// <summary>Eski kopyayı kaldırıp bir kez daha kurmak işe yarayabilir mi?</summary>
    public static bool RemovingOldCopyMayHelp(InstallProblem problem) =>
        problem is InstallProblem.CertificateMismatch or InstallProblem.PackageBlocked or InstallProblem.Other;

    public static SamsungInstallError ToError(InstallProblem problem) => problem switch
    {
        InstallProblem.ConnectionLost => SamsungInstallError.ConnectionLost,
        InstallProblem.NotEnoughSpace => SamsungInstallError.NotEnoughSpace,
        InstallProblem.CertificateMismatch => SamsungInstallError.CertificateMismatch,
        InstallProblem.CertificateRejected => SamsungInstallError.CertificateRejected,
        InstallProblem.CertificateNotYetValid => SamsungInstallError.TvClockWrong,
        InstallProblem.PackageBlocked => SamsungInstallError.PackageBlocked,
        _ => SamsungInstallError.InstallFailed,
    };

    /// <summary>
    /// Kullanıcıya gösterilecek kısa ayrıntı: TV'nin hata satırı (<c>install failed[…]</c>, sebep), yoksa çıktının
    /// sonu. Bütün çıktı günlüğe yazılır.
    /// </summary>
    public static string Summary(string? log)
    {
        if (string.IsNullOrWhiteSpace(log)) return "TV yanıt vermedi";
        var lines = log.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var key = lines.Where(line => line.Contains("fail", IC) || line.Contains("error", IC) || line.Contains("reason", IC) ||
                                      line.Contains("not match", IC) || line.Contains("space", IC))
            .Distinct().Take(3).ToList();
        var text = key.Count > 0 ? string.Join(" | ", key) : string.Join(" | ", lines.TakeLast(3));
        return text.Length <= 400 ? text : text[..400] + "…";
    }

    private static bool IsConnectionLost(string? log) =>
        Has(log, "transport connection") || Has(log, "connection reset by peer") || Has(log, "broken pipe");

    private static bool Has(string? log, string token) => !string.IsNullOrEmpty(log) && log.Contains(token, IC);
}
