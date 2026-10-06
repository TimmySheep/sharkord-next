using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

/// <summary>
/// End to end check against a real server, on by default only when <c>SHARKORD_IT_HOST</c>
/// is set. Point it at a throwaway instance, not a server anyone is using: the test
/// registers a user and sends a message. Without the variable the test is a no-op so the
/// offline suite still passes.
/// </summary>
public class IntegrationTests
{
    [Fact]
    public async Task LoginJoinSendAndReceive()
    {
        var host = Environment.GetEnvironmentVariable("SHARKORD_IT_HOST");

        if (string.IsNullOrEmpty(host))
        {
            return;
        }

        var identity = Environment.GetEnvironmentVariable("SHARKORD_IT_IDENTITY") ?? "cs-native-probe";
        var password = Environment.GetEnvironmentVariable("SHARKORD_IT_PASSWORD") ?? "probe-password";

        var http = new SharkordHttpClient(new Uri($"http://{host}"));
        var info = await http.GetInfoAsync();
        Assert.False(string.IsNullOrEmpty(info.ServerId));

        var login = await http.LoginAsync(identity, password);
        Assert.False(string.IsNullOrEmpty(login.Token));

        await using var client = new TrpcWebSocketClient(http.WebSocketUrl, login.Token);
        await client.ConnectAsync();

        var handshake = (await client.QueryAsync("others.handshake"))
            .DeserializeObject<SharkordHandshake>();
        Assert.NotNull(handshake);
        Assert.False(string.IsNullOrEmpty(handshake!.HandshakeHash));

        var join = (await client.QueryAsync(
                "others.joinServer",
                new JsonObject { ["handshakeHash"] = handshake.HandshakeHash }
            ))
            .DeserializeObject<JoinResult>();

        Assert.NotNull(join);
        Assert.Equal(info.ServerId, join!.ServerId);
        Assert.True(join.OwnUserId > 0);

        var textChannel = join.Channels.First(c => c.IsText);

        // subscribe before sending so the live event cannot be missed
        var firstEvent = FirstEventAsync(client.SubscribeAsync("messages.onNew"), TimeSpan.FromSeconds(5));
        await Task.Delay(250);

        var marker = $"cs-probe-{Guid.NewGuid()}";
        var messageId = (await client.MutationAsync(
                "messages.send",
                new JsonObject
                {
                    ["content"] = $"<p>{marker}</p>",
                    ["channelId"] = textChannel.Id,
                    ["files"] = new JsonArray()
                }
            ))
            .AsInt();

        Assert.NotNull(messageId);

        var page = (await client.QueryAsync(
                "messages.get",
                new JsonObject { ["channelId"] = textChannel.Id, ["limit"] = 50 }
            ))
            .DeserializeObject<MessagesPage>();

        Assert.NotNull(page);
        Assert.Contains(page!.Messages, m => m.Content?.Contains(marker) == true);

        var delivered = (await firstEvent).DeserializeObject<SharkordMessage>();
        Assert.NotNull(delivered);
        Assert.Contains(marker, delivered!.Content);
    }

    /// Exercises the message mutations and the DM/read-receipt routes: edit, react,
    /// delete, typing, mark read and open a direct message.
    [Fact]
    public async Task EditReactDeleteAndDirectMessage()
    {
        var host = Environment.GetEnvironmentVariable("SHARKORD_IT_HOST");

        if (string.IsNullOrEmpty(host))
        {
            return;
        }

        var identity = Environment.GetEnvironmentVariable("SHARKORD_IT_IDENTITY") ?? "cs-native-probe";
        var password = Environment.GetEnvironmentVariable("SHARKORD_IT_PASSWORD") ?? "probe-password";

        var http = new SharkordHttpClient(new Uri($"http://{host}"));
        var login = await http.LoginAsync(identity, password);

        await using var client = new TrpcWebSocketClient(http.WebSocketUrl, login.Token);
        await client.ConnectAsync();

        var handshake = (await client.QueryAsync("others.handshake")).DeserializeObject<SharkordHandshake>()!;

        var join = (await client.QueryAsync(
                "others.joinServer",
                new JsonObject { ["handshakeHash"] = handshake.HandshakeHash }
            ))
            .DeserializeObject<JoinResult>()!;

        var textChannel = join.Channels.First(c => c.IsText);

        // claim ownership on a throwaway server so the permission gated routes below are
        // reachable; a fresh server's default role has no REACT_TO_MESSAGES
        var secret = Environment.GetEnvironmentVariable("SHARKORD_IT_SECRET") ?? "dev";

        try
        {
            await client.MutationAsync(
                "others.useSecretToken",
                new JsonObject { ["token"] = secret }
            );
        }
        catch
        {
            // already claimed, or no secret on this server; the flow below still runs
        }

        var marker = $"cs-edit-{Guid.NewGuid()}";

        var messageId = (await client.MutationAsync(
                "messages.send",
                new JsonObject
                {
                    ["content"] = $"<p>{marker}</p>",
                    ["channelId"] = textChannel.Id,
                    ["files"] = new JsonArray()
                }
            ))
            .AsInt();

        Assert.NotNull(messageId);

        await client.MutationAsync(
            "messages.edit",
            new JsonObject
            {
                ["messageId"] = messageId!.Value,
                ["content"] = $"<p>{marker}-edited</p>"
            }
        );

        await client.MutationAsync(
            "messages.toggleReaction",
            new JsonObject { ["messageId"] = messageId.Value, ["emoji"] = "thumbsup" }
        );

        await client.MutationAsync(
            "messages.signalTyping",
            new JsonObject { ["channelId"] = textChannel.Id }
        );

        await client.MutationAsync(
            "channels.markAsRead",
            new JsonObject { ["channelId"] = textChannel.Id }
        );

        var edited = await Fetch(http, client, textChannel.Id, messageId.Value);
        Assert.NotNull(edited);
        Assert.Contains("edited", edited!.Content);
        Assert.Contains(edited.Reactions ?? [], r => r.Emoji == "thumbsup");

        var other = join.Users.FirstOrDefault(u => u.Id != join.OwnUserId && !u.Banned);

        if (other is not null)
        {
            var dm = (await client.MutationAsync(
                    "dms.open",
                    new JsonObject { ["userId"] = other.Id }
                ))
                .DeserializeObject<OpenDirectMessageResult>();

            Assert.NotNull(dm);
            Assert.True(dm!.ChannelId > 0);
        }

        await client.MutationAsync(
            "messages.delete",
            new JsonObject { ["messageId"] = messageId.Value }
        );

        var afterDelete = await Fetch(http, client, textChannel.Id, messageId.Value);
        Assert.Null(afterDelete);
    }

    private static async Task<SharkordMessage?> Fetch(
        SharkordHttpClient http,
        TrpcWebSocketClient client,
        int channelId,
        int messageId
    )
    {
        _ = http;

        var page = (await client.QueryAsync(
                "messages.get",
                new JsonObject { ["channelId"] = channelId, ["limit"] = 100 }
            ))
            .DeserializeObject<MessagesPage>();

        return page?.Messages.FirstOrDefault(m => m.Id == messageId);
    }

    private static async Task<JsonNode?> FirstEventAsync(IAsyncEnumerable<JsonNode> stream, TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);

        try
        {
            await foreach (var item in stream.WithCancellation(cts.Token))
            {
                return item;
            }
        }
        catch (OperationCanceledException)
        {
            // timed out waiting for the first event
        }

        return null;
    }
}
