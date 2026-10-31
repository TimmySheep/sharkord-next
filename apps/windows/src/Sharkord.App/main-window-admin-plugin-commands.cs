using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task<FrameworkElement> BuildPluginCommandsAsync(string pluginId)
    {
        var response = await _session.CallQueryAsync("plugins.getCommands", new JsonObject { ["pluginId"] = pluginId });
        return BuildPluginCommandForm(pluginId, response?[pluginId] as JsonArray ?? []);
    }

    private FrameworkElement BuildPluginCommandForm(string pluginId, JsonArray commands)
    {
        var panel = new StackPanel { Spacing = 12, Margin = new Thickness(12) };
        foreach (var command in commands)
        {
            if (command is null) { continue; }
            var name = command["name"]?.AsString() ?? "";
            var fields = new StackPanel { Spacing = 10 };
            var readers = new Dictionary<string, Func<JsonNode?>>();
            foreach (var argument in command["args"] as JsonArray ?? [])
            {
                if (argument is null) { continue; }
                fields.Children.Add(CreatePluginField(argument, null, out var read));
                readers[argument["name"]?.AsString() ?? ""] = read;
            }
            var execute = new Button { Content = L10n.T("executeCommand", ns: "admin"), IsEnabled = _session.CanUsePluginCommand(pluginId, name) };
            var result = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
            execute.Click += async (_, _) =>
            {
                if (!_session.CanUsePluginCommand(pluginId, name)) { execute.IsEnabled = false; return; }
                execute.IsEnabled = false;
                try
                {
                    var args = new JsonObject();
                    foreach (var (key, read) in readers) { if (read() is { } value) { args[key] = value; } }
                    var input = new JsonObject { ["pluginId"] = pluginId, ["commandName"] = name, ["args"] = args };
                    if (_session.SelectedChannelId is { } id) { input["channelId"] = id; }
                    var data = await _session.CallMutationAsync("plugins.executeCommand", input);
                    result.Text = data?.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }) ?? L10n.T("commandExecutedSuccess", ns: "settings");
                }
                catch (Exception exception) { result.Text = exception.Message; }
                finally { execute.IsEnabled = _session.CanUsePluginCommand(pluginId, name); }
            };
            fields.Children.Add(execute); fields.Children.Add(result);
            panel.Children.Add(new Expander { Header = $"/{name} · {command["description"]?.AsString() ?? ""}", Content = fields, HorizontalAlignment = HorizontalAlignment.Stretch });
        }
        return new ScrollViewer { Content = panel };
    }

}
