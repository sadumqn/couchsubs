// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Yerel AI önbelleğinin motor adı Mac'teki LocalAIServer.engineID ile birebir aynı metni üretir (#421). Beklenen
/// değerler Mac kodunun aynı girdilerle verdiği çıktılardır.
/// </summary>
public class LocalAiEngineIdTests
{
    [Theory]
    // Standart http …/v1 adreslerinde eski ad korunur; var olan önbellek kaybolmaz.
    [InlineData("http://127.0.0.1:11434/v1", "qwen2.5:7b", "local:127.0.0.1:11434/qwen2.5:7b")]
    [InlineData("http://localhost:11434/v1", "qwen2.5:7b", "local:localhost:11434/qwen2.5:7b")]
    [InlineData("localhost:1234", "qwen2.5-7b-instruct", "local:localhost:1234/qwen2.5-7b-instruct")]
    [InlineData("http://localhost:11434/v1/chat/completions", "m", "local:localhost:11434/m")]
    [InlineData("http://localhost:80/v1", "m", "local:localhost:80/m")]
    [InlineData("http://[::1]:11434/v1", "m", "local:::1:11434/m")]
    // Kullanıcı adı, parola, sorgu ve fragment ada girmez.
    [InlineData("http://user:pass@localhost:11434/v1?x=1#frag", "qwen2.5:7b", "local:localhost:11434/qwen2.5:7b")]
    // Başka şema ya da yol: alanlar uzunluklarıyla ön ekli.
    [InlineData("https://localhost:11434/v1", "qwen2.5:7b", "local:endpoint-v2:5:https|9:localhost|5:11434|3:/v1|10:qwen2.5:7b")]
    [InlineData("https://ai.example.com/v1", "m", "local:endpoint-v2:5:https|14:ai.example.com|0:|3:/v1|1:m")]
    [InlineData("https://ai.example.com:443/v1", "m", "local:endpoint-v2:5:https|14:ai.example.com|3:443|3:/v1|1:m")]
    [InlineData("http://localhost:11434/api/v1", "qwen2.5:7b", "local:endpoint-v2:4:http|9:localhost|5:11434|7:/api/v1|10:qwen2.5:7b")]
    [InlineData("http://localhost:11434/a", "b/c", "local:endpoint-v2:4:http|9:localhost|5:11434|2:/a|3:b/c")]
    [InlineData("http://localhost:11434/a/b", "c", "local:endpoint-v2:4:http|9:localhost|5:11434|4:/a/b|1:c")]
    [InlineData("http://localhost:11434/V1", "m", "local:endpoint-v2:4:http|9:localhost|5:11434|3:/V1|1:m")]
    [InlineData("https://[::1]:8443/v1", "m", "local:endpoint-v2:5:https|3:::1|4:8443|3:/v1|1:m")]
    [InlineData("http://localhost:8080/my%20path", "m", "local:endpoint-v2:4:http|9:localhost|4:8080|10:/my%20path|1:m")]
    [InlineData("HTTPS://AI.Example.COM:8443/Proxy/v1", "Qwen", "local:endpoint-v2:5:https|14:ai.example.com|4:8443|9:/Proxy/v1|4:Qwen")]
    public void MatchesMacEngineId(string address, string model, string expected) =>
        Assert.Equal(expected, LocalAiServer.Create(address, model)!.EngineId);

    /// <summary>Eski anahtarda "/a" + "b/c" ile "/a/b" + "c" aynı adı veriyordu; artık ayrı.</summary>
    [Fact]
    public void PathAndModelSeparatorsNeverCollide()
    {
        var first = LocalAiServer.Create("http://localhost:11434/a", "b/c")!.EngineId;
        var second = LocalAiServer.Create("http://localhost:11434/a/b", "c")!.EngineId;
        Assert.NotEqual(first, second);
    }

    [Fact]
    public void SchemeAndPathSeparateCaches()
    {
        var plain = LocalAiServer.Create("http://localhost:11434/v1", "m")!.EngineId;
        Assert.NotEqual(plain, LocalAiServer.Create("https://localhost:11434/v1", "m")!.EngineId);
        Assert.NotEqual(plain, LocalAiServer.Create("http://localhost:11434/proxy/v1", "m")!.EngineId);
        Assert.Equal(plain, LocalAiServer.Create("http://me:secret@LOCALHOST:11434/v1/?a=b", "m")!.EngineId);
    }
}
