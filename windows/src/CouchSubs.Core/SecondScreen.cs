// SPDX-License-Identifier: AGPL-3.0-only

using QRCoder;

namespace CouchSubs.Core;

/// <summary>
/// "Başka bir cihazda göster": aynı ağdaki telefon ya da tabletin tarayıcısında canlı altyazı. Sayfa (<c>/view</c>) ve
/// akışı (<c>/events?viewer=second</c>) erişim anahtarı ister; anahtar adresin içindedir ve QR kodla verilir. Sayfa TV
/// sayılmaz, altyazı hedefi ne olursa olsun olayları alır (Mac/iPhone: SecondScreen.swift, Android: SecondScreen.kt).
/// </summary>
public static class SecondScreen
{
    public const string Path = "/view";
    public const string Viewer = "second";

    /// <summary>Tarayıcıda açılan adres: <c>http://&lt;ağ adresi&gt;:&lt;port&gt;/view?k=&lt;anahtar&gt;</c>.</summary>
    public static string Address(string host, int port, string key)
    {
        var shown = host.Contains(':') ? $"[{host}]" : host;
        return $"http://{shown}:{port}{Path}?k={Uri.EscapeDataString(key)}";
    }

    /// <summary>Sayfanın kendisi (Mac ve Android ile aynı dosya).</summary>
    public static byte[] Page { get; } = Load();

    private static byte[] Load()
    {
        using var stream = typeof(SecondScreen).Assembly.GetManifestResourceStream("second-screen.html");
        if (stream is null) return [];
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return memory.ToArray();
    }

    /// <summary>Adresin QR kodu: satır satır modüller (true: koyu), çevresinde dört modül boşlukla.</summary>
    public static bool[][] QrModules(string text)
    {
        using var generator = new QRCodeGenerator();
        using var data = generator.CreateQrCode(text, QRCodeGenerator.ECCLevel.M);
        return [.. data.ModuleMatrix.Select(row => Enumerable.Range(0, row.Length).Select(i => row[i]).ToArray())];
    }
}
