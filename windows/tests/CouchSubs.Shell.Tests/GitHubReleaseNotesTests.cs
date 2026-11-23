// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using System.Text.Json;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

public class GitHubReleaseNotesTests
{
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> respond) : HttpMessageHandler
    {
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            Interlocked.Increment(ref Calls);
            return respond(request);
        }
    }

    private static HttpResponseMessage Reply(string tag, string html, string body = "") => new(HttpStatusCode.OK)
    {
        Content = new StringContent(JsonSerializer.Serialize(new { tag_name = tag, body_html = html, body }), Encoding.UTF8, "application/json"),
    };

    [Fact]
    public async Task FetchesOnlyTheOfferedTagAndKeepsContributorsAndSafeLinks()
    {
        var handler = new Handler(request =>
        {
            Assert.Equal("https://api.github.com/repos/yorulmazsinan/couchsubs/releases/tags/v0.1.0-beta.58", request.RequestUri!.AbsoluteUri);
            Assert.Contains("application/vnd.github.full+json", request.Headers.Accept.ToString());
            return Task.FromResult(Reply("v0.1.0-beta.58", """
                <ul><li><strong>Düzeltme:</strong> açık &amp; koyu temalar <a href="https://github.com/yorulmazsinan/couchsubs/pull/567">#567</a></li></ul>
                <h2>New Contributors</h2><p><a href="https://github.com/alice">@alice</a> ve Bob</p>
                <img src="https://example.org/no-network" alt="Örnek"><script>do-not-render()</script>
                <a href="file:///C:/example">dosya</a><a href="javascript:alert(1)">kod</a>
                """));
        });
        using var http = new HttpClient(handler);
        var reader = new GitHubReleaseNotes(http);
        Assert.Equal(0, handler.Calls);
        var notes = await reader.LoadAsync("0.1.0-beta.58");
        var text = string.Concat(notes.Select(n => n.Text));
        Assert.Contains("açık & koyu temalar #567", text);
        Assert.Contains("New Contributors\n@alice ve Bob", text);
        Assert.DoesNotContain("do-not-render", text);
        Assert.Equal(["https://github.com/yorulmazsinan/couchsubs/pull/567", "https://github.com/alice"],
            notes.Where(n => n.Link is not null).Select(n => n.Link!.AbsoluteUri));
        Assert.Same(notes, await reader.LoadAsync("0.1.0-beta.58"));
        Assert.Equal(1, handler.Calls);
    }

    [Fact]
    public async Task SharesAnInFlightRequestAndIgnoresOldCompletionForNewVersion()
    {
        var slow = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new Handler(request => request.RequestUri!.AbsolutePath.EndsWith("/v1") ? slow.Task : Task.FromResult(Reply("v2", "<p>Yeni</p>")));
        using var http = new HttpClient(handler);
        var reader = new GitHubReleaseNotes(http);
        var old = reader.LoadAsync("1");
        Assert.Same(old, reader.LoadAsync("1"));
        var newer = await reader.LoadAsync("2");
        slow.SetResult(Reply("v1", "<p>Eski</p>"));
        await old;
        Assert.Same(newer, await reader.LoadAsync("2"));
        Assert.Equal(2, handler.Calls);
    }

    [Fact]
    public async Task FailedOrMismatchedResponseCanBeRetriedWhenOpenedAgain()
    {
        var attempt = 0;
        var handler = new Handler(_ => Task.FromResult(++attempt switch
        {
            1 => new HttpResponseMessage(HttpStatusCode.ServiceUnavailable),
            2 => Reply("v999", "<p>Farklı sürüm</p>"),
            _ => Reply("v1", "", "Son satır: katkı @alice"),
        }));
        using var http = new HttpClient(handler);
        var reader = new GitHubReleaseNotes(http);
        Assert.Empty(await reader.LoadAsync("../latest"));
        Assert.Empty(await reader.LoadAsync("1"));
        Assert.Empty(await reader.LoadAsync("1"));
        Assert.Equal("Son satır: katkı @alice", Assert.Single(await reader.LoadAsync("1")).Text);
        Assert.Equal(3, handler.Calls);
    }

    [Fact]
    public async Task ShowsOnlyThisReleasesSectionNotTheOlderReleaseSummaries()
    {
        using var http = new HttpClient(new Handler(_ => Task.FromResult(Reply("v0.1.0-beta.82", """
            <p>CouchSubs'ın yeni deneme sürümü.</p>
            <p><strong>İndir:</strong> <a href="https://example.org/dmg">Mac (DMG)</a></p>
            <p><strong>Bu sürümde yeni</strong> (yalnız hata düzeltmeleri)</p>
            <ul>
            <li><strong>LG'de HDR yazısı</strong> düzeltildi.</li>
            </ul>
            <p><strong>beta.81'de gelenler:</strong> çevirinin durması.</p>
            <p><strong>Daha önce (beta.71):</strong> LG düzeltmesi.</p>
            <p><strong>beta.65'te gelenler:</strong> Android TV katmanı.</p>
            """))));
        var text = string.Concat((await new GitHubReleaseNotes(http).LoadAsync("0.1.0-beta.82")).Select(n => n.Text));
        Assert.StartsWith("Bu sürümde yeni (yalnız hata düzeltmeleri)\n", text);
        Assert.Contains("• LG'de HDR yazısı düzeltildi.", text);
        Assert.DoesNotContain("gelenler", text);
        Assert.DoesNotContain("Daha önce", text);
        Assert.DoesNotContain("İndir", text);
    }

    [Fact]
    public async Task OverlyNestedHtmlFallsBackToTheFullSourceAsInertText()
    {
        var nested = string.Concat(Enumerable.Repeat("<div>", 200)) + "note" + string.Concat(Enumerable.Repeat("</div>", 200));
        const string source = "Ayrıntılar ve katkı: @alice";
        using var http = new HttpClient(new Handler(_ => Task.FromResult(Reply("v2", nested, source))));
        var note = Assert.Single(await new GitHubReleaseNotes(http).LoadAsync("2"));
        Assert.Equal(source, note.Text);
        Assert.Null(note.Link);
    }
}
