// SPDX-License-Identifier: AGPL-3.0-only

using System.Runtime.CompilerServices;

namespace CouchSubs.Translation.Tests;

/// <summary>
/// Testler kullanıcının gerçek %LOCALAPPDATA%\CouchSubs klasörüne (altyazi.log, remoteplay.log, tvinstall.log, geçmiş,
/// sözlük) yazmaz: derleme yüklenir yüklenmez yerel veri klasörü bu test sürecine özel geçici klasöre yönlendirilir.
/// </summary>
internal static class TestDataRedirect
{
#pragma warning disable CA2255 // Modül başlatıcı testlerde bilerek kullanılıyor.
    [ModuleInitializer]
    internal static void Redirect() => global::CouchSubs.Core.AppDataPaths.RedirectForTests(global::CouchSubs.Core.AppDataPaths.NewTestRoot());
#pragma warning restore CA2255
}
