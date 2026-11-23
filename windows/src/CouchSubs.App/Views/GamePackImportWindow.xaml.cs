// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using CouchSubs.Core;

namespace CouchSubs.App.Views;

public partial class GamePackImportWindow : Window
{
    private readonly GamePackImportPreview preview;
    private readonly string sourcePath;

    internal GamePackImportWindow(GamePackImportPreview preview, string sourcePath)
    {
        this.preview = preview;
        this.sourcePath = sourcePath;
        InitializeComponent();

        GameTitle.Text = preview.SuggestedTitle ?? Path.GetFileNameWithoutExtension(sourcePath);
        var culture = CultureInfo.CurrentCulture;
        UsableEntries.Text = preview.Entries.Count.ToString("N0", culture);
        InvalidRecords.Text = preview.InvalidCount.ToString("N0", culture);
        DuplicatePairs.Text = preview.DuplicateCount.ToString("N0", culture);
        ConflictingEntries.Text = preview.ConflictCount.ToString("N0", culture);
        if (preview.Entries.Count == 0)
            ShowError("The file contains no usable translations.");
    }

    private void OnTitleChanged(object sender, TextChangedEventArgs e)
    {
        if (InstallPack is not null)
            InstallPack.IsEnabled = preview.Entries.Count > 0 && !string.IsNullOrWhiteSpace(GameTitle.Text);
    }

    private void OnInstall(object sender, RoutedEventArgs e)
    {
        const string sourceIsDestination = "The selected file is already at the install location. Choose a different game title.";
        var title = GameTitle.Text.Trim();
        if (title.Length == 0 || preview.Entries.Count == 0) return;
        InstallError.Visibility = Visibility.Collapsed;

        try
        {
            var directory = GamePackLibrary.UserDirectory;
            if (GamePackImporter.IsSourceDestination(title, directory, sourcePath))
            {
                ShowError(sourceIsDestination);
                return;
            }

            var destination = Path.Combine(directory, GamePackImporter.MakeId(title) + ".json");
            var replacing = File.Exists(destination);
            if (replacing)
            {
                var text = Localizer.Current;
                var answer = MessageBox.Show(this,
                    text["A game pack with this ID already exists. Replacing it will overwrite the installed pack."],
                    text["Replace game pack?"], MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
                if (answer != MessageBoxResult.Yes) return;
            }

            GamePackImporter.Install(preview, title, directory, replacing, sourcePath: sourcePath);
            DialogResult = true;
        }
        catch (InvalidOperationException)
        {
            ShowError(sourceIsDestination);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException)
        {
            ShowError("The game pack could not be installed.");
        }
    }

    private void ShowError(string key)
    {
        InstallError.Text = Localizer.Current[key];
        InstallError.Visibility = Visibility.Visible;
    }
}
