using System.Text.Json;
using System.Text.Json.Nodes;

namespace Sharkord.Core;

/// <summary>
/// Small helpers for reading the loosely typed JSON the tRPC protocol carries. Nothing
/// here throws on a missing or wrong-typed field; callers that require a value use the
/// typed models instead.
/// </summary>
internal static class JsonExtensions
{
    private static readonly JsonSerializerOptions DefaultOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    /// <summary>
    /// net8 has no `JsonNode.Deserialize`, so round-trips through the node's JSON text.
    /// </summary>
    public static T? DeserializeObject<T>(this JsonNode? node)
        => node is null ? default : JsonSerializer.Deserialize<T>(node.ToJsonString(), DefaultOptions);

    public static int? AsInt(this JsonNode? node)
    {
        if (node is not JsonValue value)
        {
            return null;
        }

        if (value.TryGetValue<int>(out var integer))
        {
            return integer;
        }

        if (value.TryGetValue<double>(out var number))
        {
            return (int)number;
        }

        return null;
    }

    public static string? AsString(this JsonNode? node)
        => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    public static bool? AsBool(this JsonNode? node)
        => node is JsonValue value && value.TryGetValue<bool>(out var flag) ? flag : null;

    public static int? GetInt(this JsonObject obj, string name)
        => obj.TryGetPropertyValue(name, out var node) ? node.AsInt() : null;

    public static string? GetString(this JsonObject obj, string name)
        => obj.TryGetPropertyValue(name, out var node) ? node.AsString() : null;
}
