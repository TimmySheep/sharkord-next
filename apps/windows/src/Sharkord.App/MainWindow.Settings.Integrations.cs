using System.Text.Json.Nodes;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task SetPluginEnabledAsync(string pluginId, bool enabled, CheckBox control, TextBlock status)
    {
        control.IsEnabled = false;
        try
        {
            await _session.CallMutationAsync("plugins.toggle", new JsonObject
            {
                ["pluginId"] = pluginId,
                ["enabled"] = enabled
            });
            status.Text = "";
        }
        catch (Exception exception)
        {
            control.Tag = true;
            control.IsChecked = !enabled;
            control.Tag = null;
            status.Text = exception.Message;
        }
        finally
        {
            control.IsEnabled = true;
        }

    }

    private async Task<FrameworkElement> BuildUpdateSettingsAsync()
    {
        var info = await _session.CallQueryAsync("others.getUpdate") as JsonObject
            ?? throw new InvalidOperationException("Update information was not returned by the server");
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var versionPanel = new StackPanel { Spacing = 8, Margin = new Thickness(20) };
        var currentVersion = info["currentVersion"]?.GetValue<string>() ?? "";
        var latestVersion = info["latestVersion"]?.GetValue<string>() ?? "";
        AddUpdateValue(versionPanel, "currentVersionLabel", currentVersion);
        AddUpdateValue(versionPanel, "latestVersionLabel", latestVersion);
        var hasUpdate = info["hasUpdate"]?.GetValue<bool>() ?? false;
        if (hasUpdate)
        {
            versionPanel.Children.Add(new TextBlock
            {
                Text = L10n.T("updateAvailableDesc", ns: "settings", ("version", latestVersion)),
                Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Colors.DarkOrange),
                TextWrapping = TextWrapping.Wrap
            });
            var canUpdate = info["canUpdate"]?.GetValue<bool>() ?? false;
            var update = new Button
            {
                Content = L10n.T("updateServerBtn", ns: "settings"),
                IsEnabled = canUpdate
            };
            update.Click += async (_, _) =>
            {
                var confirmation = new ContentDialog
                {
                    Title = L10n.T("updateServerBtn", ns: "settings"),
                    Content = L10n.T("updateAvailableDesc", ns: "settings", ("version", latestVersion)),
                    PrimaryButtonText = L10n.T("updateServerBtn", ns: "settings"),
                    CloseButtonText = L10n.T("close", ns: "windows"),
                    XamlRoot = RootGrid.XamlRoot
                };
                if (await confirmation.ShowAsync() != ContentDialogResult.Primary)
                {
                    return;
                }

                update.IsEnabled = false;
                try
                {
                    await _session.CallMutationAsync("others.updateServer");
                    status.Text = L10n.T("serverUpdateInitiated", ns: "common");
                }
                catch (Exception exception)
                {
                    status.Text = exception.Message;
                    update.IsEnabled = canUpdate;
                }
            };
            versionPanel.Children.Add(update);
            if (!canUpdate)
            {
                versionPanel.Children.Add(new TextBlock
                {
                    Text = L10n.T("updatesNotSupportedDesc", ns: "settings"),
                    TextWrapping = TextWrapping.Wrap,
                    Opacity = 0.75
                });
            }
        }
        else
        {
            versionPanel.Children.Add(new TextBlock
            {
                Text = L10n.T("upToDateDesc", ns: "settings"),
                TextWrapping = TextWrapping.Wrap
            });
        }

        versionPanel.Children.Add(status);
        return new ScrollViewer { Content = versionPanel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private static void AddUpdateValue(StackPanel panel, string labelKey, string value)
    {
        var row = new Grid { ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(new TextBlock { Text = L10n.T(labelKey, ns: "settings") });
        var valueText = new TextBlock
        {
            Text = value,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas")
        };
        Grid.SetColumn(valueText, 1);
        row.Children.Add(valueText);
        panel.Children.Add(row);
    }

}
