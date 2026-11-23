// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell;

/// <summary>
/// Deneme modunun "konsolu" (Mac DemoStream ile aynı): uygulamadaki örnek kareleri (<see cref="DemoFrameSource"/>) akış
/// gibi verir; ağ kullanmaz. <c>render</c> kareyi çizer (satırın sırası ya da null, arka planın tonu).
/// </summary>
public sealed class DemoStream : IStreamSession
{
    private readonly DemoFrameSource source;

    public DemoStream(Func<int?, int, Frame?> render)
    {
        source = new DemoFrameSource(render);
        source.FrameReady += frame => FrameReceived?.Invoke(frame);
    }

    public event Action<Frame>? FrameReceived;
    public event Action<SessionState>? StateChanged;
    public event Action<RegisteredConsole>? ConsoleMoved { add { } remove { } }

    public void Start()
    {
        source.Start();
        StateChanged?.Invoke(SessionState.Streaming);
    }

    public void Stop() => source.Stop();
    public void ReconnectNow() { }
    public void Dispose() => source.Stop();
}
