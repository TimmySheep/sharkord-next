using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

namespace Sharkord.Core;

public sealed partial class SharkordSession
{
    public async IAsyncEnumerable<JsonNode> StreamPluginLogsAsync(string pluginId, [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var client = _client ?? throw new InvalidOperationException("Not connected");
        await foreach (var value in client.SubscribeAsync("plugins.onLog", null, cancellationToken).ConfigureAwait(false))
        {
            if (value["pluginId"]?.AsString() == pluginId) { yield return value; }
        }
    }
}
