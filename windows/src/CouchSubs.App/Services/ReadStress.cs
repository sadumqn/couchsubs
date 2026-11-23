// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using CouchSubs.Core;
using Windows.Graphics.Imaging;

namespace CouchSubs.App.Services;

/// <summary>
/// Okuma hattının yük testi (<c>CouchSubs.exe --stress-okuma &lt;saniye&gt; &lt;sonuç dosyası&gt;</c>; CI gerçek Windows'ta
/// koşar). GitHub #587'de uygulama uzun oturumda erişim ihlaliyle kapanıyordu; .NET'in kaydındaki yığın paralel yedek
/// okumadaki <see cref="WindowsOcrReader.AutoLevel"/> idi. Test aynı işi gerçek oturumdan çok daha yoğun yapar: pencere
/// yakalamasının yaptığı gibi 2560x1440 kareler Windows görüntüsünden kopyalanır, altyazı bölgesi kırpılır ve her kare
/// bütün hazırlıklarla, boş okunup paralel yedek okumalara düşerek okunur (birkaç okuma hattı aynı anda, aynı kare
/// üzerinde). Süre boyunca süreç kapanmamalı; kapanırsa çökme kaydı yazılır ve adım düşer.
/// </summary>
internal static class ReadStress
{
    public const string Argument = "--stress-okuma";
    private const int Width = 2560, Height = 1440;

    public static int Run(string secondsText, string output)
    {
        if (!int.TryParse(secondsText, out var seconds) || seconds <= 0) return 2;
        CrashHandler.Install();
        // Süreç kapanırsa sonraki açılış (--crash-report) kaydı bu çalışmaya bağlar.
        CrashRecords.BeginSession(CrashHandler.Folder, Environment.ProcessId, DateTime.Now, _ => false);
        // Oturumdaki gibi: paket ve sözlük varken kare bütün hazırlıklarla okunur.
        // COUCHSUBS_STRESS_NO_OCR=1: yazı tanıma motoru atlanır; okumalar boş döner ve hep paralel yedek okumaya düşer.
        var real = Environment.GetEnvironmentVariable("COUCHSUBS_STRESS_NO_OCR") == "1" ? null : WindowsOcrReader.Create("en");
        var reader = real ?? WindowsOcrReader.CreateWithoutEngine();
        var withEngine = real is not null;
        reader.IsKnownLine = _ => false;
        WindowsOcrReader.DictionaryScore = text => text.Length;

        var clock = Stopwatch.StartNew();
        var deadline = TimeSpan.FromSeconds(seconds);
        Frame? latest = null;
        long captured = 0, read = 0;
        Exception? failure = null;

        // Pencere yakalaması: her kare Windows görüntüsünden yönetilen diziye kopyalanır (RemotePlayWindowStream).
        var capture = new Thread(() =>
        {
            try
            {
                var random = new Random(587);
                var source = new byte[Width * Height * 4];
                // Karanlık sahne: en parlak yer 235'in altında kalır, AutoLevel kareyi yeniden yazar.
                for (var i = 0; i < source.Length; i++) source[i] = (byte)random.Next(20, 200);
                using var bitmap = new SoftwareBitmap(BitmapPixelFormat.Bgra8, Width, Height, BitmapAlphaMode.Premultiplied);
                BitmapPixels.Write(new Frame(source, Width, Height, Width * 4), bitmap);
                while (clock.Elapsed < deadline && failure is null)
                {
                    Volatile.Write(ref latest, BitmapPixels.Read(bitmap));
                    Interlocked.Increment(ref captured);
                    Thread.Sleep(15);
                }
            }
            catch (Exception error) { failure = error; }
        }) { IsBackground = true, Name = "stres: yakalama" };

        // Okuma hatları: altyazı hattı ve ekran yazısı bölgeleri aynı kareyi aynı anda okur.
        var region = new CropRegion();
        var readers = Enumerable.Range(0, Math.Clamp(Environment.ProcessorCount / 2, 2, 6)).Select(index => new Thread(() =>
        {
            try
            {
                while (clock.Elapsed < deadline && failure is null)
                {
                    if (Volatile.Read(ref latest) is not { } frame)
                    {
                        Thread.Sleep(5);
                        continue;
                    }
                    var area = RegionCropper.Crop(frame, region);
                    reader.ReadLines(area, deep: true);
                    if (index == 0) reader.ReadScreen(frame.Crop(0, 0, frame.Width / 2, frame.Height / 2));
                    Interlocked.Increment(ref read);
                }
            }
            catch (Exception error) { failure = error; }
        }) { IsBackground = true, Name = $"stres: okuma {index}" }).ToList();

        capture.Start();
        foreach (var thread in readers) thread.Start();
        capture.Join();
        foreach (var thread in readers) thread.Join();

        var summary = $"süre: {clock.Elapsed.TotalSeconds:0} sn, yazı tanıma: {(withEngine ? "var" : "yok")}, okuma hattı: {readers.Count}, " +
                      $"kare: {captured}, okuma: {read}, GC: {GC.CollectionCount(0)}/{GC.CollectionCount(1)}/{GC.CollectionCount(2)}, " +
                      $"bellek: {GC.GetTotalMemory(false) >> 20} MB, en yüksek çalışma kümesi: {PeakWorkingSet() >> 20} MB" +
                      (failure is null ? "" : $"\nhata: {failure}");
        File.WriteAllText(output, summary + "\n");
        CrashRecords.EndSession(CrashHandler.Folder, Environment.ProcessId);
        return failure is null && read > 0 ? 0 : 1;
    }

    private static long PeakWorkingSet()
    {
        using var process = Process.GetCurrentProcess();
        return process.PeakWorkingSet64;
    }
}
