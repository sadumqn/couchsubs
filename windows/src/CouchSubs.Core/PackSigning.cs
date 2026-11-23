// SPDX-License-Identifier: AGPL-3.0-only

using System.Reflection;
using System.Security.Cryptography;
using System.Text;

namespace CouchSubs.Core;

/// <summary>
/// Paket sunucusuna (server/packs) giden isteklerin imzası: paketler yalnız uygulama içinden alınsın.
/// <c>x-couchsubs-time</c> (unix saniye) ve <c>x-couchsubs-signature</c> = hex(HMAC-SHA256(sır, "GET\n&lt;yol&gt;\n&lt;zaman&gt;")).
/// Sır depoda değildir; yayın derlemesinde CI sırrı <c>PACKS_APP_SECRET</c>'tan <c>-p:CouchSubsPacksSecret</c> ile gömülür.
/// Sır yoksa (yerel geliştirici derlemesi) paket indirme hiç açılmaz. Mac/iPhone'daki CouchSubsCore/PackSigning.swift ve
/// Android'deki PackSigning.kt ile aynı imza.
/// </summary>
public static class PackSigning
{
    public const string TimeHeader = "x-couchsubs-time";
    public const string SignatureHeader = "x-couchsubs-signature";

    public static string Signature(string secret, string method, string path, long time)
    {
        var mac = HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes($"{method}\n{path}\n{time}"));
        return Convert.ToHexStringLower(mac);
    }

    /// <summary>İsteğe zaman ve imza başlıklarını ekler (yol: adresin kendi yolu, ör. "/v1/packs/gta-6").</summary>
    public static void Sign(HttpRequestMessage request, string secret, DateTimeOffset now)
    {
        var time = now.ToUnixTimeSeconds();
        var path = request.RequestUri?.AbsolutePath ?? "/";
        request.Headers.Remove(TimeHeader);
        request.Headers.Remove(SignatureHeader);
        request.Headers.TryAddWithoutValidation(TimeHeader, time.ToString(System.Globalization.CultureInfo.InvariantCulture));
        request.Headers.TryAddWithoutValidation(SignatureHeader, Signature(secret, request.Method.Method, path, time));
    }

    /// <summary>
    /// Uygulama sırrı: <c>COUCHSUBS_PACKS_SECRET</c> ortam değişkeni ya da derlemedeki <c>CouchSubsPacksSecret</c> bilgisi.
    /// Boş değer yok sayılır.
    /// </summary>
    public static string? ConfiguredSecret(string? environment = null, Assembly? assembly = null)
    {
        var fromBuild = (assembly ?? Assembly.GetEntryAssembly())?.GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(a => a.Key == "CouchSubsPacksSecret")?.Value;
        foreach (var candidate in new[] { environment ?? Environment.GetEnvironmentVariable("COUCHSUBS_PACKS_SECRET"), fromBuild })
        {
            var value = candidate?.Trim();
            if (!string.IsNullOrEmpty(value)) return value;
        }
        return null;
    }
}
