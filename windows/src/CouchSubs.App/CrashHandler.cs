// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace CouchSubs.App;

/// <summary>
/// Yerel çökme kaydını kurar: süreç erişim ihlali gibi yerel bir hatayla kapanırken couchsubs_native.dll
/// %LOCALAPPDATA%\CouchSubs\cokme klasörüne metin özeti ve küçük döküm yazar (windows/native/couchsubs_crash.c).
/// Bu hatalar .NET'in istisna düzenine uğramaz; hata.log boş kalır ve uygulama uyarısız kapanır (GitHub #587). Dosyalar
/// yalnız bu bilgisayarda kalır. Bu sınıf yalnız .NET'in kendi türlerini kullanır (bkz. <see cref="StartupGuard"/>).
/// </summary>
internal static class CrashHandler
{
    internal static string Folder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CouchSubs", "cokme");

    /// <summary>Özetin başına yazılan satırlar.</summary>
    internal static string Header
    {
        get
        {
            var version = typeof(CrashHandler).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                          ?? typeof(CrashHandler).Assembly.GetName().Version?.ToString() ?? "?";
            // "0.1.0-beta.66+<commit>" biçimindeki ekin yalnız başı.
            var plus = version.IndexOf('+');
            if (plus > 0 && version.Length - plus > 9) version = version[..(plus + 9)];
            return $"Sürüm: {version}\r\nİşletim sistemi: {RuntimeInformation.OSDescription} ({RuntimeInformation.OSArchitecture})\r\n" +
                   $".NET: {RuntimeInformation.FrameworkDescription}\r\nİşlemci: {Processor()}\r\n" +
                   $"Anakart: {Board()}\r\nSanallaştırma: {Hypervisor()}\r\n";
        }
    }

    /// <summary>
    /// Anakart ve BIOS sürümü/tarihi (Windows'un kaydından). Yeni işlemcilerde (ör. Ryzen 9000X3D) erken BIOS sürümleri
    /// kararsızlığın bilinen nedenidir; kullanıcı "BIOS güncel" dediğinde hangi sürüm olduğu görülsün (GitHub #903).
    /// </summary>
    private static string Board()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\BIOS");
            string Value(string name) => (key?.GetValue(name) as string)?.Trim() ?? "";
            var board = $"{Value("BaseBoardManufacturer")} {Value("BaseBoardProduct")}".Trim();
            var bios = $"{Value("BIOSVersion")} {Value("BIOSReleaseDate")}".Trim();
            if (board.Length == 0 && bios.Length == 0) return "?";
            return $"{(board.Length > 0 ? board : "?")}, BIOS {(bios.Length > 0 ? bios : "?")}";
        }
        catch (Exception)
        {
            return "?";
        }
    }

    /// <summary>
    /// Süreç bir hipervizörün üstünde mi, öyleyse hangisi (CPUID 1 ECX bit 31 ve 0x40000000 satıcı adı). Windows'un kendi
    /// hipervizörü (VBS/Bellek bütünlüğü) "Microsoft Hv" görünür; başka bir ad, güvenlik yazılımının ya da sanal makinenin
    /// komutları kendi işlediğini gösterir. Bu katman bir komutun adresini yanlış hesaplarsa yazmaçlar doğru, adres kısa
    /// görünür (GitHub #903).
    /// </summary>
    private static string Hypervisor()
    {
        try
        {
            if (!System.Runtime.Intrinsics.X86.X86Base.IsSupported) return "?";
            var (_, _, features, _) = System.Runtime.Intrinsics.X86.X86Base.CpuId(1, 0);
            if ((features & (1 << 31)) == 0) return "yok";
            var (_, ebx, ecx, edx) = System.Runtime.Intrinsics.X86.X86Base.CpuId(0x40000000, 0);
            var vendor = new byte[12];
            BitConverter.TryWriteBytes(vendor.AsSpan(0, 4), ebx);
            BitConverter.TryWriteBytes(vendor.AsSpan(4, 4), ecx);
            BitConverter.TryWriteBytes(vendor.AsSpan(8, 4), edx);
            var name = new string(System.Text.Encoding.ASCII.GetString(vendor).Where(c => c >= ' ' && c < 127).ToArray()).Trim();
            return name.Length > 0 ? name : "var (adı yok)";
        }
        catch (Exception)
        {
            return "?";
        }
    }

    /// <summary>
    /// İşlemcinin adı ve mikrokod sürümü (Windows'un kaydından). Yazmaçları doğru olduğu hâlde yanlış adrese erişen
    /// komut (GitHub #903) işlemci kararsızlığına işaret eder; Intel 13./14. nesilde eski mikrokod bilinen bir nedendir.
    /// </summary>
    private static string Processor()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
            var name = (key?.GetValue("ProcessorNameString") as string)?.Trim();
            if (string.IsNullOrEmpty(name)) name = "?";
            // "Update Revision" (REG_BINARY, 8 bayt): Intel'de mikrokod sürümü üst dört bayttadır, AMD'de alt dört bayt.
            if (key?.GetValue("Update Revision") is byte[] { Length: >= 8 } revision)
            {
                var high = BitConverter.ToUInt32(revision, 4);
                var value = high != 0 ? high : BitConverter.ToUInt32(revision, 0);
                name += $" (mikrokod 0x{value:X})";
            }
            return $"{name}, {Environment.ProcessorCount} mantıksal çekirdek";
        }
        catch (Exception)
        {
            return "?";
        }
    }

    /// <summary>İşleyiciyi kurar. DLL yoksa ya da kurulamazsa uygulama kayıtsız açılır; neden hata.log'a yazılır.</summary>
    public static bool Install()
    {
        try
        {
            Directory.CreateDirectory(Folder);
            var result = cs_crash_install(Folder, Header);
            if (result == 0) return true;
            StartupGuard.Log($"Çökme kaydı kurulamadı ({result})", null);
        }
        catch (Exception error)
        {
            StartupGuard.Log("Çökme kaydı kurulamadı", error);
        }
        return false;
    }

    [DllImport("couchsubs_native", CallingConvention = CallingConvention.Cdecl)]
    private static extern int cs_crash_install([MarshalAs(UnmanagedType.LPWStr)] string directory, [MarshalAs(UnmanagedType.LPUTF8Str)] string header);

    [DllImport("couchsubs_native", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void cs_crash_test(int kind);
}
