using System.Text.Json.Nodes;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task<FrameworkElement> BuildStorageSettingsAsync()
    {
        var result = await _session.CallQueryAsync("others.getStorageSettings") as JsonObject
            ?? throw new InvalidOperationException("Storage settings were not returned by the server");
        var settings = result["storageSettings"] as JsonObject
            ?? throw new InvalidOperationException("Storage settings were missing from the server response");
        var uploads = new CheckBox
        {
            Content = L10n.T("allowUploadsLabel", ns: "settings"),
            IsChecked = settings["storageUploadEnabled"]?.GetValue<bool>() ?? true
        };
        var maxFileSize = new NumberBox
        {
            Header = L10n.T("maxFileSizeLabel", ns: "settings"),
            Value = settings["storageUploadMaxFileSize"]?.GetValue<double>() ?? 0,
            Minimum = 0,
            Maximum = long.MaxValue,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact
        };
        var maxFiles = new NumberBox
        {
            Header = L10n.T("maxFilesPerMessageLabel", ns: "settings"),
            Value = settings["storageMaxFilesPerMessage"]?.GetValue<double>() ?? 10,
            Minimum = 0,
            Maximum = 20,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact
        };
        var dmSharing = new CheckBox
        {
            Content = L10n.T("allowFileSharingInDMsLabel", ns: "settings"),
            IsChecked = settings["storageFileSharingInDirectMessages"]?.GetValue<bool>() ?? true
        };
        var quota = new NumberBox
        {
            Header = L10n.T("quotaPerUserLabel", ns: "settings"),
            Value = settings["storageSpaceQuotaByUser"]?.GetValue<double>() ?? 0,
            Minimum = 0,
            Maximum = long.MaxValue,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact
        };
        var overflow = new ComboBox
        {
            Header = L10n.T("overflowActionLabel", ns: "settings"),
            SelectedValuePath = "Tag",
            MinWidth = 240
        };
        overflow.Items.Add(new ComboBoxItem
        {
            Content = L10n.T("overflowDeleteOldFiles", ns: "settings"),
            Tag = "delete"
        });
        overflow.Items.Add(new ComboBoxItem
        {
            Content = L10n.T("overflowPreventUploads", ns: "settings"),
            Tag = "prevent"
        });
        overflow.SelectedValue = settings["storageOverflowAction"]?.GetValue<string>() ?? "delete";
        var signedUrls = new CheckBox
        {
            Content = L10n.T("signedUrlsLabel", ns: "settings"),
            IsChecked = settings["storageSignedUrlsEnabled"]?.GetValue<bool>() ?? true
        };
        var imageOptimization = new CheckBox
        {
            Content = L10n.T("imageOptimizationLabel", ns: "settings"),
            IsChecked = settings["storageImageOptimizationEnabled"]?.GetValue<bool>() ?? true
        };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var metrics = result["diskMetrics"] as JsonObject;
        var pluginStorage = result["pluginStorage"] as JsonArray;
        var diskSummary = new StackPanel { Spacing = 4 };
        diskSummary.Children.Add(new TextBlock
        {
            Text = L10n.T("diskUsage", ns: "settings"),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        AddDiskMetric(diskSummary, metrics, "totalSpace", "diskTotalSpace");
        AddDiskMetric(diskSummary, metrics, "sharkordUsedSpace", "diskSharkordUsed");
        AddDiskMetric(diskSummary, metrics, "freeSpace", "diskAvailableSpace");
        var pluginSummary = new StackPanel { Spacing = 4 };
        if (pluginStorage is { Count: > 0 })
        {
            pluginSummary.Children.Add(new TextBlock
            {
                Text = L10n.T("pluginStorageTitle", ns: "settings"),
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            foreach (var plugin in pluginStorage.OfType<JsonObject>())
            {
                var pluginId = plugin["pluginId"]?.GetValue<string>() ?? "";
                var usedSpace = plugin["usedSpace"]?.GetValue<long>() ?? 0;
                pluginSummary.Children.Add(new TextBlock { Text = $"{pluginId}: {FormatBytes(usedSpace)}" });
            }
        }

        var save = new Button
        {
            Content = L10n.T("saveChanges", ns: "settings"),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        save.Click += async (_, _) =>
        {
            if (!double.IsFinite(maxFileSize.Value) || Math.Truncate(maxFileSize.Value) != maxFileSize.Value
                || !double.IsFinite(maxFiles.Value) || Math.Truncate(maxFiles.Value) != maxFiles.Value
                || !double.IsFinite(quota.Value) || Math.Truncate(quota.Value) != quota.Value
                || overflow.SelectedValue is not string overflowValue)
            {
                status.Text = L10n.T(
                    "pluginInvalidNumber",
                    ns: "macos",
                    ("name", L10n.T("storageTitle", ns: "settings"))
                );
                return;
            }

            save.IsEnabled = false;
            try
            {
                await _session.UpdateAdminSettingsAsync(new JsonObject
                {
                    ["storageUploadEnabled"] = uploads.IsChecked ?? true,
                    ["storageUploadMaxFileSize"] = (long)maxFileSize.Value,
                    ["storageMaxFilesPerMessage"] = (int)maxFiles.Value,
                    ["storageFileSharingInDirectMessages"] = dmSharing.IsChecked ?? true,
                    ["storageSpaceQuotaByUser"] = (long)quota.Value,
                    ["storageOverflowAction"] = overflowValue,
                    ["storageSignedUrlsEnabled"] = signedUrls.IsChecked ?? true,
                    ["storageImageOptimizationEnabled"] = imageOptimization.IsChecked ?? true
                });
                status.Text = L10n.T("storageSettingsUpdated", ns: "settings");
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                save.IsEnabled = true;
            }
        };

        var form = new StackPanel { Spacing = 12, Margin = new Thickness(20) };
        form.Children.Add(diskSummary);
        form.Children.Add(uploads);
        form.Children.Add(new TextBlock
        {
            Text = L10n.T("allowUploadsDesc", ns: "settings"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        });
        form.Children.Add(maxFileSize);
        form.Children.Add(maxFiles);
        form.Children.Add(dmSharing);
        form.Children.Add(new TextBlock
        {
            Text = L10n.T("allowFileSharingInDMsDesc", ns: "settings"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        });
        form.Children.Add(quota);
        form.Children.Add(overflow);
        form.Children.Add(signedUrls);
        form.Children.Add(new TextBlock
        {
            Text = L10n.T("signedUrlsDesc", ns: "settings"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        });
        form.Children.Add(imageOptimization);
        form.Children.Add(new TextBlock
        {
            Text = L10n.T("imageOptimizationDesc", ns: "settings"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        });
        if (pluginSummary.Children.Count > 0)
        {
            form.Children.Add(pluginSummary);
        }
        form.Children.Add(status);
        form.Children.Add(save);
        return new ScrollViewer { Content = form, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private static void AddDiskMetric(StackPanel summary, JsonObject? metrics, string key, string labelKey)
    {
        var bytes = metrics?[key]?.GetValue<long>();
        summary.Children.Add(new TextBlock
        {
            Text = bytes is null
                ? L10n.T(labelKey, ns: "settings")
                : $"{L10n.T(labelKey, ns: "settings")}: {FormatBytes(bytes.Value)}"
        });
    }

    private static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var size = (double)bytes;
        var unit = 0;

        while (size >= 1024 && unit < units.Length - 1)
        {
            size /= 1024;
            unit++;
        }

        return $"{size:0.##} {units[unit]}";
    }

    private async Task<FrameworkElement> BuildGeneralServerSettingsAsync()
    {
        var settings = await _session.GetAdminSettingsAsync() as JsonObject
            ?? throw new InvalidOperationException("Server settings were not returned by the server");
        var name = new TextBox
        {
            Header = L10n.T("nameLabel", ns: "settings"),
            Text = settings["name"]?.GetValue<string>() ?? ""
        };
        var description = new TextBox
        {
            Header = L10n.T("descriptionLabel", ns: "settings"),
            Text = settings["description"]?.GetValue<string>() ?? "",
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 72
        };
        var password = new PasswordBox
        {
            Header = L10n.T("serverPasswordLabel", ns: "settings"),
            PlaceholderText = L10n.T("serverPasswordPlaceholder", ns: "settings")
        };
        var removePassword = new CheckBox { Content = L10n.T("deleteBtn", ns: "settings") };
        removePassword.Checked += (_, _) => password.IsEnabled = false;
        removePassword.Unchecked += (_, _) => password.IsEnabled = true;
        var allowNewUsers = new CheckBox
        {
            Content = L10n.T("allowNewUsersLabel", ns: "settings"),
            IsChecked = settings["allowNewUsers"]?.GetValue<bool>() ?? true
        };
        var directMessages = new CheckBox
        {
            Content = L10n.T("directMessagesEnabledLabel", ns: "settings"),
            IsChecked = settings["directMessagesEnabled"]?.GetValue<bool>() ?? true
        };
        var search = new CheckBox
        {
            Content = L10n.T("searchEnabledLabel", ns: "settings"),
            IsChecked = settings["enableSearch"]?.GetValue<bool>() ?? true
        };
        var plugins = new CheckBox
        {
            Content = L10n.T("pluginsLabel", ns: "settings"),
            IsChecked = settings["enablePlugins"]?.GetValue<bool>() ?? true
        };
        var simulcast = new CheckBox
        {
            Content = L10n.T("simulcastLabel", ns: "settings"),
            IsChecked = settings["webRtcSimulcastEnabled"]?.GetValue<bool>() ?? false
        };
        var welcome = new CheckBox
        {
            Content = L10n.T("showWelcomeDialogLabel", ns: "settings"),
            IsChecked = settings["showWelcomeDialog"]?.GetValue<bool>() ?? true
        };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var save = new Button
        {
            Content = L10n.T("saveChanges", ns: "settings"),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        save.Click += async (_, _) =>
        {
            save.IsEnabled = false;
            try
            {
                var updatedSettings = new JsonObject
                {
                    ["name"] = name.Text,
                    ["description"] = description.Text,
                    ["allowNewUsers"] = allowNewUsers.IsChecked ?? true,
                    ["directMessagesEnabled"] = directMessages.IsChecked ?? true,
                    ["enableSearch"] = search.IsChecked ?? true,
                    ["enablePlugins"] = plugins.IsChecked ?? true,
                    ["webRtcSimulcastEnabled"] = simulcast.IsChecked ?? false,
                    ["showWelcomeDialog"] = welcome.IsChecked ?? true
                };
                if (removePassword.IsChecked == true)
                {
                    updatedSettings["password"] = null;
                }
                else if (!string.IsNullOrEmpty(password.Password))
                {
                    updatedSettings["password"] = password.Password;
                }

                await _session.UpdateAdminSettingsAsync(updatedSettings);
                status.Text = L10n.T("settingsUpdated", ns: "settings");
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                save.IsEnabled = true;
            }
        };

        var form = new StackPanel { Spacing = 12, Margin = new Thickness(20) };
        form.Children.Add(name);
        form.Children.Add(description);
        form.Children.Add(password);
        form.Children.Add(removePassword);
        form.Children.Add(allowNewUsers);
        form.Children.Add(directMessages);
        form.Children.Add(search);
        form.Children.Add(plugins);
        form.Children.Add(simulcast);
        form.Children.Add(welcome);
        form.Children.Add(status);
        form.Children.Add(save);
        return new ScrollViewer { Content = form, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

}
