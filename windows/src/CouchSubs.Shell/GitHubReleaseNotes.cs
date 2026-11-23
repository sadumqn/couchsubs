// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using HtmlAgilityPack;

namespace CouchSubs.Shell;

public sealed record ReleaseNoteRun(string Text, Uri? Link = null, bool Bold = false);

/// <summary>GitHub'ın teklifteki etikete ait kendi biçimlendirmesi; uygulamaya yalnız metin ve web bağlantısı geçer.</summary>
public sealed class GitHubReleaseNotes(HttpClient http)
{
    private string? version;
    private Task<IReadOnlyList<ReleaseNoteRun>>? request;
    private readonly object gate = new();

    public Task<IReadOnlyList<ReleaseNoteRun>> LoadAsync(string offeredVersion)
    {
        lock (gate)
        {
            if (version == offeredVersion && request is not null &&
                (!request.IsCompleted || (request.IsCompletedSuccessfully && request.Result.Count > 0))) return request;
            version = offeredVersion;
            return request = FetchAsync(offeredVersion);
        }
    }

    private async Task<IReadOnlyList<ReleaseNoteRun>> FetchAsync(string offeredVersion)
    {
        if (offeredVersion.Length == 0 || !offeredVersion.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or '+')) return [];
        var tag = "v" + offeredVersion;
        using var message = new HttpRequestMessage(HttpMethod.Get,
            "https://api.github.com/repos/yorulmazsinan/couchsubs/releases/tags/" + Uri.EscapeDataString(tag));
        message.Headers.UserAgent.ParseAdd("CouchSubs");
        message.Headers.Accept.ParseAdd("application/vnd.github.full+json");
        try
        {
            using var response = await http.SendAsync(message).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync().ConfigureAwait(false));
            var root = json.RootElement;
            if (root.GetProperty("tag_name").GetString() != tag) return [];
            if (root.TryGetProperty("body_html", out var html) && html.GetString() is { Length: > 0 } rendered)
            {
                try
                {
                    var document = new HtmlDocument { OptionMaxNestedChildNodes = 128 };
                    document.LoadHtml(rendered);
                    var runs = new List<ReleaseNoteRun>();
                    foreach (var node in CurrentSection(document.DocumentNode)) Append(node, runs);
                    if (runs.Any(run => !string.IsNullOrWhiteSpace(run.Text))) return runs;
                }
                // Html Agility Pack iç içelik sınırı aşılınca doğrudan Exception atar.
                // Böyle bir not da aynı etiketteki kaynak metniyle okunabilir.
                catch (Exception error) when (error.GetType() == typeof(Exception)) { }
            }
            return root.TryGetProperty("body", out var body) && body.GetString() is { Length: > 0 } raw
                ? [new ReleaseNoteRun(raw)] : [];
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or IOException
            or JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return [];
        }
    }

    /// <summary>
    /// Sürüm notları geçmiş sürümlerin özetini de taşır ("beta.65'te gelenler" …). Kartta yalnız teklif edilen sürümün
    /// "Bu sürümde yeni" bölümü gösterilir: o başlıklı paragraftan bir sonraki eski sürüm paragrafına kadar.
    /// Başlık yoksa (eski ya da elle yazılmış not) bütün gövde gösterilir.
    /// </summary>
    internal static IEnumerable<HtmlNode> CurrentSection(HtmlNode document)
    {
        var start = document.Descendants().FirstOrDefault(node => node.Name is "p" or "h1" or "h2" or "h3" or "h4" &&
            LeadText(node).StartsWith("Bu sürümde yeni", StringComparison.Ordinal));
        if (start is null) return [document];
        var section = new List<HtmlNode> { start };
        for (var node = start.NextSibling; node is not null; node = node.NextSibling)
        {
            if (node.NodeType == HtmlNodeType.Element && OlderRelease.IsMatch(LeadText(node))) break;
            section.Add(node);
        }
        return section;
    }

    private static readonly Regex OlderRelease = new(@"^(beta\.\d+\S*\s+gelenler\b|Daha önce\b|Önceki sürüm)", RegexOptions.CultureInvariant);

    private static string LeadText(HtmlNode node) => WebUtility.HtmlDecode(node.InnerText).TrimStart();

    private static void Append(HtmlNode node, List<ReleaseNoteRun> runs, Uri? link = null, bool bold = false)
    {
        if (node is HtmlTextNode text)
        {
            // GitHub bloklar arasına da satır sonu koyar; boşluğu bloklardan bir kez ver.
            if (!string.IsNullOrWhiteSpace(text.Text) || !text.Text.Contains('\n'))
                runs.Add(new(WebUtility.HtmlDecode(text.Text), link, bold));
            return;
        }
        if (node.NodeType == HtmlNodeType.Comment || node.Name is "script" or "style" or "svg" or "iframe" or "object") return;
        if (node.Name == "a")
        {
            var url = WebUtility.HtmlDecode(node.GetAttributeValue("href", ""));
            link = Uri.TryCreate(url, UriKind.Absolute, out var target) && target.Scheme is "https" or "http" ? target : null;
        }
        var heading = node.Name is "h1" or "h2" or "h3" or "h4" or "h5" or "h6";
        if (node.Name == "li") runs.Add(new("• "));
        if (node.Name == "img" && node.GetAttributeValue("alt", "") is { Length: > 0 } alt)
            runs.Add(new(WebUtility.HtmlDecode(alt), link));
        foreach (var child in node.ChildNodes) Append(child, runs, link, bold || heading || node.Name is "b" or "strong");
        if (heading || node.Name is "p" or "li" or "br" or "pre" or "tr") runs.Add(new("\n"));
    }
}
