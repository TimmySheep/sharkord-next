using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading.Channels;

namespace Sharkord.Core;

/// <summary>
/// A tRPC v11 WebSocket client, mirroring the wire format used by `@trpc/client`'s wsLink:
/// JSON text frames, one envelope per request, `PING`/`PONG` keepalive, and the
/// `connectionParams` frame as the first thing sent after the socket opens. The framed
/// protocol is not a versioned public spec, so this is the single place that knows it.
/// </summary>
public sealed class TrpcWebSocketClient : IAsyncDisposable
{
    private readonly Uri _url;
    private readonly string _token;
    private readonly TimeSpan _keepAliveInterval;
    private readonly TimeSpan _pongTimeout;

    private readonly ConcurrentDictionary<int, TaskCompletionSource<JsonNode?>> _pending = new();
    private readonly ConcurrentDictionary<int, Channel<JsonNode>> _subscriptions = new();
    private readonly SemaphoreSlim _sendLock = new(1, 1);

    private ClientWebSocket? _socket;
    private CancellationTokenSource? _cts;
    private Task? _receiveLoop;
    private Task? _keepAliveLoop;
    private int _nextId;
    private DateTime _lastInbound = DateTime.UtcNow;
    private volatile bool _closed;

    /// <summary>Raised when the socket drops or the server asks for a reconnect.</summary>
    public event Action<Exception?>? Disconnected;

    public TrpcWebSocketClient(
        Uri url,
        string token,
        TimeSpan? keepAliveInterval = null,
        TimeSpan? pongTimeout = null
    )
    {
        _url = url;
        _token = token;
        _keepAliveInterval = keepAliveInterval ?? TimeSpan.FromSeconds(30);
        _pongTimeout = pongTimeout ?? TimeSpan.FromSeconds(5);
    }

    public bool IsOpen => _socket is not null && !_closed;

    public async Task ConnectAsync(CancellationToken cancellationToken = default)
    {
        if (_socket is not null)
        {
            return;
        }

        _closed = false;

        var socket = new ClientWebSocket();
        await socket.ConnectAsync(_url, cancellationToken).ConfigureAwait(false);

        _socket = socket;
        _cts = new CancellationTokenSource();

        await SendAsync(TrpcConnectionParams.ToJson(_token), cancellationToken).ConfigureAwait(false);

        _lastInbound = DateTime.UtcNow;
        _receiveLoop = Task.Run(() => ReceiveLoopAsync(_cts.Token), CancellationToken.None);
        _keepAliveLoop = Task.Run(() => KeepAliveLoopAsync(_cts.Token), CancellationToken.None);
    }

    public Task<JsonNode?> QueryAsync(
        string path,
        JsonNode? input = null,
        CancellationToken cancellationToken = default
    ) => RequestAsync(TrpcMethod.Query, path, input, cancellationToken);

    public Task<JsonNode?> MutationAsync(
        string path,
        JsonNode? input = null,
        CancellationToken cancellationToken = default
    ) => RequestAsync(TrpcMethod.Mutation, path, input, cancellationToken);

    public IAsyncEnumerable<JsonNode> SubscribeAsync(
        string path,
        JsonNode? input = null,
        CancellationToken cancellationToken = default
    ) => SubscribeCoreAsync(path, input, cancellationToken);

    private async IAsyncEnumerable<JsonNode> SubscribeCoreAsync(
        string path,
        JsonNode? input,
        [EnumeratorCancellation] CancellationToken cancellationToken
    )
    {
        await ConnectAsync(cancellationToken).ConfigureAwait(false);

        var id = Interlocked.Increment(ref _nextId);
        var channel = Channel.CreateUnbounded<JsonNode>();
        _subscriptions[id] = channel;

        await SendAsync(new TrpcRequest(id, TrpcMethod.Subscription, path, input).ToJson(), cancellationToken)
            .ConfigureAwait(false);

        try
        {
            await foreach (var item in channel.Reader.ReadAllAsync(cancellationToken).ConfigureAwait(false))
            {
                yield return item;
            }
        }
        finally
        {
            _subscriptions.TryRemove(id, out _);
            await TrySendAsync(new JsonObject { ["id"] = id, ["method"] = "subscription.stop" }).ConfigureAwait(false);
        }
    }

    private async Task<JsonNode?> RequestAsync(
        TrpcMethod method,
        string path,
        JsonNode? input,
        CancellationToken cancellationToken
    )
    {
        try
        {
            await ConnectAsync(cancellationToken).ConfigureAwait(false);

            var id = Interlocked.Increment(ref _nextId);
            var completion = new TaskCompletionSource<JsonNode?>(TaskCreationOptions.RunContinuationsAsynchronously);
            _pending[id] = completion;

            try
            {
                await SendAsync(new TrpcRequest(id, method, path, input).ToJson(), cancellationToken).ConfigureAwait(false);
            }
            catch
            {
                _pending.TryRemove(id, out _);
                throw;
            }

            return await completion.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError(
                $"trpc.{method.ToString().ToLowerInvariant()}.{path}",
                exception
            );
            throw;
        }
    }

