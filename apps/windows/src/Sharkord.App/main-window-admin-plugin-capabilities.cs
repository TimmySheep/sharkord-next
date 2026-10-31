using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task<FrameworkElement> BuildPluginCapabilitiesAsync(string pluginId)
    {
        var response = await _session.CallQueryAsync("plugins.getCapabilities", new JsonObject { ["pluginId"] = pluginId });
        var panel = new StackPanel { Spacing = 12, Margin = new Thickness(12) };
        foreach (var capability in response?["capabilities"] as JsonArray ?? [])
        {
            if (capability is null) { continue; }
            var type = capability["type"]?.AsString() ?? "";
            var name = capability["name"]?.AsString() ?? "";
            var everyone = new CheckBox { Content = L10n.T("pluginAccessEveryone", ns: "settings"), IsChecked = capability["mode"]?.AsString() == "public" };
            var roles = new Dictionary<int, CheckBox>();
            var field = new StackPanel { Spacing = 8 };
            field.Children.Add(everyone);
            foreach (var role in _session.Roles.Where(role => role.Id != 1))
            {
                var check = new CheckBox { Content = role.Name, IsChecked = (capability["roleIds"] as JsonArray ?? []).Any(id => id?.AsInt() == role.Id), IsEnabled = everyone.IsChecked != true };
                roles[role.Id] = check; field.Children.Add(check);
            }
            everyone.Click += (_, _) => { foreach (var check in roles.Values) { check.IsEnabled = everyone.IsChecked != true; } };
            var save = new Button { Content = L10n.T("saveChanges") };
            var reset = new Button { Content = L10n.T("resetAccess", ns: "admin") };
            var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
            save.Click += async (_, _) =>
            {
                try
                {
                    var roleIds = new JsonArray();
                    if (everyone.IsChecked != true) { foreach (var role in roles.Where(pair => pair.Value.IsChecked == true)) { roleIds.Add(role.Key); } }
                    await _session.CallMutationAsync("plugins.setCapabilityAccess", new JsonObject { ["pluginId"] = pluginId, ["type"] = type, ["name"] = name, ["mode"] = everyone.IsChecked == true ? "public" : "restricted", ["roleIds"] = roleIds });
                    status.Text = L10n.T("pluginPermissionsSaved", ns: "settings");
                }
                catch (Exception exception) { status.Text = exception.Message; }
            };
            reset.Click += async (_, _) =>
            {
                try
                {
                    await _session.CallMutationAsync("plugins.resetCapabilityAccess", new JsonObject { ["pluginId"] = pluginId, ["type"] = type, ["name"] = name });
                    everyone.IsChecked = capability["defaultAccess"]?["mode"]?.AsString() == "public";
                    foreach (var (id, check) in roles)
                    {
                        check.IsChecked = (capability["defaultAccess"]?["roleIds"] as JsonArray ?? []).Any(value => value?.AsInt() == id);
                        check.IsEnabled = everyone.IsChecked != true;
                    }
                    status.Text = L10n.T("pluginPermissionsSaved", ns: "settings");
                }
                catch (Exception exception) { status.Text = exception.Message; }
            };
            field.Children.Add(save); field.Children.Add(reset); field.Children.Add(status);
            panel.Children.Add(new Expander { Header = $"{type} · {name}", Content = field, HorizontalAlignment = HorizontalAlignment.Stretch });
        }
        return new ScrollViewer { Content = panel };
    }
}
