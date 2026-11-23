// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json.Nodes;
using CouchSubs.Core.LgTv;

namespace CouchSubs.Core.Tests;

/// SSAP konuşan sahte bir TV: register'a client-key ile, isteklere sırayla verilen yanıtlarla döner.
public sealed class FakeLgTv : IDisposable
{
    private readonly HttpListener listener = new();
    private readonly CancellationTokenSource stop = new();
    public List<string> ReceivedUris { get; } = [];
    public List<JsonNode?> ReceivedPayloads { get; } = [];
    public Queue<string> ForegroundApps { get; } = new();
    /// true ise register'a yalnız "soru gösterildi" yanıtı verir, onay hiç gelmez.
    public bool NeverApprove { get; set; }
    public int Port { get; }

    public FakeLgTv()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        Port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        listener.Prefixes.Add($"http://127.0.0.1:{Port}/");
        listener.Start();
        _ = AcceptLoop();
    }

    private async Task AcceptLoop()
    {
        while (!stop.IsCancellationRequested)
        {
            HttpListenerContext context;
            try { context = await listener.GetContextAsync(); } catch { return; }
            if (!context.Request.IsWebSocketRequest) { context.Response.StatusCode = 400; context.Response.Close(); continue; }
            var socket = (await context.AcceptWebSocketAsync(null)).WebSocket;
            _ = Serve(socket);
        }
    }

    private async Task Serve(WebSocket socket)
    {
        var buffer = new byte[8192];
        try
        {
            while (socket.State == WebSocketState.Open)
            {
                var result = await socket.ReceiveAsync(buffer, stop.Token);
                if (result.MessageType == WebSocketMessageType.Close) return;
                // Gerçek LG TV ikili çerçeveyi reddeder; yalnız metin çerçevesi kabul edilir.
                if (result.MessageType != WebSocketMessageType.Text)
                {
                    await Send(socket, new JsonObject { ["type"] = "error", ["id"] = "", ["error"] = "400 binary messages not supported" });
                    continue;
                }
                var message = JsonNode.Parse(Encoding.UTF8.GetString(buffer, 0, result.Count))!;
                await Handle(socket, message);
            }
        }
        catch { }
    }

    private async Task Handle(WebSocket socket, JsonNode message)
    {
        var id = (string?)message["id"] ?? "";
        if ((string?)message["type"] == "register")
        {
            await Send(socket, new JsonObject { ["type"] = "response", ["id"] = id, ["payload"] = new JsonObject { ["pairingType"] = "PROMPT", ["returnValue"] = true } });
            if (!NeverApprove)
                await Send(socket, new JsonObject { ["type"] = "registered", ["id"] = id, ["payload"] = new JsonObject { ["client-key"] = "fake-key" } });
            return;
        }
        var uri = (string?)message["uri"] ?? "";
        lock (ReceivedUris)
        {
            ReceivedUris.Add(uri);
            ReceivedPayloads.Add(message["payload"]?.DeepClone());
        }
        var payload = new JsonObject { ["returnValue"] = true };
        if (uri.EndsWith("getForegroundAppInfo"))
            payload["appId"] = ForegroundApps.Count == 0 ? "" : ForegroundApps.Dequeue();
        await Send(socket, new JsonObject { ["type"] = "response", ["id"] = id, ["payload"] = payload });
    }

    private static Task Send(WebSocket socket, JsonObject message) =>
        socket.SendAsync(Encoding.UTF8.GetBytes(message.ToJsonString()), WebSocketMessageType.Text, true, CancellationToken.None);

    public void Dispose()
    {
        stop.Cancel();
        listener.Close();
    }
}

public class SsapClientTests
{
    private static readonly Dictionary<string, string> Server = new() { ["server"] = "http://1.2.3.4:8787" };

