using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task ShowPluginMarketplaceAsync(IReadOnlyList<JsonObject> installed)
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        var registry = MarketplaceRegistry.Parse(JsonNode.Parse(await http.GetStringAsync(MarketplaceRegistry.RegistryUrl)));
        var filter = new TextBox { PlaceholderText = L10n.T("marketplaceSearchPlaceholder", ns: "settings") };
        var rows = new StackPanel { Spacing = 16 };
        var panel = new StackPanel { Width = 680, Spacing = 12 };
        panel.Children.Add(filter);
        panel.Children.Add(new TextBlock { Text = L10n.T("pluginInstallConfirmLead", ns: "dialogs"), TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(rows);
        void Render()
        {
            rows.Children.Clear();
            var query = filter.Text.Trim();
            foreach (var plugin in registry.Where(plugin => plugin.Name.Contains(query, StringComparison.CurrentCultureIgnoreCase) || plugin.Author.Contains(query, StringComparison.CurrentCultureIgnoreCase) || plugin.Description.Contains(query, StringComparison.CurrentCultureIgnoreCase)))
            {
                var row = new StackPanel { Spacing = 8 };
                var isInstalled = installed.Any(item => item["id"]?.AsString() == plugin.PluginId);
                row.Children.Add(new TextBlock { Text = $"{plugin.Name} · {plugin.Author}", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
                row.Children.Add(new TextBlock { Text = plugin.Description, TextWrapping = TextWrapping.Wrap });
                if (plugin.Verified) { row.Children.Add(new TextBlock { Text = L10n.T("marketplaceVerified", ns: "settings") }); }
                if (plugin.Homepage is { } homepage && MessageHtml.IsSafeLink(homepage))
                {
                    var open = new HyperlinkButton { Content = homepage };
                    open.Click += async (_, _) => await OpenExternalFileAsync(new Uri(homepage));
                    row.Children.Add(open);
                }
                var versions = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
                foreach (var version in plugin.Versions)
                {
                    versions.Items.Add(new ComboBoxItem
                    {
                        Content = $"{version.Version} · {FormatBytes(version.Size)} · {DateTimeOffset.FromUnixTimeMilliseconds(version.Timestamp).LocalDateTime:d}",
                        Tag = version, IsEnabled = version.SdkVersion == MarketplaceRegistry.SdkVersion
                    });
                }
                versions.SelectedItem = versions.Items.OfType<ComboBoxItem>().FirstOrDefault(item => item.IsEnabled);
                row.Children.Add(versions);
                var confirm = new CheckBox { Content = L10n.T("confirm") };
                row.Children.Add(confirm);
                var install = new Button { Content = L10n.T(isInstalled ? "marketplaceUpdateBtn" : "marketplaceInstallBtn", ns: "settings"), IsEnabled = false };
                void RefreshEnabled() => install.IsEnabled = confirm.IsChecked == true && versions.SelectedItem is ComboBoxItem { Tag: MarketplaceVersion version } && version.SdkVersion == MarketplaceRegistry.SdkVersion && _session.Settings?.EnablePlugins != false;
                confirm.Click += (_, _) => RefreshEnabled();
                versions.SelectionChanged += (_, _) => RefreshEnabled();
                var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
                install.Click += async (_, _) =>
                {
                    if (versions.SelectedItem is not ComboBoxItem { Tag: MarketplaceVersion version }) { return; }
                    install.IsEnabled = false;
                    try
                    {
                        await _session.CallMutationAsync(isInstalled ? "plugins.update" : "plugins.install", new JsonObject { ["pluginId"] = plugin.PluginId, ["version"] = version.Version });
                        status.Text = L10n.T("marketplaceInstallSuccess", ns: "settings", ("name", plugin.Name));
                        isInstalled = true;
                        install.Content = L10n.T("marketplaceUpdateBtn", ns: "settings");
                        confirm.IsChecked = false;
                    }
                    catch (Exception exception) { status.Text = exception.Message; }
                    finally { RefreshEnabled(); }
                };
                row.Children.Add(install); row.Children.Add(status); rows.Children.Add(row);
            }
        }
        filter.TextChanged += (_, _) => Render();
        Render();
        await NavigationDialog(L10n.T("marketplaceTitle", ns: "settings"), new ScrollViewer { Content = panel, MaxHeight = 540 }).ShowAsync();
    }
}