    private async Task ReceiveLoopAsync(CancellationToken cancellationToken)
    {
        var buffer = new byte[16 * 1024];
        var messageBuffer = new MemoryStream();

        try
        {
            while (!cancellationToken.IsCancellationRequested && _socket is { } socket)
            {
                var result = await socket
                    .ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken)
                    .ConfigureAwait(false);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    break;
                }

                messageBuffer.Write(buffer, 0, result.Count);

                if (!result.EndOfMessage)
                {
                    continue;
                }

                var text = Encoding.UTF8.GetString(messageBuffer.ToArray());
                messageBuffer.SetLength(0);

                await HandleFrameAsync(text).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
            return;
        }
        catch (Exception exception)
        {
            HandleDisconnect(exception);
            return;
        }

        HandleDisconnect(null);
    }

    private async Task HandleFrameAsync(string text)
    {
        if (text == "PING")
        {
            await TrySendRawAsync("PONG").ConfigureAwait(false);
            return;
        }

        if (text == "PONG")
        {
            return;
        }

        _lastInbound = DateTime.UtcNow;

        JsonNode? value;
        try
        {
            value = JsonNode.Parse(text);
        }
        catch
        {
            return;
        }

        if (value is JsonArray array)
        {
            foreach (var item in array)
            {
                Dispatch(TrpcResponseParser.Parse(item));
            }

            return;
        }

        Dispatch(TrpcResponseParser.Parse(value));
    }

    private void Dispatch(TrpcIncoming incoming)
    {
        switch (incoming.Kind)
        {
            case TrpcIncomingKind.Result:
                if (incoming.Id is not { } resultId)
                {
                    return;
                }

                if (incoming.Type == "data" || incoming.Type is null)
                {
                    if (_pending.TryRemove(resultId, out var pending))
                    {
                        pending.TrySetResult(incoming.Data);
                        return;
                    }

                    if (_subscriptions.TryGetValue(resultId, out var channel))
                    {
                        channel.Writer.TryWrite(incoming.Data ?? JsonValue.Create((object?)null)!);
                    }

                    return;
                }

                if (incoming.Type == "stopped" && _subscriptions.TryRemove(resultId, out var subscription))
                {
                    subscription.Writer.TryComplete();
                }

                return;
            case TrpcIncomingKind.Failure:
                if (incoming.Id is not { } failureId || incoming.Error is null)
                {
                    return;
                }

                if (_pending.TryRemove(failureId, out var failed))
                {
                    failed.TrySetException(incoming.Error);
                }
                else if (_subscriptions.TryRemove(failureId, out var failedSubscription))
                {
                    failedSubscription.Writer.TryComplete(incoming.Error);
                }

                return;
            case TrpcIncomingKind.ServerRequest:
                if (incoming.Method == "reconnect")
                {
                    HandleDisconnect(new TrpcClientError("RECONNECT", "Server requested reconnect"));
                }

                return;
            default:
                return;
        }
    }

    private async Task KeepAliveLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                await Task.Delay(_keepAliveInterval, cancellationToken).ConfigureAwait(false);

                var idle = DateTime.UtcNow - _lastInbound;

                if (idle > _keepAliveInterval + _pongTimeout)
                {
                    HandleDisconnect(new TrpcClientError("TIMEOUT", "Keepalive timed out"));
                    return;
                }

                await TrySendRawAsync("PING").ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
            // normal shutdown
        }
    }

    private async Task SendAsync(JsonNode node, CancellationToken cancellationToken)
        => await SendRawAsync(node.ToJsonString(), cancellationToken).ConfigureAwait(false);

    private async Task TrySendAsync(JsonNode node)
    {
        try
        {
            await SendRawAsync(node.ToJsonString(), CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
            // the socket is already gone; the disconnect path has done the cleanup
        }
    }

    private async Task TrySendRawAsync(string text)
    {
        try
        {
            await SendRawAsync(text, CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
            // ignore, see TrySendAsync
        }
    }

    private async Task SendRawAsync(string text, CancellationToken cancellationToken)
    {
        var socket = _socket ?? throw new TrpcClientError("DISCONNECTED", "Not connected");
        var bytes = Encoding.UTF8.GetBytes(text);

        await _sendLock.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            await socket
                .SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, cancellationToken)
                .ConfigureAwait(false);
        }
        finally
        {
            _sendLock.Release();
        }
    }

    private void HandleDisconnect(Exception? error)
    {
        var wasConnected = _socket is not null;
        _closed = true;

        _socket?.Dispose();
        _socket = null;
        _cts?.Cancel();

        var effective = error ?? new TrpcClientError("DISCONNECTED", "Connection closed");

        foreach (var (_, pending) in _pending)
        {
            pending.TrySetException(effective);
        }

        _pending.Clear();

        foreach (var (_, channel) in _subscriptions)
        {
            channel.Writer.TryComplete(effective);
        }

        _subscriptions.Clear();

        if (wasConnected)
        {
            Disconnected?.Invoke(error);
        }
    }

    public async ValueTask DisposeAsync()
    {
        _closed = true;
        _cts?.Cancel();

        if (_socket is { State: WebSocketState.Open } socket)
        {
            try
            {
                await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None)
                    .ConfigureAwait(false);
            }
            catch
            {
                // closing a dead socket is not an error worth surfacing
            }
        }

        _socket?.Dispose();
        _socket = null;

        foreach (var (_, pending) in _pending)
        {
            pending.TrySetException(new TrpcClientError("DISCONNECTED", "Connection closed"));
        }

        _pending.Clear();

        foreach (var (_, channel) in _subscriptions)
        {
            channel.Writer.TryComplete();
        }

        _subscriptions.Clear();

        _cts?.Dispose();
        _sendLock.Dispose();
    }
}
