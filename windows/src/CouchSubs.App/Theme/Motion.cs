// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace CouchSubs.App.Theme;

/// <summary>
/// Hareket değerleri (dört platformda aynı): kısa 150 ms, orta 250 ms, sayfa 350 ms; giriş eğrisi
/// cubic-bezier(0.05, 0.7, 0.1, 1), çıkış (0.3, 0, 0.8, 0.15) ve çıkış süresi girişin yarısı. "Hareketi azalt"
/// (Windows'un animasyon ayarı ya da Ayarlar › Temel › Geçiş Animasyonları kapalı) açıkken yalnız kısa solma (≤ 100 ms)
/// kalır, döngülü animasyonlar (nabız, nefes, parıltı) durur.
/// </summary>
public static class Motion
{
    // Değerler design/yeni-arayuz/tasarim.json › motion'dan (Mac ile ortak).
    public static readonly TimeSpan Short = TimeSpan.FromMilliseconds(Palette.MotionMs("short", 150));
    public static readonly TimeSpan Medium = TimeSpan.FromMilliseconds(Palette.MotionMs("medium", 250));
    public static readonly TimeSpan Page = TimeSpan.FromMilliseconds(Palette.MotionMs("page", 350));
    public static readonly TimeSpan ReducedFade = TimeSpan.FromMilliseconds(Palette.MotionMs("reduced", 100));

    public static readonly IEasingFunction Enter = Curve("enter", [0.05, 0.7, 0.1, 1]);
    public static readonly IEasingFunction Exit = Curve("exit", [0.3, 0, 0.8, 0.15]);

    private static IEasingFunction Curve(string name, double[] fallback)
    {
        var c = Palette.MotionCurve(name, fallback);
        return Freeze(new CubicBezierEase(c[0], c[1], c[2], c[3]));
    }
    /// <summary>Döngülü yumuşak gidip gelme (CSS ease-in-out).</summary>
    public static readonly IEasingFunction InOut = Freeze(new CubicBezierEase(0.42, 0, 0.58, 1));

    private static bool animationsSetting = true;

    /// <summary>Ayarlar › Geçiş Animasyonları. Kapalıysa ya da Windows animasyonları kapalıysa hareket azaltılır.</summary>
    public static bool AnimationsEnabled
    {
        get => animationsSetting;
        set
        {
            if (animationsSetting == value) return;
            animationsSetting = value;
            ReducedChanged?.Invoke();
        }
    }

    /// <summary>Hareket azaltılmış mı: Windows'ta animasyonlar kapalı ya da uygulamada geçiş animasyonları kapalı.</summary>
    public static bool Reduced => !animationsSetting || !SystemParameters.ClientAreaAnimation;

    public static event Action? ReducedChanged;

    /// <summary>Giriş süresi; hareket azaltılmışsa kısa solma.</summary>
    public static Duration In(TimeSpan span) => new(Reduced ? ReducedFade : span);

    /// <summary>Çıkış süresi girişin yarısıdır.</summary>
    public static Duration Out(TimeSpan span) => new(Reduced ? ReducedFade : TimeSpan.FromTicks(span.Ticks / 2));

    public static DoubleAnimation To(double to, TimeSpan span, bool exit = false) => new(to, exit ? Out(span) : In(span))
    {
        EasingFunction = exit ? Exit : Enter,
    };

