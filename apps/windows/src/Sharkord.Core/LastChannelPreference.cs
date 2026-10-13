using System.Security.Cryptography;
using System.Text;

namespace Sharkord.Core;

public static class LastChannelPreference
{
    public static string SettingKey(string serverBaseUrl)
    {
        if (!Uri.TryCreate(serverBaseUrl, UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("http" or "https"))
        {
            throw new ArgumentException("A valid HTTP server address is required.", nameof(serverBaseUrl));
        }

        var normalized = uri.GetLeftPart(UriPartial.Path).TrimEnd('/');
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(normalized));
        return $"app.lastSelectedChannel.{Convert.ToHexString(hash)}";
    }

    public static bool CanRestoreChannel(bool isText, bool isDirectMessage, bool isVoice) =>
        !isVoice && (isText || isDirectMessage);
}
