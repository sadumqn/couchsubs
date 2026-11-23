// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace CouchSubs.Translation;

/// <summary>
/// Paketlenmiş Python/CTranslate2 çalışma zamanını kalıcı bir alt süreçte tutar. JSON satırları yalnız
/// yerel stdin/stdout üzerinden geçer; her altyazıda süreç veya model yeniden açılmaz.
/// </summary>
internal sealed class Ct2MarianEngine : ISentenceEngine
{
    private readonly MarianTokenizer tokenizer;
    private readonly string modelDirectory;
    private readonly int maxOutputTokens;
    private readonly int beams;
    private readonly Action? onGpuFallback;
    private readonly Task? cudaReady;
    private readonly string? cudaDirectory;
    private readonly int cpuThreads;
    private Process worker;
    private bool gpuActive;
    private bool gpuAttempted;
    private bool disposed;

    internal bool GpuActive => gpuActive;

    public Ct2MarianEngine(string modelDirectory, int maxOutputTokens, int beams, bool useGpu, Action? onGpuFallback,
        Task? cudaReady = null, string? cudaDirectory = null, int cpuThreads = 2)
    {
        this.modelDirectory = modelDirectory;
        this.maxOutputTokens = maxOutputTokens;
        this.beams = Math.Max(1, beams);
        this.onGpuFallback = onGpuFallback;
        this.cudaReady = useGpu ? cudaReady : null;
        this.cudaDirectory = cudaDirectory;
        this.cpuThreads = Math.Clamp(cpuThreads, 1, Math.Max(1, Environment.ProcessorCount));
        tokenizer = MarianTokenizer.Load(Path.Combine(modelDirectory, ModelStore.SourceSpmFile),
            Path.Combine(modelDirectory, ModelStore.VocabFile));
        if (useGpu && (cudaReady is null || cudaReady.IsCompletedSuccessfully))
        {
            gpuAttempted = true;
            try { worker = Start("cuda"); gpuActive = true; return; }
            catch (Exception error)
            {
                Debug.WriteLine($"CTranslate2 CUDA unavailable: {error}");
                onGpuFallback?.Invoke();
            }
        }
        worker = Start("cpu");
    }

    private Process Start(string device)
    {
        var runtime = Environment.GetEnvironmentVariable("COUCHSUBS_CT2_RUNTIME")
            ?? Path.Combine(AppContext.BaseDirectory, "ct2");
        var python = Path.Combine(runtime, "python.exe");
        var script = Path.Combine(runtime, "worker.py");
        if (!File.Exists(python) || !File.Exists(script))
            throw new FileNotFoundException("CTranslate2 runtime is missing", !File.Exists(python) ? python : script);
        var info = new ProcessStartInfo(python)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false),
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = runtime,
        };
        info.Environment["PYTHONIOENCODING"] = "utf-8";
        if (device == "cuda" && cudaDirectory is not null)
        {
            info.Environment["COUCHSUBS_CUDA_DIR"] = cudaDirectory;
            info.Environment["PATH"] = cudaDirectory + Path.PathSeparator + info.Environment["PATH"];
        }
        info.ArgumentList.Add("-u");
        info.ArgumentList.Add(script);
        info.ArgumentList.Add(modelDirectory);
        info.ArgumentList.Add(device);
        info.ArgumentList.Add((device == "cpu" ? cpuThreads : 2).ToString(System.Globalization.CultureInfo.InvariantCulture));
        var process = CouchSubs.Core.ChildProcessGuard.Start(info) ?? throw new IOException("CTranslate2 worker did not start");
        process.ErrorDataReceived += (_, e) => { if (e.Data is not null) Debug.WriteLine("CTranslate2: " + e.Data); };
        process.BeginErrorReadLine();
        try
        {
            var line = process.StandardOutput.ReadLine();
            if (line is null) throw new IOException("CTranslate2 worker exited during startup");
            using var response = JsonDocument.Parse(line);
            if (!response.RootElement.TryGetProperty("ready", out var ready) || !ready.GetBoolean())
                throw new IOException(response.RootElement.GetProperty("error").GetString());
            return process;
        }
        catch { Stop(process); throw; }
    }

    public string Translate(string sentence, CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        cancellationToken.ThrowIfCancellationRequested();
        if (!gpuAttempted && cudaReady is { IsCompleted: true })
        {
            gpuAttempted = true;
            if (cudaReady.IsCompletedSuccessfully)
            {
                try
                {
                    var cudaWorker = Start("cuda");
                    Stop(worker);
                    worker = cudaWorker;
                    gpuActive = true;
                }
                catch (Exception error)
                {
                    Debug.WriteLine($"CTranslate2 CUDA unavailable after download: {error}");
                    onGpuFallback?.Invoke();
                }
            }
            else
            {
                Debug.WriteLine($"CUDA runtime download failed: {cudaReady.Exception}");
                onGpuFallback?.Invoke();
            }
        }
        try { return TranslateCurrent(sentence, cancellationToken); }
        catch (Exception error) when (gpuActive && error is not OperationCanceledException)
        {
            Debug.WriteLine($"CTranslate2 CUDA translation failed: {error}");
            Stop(worker);
            gpuActive = false;
            onGpuFallback?.Invoke();
            worker = Start("cpu");
            return TranslateCurrent(sentence, cancellationToken);
        }
    }

    private string TranslateCurrent(string sentence, CancellationToken cancellationToken)
    {
        var tokens = tokenizer.EncodeTokens(sentence);
        // Mevcut ONNX hattıyla aynı kaynak sınırı. Son belirteç EOS kalır.
        if (tokens.Length > 256) tokens = [.. tokens.Take(255), "</s>"];
        var request = JsonSerializer.Serialize(new { tokens, beams, max_output = Math.Min(maxOutputTokens, 2 * tokens.Length + 16) });
        worker.StandardInput.WriteLine(request);
        worker.StandardInput.Flush();
        var line = worker.StandardOutput.ReadLine() ?? throw new IOException("CTranslate2 worker exited during translation");
        using var response = JsonDocument.Parse(line);
        // Tek satırın hatası (süreç ayakta): yalnız o satır çevrilemez, motor kapatılmaz. IOException yalnız
        // sürecin kapandığını bildirir; MarianTranslator onu kalıcı motor hatası sayar.
        if (response.RootElement.TryGetProperty("error", out var error))
            throw new InvalidOperationException("CTranslate2: " + error.GetString());
        var output = response.RootElement.GetProperty("tokens").EnumerateArray().Select(value => value.GetString() ?? "");
        cancellationToken.ThrowIfCancellationRequested();
        return tokenizer.DecodeTokens(output);
    }

    private static void Stop(Process process)
    {
        try
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            process.WaitForExit(2000);
        }
        catch (InvalidOperationException) { }
        finally { process.Dispose(); }
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        Stop(worker);
    }
}