    /// <summary>Öğe görünürken aşağıdan (ya da yukarıdan) kayarak ve solarak gelir. Hareket azaltılmışsa yalnız solar.</summary>
    public static void EnterFrom(UIElement element, double offsetY = 8, TimeSpan? span = null, TimeSpan? delay = null)
    {
        var duration = span ?? Page;
        var start = delay ?? TimeSpan.Zero;
        var fade = new DoubleAnimation(0, 1, In(duration)) { EasingFunction = Enter, BeginTime = Reduced ? TimeSpan.Zero : start };
        element.BeginAnimation(UIElement.OpacityProperty, fade);
        if (Reduced) return;
        var move = new TranslateTransform(0, offsetY);
        element.RenderTransform = move;
        move.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(offsetY, 0, In(duration)) { EasingFunction = Enter, BeginTime = start });
    }

    /// <summary>Başarı durumunun "oturma" animasyonu (btnok: %94'ten tam boya).</summary>
    public static void Settle(FrameworkElement element)
    {
        if (Reduced) return;
        var scale = new ScaleTransform(0.94, 0.94);
        element.RenderTransformOrigin = new Point(0.5, 0.5);
        element.RenderTransform = scale;
        var grow = new DoubleAnimation(0.94, 1, In(TimeSpan.FromMilliseconds(300))) { EasingFunction = Enter };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
    }

    /// <summary>Başarı tiki ve küçük "oturma" geri bildirimleri: hafif aşmalı yay (tasarim.json › motion.spring).</summary>
    public static readonly IEasingFunction Spring = Curve("spring", [0.34, 1.56, 0.64, 1]);

    // ── Ekli özellikler: XAML'de m:Motion.Enter="True", m:Motion.Pulse="True", m:Motion.Breathe="True". ──

    public static readonly DependencyProperty EnterProperty = DependencyProperty.RegisterAttached("Enter", typeof(bool), typeof(Motion),
        new PropertyMetadata(false, (d, e) => Hook(d, e, element => EnterFrom(element))));
    public static bool GetEnter(DependencyObject d) => (bool)d.GetValue(EnterProperty);
    public static void SetEnter(DependencyObject d, bool value) => d.SetValue(EnterProperty, value);

    /// <summary>
    /// Canlı noktası: 1,6 sn'de bir %35 saydamlığa iner ve döner. Hareket kapısına bağlı (<see cref="MotionGate.Live"/>):
    /// hareket azaltılmışken ya da pencere arka plandayken durağan.
    /// </summary>
    public static readonly DependencyProperty PulseProperty = DependencyProperty.RegisterAttached("Pulse", typeof(bool), typeof(Motion),
        new PropertyMetadata(false, (d, e) =>
        {
            if (d is not FrameworkElement element || e.NewValue is not true) return;
            Gated(element, () => MotionGate.Live,
                () => element.BeginAnimation(UIElement.OpacityProperty, Fps(new DoubleAnimation(1, 0.35, new Duration(TimeSpan.FromSeconds(0.8)))
                {
                    AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = InOut,
                }, 30)),
                () => element.BeginAnimation(UIElement.OpacityProperty, null));
        }));
    public static bool GetPulse(DependencyObject d) => (bool)d.GetValue(PulseProperty);
    public static void SetPulse(DependencyObject d, bool value) => d.SetValue(PulseProperty, value);

    /// <summary>
    /// Logodaki altyazı çubuklarının nefesi: genişlik 1,6 sn'de %60'a iner ve döner. Yalnız boşta (<see cref="MotionGate.Ambient"/>):
    /// çeviri sürerken, hareket azaltılmışken ya da pencere arka plandayken durağan.
    /// </summary>
    public static readonly DependencyProperty BreatheProperty = DependencyProperty.RegisterAttached("Breathe", typeof(double), typeof(Motion),
        new PropertyMetadata(-1.0, (d, e) =>
        {
            if (d is not FrameworkElement element || (double)e.NewValue < 0) return;
            var delay = TimeSpan.FromSeconds((double)e.NewValue);
            var scale = new ScaleTransform(1, 1);
            element.RenderTransformOrigin = new Point(0.5, 0.5);
            element.RenderTransform = scale;
            Gated(element, () => MotionGate.Ambient,
                () => scale.BeginAnimation(ScaleTransform.ScaleXProperty, Fps(new DoubleAnimation(1, 0.6, new Duration(TimeSpan.FromSeconds(0.8)))
                {
                    AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = InOut, BeginTime = delay,
                }, 30)),
                () => scale.BeginAnimation(ScaleTransform.ScaleXProperty, null));
        }));
    public static double GetBreathe(DependencyObject d) => (double)d.GetValue(BreatheProperty);
    public static void SetBreathe(DependencyObject d, double value) => d.SetValue(BreatheProperty, value);

    /// <summary>Dönen yükleme halkası (1,1 sn'de bir tur). Yalnız boşta; kapı kapalıyken durağan.</summary>
    public static readonly DependencyProperty SpinProperty = DependencyProperty.RegisterAttached("Spin", typeof(bool), typeof(Motion),
        new PropertyMetadata(false, (d, e) =>
        {
            if (d is not FrameworkElement element || e.NewValue is not true) return;
            var rotate = new RotateTransform();
            element.RenderTransformOrigin = new Point(0.5, 0.5);
            element.RenderTransform = rotate;
            Gated(element, () => MotionGate.Ambient,
                () => rotate.BeginAnimation(RotateTransform.AngleProperty,
                    Fps(new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1.1)) { RepeatBehavior = RepeatBehavior.Forever }, 30)),
                () => rotate.BeginAnimation(RotateTransform.AngleProperty, null));
        }));
    public static bool GetSpin(DependencyObject d) => (bool)d.GetValue(SpinProperty);
    public static void SetSpin(DependencyObject d, bool value) => d.SetValue(SpinProperty, value);

    private static void Hook(DependencyObject d, DependencyPropertyChangedEventArgs e, Action<FrameworkElement> start)
    {
        if (d is not FrameworkElement element || e.NewValue is not true) return;
        if (element.IsLoaded) start(element);
        else element.Loaded += (_, _) => start(element);
    }

    /// <summary>Sürekli animasyonun kare hızı sınırı (WPF varsayılanı 60): boşta işlemci yükü düşük kalsın.</summary>
    public static T Fps<T>(T timeline, int fps) where T : Timeline
    {
        Timeline.SetDesiredFrameRate(timeline, fps);
        return timeline;
    }

    /// <summary>
    /// Kapıya bağlı sürekli animasyon: öğe yüklü, görünür ve <paramref name="open"/> doğruyken <paramref name="start"/>,
    /// değilse <paramref name="stop"/> (durağan kare). Kapı değişince (çeviri başladı, pencere arka plana geçti, Geçiş
    /// Animasyonları kapandı) kendiliğinden güncellenir. Animasyon hatası uygulamayı düşürmez.
    /// </summary>
    public static void Gated(FrameworkElement element, Func<bool> open, Action start, Action stop)
    {
        var running = false;
        void Update()
        {
            try
            {
                var want = element.IsLoaded && element.IsVisible && open();
                if (want == running) return;
                running = want;
                if (want) start(); else stop();
            }
            catch (Exception error) { System.Diagnostics.Debug.WriteLine($"Animasyon: {error.Message}"); }
        }
        void OnGate() => element.Dispatcher.BeginInvoke(Update);
        element.Loaded += (_, _) =>
        {
            MotionGate.Changed -= OnGate;
            MotionGate.Changed += OnGate;
            Update();
        };
        element.Unloaded += (_, _) =>
        {
            MotionGate.Changed -= OnGate;
            Update();
        };
        element.IsVisibleChanged += (_, _) => Update();
        if (element.IsLoaded)
        {
            MotionGate.Changed += OnGate;
            Update();
        }
    }

    private static T Freeze<T>(T freezable) where T : Freezable
    {
        freezable.Freeze();
        return freezable;
    }
}

