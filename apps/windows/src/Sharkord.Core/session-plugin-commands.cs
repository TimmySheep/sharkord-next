using System.Text.Json.Nodes;

namespace Sharkord.Core;

public sealed class PluginCapabilityRule
{
    public string PluginId { get; init; } = "";
    public string Type { get; init; } = "";
    public string Name { get; init; } = "";
    public List<int> RoleIds { get; init; } = [];
}

public sealed partial class SharkordSession
{
    public JsonObject PluginCommands { get; private set; } = [];
    public IReadOnlyList<PluginCapabilityRule> PluginCapabilityRules { get; private set; } = [];

    private void ApplyPluginSnapshot(JoinResult join)
    {
        PluginCommands = join.Commands ?? [];
        PluginCapabilityRules = join.PluginCapabilityAccess ?? [];
    }

    private void ApplyPluginCommands(JsonNode node)
    {
        PluginCommands = node as JsonObject ?? [];
        Notify();
    }

    private void ApplyPluginCapabilities(JsonNode node)
    {
        PluginCapabilityRules = node.DeserializeObject<List<PluginCapabilityRule>>() ?? [];
        Notify();
    }

    public bool CanUsePluginCommand(string pluginId, string name)
    {
        if (Settings?.EnablePlugins == false || !HasPermission("USE_PLUGINS")) { return false; }
        if (OwnUser?.RoleIds?.Contains(1) == true) { return true; }
        var rule = PluginCapabilityRules.FirstOrDefault(candidate => candidate.PluginId == pluginId && candidate.Type == "command" && candidate.Name == name);
        return rule is null || rule.RoleIds.Any(roleId => OwnUser?.RoleIds?.Contains(roleId) == true);
    }
}
