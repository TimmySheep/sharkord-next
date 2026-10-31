using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class WebSocketConformanceTests
{
    [Fact]
    public async Task AbortedSocketImmediatelyDisconnectsAndCompletesPendingRequest()
    {
        await WithConnectionAsync(async (client, server, token) =>
        {
            var disconnected = new TaskCompletionSource<Exception?>(TaskCreationOptions.RunContinuationsAsynchronously);
            client.Disconnected += error => disconnected.TrySetResult(error);
            var query = client.QueryAsync("pending", cancellationToken: token);
            await ReceiveAsync(server, token);
            var socket = (ClientWebSocket)typeof(TrpcWebSocketClient)
                .GetField("_socket", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(client)!;

            socket.Abort();

            var reason = await disconnected.Task.WaitAsync(TimeSpan.FromSeconds(2), token);
            Assert.NotNull(reason);
            var error = await Assert.ThrowsAnyAsync<Exception>(() => query);
            Assert.Same(reason, error);
            Assert.False(client.IsOpen);
        });
    }

    [Fact]
    public async Task ConnectionParamsPrecedeRequestsAndServerPingGetsPong()
    {
        await WithConnectionAsync(async (client, server, token) =>
        {
            await SendAsync(server, "PING", token);
            Assert.Equal("PONG", await ReceiveAsync(server, token));

            var query = client.QueryAsync("others.handshake", cancellationToken: token);
            var request = JsonNode.Parse(await ReceiveAsync(server, token))!;
            Assert.Equal("query", request["method"]!.GetValue<string>());
            Assert.Equal("others.handshake", request["params"]!["path"]!.GetValue<string>());
            var id = request["id"]!.GetValue<int>();
            await SendAsync(server, $"{{\"id\":{id},\"result\":{{\"type\":\"data\",\"data\":42}}}}", token);

            Assert.Equal(42, (await query)!.GetValue<int>());
        });
    }

    [Fact]
    public async Task PongKeepsAnOtherwiseIdleConnectionAlive()
    {
        await WithConnectionAsync(async (client, server, token) =>
        {
            for (var round = 0; round < 6; round++)
            {
                Assert.Equal("PING", await ReceiveAsync(server, token));
                await SendAsync(server, "PONG", token);
            }

            Assert.True(client.IsOpen);
        }, keepAliveInterval: TimeSpan.FromMilliseconds(200), pongTimeout: TimeSpan.FromMilliseconds(200));
    }

    [Fact]
    public async Task BatchedFragmentedResponsesPreserveIdsAndServerErrors()
    {
        await WithConnectionAsync(async (client, server, token) =>
        {
            var first = client.QueryAsync("first", cancellationToken: token);
            var firstId = JsonNode.Parse(await ReceiveAsync(server, token))!["id"]!.GetValue<int>();
            var second = client.MutationAsync("second", cancellationToken: token);
            var secondId = JsonNode.Parse(await ReceiveAsync(server, token))!["id"]!.GetValue<int>();
            var response = Encoding.UTF8.GetBytes("[" +
                $"{{\"id\":{secondId},\"error\":{{\"message\":\"No access\",\"code\":-32003,\"data\":{{\"code\":\"FORBIDDEN\"}}}}}}," +
                $"{{\"id\":{firstId},\"result\":{{\"data\":\"海🌊\"}}}}]");
            var split = response.Length - 4;
            await server.SendAsync(response.AsMemory(0, split), WebSocketMessageType.Text, false, token);
            await server.SendAsync(response.AsMemory(split), WebSocketMessageType.Text, true, token);

            Assert.Equal("海🌊", (await first)!.GetValue<string>());
            var error = await Assert.ThrowsAsync<TrpcClientError>(() => second);
            Assert.Equal("FORBIDDEN", error.Code);
            Assert.Equal("No access", error.Message);
        });
    }

    [Fact]
    public async Task ReconnectFrameClosesPendingRequestsWithItsExistingError()
    {
        await WithConnectionAsync(async (client, server, token) =>
        {
            var disconnected = new TaskCompletionSource<Exception?>(TaskCreationOptions.RunContinuationsAsynchronously);
            client.Disconnected += error => disconnected.TrySetResult(error);
            var query = client.QueryAsync("pending", cancellationToken: token);
            await ReceiveAsync(server, token);

            await SendAsync(server, "{\"method\":\"reconnect\"}", token);

            var error = await Assert.ThrowsAsync<TrpcClientError>(() => query);
            Assert.Equal("RECONNECT", error.Code);
            Assert.Same(error, await disconnected.Task.WaitAsync(token));
            Assert.False(client.IsOpen);
        });
    }

    internal static async Task WithConnectionAsync(
        Func<TrpcWebSocketClient, WebSocket, CancellationToken, Task> run,
        TimeSpan? keepAliveInterval = null,
        TimeSpan? pongTimeout = null)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var token = timeout.Token;
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        await using var client = new TrpcWebSocketClient(
            new Uri($"ws://127.0.0.1:{port}/?connectionParams=1"), "test-token", keepAliveInterval, pongTimeout);
        var connecting = client.ConnectAsync(token);
        using var peer = await listener.AcceptTcpClientAsync(token);
        var stream = peer.GetStream();
        var header = new StringBuilder();
        var oneByte = new byte[1];
        while (!header.ToString().EndsWith("\r\n\r\n", StringComparison.Ordinal))
        {
            Assert.Equal(1, await stream.ReadAsync(oneByte, token));
            header.Append((char)oneByte[0]);
            Assert.True(header.Length < 8192);
        }

        var lines = header.ToString().Split("\r\n");
        Assert.Equal("GET /?connectionParams=1 HTTP/1.1", lines[0]);
        var key = lines.Single(line => line.StartsWith("Sec-WebSocket-Key:", StringComparison.OrdinalIgnoreCase))
            .Split(':', 2)[1].Trim();
        var accept = Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
        await stream.WriteAsync(Encoding.ASCII.GetBytes(
            $"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n"), token);
        using var server = WebSocket.CreateFromStream(stream, isServer: true, subProtocol: null, Timeout.InfiniteTimeSpan);
        await connecting;
        Assert.Equal("{\"method\":\"connectionParams\",\"data\":{\"token\":\"test-token\"}}", await ReceiveAsync(server, token));

        try
        {
            await run(client, server, token);
        }
        finally
        {
            // abort the loopback peer before disposing the client, so close never waits for an unread handshake
            server.Abort();
        }
    }

    internal static Task SendAsync(WebSocket socket, string text, CancellationToken token) =>
        socket.SendAsync(new ArraySegment<byte>(Encoding.UTF8.GetBytes(text)), WebSocketMessageType.Text, true, token);

    internal static async Task<string> ReceiveAsync(WebSocket socket, CancellationToken token)
    {
        using var message = new MemoryStream();
        var buffer = new byte[4096];
        WebSocketReceiveResult received;
        do
        {
            received = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), token);
            Assert.Equal(WebSocketMessageType.Text, received.MessageType);
            message.Write(buffer, 0, received.Count);
        } while (!received.EndOfMessage);

        return Encoding.UTF8.GetString(message.ToArray());
    }
}