/// <summary>
/// Uygulamanın tek hareket kapısı (Perde; Mac DSMotionGate). Sürekli animasyonlar buradan karar verir:
/// <list type="bullet">
/// <item><see cref="Ambient"/>: boşta süren efektler (ortam ışığı, logo nefesi, arama halkası, çubuk yükleyici, parıltı,
/// başarı ışınları). Çeviri sürerken, hareket azaltılmışken (Windows'un "Animasyon efektleri" ya da Ayarlar › Geçiş
/// Animasyonları kapalı) ya da pencere önde değilken (simge durumunda, arka planda) durağan.</item>
/// <item><see cref="Live"/>: canlı nabız; çeviri sürerken de atar (ekrandaki tek sürekli animasyon), hareket
/// azaltılmışken ya da pencere arka plandayken durağan.</item>
/// </list>
/// Boşta işlemci hedefi ≤ %2: sürekli animasyonlar 15–30 kare/sn ile sınırlı, kapı kapanınca kaldırılır.
/// </summary>
public static class MotionGate
{
    private static bool translating;
    private static bool active = true;

    static MotionGate()
    {
        Motion.ReducedChanged += Raise;
        SystemParameters.StaticPropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SystemParameters.ClientAreaAnimation)) Raise();
        };
    }

    /// <summary>Çeviri sürüyor (kabuk denetleyicinin IsRunning'inden kurar).</summary>
    public static bool Translating
    {
        get => translating;
        set
        {
            if (translating == value) return;
            translating = value;
            Raise();
        }
    }

    /// <summary>Uygulamanın bir penceresi önde (etkin) ve simge durumunda değil.</summary>
    public static bool WindowActive
    {
        get => active;
        set
        {
            if (active == value) return;
            active = value;
            Raise();
        }
    }

    /// <summary>Yalnız ekran görüntüsü ve ölçüm aracı: kapıyı zorla açar (true) ya da kapatır (false).</summary>
    public static bool? Forced { get; set; }

    public static bool Reduced => Motion.Reduced;
    public static bool Ambient => Forced ?? (!Motion.Reduced && !translating && active);
    public static bool Live => Forced ?? (!Motion.Reduced && active);

    public static event Action? Changed;

    private static void Raise() => Changed?.Invoke();
}

