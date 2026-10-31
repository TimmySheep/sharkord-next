using System.Reflection;
using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public sealed class RichMessageProtocolTests
{
    [Fact]
    public async Task FormattedSendAndEditPreserveHtmlAndThreadFields()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            const string html = "<p><strong>bold</strong> <span data-type=\"mention\" data-user-id=\"2\">@Ada</span></p>";
            var send = session.SendFormattedMessageAsync(7, html, 13, ["temporary-id"], 12, token);
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("messages.send", request["params"]!["path"]!.GetValue<string>());
            var input = request["params"]!["input"]!;
            Assert.Equal(html, input["content"]!.GetValue<string>());
            Assert.Equal(12, input["parentMessageId"]!.GetValue<int>());
            Assert.Equal(13, input["replyToMessageId"]!.GetValue<int>());
            Assert.Equal("temporary-id", input["files"]![0]!.GetValue<string>());
            await Respond(request);
            await send;
            var edit = session.EditFormattedMessageAsync(13, html, token);
            request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("messages.edit", request["params"]!["path"]!.GetValue<string>());
            Assert.Equal(html, request["params"]!["input"]!["content"]!.GetValue<string>());
            await Respond(request);
            await edit;
            var cleanup = session.DeleteTemporaryAttachmentAsync("temporary-id", token);
            request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("files.deleteTemporary", request["params"]!["path"]!.GetValue<string>());
            Assert.Equal("temporary-id", request["params"]!["input"]!["fileId"]!.GetValue<string>());
            await Respond(request);
            await cleanup;
            Task Respond(JsonNode message) => WebSocketConformanceTests.SendAsync(server,
                $"{{\"id\":{message["id"]},\"result\":{{\"data\":null}}}}", token);
        });
    }

    [Fact]
    public async Task SessionUploadForwardsRawBytesAndByteProgress()
    {
        var handler = new UploadHandler();
        using var http = new HttpClient(handler);
        await using var session = new SharkordSession();
        typeof(SharkordSession).GetField("_http", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session,
            new SharkordHttpClient(new Uri("https://upload.invalid/"), http));
        typeof(SharkordSession).GetField("_token", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, "test-token");
        var progress = new ByteProgress();
        var payload = Enumerable.Range(0, 150000).Select(value => (byte)(value % 256)).ToArray();
        var result = await session.UploadAttachmentWithProgressAsync(payload, "test file.png", "image/png", progress);
        Assert.Equal("temp-id", result.Id);
        Assert.Equal(payload, handler.Bytes);
        Assert.Equal(payload.Length, progress.Last);
        Assert.True(progress.Reports > 1);
    }

    private sealed class ByteProgress : IProgress<long>
    {
        public long Last { get; private set; }
        public int Reports { get; private set; }
        public void Report(long value) { Assert.True(value >= Last); Last = value; Reports++; }
    }

    private sealed class UploadHandler : HttpMessageHandler
    {
        public byte[] Bytes { get; private set; } = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Bytes = await request.Content!.ReadAsByteArrayAsync(cancellationToken);
            Assert.Equal("test%20file.png", request.Headers.GetValues("x-file-name").Single());
            Assert.Equal(Bytes.Length, request.Content.Headers.ContentLength);
            return new HttpResponseMessage(System.Net.HttpStatusCode.OK)
            {
                Content = new StringContent("{\"id\":\"temp-id\",\"originalName\":\"test file.png\",\"size\":150000}")
            };
        }
    }
}
