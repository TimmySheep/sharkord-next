using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task ShowJoinedPluginCommandsAsync()
    {
        var pivot = new Pivot { Width = 650, Height = 480 };
        foreach (var plugin in _session.PluginCommands)
        {
            if (plugin.Value is not System.Text.Json.Nodes.JsonArray commands) { continue; }
            pivot.Items.Add(new PivotItem { Header = plugin.Key, Content = BuildPluginCommandForm(plugin.Key, commands) });
        }
        var dialog = NavigationDialog(L10n.T("commandsTitle", ns: "settings"), pivot);
        await dialog.ShowAsync();
    }
}