    [Fact]
    public async Task ConnectReturnsClientKeyAndLaunchSendsUri()
    {
        using var tv = new FakeLgTv();
        using var client = new SsapClient([new Uri($"ws://127.0.0.1:{tv.Port}")], null);
        Assert.Equal("fake-key", await client.ConnectAsync());

        await client.LaunchAsync("com.couchsubs.tv", Server);
        Assert.Equal("ssap://system.launcher/launch", tv.ReceivedUris.Last());
        Assert.Equal("com.couchsubs.tv", (string?)tv.ReceivedPayloads.Last()!["id"]);
        Assert.Equal("http://1.2.3.4:8787", (string?)tv.ReceivedPayloads.Last()!["params"]!["server"]);
    }

    [Fact]
    public async Task ForegroundAppId()
    {
        using var tv = new FakeLgTv();
        tv.ForegroundApps.Enqueue("com.webos.app.hdmi2");
        using var client = new SsapClient([new Uri($"ws://127.0.0.1:{tv.Port}")], "fake-key");
        await client.ConnectAsync();
        Assert.Equal("com.webos.app.hdmi2", await client.ForegroundAppIdAsync());
    }

    [Fact]
    public async Task UnansweredPairingPromptTimesOut()
    {
        using var tv = new FakeLgTv { NeverApprove = true };
        using var client = new SsapClient([new Uri($"ws://127.0.0.1:{tv.Port}")], null, TimeSpan.FromSeconds(1));
        var begin = DateTime.UtcNow;
        await Assert.ThrowsAnyAsync<Exception>(() => client.ConnectAsync());
        Assert.True(DateTime.UtcNow - begin < TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task FallsBackToNextEndpoint()
    {
        using var tv = new FakeLgTv();
        // İlk adreste kimse dinlemiyor; ikinciye düşmeli.
        using var client = new SsapClient([new Uri("ws://127.0.0.1:1"), new Uri($"ws://127.0.0.1:{tv.Port}")], null);
        Assert.Equal("fake-key", await client.ConnectAsync());
    }
}

public class TvKeeperTests
{
    private sealed class FakeControl(params string[] foreground) : ITvControl
    {
        private readonly Queue<string> foreground = new(foreground);
        public List<(string AppId, IReadOnlyDictionary<string, string> Params)> Launches { get; } = [];
        public bool FailNext { get; set; }

        public Task<string> ForegroundAppIdAsync(CancellationToken cancellationToken = default)
        {
            if (FailNext) { FailNext = false; throw new IOException("bağlantı koptu"); }
            return Task.FromResult(foreground.Count == 0 ? "com.couchsubs.tv" : foreground.Dequeue());
        }

        public Task LaunchAsync(string appId, IReadOnlyDictionary<string, string> parameters, CancellationToken cancellationToken = default)
        {
            Launches.Add((appId, parameters));
            return Task.CompletedTask;
        }

        public int Disposals { get; private set; }
        public void Dispose() => Disposals++;
    }

    [Fact]
    public async Task SamsungIsLeftAloneWhileTheAppIsConnected()
    {
        var control = new FakeControl();
        var connected = false;
        var connects = 0;
        var keeper = new TvKeeper(() => { connects++; return Task.FromResult<ITvControl>(control); }, "com.couchsubs.tv",
            new Dictionary<string, string>(), () => connected, TimeSpan.FromMilliseconds(200));
        await keeper.TickAsync(); // uygulama bağlı değil → aç ve bağlantıyı kapat
        Assert.Single(control.Launches);
        Assert.Equal(1, control.Disposals);
        await keeper.TickAsync(); // hemen yeniden açmaya çalışmaz
        Assert.Equal(1, connects);
        connected = true;
        await Task.Delay(250);
        for (var i = 0; i < 5; i++) await keeper.TickAsync(); // uygulama bağlıyken TV'ye dokunulmaz
        Assert.Equal(1, connects);
        connected = false;
        await keeper.TickAsync(); // uygulama kapandı → bir kez daha aç
        Assert.Equal(2, control.Launches.Count);
    }

    [Fact]
    public async Task RelaunchesOnlyWhenHdmiInputIsInFront()
    {
        var control = new FakeControl("com.couchsubs.tv", "com.webos.app.hdmi2", "com.couchsubs.tv", "netflix");
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string> { ["server"] = "http://1.2.3.4:8787" });
        await keeper.TickAsync(); // bağlanır ve uygulamayı bir kez başlatır
        await keeper.TickAsync(); // önde HDMI girişi → geri getir
        await keeper.TickAsync(); // önde bizimki
        await keeper.TickAsync(); // kullanıcı Netflix'i açtı → dokunma
        Assert.Equal(2, control.Launches.Count);
        Assert.Equal("com.couchsubs.tv", control.Launches[^1].AppId);
        Assert.Equal("http://1.2.3.4:8787", control.Launches[^1].Params["server"]);
    }

    [Fact]
    public async Task StandsDownWhenTheUserKeepsReturningToTheInput()
    {
        // Kullanıcı PS5 kapalıyken TV'yi başka girişe alıyor; bekçi her seferinde CouchSubs'ı geri getiriyordu.
        var control = new FakeControl("com.couchsubs.tv", "com.webos.app.hdmi1", "com.webos.app.hdmi1", "com.webos.app.hdmi1",
            "com.webos.app.hdmi1", "com.webos.app.hdmi1", "com.couchsubs.tv", "com.webos.app.hdmi1");
        var time = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string>(), clock: () => time);
        await keeper.TickAsync(); // bağlanır ve başlatır
        await keeper.TickAsync(); // uygulama önde
        for (var i = 0; i < TvKeeper.StandDownAfter; i++)
        {
            time += TimeSpan.FromSeconds(10);
            await keeper.TickAsync(); // girişte → geri getir
        }
        Assert.Equal(1 + TvKeeper.StandDownAfter, control.Launches.Count);
        time += TimeSpan.FromSeconds(10);
        await keeper.TickAsync(); // yine girişte: kullanıcı ısrarlı → bekçi çekilir
        Assert.True(keeper.StoodDown);
        time += TimeSpan.FromMinutes(10);
        await keeper.TickAsync(); // sonra da zorlamaz
        Assert.Equal(1 + TvKeeper.StandDownAfter, control.Launches.Count);
        await keeper.TickAsync(); // kullanıcı CouchSubs'ı TV'de kendisi açtı → bekçi işine döner
        Assert.False(keeper.StoodDown);
        await keeper.TickAsync(); // TV yine girişe geçti (SimpLink) → geri getir
        Assert.Equal(2 + TvKeeper.StandDownAfter, control.Launches.Count);
    }

