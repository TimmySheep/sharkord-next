using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;
using WinRT.Interop;
using Windows.Storage.Pickers;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task<FrameworkElement> BuildUserSettingsAsync()
    {
        var users = new List<JsonObject>();
        var search = new TextBox
        {
            PlaceholderText = L10n.T("searchUsersPlaceholder", ns: "settings")
        };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var rows = new StackPanel { Spacing = 8 };

        async Task RunUserActionAsync(string path, JsonObject input, string title, string name)
        {
            var reason = new TextBox { Header = L10n.T("banReason", ns: "admin"), MaxLength = 1000, AcceptsReturn = true };
            var wipe = new CheckBox { Content = L10n.T("wipeUserData", ns: "admin") };
            var confirmation = new StackPanel { Spacing = 12 };
            confirmation.Children.Add(new TextBlock { Text = name, TextWrapping = TextWrapping.Wrap });
            if (path == "users.ban") { confirmation.Children.Add(reason); }
            if (path == "users.delete") { confirmation.Children.Add(wipe); }
            var confirm = new ContentDialog
            {
                Title = title,
                Content = confirmation,
                PrimaryButtonText = title,
                CloseButtonText = L10n.T("close", ns: "windows"),
                XamlRoot = RootGrid.XamlRoot
            };
            if (await confirm.ShowAsync() != ContentDialogResult.Primary)
            {
                return;
            }

            try
            {
                if (path == "users.ban" && !string.IsNullOrWhiteSpace(reason.Text)) { input["reason"] = reason.Text.Trim(); }
                if (path == "users.delete") { input["wipe"] = wipe.IsChecked == true; }
                await _session.CallMutationAsync(path, input);
                await ReloadAsync();
                status.Text = "";
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
        }

        void RenderRows()
        {
            rows.Children.Clear();
            var query = search.Text.Trim();
            foreach (var user in users.Where(user =>
                         string.IsNullOrEmpty(query)
                         || (user["name"]?.GetValue<string>() ?? "").Contains(query, StringComparison.CurrentCultureIgnoreCase)
                         || (user["identity"]?.GetValue<string>() ?? "").Contains(query, StringComparison.CurrentCultureIgnoreCase)))
            {
                var userId = user["id"]?.GetValue<int>() ?? 0;
                var userName = user["name"]?.GetValue<string>() ?? "";
                var banned = user["banned"]?.GetValue<bool>() ?? false;
                var identity = user["identity"]?.GetValue<string>() ?? "";
                var details = new Button { Content = L10n.T("detailsTitle", ns: "settings") };
                details.Click += async (_, _) =>
                {
                    try
                    {
                        await ShowUserModerationAsync(userId, userName);

                    }
                    catch (Exception exception)
                    {
                        status.Text = exception.Message;
                    }
                };

                var row = new Grid { ColumnSpacing = 10, Margin = new Thickness(0, 0, 0, 8) };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var identityText = new TextBlock
                {
                    Text = string.IsNullOrEmpty(identity) ? userName : $"{userName}\n{identity}",
                    TextWrapping = TextWrapping.Wrap,
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(identityText, 0);
                Grid.SetColumn(details, 1);
                row.Children.Add(identityText);
                row.Children.Add(details);
                var contextMenu = new MenuFlyout();
                var actionLabel = banned ? "unbanBtn" : "banBtn";
                var actionPath = banned ? "users.unban" : "users.ban";
                var actionInput = new JsonObject { ["userId"] = userId };
                var mayModerate = userId != _session.OwnUserId && (_session.User(userId)?.RoleIds?.Contains(1) != true || _session.OwnUser?.RoleIds?.Contains(1) == true);
                var action = new MenuFlyoutItem { Text = L10n.T(actionLabel, ns: "settings"), IsEnabled = mayModerate };
                action.Click += async (_, _) => await RunUserActionAsync(
                    actionPath,
                    actionInput,
                    L10n.T(actionLabel, ns: "settings"),
                    userName
                );
                contextMenu.Items.Add(action);
                if (!banned)
                {
                    var kick = new MenuFlyoutItem { Text = L10n.T("kickBtn", ns: "settings"), IsEnabled = mayModerate };
                    kick.Click += async (_, _) => await RunUserActionAsync(
                        "users.kick",
                        new JsonObject { ["userId"] = userId },
                        L10n.T("kickBtn", ns: "settings"),
                        userName
                    );
                    contextMenu.Items.Add(kick);
                }

                var delete = new MenuFlyoutItem { Text = L10n.T("deleteBtn", ns: "settings"), IsEnabled = mayModerate };
                delete.Click += async (_, _) => await RunUserActionAsync(
                    "users.delete",
                    new JsonObject { ["userId"] = userId, ["wipe"] = false },
                    L10n.T("deleteBtn", ns: "settings"),
                    userName
                );
                contextMenu.Items.Add(delete);
                row.ContextFlyout = contextMenu;
                rows.Children.Add(row);
            }
        }

        async Task ReloadAsync()
        {
            var result = await _session.CallQueryAsync("users.getAll") as JsonArray;
            users = result?.OfType<JsonObject>().ToList() ?? [];
            RenderRows();
        }

        search.TextChanged += (_, _) => RenderRows();
        var refresh = new Button { Content = L10n.T("refreshBtn", ns: "settings") };
        refresh.Click += async (_, _) =>
        {
            refresh.IsEnabled = false;
            try
            {
                await ReloadAsync();
                status.Text = "";
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                refresh.IsEnabled = true;
            }
        };
        await ReloadAsync();

        var form = new StackPanel { Spacing = 10, Margin = new Thickness(20) };
        form.Children.Add(search);
        form.Children.Add(refresh);
        form.Children.Add(status);
        form.Children.Add(rows);
        return new ScrollViewer { Content = form, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private async Task<FrameworkElement> BuildInviteSettingsAsync()
    {
        var invites = new List<JsonObject>();
        var rows = new StackPanel { Spacing = 8 };
        var customCode = new TextBox { Header = L10n.T("inviteCodeLabel", ns: "macos"), MaxLength = 64 };
        var assignedRole = new ComboBox { Header = L10n.T("assignRoleLabel", ns: "dialogs"), HorizontalAlignment = HorizontalAlignment.Stretch };
        assignedRole.Items.Add(new ComboBoxItem { Content = L10n.T("roleDefault", ns: "dialogs"), Tag = 0 });
        foreach (var role in _session.Roles) { assignedRole.Items.Add(new ComboBoxItem { Content = role.Name, Tag = role.Id }); }
        assignedRole.SelectedIndex = 0;
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var maxUses = new NumberBox
        {
            Header = L10n.T("maxUsesLabel", ns: "dialogs"),
            Value = 0,
            Minimum = 0,
            Maximum = 100,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact
        };
        var expiryDays = new NumberBox
        {
            Header = L10n.T("expiresInLabel", ns: "dialogs"),
            Value = 7,
            Minimum = 0,
            Maximum = 365,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact
        };

        async Task ReloadAsync()
        {
            var result = await _session.CallQueryAsync("invites.getAll") as JsonArray;
            invites = result?.OfType<JsonObject>().ToList() ?? [];
            rows.Children.Clear();
            foreach (var invite in invites)
            {
                var inviteId = invite["id"]?.GetValue<int>() ?? 0;
                var code = invite["code"]?.GetValue<string>() ?? "";
                var uses = invite["uses"]?.GetValue<int>() ?? 0;
                var limit = invite["maxUses"]?.GetValue<int?>();
                var row = new Grid { ColumnSpacing = 10, Margin = new Thickness(0, 0, 0, 8) };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var codeText = new TextBlock
                {
                    Text = $"{code}  {uses}/{limit?.ToString() ?? "∞"}",
                    FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
                    VerticalAlignment = VerticalAlignment.Center,
                    TextTrimming = TextTrimming.CharacterEllipsis
                };
                var copy = new Button { Content = L10n.T("copyInviteLink", ns: "settings") };
                copy.Click += (_, _) =>
                {
                    var url = $"{_session.ServerBaseUrl}?invite={Uri.EscapeDataString(code)}";
                    var data = new Windows.ApplicationModel.DataTransfer.DataPackage();
                    data.SetText(url);
                    Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(data);
                    status.Text = L10n.T("inviteCopied", ns: "settings");
                };
                var delete = new Button { Content = L10n.T("deleteBtn", ns: "settings") };
                delete.Click += async (_, _) =>
                {
                    var confirmation = new ContentDialog
                    {
                        Title = L10n.T("deleteBtn", ns: "settings"),
                        Content = code,
                        PrimaryButtonText = L10n.T("deleteBtn", ns: "settings"),
                        CloseButtonText = L10n.T("close", ns: "windows"),
                        XamlRoot = RootGrid.XamlRoot
                    };
                    if (await confirmation.ShowAsync() != ContentDialogResult.Primary)
                    {
                        return;
                    }

                    try
                    {
                        await _session.CallMutationAsync("invites.delete", new JsonObject { ["inviteId"] = inviteId });
                        await ReloadAsync();
                        status.Text = "";
                    }
                    catch (Exception exception)
                    {
                        status.Text = exception.Message;
                    }
                };
                Grid.SetColumn(codeText, 0);
                Grid.SetColumn(copy, 1);
                Grid.SetColumn(delete, 2);
                row.Children.Add(codeText);
                row.Children.Add(copy);
                row.Children.Add(delete);
                rows.Children.Add(row);
            }
        }

        var create = new Button
        {
            Content = L10n.T("createInviteBtn", ns: "settings"),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        create.Click += async (_, _) =>
        {
            if (!double.IsFinite(maxUses.Value) || Math.Truncate(maxUses.Value) != maxUses.Value
                || !double.IsFinite(expiryDays.Value) || Math.Truncate(expiryDays.Value) != expiryDays.Value)
            {
                status.Text = L10n.T("pluginInvalidNumber", ns: "macos", ("name", L10n.T("invitesTitle", ns: "settings")));
                return;
            }

            var inviteCode = customCode.Text.Trim();
            if (inviteCode.Length > 0 && (inviteCode.Length < 4 || !Regex.IsMatch(inviteCode, "^[A-Za-z0-9_-]+$")))
            {
                status.Text = L10n.T("invalidField", ns: "admin", ("name", L10n.T("inviteCodeLabel", ns: "macos")));
                return;
            }

            create.IsEnabled = false;
            try
            {
                var input = new JsonObject();
                if (!string.IsNullOrWhiteSpace(customCode.Text)) { input["code"] = customCode.Text.Trim(); }
                if (assignedRole.SelectedItem is ComboBoxItem { Tag: int roleId } && roleId > 0) { input["roleId"] = roleId; }
                if (maxUses.Value > 0)
                {
                    input["maxUses"] = (int)maxUses.Value;
                }
                if (expiryDays.Value > 0)
                {
                    input["expiresAt"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                        + (long)expiryDays.Value * 86_400_000;
                }

                await _session.CallMutationAsync("invites.add", input);
                await ReloadAsync();
                status.Text = "";
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                create.IsEnabled = true;
            }
        };

        await ReloadAsync();
        var form = new StackPanel { Spacing = 10, Margin = new Thickness(20) };
        form.Children.Add(customCode);
        form.Children.Add(assignedRole);
        form.Children.Add(maxUses);
        form.Children.Add(expiryDays);
        form.Children.Add(create);
        form.Children.Add(status);
        form.Children.Add(rows);
        return new ScrollViewer { Content = form, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private async Task<FrameworkElement> BuildRoleSettingsAsync()
    {
        string[] permissions =
        [
            "SEND_MESSAGES", "REACT_TO_MESSAGES", "PIN_MESSAGES", "UPLOAD_FILES",
            "JOIN_VOICE_CHANNELS", "SHARE_SCREEN", "ENABLE_WEBCAM", "SEND_VOICE_REACTION",
            "MANAGE_CHANNELS", "MANAGE_CHANNEL_PERMISSIONS", "MANAGE_CATEGORIES", "MANAGE_ROLES",
            "MANAGE_EMOJIS", "MANAGE_SETTINGS", "MANAGE_USERS", "MOVE_MEMBERS", "MANAGE_MESSAGES",
            "MANAGE_STORAGE", "MANAGE_INVITES", "MANAGE_UPDATES", "MANAGE_PLUGINS",
            "MANAGE_PLUGIN_PERMISSIONS", "USE_PLUGINS", "VIEW_USER_SENSITIVE_DATA"
        ];
        var roles = new List<JsonObject>();
        JsonObject? selectedRole = null;
        var name = new TextBox { Header = L10n.T("roleNameLabel", ns: "settings") };
        var color = new TextBox { Header = L10n.T("roleColorLabel", ns: "settings"), Text = "#1447E6" };
        var quotaOverride = new CheckBox { Content = L10n.T("roleStorageOverrideLabel", ns: "settings") };
        var quota = new NumberBox
        {
            Header = L10n.T("roleStorageQuotaLabel", ns: "settings"),
            Value = 0,
            Minimum = 0,
            Maximum = int.MaxValue,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact
        };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var permissionList = new StackPanel { Spacing = 2 };
        var roleList = new StackPanel { Spacing = 4 };

        void SelectRole(JsonObject? role)
        {
            selectedRole = role;
            name.Text = role?["name"]?.GetValue<string>() ?? "";
            color.Text = role?["color"]?.GetValue<string>() ?? "#1447E6";
            quotaOverride.IsChecked = role?["storageQuotaOverrideEnabled"]?.GetValue<bool>() ?? false;
            quota.Value = role?["storageSpaceQuota"]?.GetValue<double>() ?? 0;
            var assigned = (role?["permissions"] as JsonArray)?.Select(node => node?.GetValue<string>() ?? "")
                .ToHashSet(StringComparer.Ordinal) ?? [];
            permissionList.Children.Clear();
            foreach (var permission in permissions)
            {
                permissionList.Children.Add(new CheckBox
                {
                    Content = L10n.T($"server.{permission}", ns: "permissions"),
                    Tag = permission,
                    IsChecked = assigned.Contains(permission)
                });
            }
        }

        async Task ReloadRolesAsync()
        {
            var result = await _session.CallQueryAsync("roles.getAll") as JsonArray;
            roles = result?.OfType<JsonObject>().ToList() ?? [];
            roleList.Children.Clear();
            foreach (var role in roles)
            {
                var roleButton = new Button
                {
                    Content = role["name"]?.GetValue<string>() ?? "",
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Left
                };
                roleButton.Click += (_, _) => SelectRole(role);
                roleList.Children.Add(roleButton);
            }

            if (selectedRole is not null)
            {
                var selectedId = selectedRole["id"]?.GetValue<int>();
                SelectRole(roles.FirstOrDefault(role => role["id"]?.GetValue<int>() == selectedId));
            }
        }

        var add = new Button { Content = L10n.T("addRoleTooltip", ns: "settings") };
        add.Click += async (_, _) =>
        {
            try
            {
                await _session.CallMutationAsync("roles.add");
                await ReloadRolesAsync();
                SelectRole(roles.LastOrDefault());
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
        };
        var makeDefault = new Button { Content = L10n.T("roleDefault", ns: "dialogs") };
        makeDefault.Click += async (_, _) =>
        {
            if (selectedRole is null)
            {
                return;
            }

            try
            {
                await _session.CallMutationAsync("roles.setDefault", new JsonObject
                {
                    ["roleId"] = selectedRole["id"]?.GetValue<int>() ?? 0
                });
                await ReloadRolesAsync();
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
        };
        var delete = new Button { Content = L10n.T("deleteBtn", ns: "settings") };
        delete.Click += async (_, _) =>
        {
            if (selectedRole is null)
            {
                return;
            }

            var roleId = selectedRole["id"]?.GetValue<int>() ?? 0;
            var roleName = selectedRole["name"]?.GetValue<string>() ?? "";
            var confirmation = new ContentDialog
            {
                Title = L10n.T("deleteBtn", ns: "settings"),
                Content = roleName,
                PrimaryButtonText = L10n.T("deleteBtn", ns: "settings"),
                CloseButtonText = L10n.T("close", ns: "windows"),
                XamlRoot = RootGrid.XamlRoot
            };
            if (await confirmation.ShowAsync() != ContentDialogResult.Primary)
            {
                return;
            }

            try
            {
                await _session.CallMutationAsync("roles.delete", new JsonObject { ["roleId"] = roleId });
                SelectRole(null);
                await ReloadRolesAsync();
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
        };
        var save = new Button
        {
            Content = L10n.T("saveChanges", ns: "settings"),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        save.Click += async (_, _) =>
        {
            if (selectedRole is null || !double.IsFinite(quota.Value)
                || Math.Truncate(quota.Value) != quota.Value)
            {
                return;
            }

            var selectedPermissions = permissionList.Children
                .OfType<CheckBox>()
                .Where(checkBox => checkBox.IsChecked == true)
                .Select(checkBox => checkBox.Tag as string)
                .Where(permission => permission is not null)
                .Select(permission => permission!);
            save.IsEnabled = false;
            try
            {
                await _session.CallMutationAsync("roles.update", new JsonObject
                {
                    ["roleId"] = selectedRole["id"]?.GetValue<int>() ?? 0,
                    ["name"] = name.Text,
                    ["color"] = color.Text,
                    ["permissions"] = new JsonArray(
                        selectedPermissions.Select(permission => (JsonNode?)JsonValue.Create(permission)).ToArray()
                    ),
                    ["storageQuotaOverrideEnabled"] = quotaOverride.IsChecked ?? false,
                    ["storageSpaceQuota"] = (long)quota.Value
                });
                status.Text = L10n.T("roleUpdated", ns: "settings");
                await ReloadRolesAsync();
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

        await ReloadRolesAsync();
        var editor = new StackPanel { Spacing = 10, Margin = new Thickness(16) };
        editor.Children.Add(name);
        editor.Children.Add(color);
        editor.Children.Add(quotaOverride);
        editor.Children.Add(quota);
        editor.Children.Add(new TextBlock
        {
            Text = L10n.T("permissionsTab", ns: "settings"),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        editor.Children.Add(permissionList);
        editor.Children.Add(makeDefault);
        editor.Children.Add(delete);
        editor.Children.Add(save);
        editor.Children.Add(status);
        var sidebar = new StackPanel { Spacing = 10, Margin = new Thickness(16) };
        sidebar.Children.Add(roleList);
        sidebar.Children.Add(add);
        var layout = new Grid { ColumnSpacing = 12 };
        layout.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(220) });
        layout.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(sidebar, 0);
        Grid.SetColumn(editor, 1);
        layout.Children.Add(sidebar);
        layout.Children.Add(editor);
        return new ScrollViewer { Content = layout, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private async Task<FrameworkElement> BuildEmojiSettingsAsync()
    {
        var emojis = new List<JsonObject>();
        var search = new TextBox { PlaceholderText = L10n.T("searchEmojisPlaceholder", ns: "settings") };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var rows = new StackPanel { Spacing = 8 };

        void RenderEmojis()
        {
            rows.Children.Clear();
            var query = search.Text.Trim();
            var filtered = emojis.Where(emoji => string.IsNullOrEmpty(query)
                || (emoji["name"]?.GetValue<string>() ?? "").Contains(query, StringComparison.CurrentCultureIgnoreCase));
            foreach (var emoji in filtered)
            {
                var emojiId = emoji["id"]?.GetValue<int>() ?? 0;
                var emojiName = emoji["name"]?.GetValue<string>() ?? "";
                var name = new TextBox { Text = emojiName, MinWidth = 180 };
                var save = new Button { Content = L10n.T("editLabel", ns: "sidebar") };
                save.Click += async (_, _) =>
                {
                    try
                    {
                        await _session.CallMutationAsync("emojis.update", new JsonObject
                        {
                            ["emojiId"] = emojiId,
                            ["name"] = name.Text.Trim()
                        });
                        await ReloadAsync();
                        status.Text = "";
                    }
                    catch (Exception exception)
                    {
                        status.Text = exception.Message;
                    }
                };
                var delete = new Button { Content = L10n.T("deleteEmojiBtn", ns: "settings") };
                delete.Click += async (_, _) =>
                {
                    var confirmation = new ContentDialog
                    {
                        Title = L10n.T("deleteEmojiBtn", ns: "settings"),
                        Content = $":{emojiName}:",
                        PrimaryButtonText = L10n.T("deleteEmojiBtn", ns: "settings"),
                        CloseButtonText = L10n.T("close", ns: "windows"),
                        XamlRoot = RootGrid.XamlRoot
                    };
                    if (await confirmation.ShowAsync() != ContentDialogResult.Primary)
                    {
                        return;
                    }

                    try
                    {
                        await _session.CallMutationAsync("emojis.delete", new JsonObject { ["emojiId"] = emojiId });
                        await ReloadAsync();
                    }
                    catch (Exception exception)
                    {
                        status.Text = exception.Message;
                    }
                };
                var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                row.Children.Add(new TextBlock
                {
                    Text = $":{emojiName}:",
                    VerticalAlignment = VerticalAlignment.Center,
                    MinWidth = 140
                });
                row.Children.Add(name);
                row.Children.Add(save);
                row.Children.Add(delete);
                rows.Children.Add(row);
            }

            if (!rows.Children.Any())
            {
                rows.Children.Add(new TextBlock { Text = L10n.T("noCustomEmojisYet", ns: "settings") });
            }
        }

        async Task ReloadAsync()
        {
            var result = await _session.CallQueryAsync("emojis.getAll") as JsonArray;
            emojis = result?.OfType<JsonObject>().ToList() ?? [];
            RenderEmojis();
        }

        var upload = new Button { Content = L10n.T("uploadEmojiBtn", ns: "settings") };
        upload.Click += async (_, _) =>
        {
            var picker = new FileOpenPicker();
            foreach (var extension in new[] { ".png", ".jpg", ".jpeg", ".gif", ".webp" })
            {
                picker.FileTypeFilter.Add(extension);
            }
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            var files = await picker.PickMultipleFilesAsync();
            if (files.Count == 0)
            {
                return;
            }

            upload.IsEnabled = false;
            try
            {
                foreach (var file in files)
                {
                    var fileId = await _session.UploadAttachmentAsync(
                        await File.ReadAllBytesAsync(file.Path),
                        file.Name,
                        file.ContentType
                    );
                    var name = Path.GetFileNameWithoutExtension(file.Name).Replace(" ", "_");
                    await _session.CallMutationAsync("emojis.add", new JsonArray
                    {
                        new JsonObject { ["fileId"] = fileId, ["name"] = name }
                    });
                }
                await ReloadAsync();
                status.Text = "";
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                upload.IsEnabled = true;
            }
        };
        search.TextChanged += (_, _) => RenderEmojis();
        await ReloadAsync();
        var form = new StackPanel { Spacing = 10, Margin = new Thickness(20) };
        form.Children.Add(search);
        form.Children.Add(upload);
        form.Children.Add(status);
        form.Children.Add(rows);
        return new ScrollViewer { Content = form, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

}
