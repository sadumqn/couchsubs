// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Markup;
using CouchSubs.Core;

namespace CouchSubs.App.Theme;

/// <summary>XAML'de ekran metni: <c>{t:T 'Start translating'}</c>. Metin Mac'le ortak katalogdan gelir.</summary>
[MarkupExtensionReturnType(typeof(string))]
public sealed class T(string key) : MarkupExtension
{
    public override object ProvideValue(IServiceProvider serviceProvider) => Localizer.Current[key];
}

/// <summary>true → görünür; <c>ConverterParameter=invert</c> ile tersi.</summary>
public sealed class VisibleIf : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var shown = value switch
        {
            bool flag => flag,
            string text => text.Length > 0,
            null => false,
            _ => true,
        };
        if (parameter as string == "invert") shown = !shown;
        return shown ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

/// <summary>Bool'u tersine çevirir (ör. IsEnabled="{Binding IsStarting, Converter={StaticResource Not}}").</summary>
public sealed class Not : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => value is not true;
    public object ConvertBack(object value, Type targetType, object? parameter, CultureInfo culture) => value is not true;
}

/// <summary>Yüksekliğin yarısı köşe (hap biçimi); <c>{Binding ActualHeight, RelativeSource={RelativeSource Self}, Converter={StaticResource Pill}}</c>.</summary>
public sealed class PillCorner : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        new CornerRadius(value is double height && height > 0 ? height / 2 : 0);

    public object ConvertBack(object value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}
