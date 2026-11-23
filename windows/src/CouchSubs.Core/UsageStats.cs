// SPDX-License-Identifier: AGPL-3.0-only

using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;

namespace CouchSubs.Core;

/// <summary>
/// Kullanım verisi (Ayarlar › Oyun paketleri › Kullanım verisi, varsayılan açık): telefonlardaki Firebase Analytics
/// olaylarının aynısı Google Analytics 4 Measurement Protocol ile (HTTPS POST) gönderilir. Kimlik olarak kuruluma özgü
/// rastgele bir UUID (<c>usage-id</c> dosyası) kullanılır; altyazı metni, görüntü, PSN/Microsoft hesabı ve anahtarlar
/// hiçbir olayda yoktur. Ölçüm kimliği ve API sırrı derlemeden gelir (CI sırları <c>GA_MEASUREMENT_ID</c>,
/// <c>GA_API_SECRET</c>); yoksa (<c>config</c> null) hiçbir şey kuyruğa girmez, hiçbir istek gitmez. Olaylar bellekte
/// birikir, dakikada bir (ve uygulama kapanırken) 25'lik parçalar hâlinde arka planda gönderilir; ağ hatasında sessizce
/// sonraki tura kalır. <see cref="Record"/> yalnız kilit altında listeye ekler: çeviri hattını yavaşlatmaz. Kapatılınca
/// kuyruk silinir.
/// Mac'teki CouchSubsCore/UsageStats.swift ile aynı olaylar ve gövde (ortak deneme: Fixtures/usage-stats.json).
/// </summary>
public sealed class UsageStats : IDisposable
{
    public const bool EnabledByDefault = true;
    public const string Endpoint = "https://www.google-analytics.com/mp/collect";
    /// <summary>Measurement Protocol bir istekte en çok 25 olay alır.</summary>
    public const int BatchSize = 25;
    /// <summary>Gönderilemeyen olaylardan en çok bu kadarı bellekte bekler (en eskiler düşer).</summary>
    public const int MaxQueue = 200;
    public static readonly TimeSpan FlushInterval = TimeSpan.FromMinutes(1);

    /// <summary>Ölçüm kimliği (G-…) ve Measurement Protocol API sırrı.</summary>
    public sealed record Config(string MeasurementId, string ApiSecret)
    {
        /// <summary>Biri boşsa null: ölçüm kapalı.</summary>
        public static Config? Create(string? measurementId, string? apiSecret)
        {
            var id = measurementId?.Trim() ?? "";
            var secret = apiSecret?.Trim() ?? "";
            return id.Length == 0 || secret.Length == 0 || id.Contains("$(") || secret.Contains("$(") ? null : new Config(id, secret);
        }

        /// <summary>
        /// Derlemedeki kimlikler: <c>COUCHSUBS_GA_MEASUREMENT_ID</c>/<c>COUCHSUBS_GA_API_SECRET</c> ortam değişkenleri
        /// (yerel deneme) ya da App projesindeki MSBuild özellikleri <c>CouchSubsGaMeasurementId</c>/<c>CouchSubsGaApiSecret</c>
        /// (CI: aynı adlı sırlar). Hiçbiri yoksa null.
        /// </summary>
        public static Config? FromBuild(Assembly? assembly = null, Func<string, string?>? environment = null)
        {
            environment ??= Environment.GetEnvironmentVariable;
            if (Create(environment("COUCHSUBS_GA_MEASUREMENT_ID"), environment("COUCHSUBS_GA_API_SECRET")) is { } fromEnvironment) return fromEnvironment;
            var metadata = (assembly ?? Assembly.GetEntryAssembly())?.GetCustomAttributes<AssemblyMetadataAttribute>().ToList() ?? [];
            string? Value(string key) => metadata.FirstOrDefault(a => a.Key == key)?.Value;
            return Create(Value("CouchSubsGaMeasurementId"), Value("CouchSubsGaApiSecret"));
        }
    }

    /// <summary>Telefonlardaki olaylarla aynı adlar ve alanlar (Android Telemetry, iPhone AnalyticsEvent). Değer string ya da int.</summary>
    public sealed record Event(string Name, IReadOnlyDictionary<string, object> Params)
    {
        public bool Equals(Event? other) =>
            other is not null && Name == other.Name && Params.Count == other.Params.Count
            && Params.All(pair => other.Params.TryGetValue(pair.Key, out var value) && Equals(value, pair.Value));