    [Fact]
    public async Task OccasionalInputSwitchesNeverStandDown()
    {
        // SimpLink/CEC arada bir TV'yi girişe geçirir: aralıklı geçişler sınıra takılmaz.
        var control = new FakeControl(Enumerable.Repeat("com.webos.app.hdmi2", 12).Prepend("com.couchsubs.tv").ToArray());
        var time = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string>(), clock: () => time);
        await keeper.TickAsync();
        await keeper.TickAsync();
        for (var i = 0; i < 12; i++)
        {
            time += TimeSpan.FromSeconds(60);
            await keeper.TickAsync();
        }
        Assert.False(keeper.StoodDown);
        Assert.Equal(13, control.Launches.Count);
    }

    [Fact]
    public async Task ReconnectsWhenTvWasOffOrConnectionDropped()
    {
        var control = new FakeControl();
        var attempts = 0;
        var keeper = new TvKeeper(() =>
        {
            attempts++;
            if (attempts == 1) throw new IOException("TV kapalı");
            return Task.FromResult<ITvControl>(control);
        }, "com.couchsubs.tv", new Dictionary<string, string>());
        await keeper.TickAsync();
        Assert.Empty(control.Launches);
        await keeper.TickAsync(); // TV açıldı → bağlan ve başlat
        Assert.Single(control.Launches);

        control.FailNext = true;  // bağlantı koptu
        await keeper.TickAsync();
        await keeper.TickAsync(); // yeniden bağlanır ve tekrar başlatır
        Assert.Equal(3, attempts);
        Assert.Equal(2, control.Launches.Count);
    }

    /// <summary>
    /// #1055 (LG OLED C4, beta.86): her yeni SSAP bağlantısı açık ve bağlı uygulamaya da açma komutu gönderiyordu; webOS
    /// uygulamayı yeniden başlatıp HDMI görüntüsünü yeniden kuruyor, ekran kararıyordu. 30 dk boyunca bağlantı 20 sn'de bir
    /// kopup bekçi her dakika yenilense de (alındı kesintisi) açık ve bağlı uygulamaya tek açma komutu gitmez.
    /// </summary>
    [Fact]
    public async Task OpenConnectedAppGetsNoLaunchFor30MinutesEvenWhenSsapKeepsReconnecting()
    {
        var control = new FakeControl(); // önde hep CouchSubs
        var time = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv",
            new Dictionary<string, string> { ["server"] = "http://1.2.3.4:8787" }, clock: () => time, tvConnected: () => true);
        for (var second = 0; second < 30 * 60; second++)
        {
            time += TimeSpan.FromSeconds(1);
            if (second % 20 == 0) control.FailNext = true; // SSAP koptu
            if (second % 60 == 30) keeper.Reconnect();      // alındı kesildi, bekçi yenilendi
            await keeper.TickAsync();
        }
        Assert.Empty(control.Launches);
    }

    /// <summary>Uygulama önde ama bağlı değil (yanıtsız): yeniden kurulan bağlantıda geri çekilerek açılır (30 sn, 1, 2, 5 dk),
    /// her kopuşta değil. İlk açılışta bağlı değilse eskisi gibi hemen açılır.</summary>
    [Fact]
    public async Task UnresponsiveAppIsReopenedWithBackoff()
    {
        var control = new FakeControl();
        var time = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string>(),
            clock: () => time, tvConnected: () => false);
        await keeper.TickAsync();
        Assert.Single(control.Launches); // ilk açılış
        for (var second = 0; second < 10 * 60; second++)
        {
            time += TimeSpan.FromSeconds(1);
            control.FailNext = true; // her saniye kopuyor: her tur yeni bağlantı
            await keeper.TickAsync();
            await keeper.TickAsync();
        }
        // 10 dk'da: ilk yeniden açma, +30 sn, +60 sn, +120 sn, sonra 5 dk'da bir.
        Assert.InRange(control.Launches.Count, 1 + 4, 1 + 6);
    }

    /// <summary>Çeviri başlarken uygulama zaten açık ve bağlıysa açma komutu gitmez; kapalıysa açılır.</summary>
    [Fact]
    public async Task FirstOpenSkipsAConnectedAppButOpensAClosedOne()
    {
        var open = new FakeControl();
        var keeperOpen = new TvKeeper(() => Task.FromResult<ITvControl>(open), "com.couchsubs.tv", new Dictionary<string, string>(),
            tvConnected: () => true);
        await keeperOpen.TickAsync();
        await keeperOpen.TickAsync();
        Assert.Empty(open.Launches);

        var closed = new FakeControl("com.webos.app.hdmi2");
        var keeperClosed = new TvKeeper(() => Task.FromResult<ITvControl>(closed), "com.couchsubs.tv", new Dictionary<string, string>(),
            tvConnected: () => false);
        await keeperClosed.TickAsync();
        Assert.Single(closed.Launches);
    }

    [Fact]
    public async Task PsButtonOnTheConsoleInputIsNeverCountedAsInsisting()
    {
        // X (Kas 2026): oyunda PS tuşu TV'yi PS5'in girişine (CEC) geçiriyor. Eskiden her basış "ısrar" sayılıyordu;
        // 90 sn'de dördüncü basışta bekçi çekiliyor, çeviri bir daha TV'ye gelmiyordu.
        var presses = 8;
        var foreground = new List<string> { "com.couchsubs.tv" };
        for (var i = 0; i < presses; i++) foreground.AddRange(["com.webos.app.hdmi2", "com.couchsubs.tv"]);
        var control = new FakeControl([.. foreground]);
        var time = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string>(),
            clock: () => time, consolePort: () => 2);
        await keeper.TickAsync(); // bağlanır ve başlatır
        await keeper.TickAsync(); // uygulama önde
        for (var i = 0; i < presses; i++)
        {
            time += TimeSpan.FromSeconds(5);
            await keeper.TickAsync(); // PS tuşu → konsol girişi → hemen geri getir
            time += TimeSpan.FromSeconds(3);
            await keeper.TickAsync(); // uygulama yine önde
        }
        Assert.False(keeper.StoodDown);
        Assert.Equal(1 + presses, control.Launches.Count);
    }

    [Fact]
    public async Task AnotherHdmiNumberIsStillRespected()
    {
        // Konsol HDMI 2'de; kullanıcı HDMI 1'e (başka cihaz) geçiyor: eskisi gibi üç geri getirmeden sonra bekçi çekilir.
        var control = new FakeControl(Enumerable.Repeat("com.webos.app.hdmi1", 5).Prepend("com.couchsubs.tv").ToArray());
        var time = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string>(),
            clock: () => time, consolePort: () => 2);
        await keeper.TickAsync();
        await keeper.TickAsync();
        for (var i = 0; i <= TvKeeper.StandDownAfter; i++)
        {
            time += TimeSpan.FromSeconds(10);
            await keeper.TickAsync();
        }
        Assert.True(keeper.StoodDown);
        Assert.Equal(1 + TvKeeper.StandDownAfter, control.Launches.Count);
    }

    [Fact]
    public async Task EndlessConsoleBounceStandsDown()
    {
        // TV her geri getirmede konsol girişine dönüyorsa (bitmeyen CEC döngüsü) bekçi bir dakikada sınırda çekilir.
        var control = new FakeControl(Enumerable.Repeat("com.webos.app.hdmi3", 30).Prepend("com.couchsubs.tv").ToArray());
        var time = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string>(),
            clock: () => time, consolePort: () => 3);
        await keeper.TickAsync();
        await keeper.TickAsync();
        for (var i = 0; i < 20; i++)
        {
            time += TimeSpan.FromSeconds(3);
            await keeper.TickAsync();
        }
        Assert.True(keeper.StoodDown);
        Assert.Equal(1 + TvKeeper.ConsoleLoopLimit, control.Launches.Count);
    }

    [Fact]
    public async Task WaitsForTheAppToComeForwardBeforeLookingAgain()
    {
        // Geri getirdikten hemen sonra önplan bir an eski girişi gösterir: ikinci kez açılmaz, sayılmaz.
        var control = new FakeControl("com.couchsubs.tv", "com.webos.app.hdmi1", "com.webos.app.hdmi1", "com.couchsubs.tv");
        var time = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var keeper = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string>(), clock: () => time);
        await keeper.TickAsync();
        await keeper.TickAsync();
        time += TimeSpan.FromSeconds(1);
        await keeper.TickAsync(); // girişte → geri getir
        time += TimeSpan.FromSeconds(1);
        await keeper.TickAsync(); // daha öne gelmedi: bekle
        Assert.Equal(2, control.Launches.Count);
    }

    [Fact]
    public void LgPollsEverySecondSamsungKeepsItsInterval()
    {
        var control = new FakeControl();
        var lg = new TvKeeper(() => Task.FromResult<ITvControl>(control), "com.couchsubs.tv", new Dictionary<string, string>());
        var samsung = new TvKeeper(() => Task.FromResult<ITvControl>(control), "x", new Dictionary<string, string>(), () => true);
        Assert.Equal(TimeSpan.FromSeconds(1), lg.PollInterval(TimeSpan.FromSeconds(5)));
        Assert.Equal(TimeSpan.FromSeconds(5), samsung.PollInterval(TimeSpan.FromSeconds(5)));
        Assert.True(TvKeeper.IsConsoleInput("com.webos.app.hdmi2", 2));
        Assert.False(TvKeeper.IsConsoleInput("com.webos.app.hdmi2", 1));
        Assert.False(TvKeeper.IsConsoleInput("com.webos.app.hdmi2", null));
        Assert.False(TvKeeper.IsConsoleInput("com.webos.app.livetv", 2));
    }
}
