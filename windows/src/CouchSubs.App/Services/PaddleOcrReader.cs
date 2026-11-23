// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Runtime.InteropServices;
using CouchSubs.Core;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace CouchSubs.App.Services;

/// <summary>
/// Gelişmiş yazı tanıma (PP-OCRv6 small, <see cref="PaddleOcr"/>). Modeller ekran kartında DirectML ile çalışır; DirectML
/// açılamazsa işlemcide. Windows'un yazı tanımasından farkı: açık zeminde (gökyüzü, kar, gündüz sokak) beyaz altyazıyı da
/// okur ve her satır için güven verir; bu yüzden birden çok görüntü hazırlığı gerekmez. Oturumlar pahalıdır: bir model
/// klasörü için bir kez kurulur, okuyucular paylaşır. DirectML aynı oturumda eşzamanlı çalıştırmayı desteklemez; okumalar
/// sıraya girer.
/// </summary>
public sealed class PaddleOcrReader : ITextReader
{
    private static readonly object CacheGate = new();
    private static (string Directory, Engine Engine)? cache;

    /// <summary>Paylaşılan oturumun kilidi en çok bu kadar beklenir.</summary>
    private const int LockTimeoutMs = 10_000;

    private readonly Engine engine;
    /// <summary>Oyun dili Latin alfabeliyse Çince/Japonca/Korece karakterler atılır (<see cref="PaddleOcr.LatinOnly"/>).</summary>
    private readonly bool latin;

    private PaddleOcrReader(Engine engine, bool latin) => (this.engine, this.latin) = (engine, latin);

    /// <summary>Modeller <paramref name="directory"/>'de; çalışıyorsa ekran kartı mı işlemci mi.</summary>
    public string Device => engine.Device;

    /// <summary>Okuyucu; modeller eksik ya da açılamıyorsa null (çağıran Windows'un yazı tanımasına döner).</summary>
    public static PaddleOcrReader? Create(string directory, string language = "en")
    {
        var latin = PaddleOcr.IsLatinLanguage(language);
        lock (CacheGate)
        {
            if (cache is { } cached && cached.Directory == directory) return new PaddleOcrReader(cached.Engine, latin);
            try
            {
                var engine = Engine.Load(directory);
                cache = (directory, engine);
                return new PaddleOcrReader(engine, latin);
            }
            catch (Exception error) when (error is OnnxRuntimeException or IOException or InvalidDataException
                                              or DllNotFoundException or BadImageFormatException or UnauthorizedAccessException)
            {
                return null;
            }
        }
    }

    /// <summary>
    /// Bu okuyucunun oturumlarını bırakır (ekran kartı belleği boşalır). Paylaşılan önbellekteki oturum buysa önbellek de
    /// boşalır; sonraki <see cref="Create"/> modelleri yeniden yükler. Aynı oturumu kullanan diğer okuyucular bundan sonra
    /// <see cref="ObjectDisposedException"/> verir (sarmalayıcıları Windows'un yazı tanımasına döner).
    /// </summary>
    public void Release()
    {
        lock (CacheGate)
            if (cache is { } cached && ReferenceEquals(cached.Engine, engine)) cache = null;
        engine.Dispose();
    }

    /// <summary>Önbellekteki oturumları bırakır (seçim Windows'a dönünce ekran kartı belleği boşalsın).</summary>
    public static void ReleaseAll()
    {
        Engine? engine;
        lock (CacheGate)
        {
            engine = cache?.Engine;
            cache = null;
        }
        engine?.Dispose();
    }

    public string Read(Frame image) => ReadLines(image, deep: true).Text;

    public Reading ReadLines(Frame image, bool deep)
    {
        if (image.Width < 8 || image.Height < 8 || !WindowsOcrReader.Usable(image)) return Reading.Empty;
        Reading reading;
        // Oturum paylaşılır; içinde takılan bir okuma kilidi bırakmazsa yeni kurulan hat da sonsuza dek beklerdi (#679).
        // Kilit süresinde alınamazsa hata verilir: sarmalayıcı (FallbackTextReader) kareyi Windows'un yazı tanımasıyla okur,
        // üç kez üst üste olursa ona kalıcı geçer.
        if (!System.Threading.Monitor.TryEnter(engine, LockTimeoutMs))
            throw new TimeoutException($"gelişmiş yazı tanıma {LockTimeoutMs} ms'dir meşgul (önceki okuma bitmedi)");
        try { reading = engine.Read(image); }
        finally { System.Threading.Monitor.Exit(engine); }
        if (!latin) return reading;
        return new Reading(reading.Lines.Select(line => line with
        {
            Text = PaddleOcr.LatinOnly(line.Text),
            Words = line.Words?.Select(word => word with { Text = PaddleOcr.WithoutCjk(word.Text) }).Where(word => word.Text.Length > 0).ToList(),
        }).Where(line => line.Text.Length > 0));
    }

