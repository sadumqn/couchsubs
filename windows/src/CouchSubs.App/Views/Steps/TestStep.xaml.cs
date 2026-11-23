// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using CouchSubs.App.Controls;
using System.Windows.Controls;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

public partial class TestStep : UserControl
{
    private bool sent;

    public TestStep()
    {
        InitializeComponent();
        // Perde önizlemesi: örnek Türkçe altyazı plakası (Mac DSPerdePreview).
        Preview.SetLine("Lucia:", "Hazır olduğunda haber ver, gidiyoruz.", 15);
        Loaded += (_, _) =>
        {
            ShowTarget();
            ShowTimeline();
            Controller.PropertyChanged += OnChanged;
        };
        Unloaded += (_, _) => { if (DataContext is AppController controller) controller.PropertyChanged -= OnChanged; };
    }

    private void OnChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppController.TvClients) or nameof(AppController.TranslatorStatus) or nameof(AppController.Console))
            Dispatcher.BeginInvoke(ShowTimeline);
    }

    /// <summary>
    /// Adım çizelgesi (Mac TryItStep): PS5 bağlantısı (ya da pencere / Xbox), çeviri çalışıyor, TV'de (ya da bu ekranda) altyazı;
    /// biten amber + tik, şimdiki amber halka.
    /// </summary>
    private void ShowTimeline()
    {
        var text = Localizer.Current;
        var onComputer = Controller.Settings.Output == SubtitleOutput.Computer;
        var picture = Controller.Console is not null || Controller.IsXbox || Controller.CanStart;
        var translation = Controller.TranslatorStatus == TranslatorStatus.Ready;
        var shown = sent && (onComputer || Controller.TvClients > 0);
        var console = Controller.Console is { } registered ? (string.IsNullOrEmpty(registered.Name) ? "PS5" : registered.Name) : Controller.ConsoleTitle;
        var engine = Controller.Settings.Engine == TranslationEngine.Free ? text["Free Translation"] : Controller.Settings.Engine.DisplayName();
        var screen = Controller.Tv?.Name ?? text["This PC"];
        Timeline.Steps =
        [
            new(text[Controller.IsXbox ? "Xbox · Beta" : "PS5 Connection"], console, StepTimeline.Phase(picture, true)),
            new(text["Translation Working"], engine, StepTimeline.Phase(translation, picture)),
            new(text[onComputer ? "Subtitle on This Screen" : "TV Shows the Subtitle"], screen, StepTimeline.Phase(shown, picture && translation)),
        ];
    }

    private AppController Controller => (AppController)DataContext;

    /// <summary>TV seçilmediyse ("TV'm yok") örnek altyazı bu bilgisayarın ekranında görünür.</summary>
    private void ShowTarget()
    {
        if (Controller.Settings.Output != SubtitleOutput.Computer) return;
        var text = Localizer.Current;
        Layout.Message = text["CouchSubs will show a sample subtitle on this computer's screen, at the bottom."];
        Question.Title = text["Do you see it on the screen?"];
        Hint.Text = text["If you don't see it, send it again. It shows for a few seconds at the bottom of the screen."];
        Adjust.Visibility = Visibility.Visible;
        AutoOpenNote.Visibility = Visibility.Collapsed;
    }

    private void OnSend(object sender, RoutedEventArgs e)
    {
        Controller.SendTestSubtitle();
        sent = true;
        Send.Style = (Style)FindResource("SecondaryButton");
        Question.Visibility = Visibility.Visible;
        ShowTimeline();
    }

    private void OnAdjust(object sender, RoutedEventArgs e) => Controller.OverlayAdjusting = true;

    private void OnYes(object sender, RoutedEventArgs e)
    {
        // Konumlandırılırken "Evet" denirse yeni yer kaydedilir (Bitti gibi).
        Controller.CommitOverlayEdit();
        Controller.Advance();
    }

    private void OnNo(object sender, RoutedEventArgs e) => Controller.Step = OnboardingStep.Tv;
}
