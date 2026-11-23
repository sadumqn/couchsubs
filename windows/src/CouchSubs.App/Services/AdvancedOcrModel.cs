// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using CouchSubs.Core;
using CouchSubs.Shell;
using CouchSubs.Translation;

namespace CouchSubs.App.Services;

/// <summary>
/// Gelişmiş yazı tanımanın modelleri (PP-OCRv6 small, Baidu / PaddlePaddle, Apache-2.0): ilk seçildiğinde
/// %LOCALAPPDATA%\CouchSubs\models\ocr\&lt;sürüm&gt; altına resmî Hugging Face depolarından indirilir, özetleri denetlenir.
/// </summary>
internal sealed class AdvancedOcrModel : IOcrModel
{
    private readonly ModelStore store = new(Path.Combine(AppPaths.Models, "ocr", PaddleOcr.Version),
        [.. PaddleOcr.Files.Select(file => new ModelFile(file.Name, file.Url, file.Bytes, file.Sha256))]);

    public string Directory => store.InstallDirectory;
    public bool IsInstalled => store.IsInstalled;
    public long DownloadBytes => store.TotalBytes;

    public async Task DownloadAsync(IProgress<double> progress, CancellationToken cancellationToken)
    {
        await store.DownloadAsync(progress, cancellationToken).ConfigureAwait(false);
        // Önceki model sürümleri yer kaplamasın.
        foreach (var old in System.IO.Directory.EnumerateDirectories(Path.Combine(AppPaths.Models, "ocr")))
            if (!string.Equals(Path.GetFileName(old), PaddleOcr.Version, StringComparison.Ordinal))
                try { System.IO.Directory.Delete(old, recursive: true); } catch (IOException) { }
    }
}
