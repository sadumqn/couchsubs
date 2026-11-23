// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.IO;
using CouchSubs.RemotePlay;

namespace CouchSubs.App.Views.Steps;

/// <summary>"Günlük dosyasını göster": remoteplay.log Dosya Gezgini'nde seçili açılır (PS5 ve Xbox adımları ortak).</summary>
internal static class LogFile
{
    public static void Show()
    {
        var path = RemotePlayLog.FilePath;
        try
        {
            var folder = Path.GetDirectoryName(path)!;
            Directory.CreateDirectory(folder);
            var arguments = File.Exists(path) ? $"/select,\"{path}\"" : $"\"{folder}\"";
            Process.Start(new ProcessStartInfo("explorer.exe", arguments) { UseShellExecute = true });
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            // Dosya Gezgini açılamazsa yol zaten hata iletisinde yazıyor.
        }
    }
}