        public override int GetHashCode() => Name.GetHashCode();

        /// <summary>
        /// Açılan ekran. Firebase'in <c>screen_view</c> adı Measurement Protocol'de ayrılmış olduğundan web akışının
        /// "Sayfalar ve ekranlar" raporunu dolduran <c>page_view</c> gider; ekranın adı <c>screen_name</c> ve <c>page_title</c>'dadır.
        /// </summary>
        public static Event Screen(string name) => new("page_view", new Dictionary<string, object>
        {
            ["screen_name"] = name, ["page_title"] = name, ["page_location"] = "app://couchsubs/" + name,
        });

        /// <summary>Kurulum bitti; altyazının hedefi (tv, computer, both) ve konsol türü (ps5, xbox).</summary>
        public static Event OnboardingDone(string target, string console) =>
            new("onboarding_done", new Dictionary<string, object> { ["target"] = target, ["console"] = console });

        /// <summary>Çeviri başladı: hedef, çeviri motoru, paketler açık mı, konsol türü.</summary>
        public static Event SessionStart(string target, string engine, bool packs, string console) =>
            new("subtitle_session_start", new Dictionary<string, object>
            {
                ["target"] = target, ["engine"] = engine, ["packs"] = packs ? "true" : "false", ["console"] = console,
            });

        /// <summary>Çeviri bitti: süre (saniye), gösterilen satır sayısı, bunlardan hazır paketten gelenler.</summary>
        public static Event SessionStop(int seconds, int lines, int packLines) =>
            new("subtitle_session_stop", new Dictionary<string, object> { ["seconds"] = seconds, ["lines"] = lines, ["pack_lines"] = packLines });

        /// <summary>TV uygulaması bağlandı: bağlı TV sayısı ve markası (lg, samsung, androidTV).</summary>
        public static Event TvConnected(int count, string brand) =>
            new("tv_connected", new Dictionary<string, object> { ["count"] = count, ["brand"] = brand });

        /// <summary>Oturumda ilk kez satır gelen oyun paketi (kimliği, ör. gta6).</summary>
        public static Event PackHit(string pack) => new("pack_hit", new Dictionary<string, object> { ["pack"] = pack });
    }

    private readonly object gate = new();
    private readonly SemaphoreSlim sending = new(1, 1);
    private readonly Config? config;
    private readonly string idFile;
    private readonly IReadOnlyDictionary<string, string> userProperties;
    private readonly string sessionId;
    private readonly HttpClient http;
    private readonly List<Event> queue = [];
    private bool enabled;
    private string? clientId;

    /// <param name="config">null ise (derlemede kimlik yok, testler) hiçbir şey yapılmaz.</param>
    /// <param name="idFile">Kuruluma özgü rastgele kimliğin dosyası; ilk gönderimde oluşturulur.</param>
    /// <param name="handler">HTTP katmanı; testlerde sahtesi verilir.</param>
    public UsageStats(Config? config, string idFile, string appVersion, string osVersion, string platform = "windows",
        bool enabled = EnabledByDefault, HttpMessageHandler? handler = null, DateTimeOffset? now = null)
    {
        this.config = config;
        this.idFile = idFile;
        this.enabled = enabled;
        userProperties = new Dictionary<string, string> { ["app_version"] = appVersion, ["os_version"] = osVersion, ["platform"] = platform };
        sessionId = (now ?? DateTimeOffset.UtcNow).ToUnixTimeSeconds().ToString(System.Globalization.CultureInfo.InvariantCulture);
        http = handler is null ? new HttpClient() : new HttpClient(handler);
        http.Timeout = TimeSpan.FromSeconds(15);
    }

    /// <summary>Derlemede ölçüm kimliği var mı (yoksa ayar ve bilgi notu gösterilmez).</summary>
    public bool IsConfigured => config is not null;
    public bool IsEnabled { get { lock (gate) return enabled; } }
    public IReadOnlyList<Event> Queued { get { lock (gate) return [.. queue]; } }

    /// <summary>Kapatılınca bekleyen olaylar da silinir: kullanıcı vazgeçtiyse hiçbir şey gitmez.</summary>
    public void SetEnabled(bool value)
    {
        lock (gate)
        {
            enabled = value;
            if (!value) queue.Clear();
        }
    }

