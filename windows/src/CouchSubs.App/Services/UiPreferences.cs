// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Text.Json;

namespace CouchSubs.App.Services;

/// <summary>
/// Yalnız bu bilgisayarın arayüz kayıtları: açılır reklamın son gösterildiği an. (Açılış Sesi ve Geçiş Animasyonları
/// ortak ayar kaydındadır: UserSettings.StartupSound / TransitionAnimations.) Dosya okunamazsa varsayılanlar kullanılır.
/// </summary>
public static class UiPreferences
{
    /// <param name="LastPopupAd">Açılır reklamın son gösterildiği an (günde en fazla bir kez).</param>
    /// <param name="NewLookApplied">Yeni arayüzün ilk açılış ayarı yapıldı (bir kez; Mac ile aynı).</param>
    public sealed record Values(DateTime? LastPopupAd = null, bool NewLookApplied = false);

    private static readonly string FilePath = Path.Combine(AppPaths.Data, "ui.json");
    private static Values? current;

    public static Values Current => current ??= Load();

    public static event Action? Changed;

    public static void Save(Values values)
    {
        current = values;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(values));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        Changed?.Invoke();
    }

    private static Values Load()
    {
        try { return File.Exists(FilePath) ? JsonSerializer.Deserialize<Values>(File.ReadAllText(FilePath)) ?? new() : new(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }
}
