using System.Text.Json.Nodes;

namespace Sharkord.Core;

public sealed partial class SharkordSession
{
    public Task SendFormattedMessageAsync(int channelId, string html, int? replyToMessageId = null,
        IReadOnlyList<string>? files = null, int? parentMessageId = null, CancellationToken cancellationToken = default)
    {
        if (html.Length > ProtocolDefaults.MessageMaxLength) { throw new ArgumentOutOfRangeException(nameof(html)); }
        var input = new JsonObject
        {
            ["channelId"] = channelId, ["content"] = html,
            ["files"] = new JsonArray((files ?? []).Select(file => (JsonNode?)JsonValue.Create(file)).ToArray())
        };
        if (replyToMessageId is { } reply) { input["replyToMessageId"] = reply; }
        if (parentMessageId is { } parent) { input["parentMessageId"] = parent; }
        return CallMutationAsync("messages.send", input, cancellationToken);
    }

    public Task EditFormattedMessageAsync(int messageId, string html, CancellationToken cancellationToken = default)
    {
        if (html.Length > ProtocolDefaults.MessageMaxLength) { throw new ArgumentOutOfRangeException(nameof(html)); }
        return CallMutationAsync("messages.edit", new JsonObject { ["messageId"] = messageId, ["content"] = html }, cancellationToken);
    }

    public async Task<SharkordTempFile> UploadAttachmentWithProgressAsync(byte[] data, string name, string mimeType,
        IProgress<long>? progress = null, CancellationToken cancellationToken = default)
    {
        var http = _http ?? throw new TrpcClientError("DISCONNECTED", "Not connected");
        var token = _token ?? throw new TrpcClientError("DISCONNECTED", "Not connected");
        return await http.UploadAsync(data, name, mimeType, token, cancellationToken, progress).ConfigureAwait(false);
    }

    public Task DeleteTemporaryAttachmentAsync(string fileId, CancellationToken cancellationToken = default) =>
        CallMutationAsync("files.deleteTemporary", new JsonObject { ["fileId"] = fileId }, cancellationToken);
}