    private sealed class Engine(InferenceSession detection, InferenceSession recognition, string[] characters, string device) : IDisposable
    {
        private bool disposed;

        public string Device { get; } = device;

        /// <summary>Süren okuma bitince oturumları bırakır; sonraki okumalar hata verir.</summary>
        public void Dispose()
        {
            lock (this)
            {
                if (disposed) return;
                disposed = true;
                detection.Dispose();
                recognition.Dispose();
            }
        }

        public static Engine Load(string directory)
        {
            var characters = PaddleOcr.ParseCharacters(File.ReadAllText(Path.Combine(directory, PaddleOcr.RecognitionConfigFile)));
            var gpu = GraphicsAdapters.Best();
            if (gpu is { } index)
            {
                try
                {
                    return new Engine(Session(Path.Combine(directory, PaddleOcr.DetectionFile), index),
                        Session(Path.Combine(directory, PaddleOcr.RecognitionFile), index), characters, "gpu");
                }
                catch (Exception error) when (error is OnnxRuntimeException or DllNotFoundException or EntryPointNotFoundException)
                {
                    // Sürücü ya da DirectML sorunu: işlemciyle devam.
                }
            }
            return new Engine(Session(Path.Combine(directory, PaddleOcr.DetectionFile), null),
                Session(Path.Combine(directory, PaddleOcr.RecognitionFile), null), characters, "cpu");
        }

        private static InferenceSession Session(string path, int? gpu)
        {
            var options = new SessionOptions
            {
                GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
                LogSeverityLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_FATAL,
                IntraOpNumThreads = Math.Clamp(Environment.ProcessorCount / 2, 1, 4),
                InterOpNumThreads = 1,
            };
            // Boşta dönen iş parçacıkları dizüstünde işlemciyi gereksiz yorar.
            options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");
            options.AddSessionConfigEntry("session.inter_op.allow_spinning", "0");
            if (gpu is { } device)
            {
                // DirectML bellek düzeni iyileştirmesini ve paralel çalıştırmayı desteklemez.
                options.EnableMemoryPattern = false;
                options.ExecutionMode = ExecutionMode.ORT_SEQUENTIAL;
                options.AppendExecutionProvider_DML(device);
            }
            return new InferenceSession(path, options);
        }

        /// <summary>Çağıran <c>lock (engine)</c> tutar (DirectML eşzamanlı çalıştırmayı desteklemez).</summary>
        public Reading Read(Frame image)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            var input = PaddleOcr.PrepareDetection(image, PaddleOcr.DetectionLimitFor(image.Width, image.Height));
            List<PaddleOcr.Box> boxes;
            using (var results = detection.Run([NamedOnnxValue.CreateFromTensor(detection.InputNames[0],
                       new DenseTensor<float>(input.Data, [1, 3, input.Height, input.Width]))]))
            {
                var map = results[0].AsTensor<float>();
                boxes = PaddleOcr.FindBoxes(((DenseTensor<float>)map).Buffer.Span, input.Width, input.Height, image.Width, image.Height);
            }
            if (boxes.Count == 0) return Reading.Empty;

            // Benzer en-boy oranlı satırlar birlikte okunur (RapidOCR gibi): dolgu az olur.
            var crops = boxes.Select(box => PaddleOcr.CropBox(image, box)).ToList();
            var order = Enumerable.Range(0, crops.Count).OrderBy(i => (double)crops[i].Width / Math.Max(1, crops[i].Height)).ToList();
            var texts = new (string Text, double Confidence)[crops.Count];
            // Sözcüklerin satır kesitindeki yerleri (piksel); kumanda simgesini bulmaya yarar (ButtonIcons).
            var words = new IReadOnlyList<(string Text, double Left, double Right)>[crops.Count];
            for (var start = 0; start < order.Count; start += PaddleOcr.RecognitionBatch)
            {
                var batch = order.Skip(start).Take(PaddleOcr.RecognitionBatch).ToList();
                var (data, width) = PaddleOcr.PrepareRecognition(batch.Select(i => crops[i]).ToList());
                using var results = recognition.Run([NamedOnnxValue.CreateFromTensor(recognition.InputNames[0],
                    new DenseTensor<float>(data, [batch.Count, 3, PaddleOcr.RecognitionHeight, width]))]);
                var output = (DenseTensor<float>)results[0].AsTensor<float>();
                int steps = output.Dimensions[1], classes = output.Dimensions[2];
                if (classes != characters.Length) throw new InvalidDataException($"model has {classes} classes, dictionary {characters.Length}");
                for (var n = 0; n < batch.Count; n++)
                {
                    var (text, confidence, places) = PaddleOcr.DecodeWithPlaces(output.Buffer.Span.Slice(n * steps * classes, steps * classes), steps, characters);
                    texts[batch[n]] = (text, confidence);
                    // Bir zaman adımı girdide width/steps piksel; satır PrepareRecognition'daki genişliğe ölçeklenmişti.
                    var crop = crops[batch[n]];
                    var resized = Math.Max(1, Math.Min(width, (int)Math.Ceiling(PaddleOcr.RecognitionHeight * ((double)crop.Width / Math.Max(1, crop.Height)))));
                    var scale = (double)width / steps * crop.Width / resized;
                    words[batch[n]] = [.. PaddleOcr.Words(places).Select(word => (word.Text, word.Left * scale, word.Right * scale))];
                }
            }

