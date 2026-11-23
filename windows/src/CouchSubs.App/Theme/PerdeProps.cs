// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;

namespace CouchSubs.App.Theme;

/// <summary>
/// Perde şablonlarının ekli özellikleri. <c>Glow</c>: düğme şablonunda ana eylemin amber ışıması ve üst kenar parlaması
/// (effect.glowPrimary); yalnız PrimaryButton açar, pasifken kapanır. <c>Busy</c>: işlem sürüyor ("…ıyor…"); düğme yazının
/// solunda çubuk yükleyici gösterir.
/// </summary>
public static class PerdeProps
{
    public static readonly DependencyProperty GlowProperty = DependencyProperty.RegisterAttached("Glow", typeof(bool), typeof(PerdeProps),
        new FrameworkPropertyMetadata(false));

    public static bool GetGlow(DependencyObject d) => (bool)d.GetValue(GlowProperty);
    public static void SetGlow(DependencyObject d, bool value) => d.SetValue(GlowProperty, value);

    public static readonly DependencyProperty BusyProperty = DependencyProperty.RegisterAttached("Busy", typeof(bool), typeof(PerdeProps),
        new FrameworkPropertyMetadata(false));

    public static bool GetBusy(DependencyObject d) => (bool)d.GetValue(BusyProperty);
    public static void SetBusy(DependencyObject d, bool value) => d.SetValue(BusyProperty, value);
}
