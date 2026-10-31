using System.Collections.ObjectModel;
using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task<FrameworkElement> BuildPluginSettingsAsync()
    {
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var filter = new TextBox { PlaceholderText = L10n.T("marketplaceSearchPlaceholder", ns: "settings") };
        var rows = new StackPanel { Spacing = 10 };
        var installed = new List<JsonObject>();
        async Task ReloadAsync()
        {
            var response = await _session.CallQueryAsync("plugins.get");
            installed = (response?["plugins"] as JsonArray)?.OfType<JsonObject>().ToList() ?? [];
            Render();
        }
        void Render()
        {
            rows.Children.Clear();
            foreach (var plugin in installed.Where(plugin => (plugin["name"]?.AsString() ?? plugin["id"]?.AsString() ?? "").Contains(filter.Text.Trim(), StringComparison.CurrentCultureIgnoreCase)))
            {
                var id = plugin["id"]?.AsString() ?? "";
                var name = plugin["name"]?.AsString() ?? id;
                var row = new StackPanel { Spacing = 6 };
                var enabled = new CheckBox { Content = $"{name} · {plugin["version"]?.AsString() ?? ""}", IsChecked = plugin["enabled"]?.AsBool() == true, IsEnabled = _session.Settings?.EnablePlugins != false };
                enabled.Checked += async (_, _) => { if (enabled.Tag is not true) { await SetPluginEnabledAsync(id, true, enabled, status); } };
                enabled.Unchecked += async (_, _) => { if (enabled.Tag is not true) { await SetPluginEnabledAsync(id, false, enabled, status); } };
                row.Children.Add(enabled);
                if (plugin["description"]?.AsString() is { } description) { row.Children.Add(new TextBlock { Text = description, TextWrapping = TextWrapping.Wrap }); }
                if (plugin["loadError"]?.AsString() is { } error) { row.Children.Add(new TextBlock { Text = error, TextWrapping = TextWrapping.Wrap }); }
                var details = new Button { Content = L10n.T("detailsTitle", ns: "settings") };
                details.Click += async (_, _) =>
                {
                    try { await ShowPluginDetailsAsync(plugin); }
                    catch (Exception exception) { status.Text = exception.Message; }
                };
                var remove = new Button { Content = L10n.T("removeBtn", ns: "settings") };
                remove.Click += async (_, _) =>
                {
                    var confirm = NavigationDialog(L10n.T("removePluginTitle", ns: "settings"), new TextBlock { Text = L10n.T("removePluginConfirm", ns: "settings", ("name", name)), TextWrapping = TextWrapping.Wrap });
                    confirm.PrimaryButtonText = L10n.T("removeBtn", ns: "settings");
                    if (await confirm.ShowAsync() != ContentDialogResult.Primary) { return; }
                    try { await _session.CallMutationAsync("plugins.remove", new JsonObject { ["pluginId"] = id }); await ReloadAsync(); }
                    catch (Exception exception) { status.Text = exception.Message; }
                };
                var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                actions.Children.Add(details); actions.Children.Add(remove);
                row.Children.Add(actions); rows.Children.Add(row);
            }
        }
        filter.TextChanged += (_, _) => Render();
        var marketplace = new Button { Content = L10n.T("marketplaceTab", ns: "settings"), IsEnabled = _session.Settings?.EnablePlugins != false };
        marketplace.Click += async (_, _) =>
        {
            marketplace.IsEnabled = false;
            try { await ShowPluginMarketplaceAsync(installed); await ReloadAsync(); }
            catch (Exception exception) { status.Text = exception.Message; }
            finally { marketplace.IsEnabled = _session.Settings?.EnablePlugins != false; }
        };
        var refresh = new Button { Content = L10n.T("refreshBtn", ns: "settings") };
        refresh.Click += async (_, _) =>
        {
            try { await ReloadAsync(); }
            catch (Exception exception) { status.Text = exception.Message; }
        };
        await ReloadAsync();
        var panel = new StackPanel { Spacing = 12, Margin = new Thickness(16) };
        panel.Children.Add(marketplace); panel.Children.Add(refresh); panel.Children.Add(filter); panel.Children.Add(status); panel.Children.Add(rows);
        return new ScrollViewer { Content = panel };
    }

    private async Task ShowPluginDetailsAsync(JsonObject plugin)
    {
        var id = plugin["id"]?.AsString() ?? "";
        var pivot = new Pivot { Width = 720, Height = 500 };
        var details = new StackPanel { Spacing = 10, Margin = new Thickness(12) };
        foreach (var key in new[] { "name", "version", "author", "description", "loadError" })
        {
            if (plugin[key]?.AsString() is { } value) { details.Children.Add(new TextBlock { Text = value, TextWrapping = TextWrapping.Wrap }); }
        }
        pivot.Items.Add(new PivotItem { Header = L10n.T("detailsTitle", ns: "settings"), Content = details });
        var settings = BuildPluginSectionAsync(() => BuildPluginFieldsAsync(id));
        var commands = BuildPluginSectionAsync(() => BuildPluginCommandsAsync(id));
        var permissions = Task.FromResult<FrameworkElement>(new TextBlock { Text = L10n.T("pluginNoCapabilities", ns: "settings") });
        if (_session.HasPermission("MANAGE_PLUGIN_PERMISSIONS")) { permissions = BuildPluginSectionAsync(() => BuildPluginCapabilitiesAsync(id)); }
        await Task.WhenAll(settings, commands, permissions);
        pivot.Items.Add(new PivotItem { Header = L10n.T("pluginSettingsTab", ns: "settings"), Content = await settings });
        pivot.Items.Add(new PivotItem { Header = L10n.T("pluginCommandsTab", ns: "settings"), Content = await commands });
        if (_session.HasPermission("MANAGE_PLUGIN_PERMISSIONS")) { pivot.Items.Add(new PivotItem { Header = L10n.T("pluginPermissionsTab", ns: "settings"), Content = await permissions }); }
        using var cancellation = new CancellationTokenSource();
        var logs = new ObservableCollection<string>();
        var logList = new ListView { ItemsSource = logs, SelectionMode = ListViewSelectionMode.None };
        var logPanel = new Grid();
        logPanel.Children.Add(logList);
        pivot.Items.Add(new PivotItem { Header = L10n.T("logsTitle", ns: "settings"), Content = logPanel });
        try
        {
            var initial = await _session.CallQueryAsync("plugins.getLogs", new JsonObject { ["pluginId"] = id });
            foreach (var log in initial as JsonArray ?? []) { if (log is not null) { logs.Add(PluginLogText(log)); } }
        }
        catch (Exception exception) { logs.Add(exception.Message); }
        var streaming = ReadPluginLogsAsync(id, logs, cancellation.Token);
        var dialog = NavigationDialog(plugin["name"]?.AsString() ?? id, pivot);
        try { await dialog.ShowAsync(); }
        finally { cancellation.Cancel(); await streaming; }
    }

    private static async Task<FrameworkElement> BuildPluginSectionAsync(Func<Task<FrameworkElement>> build)
    {
        try { return await build(); }
        catch (Exception exception) { return new TextBlock { Text = exception.Message, TextWrapping = TextWrapping.Wrap }; }
    }

    private async Task ReadPluginLogsAsync(string id, ObservableCollection<string> logs, CancellationToken cancellationToken)
    {
        try
        {
            await foreach (var log in _session.StreamPluginLogsAsync(id, cancellationToken))
            {
                DispatcherQueue.TryEnqueue(() => { if (cancellationToken.IsCancellationRequested) { return; } logs.Add(PluginLogText(log)); if (logs.Count > 1000) { logs.RemoveAt(0); } });
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception exception) { DispatcherQueue.TryEnqueue(() => logs.Add(exception.Message)); }
    }

    private static string PluginLogText(JsonNode log) => $"{DateTimeOffset.FromUnixTimeMilliseconds(log["timestamp"]?.GetValue<long>() ?? 0).LocalDateTime:T} · {log["type"]?.AsString()} · {log["message"]?.AsString()}";
}
