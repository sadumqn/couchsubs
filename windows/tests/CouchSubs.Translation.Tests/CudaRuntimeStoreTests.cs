// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Translation.Tests;

public sealed class CudaRuntimeStoreTests
{
    [CudaGpuFact]
    public void RunningCpuWorkerSwitchesToGpuAfterBackgroundDownload()
    {
        var cudaDirectory = Environment.GetEnvironmentVariable("COUCHSUBS_TEST_CUDA_DIR")!;
        var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var engine = new Ct2MarianEngine(TestModels.Directory, 128, 4, true, null,
            ready.Task, cudaDirectory);
        Assert.False(engine.GpuActive);
        Assert.NotEmpty(engine.Translate("Hello.", CancellationToken.None));
        ready.SetResult();
        Assert.NotEmpty(engine.Translate("How are you?", CancellationToken.None));
        Assert.True(engine.GpuActive);
    }

    [CudaArchiveFact]
    public async Task OfficialArchivesInstallOnlyVerifiedRuntimeFiles()
    {
        var source = Environment.GetEnvironmentVariable("COUCHSUBS_TEST_CUDA_ARCHIVES")!;
        var directory = Path.Combine(Path.GetTempPath(), "couchsubs-cuda-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            foreach (var name in new[]
            {
                "libcublas-windows-x86_64-12.8.4.1-archive.zip",
                "cuda_cudart-windows-x86_64-12.8.90-archive.zip",
            })
                File.Copy(Path.Combine(source, name), Path.Combine(directory, name));
            var store = new CudaRuntimeStore(directory);
            Assert.False(store.IsInstalled);
            await store.DownloadAsync(CancellationToken.None);
            Assert.True(store.IsInstalled);
            Assert.True(File.Exists(Path.Combine(directory, "CUDA-LICENSE.txt")));
            Assert.Empty(Directory.GetFiles(directory, "*.zip"));
            Assert.True(store.StartDownload().IsCompletedSuccessfully);
        }
        finally { Directory.Delete(directory, recursive: true); }
    }
}

public sealed class CudaArchiveFactAttribute : FactAttribute
{
    public CudaArchiveFactAttribute()
    {
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("COUCHSUBS_TEST_CUDA_ARCHIVES")))
            Skip = "Official CUDA archives are not available";
    }
}

public sealed class CudaGpuFactAttribute : FactAttribute
{
    public CudaGpuFactAttribute()
    {
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("COUCHSUBS_TEST_CUDA_DIR")) || !TestModels.ModelAvailable)
            Skip = "NVIDIA GPU, CUDA libraries, and translation model are required";
    }
}
