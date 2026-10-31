using System.Globalization;
using System.Text.Json.Nodes;

namespace Sharkord.Core;

public static class PluginFormValue
{
    public static JsonNode? Parse(string type, string text, bool flag = false, bool required = false)
    {
        if (type == "boolean") { return JsonValue.Create(flag); }
        if (text.Length == 0)
        {
            if (required) { throw new FormatException("A required field is empty"); }
            return null;
        }
        if (type == "number")
        {
            if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var number) || !double.IsFinite(number))
            {
                throw new FormatException("A number must be finite");
            }
            return JsonValue.Create(number);
        }
        return JsonValue.Create(text);
    }
}
