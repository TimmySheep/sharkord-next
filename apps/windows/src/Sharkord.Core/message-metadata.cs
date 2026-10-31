namespace Sharkord.Core;

public sealed record MessageLinkMetadata(string? Kind, string? Url, string? Title, string? SiteName, string? Description, string? MediaType, string[]? Images);
public sealed record MessagePreview(Uri Url, string Title, string? Description, string? MediaType, Uri? Image);

public static class MessageMetadata
{
    public static IReadOnlyList<MessagePreview> Previews(SharkordMessage message)
    {
        var result = new List<MessagePreview>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var metadata in message.Metadata ?? [])
        {
            if (HttpUrl(metadata.Url) is not { } url || !seen.Add(url.GetComponents(UriComponents.SchemeAndServer | UriComponents.PathAndQuery, UriFormat.UriEscaped))) { continue; }
            var media = metadata.MediaType is "image" or "video" or "audio" ? metadata.MediaType : null;
            var title = metadata.Title ?? metadata.SiteName ?? url.Host;
            result.Add(new MessagePreview(url, title, metadata.Description, media, metadata.Images?.Select(HttpUrl).FirstOrDefault(image => image is not null)));
        }
        return result;
    }

    private static Uri? HttpUrl(string? value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" ? uri : null;
}
