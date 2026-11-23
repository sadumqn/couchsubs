// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using CouchSubs.App.Theme;
using System.Windows.Controls;
using System.Windows.Media;
using CouchSubs.App.Controls;
using CouchSubs.App.Services;
using CouchSubs.Core;

namespace CouchSubs.App.Views;

/// <summary>
/// Geliştirme aracı: yeni arayüzün ortak bileşenleri tek sayfada (ScreenRenderer "bilesenler-*.png" olarak döker).
/// Uygulamada gösterilmez; bileşenlerin görünümü Windows makinesi olmadan böyle denetlenir.
/// </summary>
public sealed class DesignGallery : UserControl
{
    public DesignGallery()
    {
        var text = Localizer.Current;
        var root = new DockPanel();
        var titleBar = new Grid { Height = 72, Margin = Sp.T("l", "0", "l", "0") };
        titleBar.ColumnDefinitions.Add(new ColumnDefinition());
        titleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        titleBar.ColumnDefinitions.Add(new ColumnDefinition());
        var brand = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        brand.Children.Add(new CouchLogo());
        brand.Children.Add(new TextBlock { Text = "CouchSubs", FontWeight = FontWeights.Bold, Margin = Sp.T("s", "0", "0", "0"), VerticalAlignment = VerticalAlignment.Center });
        titleBar.Children.Add(brand);
        var tabs = Group("TabGroup", "TopTab", [text["Home"], text["History"], text["Settings"]], 0);
        Grid.SetColumn(tabs, 1);
        titleBar.Children.Add(tabs);
        var pill = new StatusPill { Text = text["Ready"], Tone = PillTone.Success, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(pill, 2);
        titleBar.Children.Add(pill);
        DockPanel.SetDock(titleBar, Dock.Top);
        root.Children.Add(titleBar);
        var band = new AdBand();
        DockPanel.SetDock(band, Dock.Bottom);
        root.Children.Add(band);

        var grid = new Grid { Margin = Sp.T("l") };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Sp.V("l")) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Sp.V("l")) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var perde = PerdeColumn();
        Grid.SetColumn(perde, 4);
        grid.Children.Add(perde);
        var left = new Card { Title = "Düğmeler" };
        var buttons = new WrapPanel();
        foreach (var (style, label) in new[] { ("PrimaryButton", "Çeviriyi Başlat"), ("LiveButton", "Çeviriyi Durdur"), ("SecondaryButton", "Ekranı Çevir"),
                     ("DarkButton", "Devam"), ("SuccessButton", "Eşleşti"), ("GhostButton", "Atla") })
        {
            var button = new Button { Content = label, Margin = Sp.T("0", "0", "s", "s") };
            button.SetResourceReference(StyleProperty, style);
            buttons.Children.Add(button);
        }
        var busy = new Button { Content = "Aranıyor…", IsEnabled = false, Margin = Sp.T("0", "0", "s", "s") };
        busy.SetResourceReference(StyleProperty, "SecondaryButton");
        buttons.Children.Add(busy);
        var leftStack = new StackPanel();
        leftStack.Children.Add(buttons);
        leftStack.Children.Add(Group("SegmentGroup", "SegmentButton", ["Hızlı", "Dengeli", "Doğru"], 1));
        leftStack.Children.Add(new System.Windows.Controls.TextBox { Text = "192.168.1.20", Margin = Sp.T("0", "m", "0", "0") });
        var badges = new StackPanel { Orientation = Orientation.Horizontal, Margin = Sp.T("0", "m", "0", "0") };
        foreach (var (tone, label) in new[] { (PillTone.Success, "Açık"), (PillTone.Live, "Kapalı"), (PillTone.Idle, "Bilinmiyor"), (PillTone.Attention, "Önerilir") })
            badges.Children.Add(new Badge { Tone = tone, Content = label, Margin = Sp.T("0", "0", "xs", "0") });
        leftStack.Children.Add(badges);
        var slider = new Slider { Minimum = 16, Maximum = 50, Value = 28, Margin = Sp.T("0", "m", "0", "0") };
        leftStack.Children.Add(slider);
        left.Content = leftStack;
        grid.Children.Add(left);

