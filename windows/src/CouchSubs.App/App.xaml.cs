// SPDX-License-Identifier: AGPL-3.0-only

using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using CouchSubs.App.Services;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var renderFolder = e.Args is ["--render-screens", var folder] ? folder : null;
        // Boşta işlemci ölçümü (Services/IdleCpu): sonuç dosyasının klasörü hata kaydı için render klasörü gibi kullanılır.
        var idle = e.Args is ["--olc-bosta", var seconds, var result] ? (seconds, result) : default((string, string)?);
        if (idle is not null) renderFolder ??= Path.GetDirectoryName(Path.GetFullPath(idle.Value.Item2));
        // Eksik bir DLL, onu kullanan yöntem derlenirken hata verir. Bu yüzden denetim ve yakalama burada, uygulamanın
        // kendi türlerine dokunan kod ise ayrı yöntemde (Start) durur.
        var missing = StartupGuard.MissingFiles(AppContext.BaseDirectory);
        if (missing.Count > 0)
        {
            StartupGuard.Fail(this, StartupGuard.MissingMessage(missing), null, renderFolder);
            return;
        }
        if (renderFolder is null) StartupGuard.Watch(this);
        try
        {
            if (idle is { } measure) MeasureIdle(measure.Item1, measure.Item2);
            else Start(renderFolder);
        }
        catch (Exception error)
        {
            StartupGuard.Fail(this, StartupGuard.LaunchMessage(error), error, renderFolder);
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    void MeasureIdle(string seconds, string output)
    {
        Controls.SmoothScroll.Register();
        IdleCpu.Run(this, seconds, output);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    void Start(string? renderFolder)
    {
        Controls.SmoothScroll.Register();
        if (renderFolder is not null)
        {
            ScreenRenderer.Run(this, renderFolder);
            return;
        }
        RemotePlayDiagnostics.Start();
        // Önceki çalışma yerel bir hatayla kapandıysa ana ekran bir kez bildirir.
        CrashWatch.Start();
        var controller = new AppController(new LiveServices(), new DpapiAppStore(), new FileSettingsStore(), new WindowsSleepGuard(),
            Localizer.Current, action => Dispatcher.BeginInvoke(action))
        {
            // Samsung'un sertifika için giriş sayfası varsayılan tarayıcıda açılır.
            OpenInBrowser = BrowserLauncher.Open,
        };
        // Yeni arayüz ilk açılışta bir kez (Mac ile aynı): konuşan rengi yalnız adı boyar (style.nameOnly). Görünüm ayarına
        // dokunulmaz: Perde tasarım dili koyu temalıdır ve varsayılan da koyudur (tasarim.json › defaultTheme); kullanıcının
        // seçtiği Açık / Koyu / Sisteme Uy korunur.
        if (!UiPreferences.Current.NewLookApplied)
        {
            var current = controller.Settings;
            controller.Settings = current with { Style = current.Style with { NameOnly = true } };
            UiPreferences.Save(UiPreferences.Current with { NewLookApplied = true });
        }
        // Görünüm (varsayılan koyu) pencere açılmadan uygulanır; ayarlarda değişince anında yenilenir.
        ThemeManager.Use(Resources, controller.Settings.Appearance);
        ThemeManager.Follow(Resources);
        controller.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName != nameof(AppController.Settings)) return;
            var appearance = controller.Settings.Appearance;
            if (Dispatcher.CheckAccess()) ThemeManager.Use(Resources, appearance);
            else Dispatcher.BeginInvoke(() => ThemeManager.Use(Resources, appearance));
        };
        Theme.Motion.AnimationsEnabled = controller.Settings.TransitionAnimations;
        var window = new ShellWindow(controller);
        MainWindow = window;
        // Pencere çizildi: açılış başarılı, kurtarma güncellemesinin işareti silinir.
        window.ContentRendered += (_, _) => RescueUpdate.Reached();
        window.Show();
    }
}
