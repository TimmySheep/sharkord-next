using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Sharkord.Core;

public sealed record MarketplaceVersion(string Version, int SdkVersion, long Timestamp, long Size);
public sealed record MarketplacePlugin(string PluginId, string Name, string Description, string Author, bool Verified, string? Homepage, IReadOnlyList<MarketplaceVersion> Versions);

public static class MarketplaceRegistry
{
    public const string RegistryUrl = "https://raw.githubusercontent.com/Sharkord/plugins/refs/heads/main/plugins.json?raw=true";
    public const int SdkVersion = 2;

    public static IReadOnlyList<MarketplacePlugin> Parse(JsonNode? node)
    {
        var result = new List<MarketplacePlugin>();
        foreach (var row in node as JsonArray ?? [])
        {
            try
            {
                var plugin = row?["plugin"];
                var id = plugin?["id"]?.GetValue<string>() ?? "";
                var name = plugin?["name"]?.GetValue<string>() ?? "";
                if (id.Length is < 1 or > 64 || !Regex.IsMatch(id, "^[a-z0-9-]+$") || name.Length == 0) { continue; }
                if (!HttpUrl(plugin?["logo"]?.GetValue<string>())) { continue; }
                var description = plugin?["description"]?.GetValue<string>();
                var author = plugin?["author"]?.GetValue<string>();
                var verified = plugin?["verified"]?.GetValue<bool>();
                if (description is null || author is null || verified is null || row?["versions"] is not JsonArray versions) { continue; }
                var parsed = new List<MarketplaceVersion>();
                foreach (var version in versions)
                {
                    var value = version?["version"]?.GetValue<string>() ?? "";
                    var download = version?["downloadUrl"]?.GetValue<string>();
                    if (value.Length == 0 || !Uri.TryCreate(download, UriKind.Absolute, out var url) || url.Scheme != "https" ||
                        string.IsNullOrEmpty(version?["checksum"]?.GetValue<string>())) { continue; }
                    var sdk = version?["sdkVersion"]?.GetValue<int>() ?? -1;
                    if (sdk < 0) { continue; }
                    parsed.Add(new(value, sdk, version?["timestamp"]?.GetValue<long>() ?? 0, version?["size"]?.GetValue<long>() ?? 0));
                }
                result.Add(new(id, name, description, author, verified.Value, plugin?["homepage"]?.GetValue<string>(), parsed.OrderByDescending(version => version.Timestamp).ToArray()));
            }
            catch (InvalidOperationException) { }
            catch (FormatException) { }
        }
        return result.OrderByDescending(plugin => plugin.Versions.FirstOrDefault()?.Timestamp ?? 0).ToArray();
    }

    private static bool HttpUrl(string? value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https";
}