/// <summary>CSS cubic-bezier(x1, y1, x2, y2) eğrisi.</summary>
public sealed class CubicBezierEase : EasingFunctionBase
{
    private double x1, y1, x2, y2;

    public CubicBezierEase() : this(0.25, 0.1, 0.25, 1) { }

    public CubicBezierEase(double x1, double y1, double x2, double y2)
    {
        this.x1 = x1; this.y1 = y1; this.x2 = x2; this.y2 = y2;
        // EaseIn kipinde EaseInCore değeri olduğu gibi kullanılır.
        EasingMode = EasingMode.EaseIn;
    }

    protected override double EaseInCore(double normalizedTime)
    {
        var t = Solve(normalizedTime);
        return Bezier(t, y1, y2);
    }

    private static double Bezier(double t, double p1, double p2) => 3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t;

    private static double Slope(double t, double p1, double p2) => 3 * (1 - t) * (1 - t) * p1 + 6 * (1 - t) * t * (p2 - p1) + 3 * t * t * (1 - p2);

    /// <summary>x(t) = x için t (Newton, gerekirse ikiye bölme).</summary>
    private double Solve(double x)
    {
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        var t = x;
        for (var i = 0; i < 8; i++)
        {
            var error = Bezier(t, x1, x2) - x;
            if (Math.Abs(error) < 1e-6) return t;
            var slope = Slope(t, x1, x2);
            if (Math.Abs(slope) < 1e-6) break;
            t -= error / slope;
        }
        double lo = 0, hi = 1;
        t = x;
        for (var i = 0; i < 30; i++)
        {
            var value = Bezier(t, x1, x2);
            if (Math.Abs(value - x) < 1e-6) break;
            if (value < x) lo = t; else hi = t;
            t = (lo + hi) / 2;
        }
        return t;
    }

    protected override Freezable CreateInstanceCore() => new CubicBezierEase(x1, y1, x2, y2);

    protected override void CloneCore(Freezable source)
    {
        base.CloneCore(source);
        if (source is CubicBezierEase other) { x1 = other.x1; y1 = other.y1; x2 = other.x2; y2 = other.y2; }
    }

    protected override void GetAsFrozenCore(Freezable source)
    {
        base.GetAsFrozenCore(source);
        if (source is CubicBezierEase other) { x1 = other.x1; y1 = other.y1; x2 = other.x2; y2 = other.y2; }
    }

    protected override void CloneCurrentValueCore(Freezable source)
    {
        base.CloneCurrentValueCore(source);
        if (source is CubicBezierEase other) { x1 = other.x1; y1 = other.y1; x2 = other.x2; y2 = other.y2; }
    }

    protected override void GetCurrentValueAsFrozenCore(Freezable source)
    {
        base.GetCurrentValueAsFrozenCore(source);
        if (source is CubicBezierEase other) { x1 = other.x1; y1 = other.y1; x2 = other.x2; y2 = other.y2; }
    }
}
