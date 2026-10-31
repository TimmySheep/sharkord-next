using System.Text.Json.Nodes;
using System.Reflection;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public sealed class PluginAdminTests
{
    [Fact]
    public void SchemaValuesPreservePrimitiveTypesAndRejectNonFiniteNumbers()
    {
        Assert.True(PluginFormValue.Parse("boolean", "", true)!.GetValue<bool>());
        Assert.Equal(12.5, PluginFormValue.Parse("number", "12.5")!.GetValue<double>());
        Assert.Null(PluginFormValue.Parse("string", ""));
        Assert.Throws<FormatException>(() => PluginFormValue.Parse("number", "NaN"));
        Assert.Throws<FormatException>(() => PluginFormValue.Parse("number", "Infinity"));
        Assert.Throws<FormatException>(() => PluginFormValue.Parse("string", "", required: true));
        Assert.Equal("secret", PluginFormValue.Parse("secret", "secret")!.GetValue<string>());
    }

    [Fact]
    public void MarketplaceParsingSkipsInvalidRowsAndOrdersNewestCompatibleVersions()
    {
        var rows = MarketplaceRegistry.Parse(JsonNode.Parse("[{\"plugin\":{\"id\":\"bad id\"},\"versions\":[]},{\"plugin\":{\"id\":\"good-plugin\",\"name\":\"Good\",\"description\":\"D\",\"author\":\"A\",\"logo\":\"https://example.com/logo.png\",\"verified\":true},\"versions\":[{\"version\":\"1.0\",\"sdkVersion\":2,\"timestamp\":1,\"downloadUrl\":\"https://example.com/a.zip\",\"checksum\":\"sha\",\"size\":10},{\"version\":\"2.0\",\"sdkVersion\":2,\"timestamp\":2,\"downloadUrl\":\"https://example.com/b.zip\",\"checksum\":\"sha2\",\"size\":20}]}]")!);
        var row = Assert.Single(rows);
        Assert.Equal("good-plugin", row.PluginId);
        Assert.Equal("2.0", row.Versions[0].Version);
    }

    [Fact]
    public async Task JoinedCommandsAndLiveAccessRulesWorkForNormalPluginUsers()
    {
        await using var session = new SharkordSession();
        var apply = typeof(SharkordSession).GetMethod("Apply", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var join = JsonNode.Parse("{\"ownUserId\":1,\"users\":[{\"id\":1,\"roleIds\":[2]}],\"roles\":[{\"id\":2,\"permissions\":[\"USE_PLUGINS\"]}],\"publicSettings\":{\"enablePlugins\":true},\"commands\":{\"example\":[{\"pluginId\":\"example\",\"name\":\"hello\"}]},\"pluginCapabilityAccess\":[{\"pluginId\":\"example\",\"type\":\"command\",\"name\":\"hello\",\"roleIds\":[3]}]}").DeserializeObject<JoinResult>()!;
        apply.Invoke(session, [join]);
        Assert.Equal("hello", session.PluginCommands["example"]![0]!["name"]!.GetValue<string>());
        Assert.False(session.CanUsePluginCommand("example", "hello"));
        typeof(SharkordSession).GetMethod("ApplyPluginCapabilities", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(session,
            [JsonNode.Parse("[{\"pluginId\":\"example\",\"type\":\"command\",\"name\":\"hello\",\"roleIds\":[2]}]")!]);
        Assert.True(session.CanUsePluginCommand("example", "hello"));
        typeof(SharkordSession).GetMethod("ApplyPluginCommands", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(session, [JsonNode.Parse("{\"example\":[{\"name\":\"updated\"}]}")!]);
        Assert.Equal("updated", session.PluginCommands["example"]![0]!["name"]!.GetValue<string>());
        apply.Invoke(session, [new JoinResult()]);
        Assert.Empty(session.PluginCommands);
        Assert.False(session.CanUsePluginCommand("example", "hello"));
    }

    [Fact]
    public async Task PluginLogSubscriptionUsesNoInputAndFiltersOtherPlugins()
    {
        await WebSocketConformanceTests.WithConnectionAsync(async (client, server, token) =>
        {
            var session = new SharkordSession();
            typeof(SharkordSession).GetField("_client", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(session, client);
            await using var logs = session.StreamPluginLogsAsync("wanted", token).GetAsyncEnumerator(token);
            var move = logs.MoveNextAsync().AsTask();
            var request = JsonNode.Parse(await WebSocketConformanceTests.ReceiveAsync(server, token))!;
            Assert.Equal("subscription", request["method"]!.GetValue<string>());
            Assert.Equal("plugins.onLog", request["params"]!["path"]!.GetValue<string>());
            Assert.Null(request["params"]!["input"]);
            await WebSocketConformanceTests.SendAsync(server, $"{{\"id\":{request["id"]},\"result\":{{\"type\":\"data\",\"data\":{{\"pluginId\":\"other\",\"message\":\"ignore\"}}}}}}", token);
            await WebSocketConformanceTests.SendAsync(server, $"{{\"id\":{request["id"]},\"result\":{{\"type\":\"data\",\"data\":{{\"pluginId\":\"wanted\",\"message\":\"display\"}}}}}}", token);
            Assert.True(await move);
            Assert.Equal("display", logs.Current["message"]!.GetValue<string>());
        });
    }
}
