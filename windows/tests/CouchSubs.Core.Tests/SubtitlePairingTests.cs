// SPDX-License-Identifier: AGPL-3.0-only
using System.Text.Json;
using CouchSubs.Core;
namespace CouchSubs.Core.Tests;
public class SubtitlePairingTests
{
    [Fact] public void SharedLifecycleVectors()
    {
        using var fixture = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("subtitle-pairing.json")));
        foreach (var scenario in fixture.RootElement.EnumerateArray())
        {
            long time = 1000;
            var pairing = new SubtitlePairing(() => time);
            var id = "";
            var previous = "";
            var name = scenario.GetProperty("name").GetString();
            foreach (var step in scenario.GetProperty("steps").EnumerateArray())
            {
                var who = step.TryGetProperty("wrong", out var wrong) && wrong.GetBoolean() ? "not-the-request-secret"
                    : step.TryGetProperty("previous", out var earlier) && earlier.GetBoolean() ? previous : id;
                var op = step.GetProperty("op").GetString();
                switch (op)
                {
                    case "session": pairing.SetSession(step.GetProperty("value").GetBoolean()); break;
                    case "open": pairing.Open(); break;
                    case "reset": pairing.Reset(); break;
                    case "advance": time += step.GetProperty("ms").GetInt64(); break;
                    case "begin":
                        var ticket = pairing.Begin();
                        Assert.True(step.GetProperty("ok").GetBoolean() == ticket is not null, name);
                        if (ticket is not null) { Assert.Matches("^[A-Za-z0-9_-]{22}$", ticket.Id); Assert.Matches("^[0-9]{6}$", ticket.Code); previous = id; id = ticket.Id; }
                        break;
                    case "resolve": Assert.True(step.GetProperty("ok").GetBoolean() == pairing.Resolve(who, step.GetProperty("accept").GetBoolean()), name); break;
                    case "poll": Assert.Equal(step.GetProperty("state").GetString(), pairing.Poll(who)); break;
                    case "pending": Assert.Equal(step.GetProperty("state").GetString() == "current" ? id : null, pairing.Pending?.Id); break;
                    case "isOpen": Assert.True(step.GetProperty("value").GetBoolean() == pairing.IsOpen, name); break;
                    default: Assert.Fail("Bilinmeyen adım: " + op); break;
                }
            }
        }
    }
    /// <summary>
    /// Sunucu yeniden açılınca (Stop(keepPairing: true)) ya da port değişip yeni örnekle kurulunca bekleyen istek, "TV
    /// eşleştir" süresi ve anahtar korunur; sıradan Stop eşleştirmeyi kapatır (Mac/iPhone ile aynı).
    /// </summary>
    [Fact] public async Task RestartAndReplacementKeepPendingRequestAndKey()
    {
        using var first = new SubtitleServer(0, allowLegacy: false);
        var port = await first.StartAsync();
        first.Pairing.Open();
        using var http = new HttpClient();
        async Task<JsonDocument> Json(HttpMethod method, string url)
        {
            using var request = new HttpRequestMessage(method, url);
            using var response = await http.SendAsync(request);
            return JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        }
        using var ticket = await Json(HttpMethod.Post, $"http://127.0.0.1:{port}/pair");
        var id = ticket.RootElement.GetProperty("id").GetString()!;
        first.Stop(keepPairing: true);
        port = await first.StartAsync();
        Assert.Equal(id, first.Pairing.Pending?.Id);
        first.Stop(keepPairing: true);
        using var second = new SubtitleServer(0, key: first.AccessKey, allowLegacy: false, pairing: first.Pairing);
        port = await second.StartAsync();
        Assert.True(second.Pairing.Resolve(id, true));
        using var approved = await Json(HttpMethod.Get, $"http://127.0.0.1:{port}/pair?id={id}");
        Assert.Equal(first.AccessKey, approved.RootElement.GetProperty("key").GetString());
        second.Stop();
        Assert.False(second.Pairing.IsOpen);
        Assert.Null(second.Pairing.Pending);
    }

    [Fact] public async Task WireRequiresLocalApprovalAndInvalidatesOnRotation()
    {
        using var server = new SubtitleServer(0, allowLegacy: false);
        var port = await server.StartAsync();
        using var http = new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{port}") };
        using var closed = await http.PostAsync("/pair", null);
        Assert.Equal(409, (int)closed.StatusCode);
        server.Pairing.Open();
        using var foreign = new HttpRequestMessage(HttpMethod.Post, "/pair");
        foreign.Headers.Add("Origin", "https://foreign.example");
        using var rejected = await http.SendAsync(foreign);
        Assert.Equal(403, (int)rejected.StatusCode);
        using var created = await http.PostAsync("/pair", null);
        using var ticket = JsonDocument.Parse(await created.Content.ReadAsStringAsync());
        var id = ticket.RootElement.GetProperty("id").GetString()!;
        var pending = await http.GetStringAsync("/pair?id=" + id);
        Assert.DoesNotContain(server.AccessKey, pending);
        Assert.DoesNotContain(server.AccessKey, await http.GetStringAsync("/hello"));
        Assert.True(server.Pairing.Resolve(id, true));
        Assert.Contains(server.AccessKey, await http.GetStringAsync("/pair?id=" + id));
        Assert.DoesNotContain(server.AccessKey, await http.GetStringAsync("/pair?id=wrong"));
        server.RotateKey(SubtitleAccess.CreateKey());
        Assert.DoesNotContain(server.AccessKey, await http.GetStringAsync("/pair?id=" + id));
        Assert.Contains("expired", await http.GetStringAsync("/pair?id=" + id));
    }
}
