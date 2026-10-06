using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Sharkord.Core;

public sealed class SharkordHttpError : Exception
{
    public int Status { get; }

    public SharkordHttpError(int status, string message)
        : base(message)
    {
        Status = status;
    }
}

/// <summary>
/// The non tRPC half of the server: <c>GET /info</c>, <c>POST /login</c>,
/// <c>POST /upload</c> and the <c>/public</c> file route.
/// </summary>
public sealed class SharkordHttpClient
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _http;

    public Uri BaseUrl { get; }

    public SharkordHttpClient(Uri baseUrl, HttpClient? http = null)
    {
        BaseUrl = baseUrl;
        _http = http ?? new HttpClient();
    }

    /// <summary>
    /// The tRPC WebSocket lives on the same origin. <c>?connectionParams=1</c> is required,
    /// otherwise the server creates the request context before the token arrives.
    /// </summary>
    public Uri WebSocketUrl => new UriBuilder(BaseUrl)
    {
        Scheme = BaseUrl.Scheme == Uri.UriSchemeHttps ? "wss" : "ws",
        Path = "/",
        Query = "connectionParams=1"
    }.Uri;

    public async Task<SharkordServerInfo> GetInfoAsync(CancellationToken cancellationToken = default)
    {
        var response = await _http.GetAsync(new Uri(BaseUrl, "info"), cancellationToken).ConfigureAwait(false);

        return await ReadAsync<SharkordServerInfo>(response, cancellationToken).ConfigureAwait(false);
    }

    public async Task<SharkordLoginResult> LoginAsync(
        string identity,
        string password,
        string? invite = null,
        CancellationToken cancellationToken = default
    )
    {
        var body = new JsonObject
        {
            ["identity"] = identity,
            ["password"] = password
        };

        if (!string.IsNullOrEmpty(invite))
        {
            body["invite"] = invite;
        }

        using var content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
        var response = await _http.PostAsync(new Uri(BaseUrl, "login"), content, cancellationToken).ConfigureAwait(false);

        return await ReadAsync<SharkordLoginResult>(response, cancellationToken).ConfigureAwait(false);
    }

    public async Task<SharkordTempFile> UploadAsync(
        byte[] data,
        string fileName,
        string mimeType,
        string token,
        CancellationToken cancellationToken = default
    )
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(BaseUrl, "upload"));
        request.Headers.Add("x-token", token);
        request.Headers.Add("x-file-name", fileName);
        request.Headers.Add("x-file-type", mimeType);
        request.Content = new ByteArrayContent(data);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");

        var response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);

        return await ReadAsync<SharkordTempFile>(response, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>Attachments are served from <c>/public/&lt;name&gt;</c>, signed only when the server enables it.</summary>
    public Uri PublicFileUrl(SharkordFile file)
    {
        var builder = new UriBuilder(new Uri(BaseUrl, $"public/{Uri.EscapeDataString(file.Name)}"));

        if (file.AccessToken is not null && file.AccessTokenExpiresAt is not null)
        {
            builder.Query =
                $"accessToken={Uri.EscapeDataString(file.AccessToken)}&expires={file.AccessTokenExpiresAt}";
        }

        return builder.Uri;
    }

    private static async Task<T> ReadAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

        if (!response.IsSuccessStatusCode)
        {
            throw new SharkordHttpError(
                (int)response.StatusCode,
                ErrorMessage(body) ?? $"Request failed ({(int)response.StatusCode})"
            );
        }

        return JsonSerializer.Deserialize<T>(body, JsonOptions)
            ?? throw new SharkordHttpError((int)response.StatusCode, "Empty response");
    }

    /// <summary>The server answers failures as <c>{ error }</c> or <c>{ errors: { field } }</c>.</summary>
    private static string? ErrorMessage(string body)
    {
        JsonNode? value;

        try
        {
            value = JsonNode.Parse(body);
        }
        catch
        {
            return null;
        }

        if (value is not JsonObject obj)
        {
            return null;
        }

        if (obj.GetString("error") is { } error)
        {
            return error;
        }

        if (obj["errors"] is JsonObject errors)
        {
            foreach (var (_, field) in errors)
            {
                if (field.AsString() is { } message)
                {
                    return message;
                }
            }
        }

        return null;
    }
}
