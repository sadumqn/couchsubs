// SPDX-License-Identifier: AGPL-3.0-only

using System.Runtime.InteropServices;

namespace CouchSubs.App.Services;

/// <summary>Çeviri sürerken bilgisayarın boşta uykuya geçmesini engeller (kullanıcı TV'de oynuyor, bilgisayara dokunmuyor).
/// Görüntü bir pencereden okunuyorsa ya da altyazı bu ekrandaysa ekranın kapanması da engellenir.</summary>
public static partial class SleepGuard
{
    private const uint EsContinuous = 0x80000000;
    private const uint EsSystemRequired = 0x00000001;
    private const uint EsDisplayRequired = 0x00000002;

    [LibraryImport("kernel32.dll")]
    private static partial uint SetThreadExecutionState(uint flags);

    public static bool IsActive { get; private set; }

    /// <summary>ES_CONTINUOUS ile verilen bayraklar öncekilerin yerine geçer; yeniden çağrı ekran isteğini açıp kapatabilir.</summary>
    public static void Begin(bool keepDisplayOn)
    {
        SetThreadExecutionState(EsContinuous | EsSystemRequired | (keepDisplayOn ? EsDisplayRequired : 0));
        IsActive = true;
    }

    public static void End()
    {
        SetThreadExecutionState(EsContinuous);
        IsActive = false;
    }
}