            double width0 = image.Width, height0 = image.Height;
            var lines = new List<TextLine>();
            for (var i = 0; i < boxes.Count; i++)
            {
                var (text, confidence) = texts[i];
                if (confidence < PaddleOcr.MinConfidence || string.IsNullOrWhiteSpace(text)) continue;
                var box = boxes[i];
                var left = (double)(int)box.Left; // CropBox'un kestiği yer
                var lineWords = words[i]?.Select(word => new TextWord(word.Text, new TextBox(
                    Math.Clamp((left + word.Left) / width0, 0, 1), box.Top / height0,
                    Math.Clamp((left + word.Right) / width0, 0, 1), box.Bottom / height0))).ToList();
                lines.Add(new TextLine(text.Trim(), new TextBox(box.Left / width0, box.Top / height0, box.Right / width0, box.Bottom / height0), confidence,
                                       Words: lineWords is { Count: > 0 } ? lineWords : null));
            }
            return new Reading(lines);
        }
    }

    /// <summary>
    /// DirectML'in adaptör sırası DXGI'nin sırasıdır; dizüstünde 0. adaptör çoğunlukla işlemcinin ekran kartıdır. En çok
    /// ayrılmış video belleği olan donanım adaptörü seçilir. Yazılım adaptörü (Microsoft Basic Render) sayılmaz.
    /// </summary>
    private static unsafe class GraphicsAdapters
    {
        [DllImport("dxgi.dll")]
        private static extern int CreateDXGIFactory1(in Guid riid, out IntPtr factory);

        private static readonly Guid IdxgiFactory1 = new("770aae78-f26f-4dba-a829-253c83d1b387");

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct AdapterDesc1
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
            public uint VendorId, DeviceId, SubSysId, Revision;
            public nuint DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
            public long AdapterLuid;
            public uint Flags;
        }

        public static int? Best()
        {
            try
            {
                if (CreateDXGIFactory1(IdxgiFactory1, out var factory) < 0 || factory == IntPtr.Zero) return null;
                try
                {
                    int? best = null;
                    nuint bestMemory = 0;
                    var vtable = *(IntPtr**)factory;
                    // IDXGIFactory1::EnumAdapters1 (12), IDXGIAdapter1::GetDesc1 (10), IUnknown::Release (2).
                    var enumAdapters1 = (delegate* unmanaged[Stdcall]<IntPtr, uint, out IntPtr, int>)vtable[12];
                    for (uint index = 0; index < 16; index++)
                    {
                        if (enumAdapters1(factory, index, out var adapter) < 0 || adapter == IntPtr.Zero) break;
                        var adapterTable = *(IntPtr**)adapter;
                        var getDesc1 = (delegate* unmanaged[Stdcall]<IntPtr, IntPtr, int>)adapterTable[10];
                        var buffer = Marshal.AllocHGlobal(Marshal.SizeOf<AdapterDesc1>());
                        try
                        {
                            if (getDesc1(adapter, buffer) >= 0)
                            {
                                var desc = Marshal.PtrToStructure<AdapterDesc1>(buffer);
                                const uint software = 2;
                                if ((desc.Flags & software) == 0 && desc.DedicatedVideoMemory > bestMemory)
                                    (best, bestMemory) = ((int)index, desc.DedicatedVideoMemory);
                            }
                        }
                        finally
                        {
                            Marshal.FreeHGlobal(buffer);
                            ((delegate* unmanaged[Stdcall]<IntPtr, uint>)adapterTable[2])(adapter);
                        }
                    }
                    return best;
                }
                finally
                {
                    ((delegate* unmanaged[Stdcall]<IntPtr, uint>)(*(IntPtr**)factory)[2])(factory);
                }
            }
            catch (DllNotFoundException) { return null; }
        }
    }
}
