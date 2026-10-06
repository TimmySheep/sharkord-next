using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

/// <summary>
/// Pins the exact frames the transport puts on the wire. The tRPC WebSocket envelope is
/// an implementation detail of `@trpc/client`, so these tests are the guard that the C#
/// mirror still matches the reference client.
/// </summary>
public class TrpcProtocolTests
{
    [Fact]
    public void QueryWithoutInputOmitsInput()
    {
        var request = new TrpcRequest(1, TrpcMethod.Query, "others.handshake", null);

        Assert.Equal(
            "{\"id\":1,\"method\":\"query\",\"params\":{\"path\":\"others.handshake\"}}",
            request.ToJson().ToJsonString()
        );
    }

    [Fact]
    public void MutationWithInputCarriesIt()
    {
        var request = new TrpcRequest(
            7,
            TrpcMethod.Mutation,
            "messages.send",
            new JsonObject
            {
                ["channelId"] = 3,
                ["content"] = "hi",
                ["files"] = new JsonArray()
            }
        );

        Assert.Equal(
            "{\"id\":7,\"method\":\"mutation\",\"params\":{\"path\":\"messages.send\",\"input\":{\"channelId\":3,\"content\":\"hi\",\"files\":[]}}}",
            request.ToJson().ToJsonString()
        );
    }

    [Fact]
    public void ConnectionParamsFrameMatchesReferenceClient()
    {
        Assert.Equal(
            "{\"method\":\"connectionParams\",\"data\":{\"token\":\"abc\"}}",
            TrpcConnectionParams.ToJson("abc").ToJsonString()
        );
    }

    [Fact]
    public void ParsesDataResult()
    {
        var value = JsonNode.Parse(
            "{\"id\":2,\"result\":{\"type\":\"data\",\"data\":42}}"
        );

        var incoming = TrpcResponseParser.Parse(value);

        Assert.Equal(TrpcIncomingKind.Result, incoming.Kind);
        Assert.Equal(2, incoming.Id);
        Assert.Equal("data", incoming.Type);
        Assert.Equal(42, incoming.Data!.AsInt());
    }

    [Fact]
    public void ParsesErrorWithStringCode()
    {
        var value = JsonNode.Parse(
            "{\"id\":3,\"error\":{\"message\":\"You must be authenticated to perform this action.\",\"code\":-32001,\"data\":{\"code\":\"UNAUTHORIZED\"}}}"
        );

        var incoming = TrpcResponseParser.Parse(value);

        Assert.Equal(TrpcIncomingKind.Failure, incoming.Kind);
        Assert.Equal(3, incoming.Id);
        Assert.Equal("UNAUTHORIZED", incoming.Error!.Code);
        Assert.Equal("You must be authenticated to perform this action.", incoming.Error.Message);
    }

    [Fact]
    public void ParsesStoppedSubscription()
    {
        var value = JsonNode.Parse("{\"id\":4,\"result\":{\"type\":\"stopped\"}}");
        var incoming = TrpcResponseParser.Parse(value);

        Assert.Equal(TrpcIncomingKind.Result, incoming.Kind);
        Assert.Equal(4, incoming.Id);
        Assert.Equal("stopped", incoming.Type);
    }

    [Fact]
    public void ParsesServerReconnectRequest()
    {
        var value = JsonNode.Parse("{\"method\":\"reconnect\"}");
        var incoming = TrpcResponseParser.Parse(value);

        Assert.Equal(TrpcIncomingKind.ServerRequest, incoming.Kind);
        Assert.Equal("reconnect", incoming.Method);
    }

    [Fact]
    public void MessageHtmlKeepsLineStructure()
    {
        Assert.Equal("<p>hello</p>", MessageHtml.FromPlainText("hello"));
        Assert.Equal(
            "<p>a</p><br class=\"hard-break\"><p>b</p>",
            MessageHtml.FromPlainText("a\nb")
        );
        Assert.Equal("<p>&lt;b&gt;</p>", MessageHtml.FromPlainText("<b>"));
    }

    [Fact]
    public void PlainTextRoundTrip()
    {
        Assert.Equal("a\nb", MessageHtml.ToPlainText(MessageHtml.FromPlainText("a\nb")));
    }

    [Fact]
    public void JoinPayloadDecodesWithUnknownKeys()
    {
        var payload = JsonNode.Parse(
            """
            {
              "categories": [],
              "channels": [],
              "users": [],
              "roles": [],
              "serverId": "x",
              "serverName": "Test",
              "ownUserId": 1,
              "publicSettings": { "name": "Test", "serverId": "x" },
              "voiceMap": {},
              "externalStreamsMap": {}
            }
            """
        );

        var join = payload!.DeserializeObject<JoinResult>();

        Assert.NotNull(join);
        Assert.Equal("Test", join!.ServerName);
        Assert.Equal(1, join.OwnUserId);
    }
}
