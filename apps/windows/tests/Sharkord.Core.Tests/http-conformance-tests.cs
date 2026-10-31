using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class HttpConformanceTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("invite-code")]
    public async Task LoginUsesJsonAndOmitsAnEmptyInvite(string? invite)
    {
        using var http = new HttpClient(new RequestHandler(async request =>
        {
            Assert.Equal(HttpMethod.Post, request.Method);
            Assert.Equal("/login", request.RequestUri!.AbsolutePath);
            Assert.Equal("application/json", request.Content!.Headers.ContentType!.MediaType);
            var body = JsonNode.Parse(await request.Content.ReadAsStringAsync())!.AsObject();
            Assert.Equal("user", body["identity"]!.GetValue<string>());
            Assert.Equal("password", body["password"]!.GetValue<string>());
            Assert.Equal(!string.IsNullOrEmpty(invite), body.ContainsKey("invite"));
            if (!string.IsNullOrEmpty(invite))
            {
                Assert.Equal(invite, body["invite"]!.GetValue<string>());
            }
            return JsonResponse("{\"success\":true,\"token\":\"test-token\"}");
        }));
        var client = new SharkordHttpClient(new Uri("https://example.test/"), http);

        var result = await client.LoginAsync("user", "password", invite);

        Assert.Equal("test-token", result.Token);
    }

    [Theory]
    [InlineData("")]
    [InlineData("hello")]
    [InlineData("海🌊\r\n")]
    public async Task UploadSendsRawBytesWithMatchingContentLength(string text)
    {
        var data = Encoding.UTF8.GetBytes(text);
        using var http = new HttpClient(new RequestHandler(async request =>
        {
            Assert.Equal(HttpMethod.Post, request.Method);
            Assert.Equal("/upload", request.RequestUri!.AbsolutePath);
            Assert.Equal("test-token", Assert.Single(request.Headers.GetValues("x-token")));
            Assert.Equal("note.txt", Assert.Single(request.Headers.GetValues("x-file-name")));
            Assert.Equal("text/plain", Assert.Single(request.Headers.GetValues("x-file-type")));
            Assert.Equal("application/octet-stream", request.Content!.Headers.ContentType!.MediaType);
            Assert.Equal(data.LongLength, request.Content.Headers.ContentLength);
            Assert.Equal(data, await request.Content.ReadAsByteArrayAsync());
            return JsonResponse("{\"id\":\"temporary-id\",\"originalName\":\"note.txt\"}");
        }));
        var client = new SharkordHttpClient(new Uri("https://example.test/"), http);

        var result = await client.UploadAsync(data, "note.txt", "text/plain", "test-token");

        Assert.Equal("temporary-id", result.Id);
    }

    [Theory]
    [InlineData("{\"error\":\"Uploads are disabled\"}", "Uploads are disabled")]
    [InlineData("{\"errors\":{\"identity\":\"Identity is required\"}}", "Identity is required")]
    [InlineData("unavailable", "Request failed (403)")]
    public async Task HttpFailuresKeepTheServerStatusAndMessage(string body, string message)
    {
        using var http = new HttpClient(new RequestHandler(_ =>
            Task.FromResult(JsonResponse(body, HttpStatusCode.Forbidden))));
        var client = new SharkordHttpClient(new Uri("https://example.test/"), http);

        var error = await Assert.ThrowsAsync<SharkordHttpError>(() => client.LoginAsync("user", "password"));

        Assert.Equal(403, error.Status);
        Assert.Equal(message, error.Message);
    }

    [Theory]
    [InlineData("http://example.test:4991/", "ws://example.test:4991/?connectionParams=1")]
    [InlineData("https://example.test/", "wss://example.test/?connectionParams=1")]
    public void WebSocketUsesTheSameOriginAndRequestsConnectionParams(string origin, string expected)
    {
        using var http = new HttpClient();
        var client = new SharkordHttpClient(new Uri(origin), http);

        Assert.Equal(expected, client.WebSocketUrl.AbsoluteUri);
    }

    [Fact]
    public void PublicUrlsEscapeFileNamesAndIncludeBothSigningFields()
    {
        using var http = new HttpClient();
        var client = new SharkordHttpClient(new Uri("https://example.test/"), http);

        var signed = client.PublicFileUrl(new SharkordFile
        {
            Name = "file #1.png", AccessToken = "a+b/c=", AccessTokenExpiresAt = 123456789
        });
        var unsigned = client.PublicFileUrl(new SharkordFile { Name = "file.png", AccessToken = "incomplete" });

        Assert.Equal("https://example.test/public/file%20%231.png?accessToken=a%2Bb%2Fc%3D&expires=123456789", signed.AbsoluteUri);
        Assert.Equal("https://example.test/public/file.png", unsigned.AbsoluteUri);
    }

    private static HttpResponseMessage JsonResponse(string body, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    private sealed class RequestHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> handle) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            handle(request);
    }
}
