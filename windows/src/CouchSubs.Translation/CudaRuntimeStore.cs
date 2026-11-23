// SPDX-License-Identifier: AGPL-3.0-only

using System.IO.Compression;
using System.Security.Cryptography;

namespace CouchSubs.Translation;

/// <summary>NVIDIA'nın sabit sürümlü CUDA 12 çalışma zamanı. Yalnız GPU seçilince indirilir.</summary>
public sealed class CudaRuntimeStore
{
    private const string BaseUrl = "https://developer.download.nvidia.com/compute/cuda/redist/";
    private const string CublasArchive = "libcublas-windows-x86_64-12.8.4.1-archive.zip";
    private const string CudartArchive = "cuda_cudart-windows-x86_64-12.8.90-archive.zip";
    private static readonly (string Name, long Size)[] Required =
        [("cublas64_12.dll", 113_716_224), ("cublasLt64_12.dll", 674_667_520), ("cudart64_12.dll", 573_952)];
    private readonly ModelStore archives;
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly object taskLock = new();
    private Task? download;

    public CudaRuntimeStore(string installDirectory)
    {
        InstallDirectory = installDirectory;
        archives = new ModelStore(installDirectory,
        [
            new(CublasArchive, new Uri(BaseUrl + "libcublas/windows-x86_64/" + CublasArchive),
                563_660_944, "57a470112cec7e112c95253dde8b3c7184d795dbd92b0bde77a4cb7f8c94c8aa"),
            new(CudartArchive, new Uri(BaseUrl + "cuda_cudart/windows-x86_64/" + CudartArchive),
                3_037_735, "4a39058fd8519444a81cfc7ae055d136f48d1a31ffa41ae255b35b2edd61e13b"),
        ]);
    }

    public string InstallDirectory { get; }
    public bool IsInstalled => Required.All(file =>
        new FileInfo(Path.Combine(InstallDirectory, file.Name)) is { Exists: true } info && info.Length == file.Size);

    /// <summary>Tek indirme görevini paylaşır; başarısız bir deneme sonraki seçimde yeniden denenebilir.</summary>
    public Task StartDownload()
    {
        lock (taskLock)
        {
            if (IsInstalled) return Task.CompletedTask;
            if (download is null || download.IsCompleted && !download.IsCompletedSuccessfully)
                download = DownloadAsync(CancellationToken.None);
            return download;
        }
    }

    public async Task DownloadAsync(CancellationToken ct)
    {
        await gate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (IsInstalled) return;
            await archives.DownloadAsync(null, ct).ConfigureAwait(false);
            foreach (var file in archives.Files)
            {
                await using var stream = File.OpenRead(archives.PathOf(file.Name));
                var hash = Convert.ToHexStringLower(await SHA256.HashDataAsync(stream, ct).ConfigureAwait(false));
                if (!string.Equals(hash, file.Sha256, StringComparison.OrdinalIgnoreCase))
                {
                    stream.Close();
                    File.Delete(archives.PathOf(file.Name));
                    throw new InvalidDataException($"CUDA archive checksum mismatch: {file.Name}");
                }
            }
            foreach (var archiveName in new[] { CublasArchive, CudartArchive })
            {
                using var zip = ZipFile.OpenRead(archives.PathOf(archiveName));
                foreach (var file in Required)
                {
                    var entry = zip.Entries.SingleOrDefault(e => e.FullName.EndsWith("/bin/" + file.Name, StringComparison.Ordinal));
                    if (entry is null) continue;
                    if (entry.Length != file.Size) throw new InvalidDataException($"CUDA library size mismatch: {file.Name}");
                    ct.ThrowIfCancellationRequested();
                    var target = Path.Combine(InstallDirectory, file.Name);
                    var part = target + ".part";
                    await using (var input = entry.Open())
                    await using (var output = new FileStream(part, FileMode.Create, FileAccess.Write, FileShare.None))
                        await input.CopyToAsync(output, ct).ConfigureAwait(false);
                    File.Move(part, target, overwrite: true);
                }
                if (archiveName == CublasArchive)
                {
                    var license = zip.Entries.Single(e => e.FullName.EndsWith("/LICENSE", StringComparison.Ordinal));
                    license.ExtractToFile(Path.Combine(InstallDirectory, "CUDA-LICENSE.txt"), overwrite: true);
                }
            }
            if (!IsInstalled) throw new InvalidDataException("CUDA archive lacks required runtime libraries");
            foreach (var archiveName in new[] { CublasArchive, CudartArchive })
                File.Delete(archives.PathOf(archiveName));
        }
        finally { gate.Release(); }
    }
}