    /// <summary>Olayı kuyruğa ekler; kapalıysa ya da yapılandırılmadıysa bir şey yapmaz. Ağa çıkmaz.</summary>
    public void Record(Event item)
    {
        if (config is null) return;
        lock (gate)
        {
            if (!enabled) return;
            queue.Add(item);
            if (queue.Count > MaxQueue) queue.RemoveRange(0, queue.Count - MaxQueue);
        }
    }

    /// <summary>
    /// Kuyruğu 25'lik parçalar hâlinde gönderir. Ağ hatasında ya da 5xx'te kuyruk kalır; başka yanıtta parça atılır
    /// (Measurement Protocol hatalı olayı da 2xx ile yanıtlar, yeniden göndermek düzeltmez).
    /// </summary>
    public async Task FlushAsync(CancellationToken cancellationToken = default)
    {
        if (config is null || !await sending.WaitAsync(0, cancellationToken).ConfigureAwait(false)) return;
        try
        {
            while (true)
            {
                List<Event> batch;
                lock (gate) batch = enabled ? [.. queue.Take(BatchSize)] : [];
                if (batch.Count == 0) return;
                var body = Payload(LoadClientId(), sessionId, userProperties, batch);
                try
                {
                    using var content = new StringContent(body, Encoding.UTF8, "application/json");
                    using var response = await http.PostAsync(RequestUri(config), content, cancellationToken).ConfigureAwait(false);
                    if ((int)response.StatusCode >= 500) return;
                }
                catch (Exception error) when (error is HttpRequestException or TaskCanceledException or OperationCanceledException)
                {
                    return;
                }
                lock (gate)
                {
                    // Bu arada kapatıldıysa kuyruk zaten boştur.
                    var sent = Math.Min(batch.Count, queue.Count);
                    if (sent > 0 && queue.Take(sent).SequenceEqual(batch.Take(sent))) queue.RemoveRange(0, sent);
                }
            }
        }
        finally
        {
            sending.Release();
        }
    }

    /// <summary>İsteğin adresi: ölçüm kimliği ve API sırrı sorgu dizesinde.</summary>
    public static Uri RequestUri(Config config) =>
        new($"{Endpoint}?measurement_id={Uri.EscapeDataString(config.MeasurementId)}&api_secret={Uri.EscapeDataString(config.ApiSecret)}");

    /// <summary>
    /// Measurement Protocol gövdesi. Her olaya oturum kimliği (uygulamanın açıldığı an) ve etkileşim süresi eklenir; reklam
    /// kişiselleştirmesi ve reklam verisi her zaman reddedilir.
    /// </summary>
    public static string Payload(string clientId, string sessionId, IReadOnlyDictionary<string, string> userProperties, IEnumerable<Event> events)
    {
        var properties = new JsonObject();
        foreach (var (key, value) in userProperties.OrderBy(pair => pair.Key, StringComparer.Ordinal))
            properties[key] = new JsonObject { ["value"] = value };
        var list = new JsonArray();
        foreach (var item in events)
        {
            var parameters = new JsonObject();
            foreach (var (key, value) in item.Params.OrderBy(pair => pair.Key, StringComparer.Ordinal))
                parameters[key] = value switch
                {
                    int number => JsonValue.Create(number),
                    long number => JsonValue.Create(number),
                    _ => JsonValue.Create(value.ToString()),
                };
            parameters["session_id"] = sessionId;
            parameters["engagement_time_msec"] = 100;
            list.Add(new JsonObject { ["name"] = item.Name, ["params"] = parameters });
        }
        return new JsonObject
        {
            ["client_id"] = clientId,
            ["consent"] = new JsonObject { ["ad_personalization"] = "DENIED", ["ad_user_data"] = "DENIED" },
            ["events"] = list,
            ["non_personalized_ads"] = true,
            ["user_properties"] = properties,
        }.ToJsonString();
    }

    private string LoadClientId()
    {
        lock (gate) if (clientId is not null) return clientId;
        string? saved = null;
        try { saved = File.Exists(idFile) ? File.ReadAllText(idFile).Trim() : null; }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        var id = saved is not null && Guid.TryParse(saved, out _) ? saved : Guid.NewGuid().ToString();
        if (id != saved)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(idFile)!);
                File.WriteAllText(idFile, id);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        lock (gate) clientId = id;
        return id;
    }

    public void Dispose()
    {
        http.Dispose();
        sending.Dispose();
    }
}