        var right = new Card { Title = "Ses" };
        var rightStack = new StackPanel();
        rightStack.Children.Add(new SwitchRow { Content = "Açılış Sesi", Description = "Yalnız ilk açılışta çalar.", IsChecked = true });
        rightStack.Children.Add(new SwitchRow { Content = "Geçiş Animasyonları", Description = "Kapalıyken yalnız kısa solma kullanılır.", Divider = false });
        rightStack.Children.Add(new OptionCard { Content = "Gemini", Description = "Ücretsiz Google anahtarıyla daha iyi çeviri.", IsChecked = true, GroupName = "g", Margin = Sp.T("0", "m", "0", "xs") });
        rightStack.Children.Add(new OptionCard { Content = "DeepL", Description = "Kendi DeepL anahtarınızla.", GroupName = "g" });
        var swatches = new StackPanel { Orientation = Orientation.Horizontal, Margin = Sp.T("0", "m", "0", "0") };
        foreach (var (hex, on) in new[] { ("#101014", true), ("#0E1A30", false), ("#2B2D33", false), ("#FFFFFF", false) })
            swatches.Children.Add(new ColorSwatch { Swatch = (Brush)new BrushConverter().ConvertFromString(hex)!, IsChecked = on, GroupName = "s", Margin = Sp.T("0", "0", "s", "0") });
        rightStack.Children.Add(swatches);
        var nav = new StackPanel { Margin = Sp.T("0", "m", "0", "0") };
        nav.Children.Add(new NavItem { Content = "Temel", Hint = "Çeviri, Ses", IsChecked = true, GroupName = "n" });
        nav.Children.Add(new NavItem { Content = "Oyun Paketleri", GroupName = "n" });
        rightStack.Children.Add(nav);
        right.Content = rightStack;
        Grid.SetColumn(right, 2);
        grid.Children.Add(right);
        root.Children.Add(grid);
        Content = root;
    }

    /// <summary>
    /// Perde bileşenleri (Mac PerdeCatalog): durum hapları, nabız / çubuk yükleyici / arama halkası, simge kareleri, adım
    /// çizelgesi, perde önizlemesi ve altyazı plakası, oyun kapakları (seçili ve seçisiz), başarı anı.
    /// </summary>
    private static UIElement PerdeColumn()
    {
        var stack = new SpacedStack { Gap = "m" };
        var chips = new WrapPanel();
        foreach (var (tone, label) in new[] { (ChipTone.Ok, "Eşli"), (ChipTone.Live, "Canlı"), (ChipTone.Amber, "Aranıyor…"), (ChipTone.Info, "Bilgi"), (ChipTone.Muted, "Durdu") })
            chips.Children.Add(new Chip { Text = label, Tone = tone, Margin = Sp.T("0", "0", "xs", "xs") });
        stack.Children.Add(chips);
        var loaders = new StackPanel { Orientation = Orientation.Horizontal };
        loaders.Children.Add(new PulseDot { Diameter = 10, Margin = Sp.T("0", "0", "m", "0") });
        loaders.Children.Add(new BarsLoader { Margin = Sp.T("0", "0", "m", "0") });
        loaders.Children.Add(new SearchRings { Size = 48, Margin = Sp.T("0", "0", "m", "0") });
        foreach (var tone in new[] { IconTone.Amber, IconTone.Peach, IconTone.Olive, IconTone.Teal, IconTone.Plum, IconTone.Sky, IconTone.Gray })
            loaders.Children.Add(new IconSquare { Glyph = "", Tone = tone, Size = 28, Margin = Sp.T("0", "0", "xxs", "0") });
        stack.Children.Add(loaders);
        stack.Children.Add(new StepTimeline
        {
            Steps = [new("PlayStation Hesabı", "İkinci hesapla giriş yapıldı.", StepPhase.Done), new("PS5 Bulundu", null, StepPhase.Current), new("Eşleşme ve İlk Görüntü", null, StepPhase.Todo)],
        });
        var preview = new PerdePreview { ShowArea = true };
        preview.SetLine("Lucia:", "Hazır olduğunda haber ver, gidiyoruz.", 13);
        preview.SetPills(new Chip { Text = "CANLI", Tone = ChipTone.GlassLive });
        stack.Children.Add(preview);
        var covers = new StackPanel { Orientation = Orientation.Horizontal, Margin = Sp.T("xxs", "xs", "0", "xs") };
        covers.Children.Add(new GameCover("Red Dead Redemption 2", "Paket Var", true, 88) { Margin = Sp.T("0", "0", "m", "0") });
        covers.Children.Add(new GameCover("Grand Theft Auto V", null, false, 88) { Margin = Sp.T("0", "0", "m", "0") });
        covers.Children.Add(new SuccessMoment("Eşleşti") { VerticalAlignment = VerticalAlignment.Center });
        stack.Children.Add(covers);
        return new Card { Title = "Perde", Content = stack, VerticalAlignment = VerticalAlignment.Top };
    }

    private static Border Group(string groupStyle, string itemStyle, string[] labels, int selected)
    {
        var group = new Border();
        group.SetResourceReference(StyleProperty, groupStyle);
        var row = new UniformGrid1(labels.Length);
        var name = Guid.NewGuid().ToString("N");
        for (var i = 0; i < labels.Length; i++)
        {
            var item = new RadioButton { Content = labels[i], GroupName = name, IsChecked = i == selected };
            item.SetResourceReference(StyleProperty, itemStyle);
            row.Children.Add(item);
        }
        group.Child = row;
        return group;
    }

    /// <summary>Tek satırlı eşit genişlikli dizilim.</summary>
    private sealed class UniformGrid1 : System.Windows.Controls.Primitives.UniformGrid
    {
        public UniformGrid1(int columns) { Rows = 1; Columns = columns; }
    }
}
