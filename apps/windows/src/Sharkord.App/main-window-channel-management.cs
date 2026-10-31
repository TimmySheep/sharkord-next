using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private void AddChannelManagement(MenuFlyout menu)
    {
        if (_session.HasPermission("MANAGE_CATEGORIES"))
        {
            AddNavigationAction(menu, L10n.T("createCategoryTitle", ns: "dialogs"), () => EditCategoryAsync(null));
        }
        foreach (var category in _session.Categories)
        {
            var categoryMenu = new MenuFlyoutSubItem { Text = category.Name };
            if (_session.HasPermission("MANAGE_CHANNELS"))
            {
                AddManagementItem(categoryMenu, L10n.T("createChannelTitle", ns: "dialogs"), () => EditChannelAsync(null, category.Id));
            }
            if (_session.HasPermission("MANAGE_CATEGORIES"))
            {
                AddManagementItem(categoryMenu, L10n.T("editCategoryTitle", ns: "macos"), () => EditCategoryAsync(category));
                AddManagementItem(categoryMenu, L10n.T("moveUp", ns: "macos"), () => MoveCategoryAsync(category, -1));
                AddManagementItem(categoryMenu, L10n.T("moveDown", ns: "macos"), () => MoveCategoryAsync(category, 1));
                AddManagementItem(categoryMenu, L10n.T("deleteCategoryTitle", ns: "sidebar"), () => DeleteNavigationItemAsync(category.Id, true));
            }
            if (categoryMenu.Items.Count > 0) { menu.Items.Add(categoryMenu); }
        }
        if (_session.SelectedChannelId is not { } id || _session.Channel(id) is not { IsDm: false } channel) { return; }
        var selected = new MenuFlyoutSubItem { Text = L10n.T("channelSettingsTitle", ns: "settings") };
        if (_session.HasPermission("MANAGE_CHANNELS"))
        {
            AddManagementItem(selected, L10n.T("editChannelTitle", ns: "macos"), () => EditChannelAsync(channel, channel.CategoryId));
            AddManagementItem(selected, L10n.T("moveUp", ns: "macos"), () => MoveChannelAsync(channel, -1));
            AddManagementItem(selected, L10n.T("moveDown", ns: "macos"), () => MoveChannelAsync(channel, 1));
            AddManagementItem(selected, L10n.T("deleteChannelTitle", ns: "sidebar"), () => DeleteNavigationItemAsync(channel.Id, false));
        }
        if (_session.HasPermission("MANAGE_CHANNEL_PERMISSIONS"))
        {
            AddManagementItem(selected, L10n.T("permissionsTab", ns: "settings"), () => EditChannelPermissionsAsync(channel));
        }
        if (selected.Items.Count > 0) { menu.Items.Add(selected); }
    }

    private void AddManagementItem(MenuFlyoutSubItem menu, string title, Func<Task> action)
    {
        var item = new MenuFlyoutItem { Text = title };
        item.Click += async (_, _) =>
        {
            try { await action(); }
            catch (Exception exception) { ChatErrorText.Text = exception.Message; }
        };
        menu.Items.Add(item);
    }

    private async Task EditCategoryAsync(SharkordCategory? category)
    {
        var name = new TextBox { Header = L10n.T("categoryNameLabel", ns: "dialogs"), Text = category?.Name ?? "", MaxLength = 32 };
        var dialog = NavigationDialog(L10n.T("categorySettingsTitle", ns: "settings"), name);
        dialog.PrimaryButtonText = L10n.T("saveChanges");
        name.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = !string.IsNullOrWhiteSpace(name.Text);
        dialog.IsPrimaryButtonEnabled = !string.IsNullOrWhiteSpace(name.Text);
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) { return; }
        var input = new JsonObject { ["name"] = name.Text.Trim() };
        if (category is not null) { input["categoryId"] = category.Id; }
        await _session.CallMutationAsync(category is null ? "categories.add" : "categories.update", input);
    }

    private async Task EditChannelAsync(SharkordChannel? channel, int? categoryId)
    {
        var name = new TextBox { Header = L10n.T("channelNameLabel", ns: "dialogs"), Text = channel?.Name ?? "", MaxLength = 27 };
        var topic = new TextBox { Header = L10n.T("channelTopicLabel", ns: "settings"), Text = channel?.Topic ?? "", MaxLength = 128 };
        var privateChannel = new CheckBox { Content = L10n.T("privateLabel", ns: "settings"), IsChecked = channel?.IsPrivate == true };
        var type = new ComboBox { Header = L10n.T("channelTypeLabel", ns: "dialogs"), HorizontalAlignment = HorizontalAlignment.Stretch };
        type.Items.Add(L10n.T("textChannelTitle", ns: "dialogs"));
        type.Items.Add(L10n.T("voiceChannelTitle", ns: "dialogs"));
        type.SelectedIndex = channel?.IsVoice == true ? 1 : 0;
        type.IsEnabled = channel is null;
        var category = new ComboBox { Header = L10n.T("categoryNameLabel", ns: "dialogs"), HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var item in _session.Categories) { category.Items.Add(new ComboBoxItem { Content = item.Name, Tag = item.Id }); }
        category.SelectedItem = category.Items.OfType<ComboBoxItem>().FirstOrDefault(item => item.Tag is int id && id == categoryId);
        var panel = new StackPanel { Width = 440, Spacing = 12 };
        panel.Children.Add(name);
        panel.Children.Add(type);
        panel.Children.Add(category);
        if (channel is not null) { panel.Children.Add(topic); panel.Children.Add(privateChannel); }
        var dialog = NavigationDialog(L10n.T("channelSettingsTitle", ns: "settings"), panel);
        dialog.PrimaryButtonText = L10n.T("saveChanges");
        name.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = name.Text.Trim().Length >= 2;
        dialog.IsPrimaryButtonEnabled = name.Text.Trim().Length >= 2;
        if (await dialog.ShowAsync() != ContentDialogResult.Primary || category.SelectedItem is not ComboBoxItem { Tag: int selectedCategory }) { return; }
        var input = new JsonObject { ["name"] = name.Text.Trim() };
        if (channel is null)
        {
            input["categoryId"] = selectedCategory;
            input["type"] = type.SelectedIndex == 1 ? "VOICE" : "TEXT";
            await _session.CallMutationAsync("channels.add", input);
        }
        else
        {
            input["channelId"] = channel.Id;
            input["topic"] = topic.Text;
            input["private"] = privateChannel.IsChecked == true;
            await _session.CallMutationAsync("channels.update", input);
            if (channel.CategoryId != selectedCategory)
            {
                await _session.CallMutationAsync("channels.reorder", new JsonObject
                {
                    ["categoryId"] = selectedCategory,
                    ["channelIds"] = new JsonArray(channel.Id)
                });
            }
        }
    }

    private async Task DeleteNavigationItemAsync(int id, bool category)
    {
        var dialog = NavigationDialog(L10n.T(category ? "deleteCategoryTitle" : "deleteChannelTitle", ns: "sidebar"),
            new TextBlock { Text = L10n.T(category ? "deleteCategoryMsg" : "deleteChannelMsg", ns: "sidebar"), TextWrapping = TextWrapping.Wrap });
        dialog.PrimaryButtonText = L10n.T("deleteLabel");
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) { return; }
        await _session.CallMutationAsync(category ? "categories.delete" : "channels.delete",
            new JsonObject { [category ? "categoryId" : "channelId"] = id });
    }

    private async Task MoveCategoryAsync(SharkordCategory category, int delta)
    {
        var ordered = _session.Categories.OrderBy(item => item.Position).Select(item => item.Id).ToList();
        var index = ordered.IndexOf(category.Id);
        var next = index + delta;
        if (index < 0 || next < 0 || next >= ordered.Count) { return; }
        (ordered[index], ordered[next]) = (ordered[next], ordered[index]);
        await _session.CallMutationAsync("categories.reorder", new JsonObject { ["categoryIds"] = new JsonArray(ordered.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray()) });
    }

    private async Task MoveChannelAsync(SharkordChannel channel, int delta)
    {
        if (channel.CategoryId is not { } categoryId) { return; }
        var ordered = _session.Channels.Where(item => !item.IsDm && item.CategoryId == categoryId).OrderBy(item => item.Position).Select(item => item.Id).ToList();
        var index = ordered.IndexOf(channel.Id);
        var next = index + delta;
        if (index < 0 || next < 0 || next >= ordered.Count) { return; }
        (ordered[index], ordered[next]) = (ordered[next], ordered[index]);
        await _session.CallMutationAsync("channels.reorder", new JsonObject
        {
            ["categoryId"] = categoryId,
            ["channelIds"] = new JsonArray(ordered.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray())
        });
    }

    private async Task EditChannelPermissionsAsync(SharkordChannel channel)
    {
        var data = await _session.CallQueryAsync("channels.getPermissions", new JsonObject { ["channelId"] = channel.Id });
        var target = new ComboBox { Header = L10n.T("rolesUsersTitle", ns: "settings"), HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var role in _session.Roles) { target.Items.Add(new ComboBoxItem { Content = $"{L10n.T("rolesSection", ns: "settings")} · {role.Name}", Tag = ("roleId", role.Id) }); }
        foreach (var user in _session.Users.Where(user => !user.Banned && user.Name != "__deleted_user__"))
        {
            target.Items.Add(new ComboBoxItem { Content = $"{L10n.T("usersSection", ns: "settings")} · {user.Name}", Tag = ("userId", user.Id) });
        }
        var panel = new StackPanel { Width = 450, Spacing = 12 };
        panel.Children.Add(new TextBlock { Text = L10n.T("selectRoleOrUser", ns: "settings"), TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(target);
        var checks = new Dictionary<string, CheckBox>();
        foreach (var permission in new[] { "VIEW_CHANNEL", "SEND_MESSAGES", "JOIN", "SPEAK", "SHARE_SCREEN", "WEBCAM" })
        {
            var check = new CheckBox { Content = L10n.T($"channel.{permission}", ns: "permissions") };
            checks.Add(permission, check);
            panel.Children.Add(check);
        }
        var remove = new CheckBox { Content = L10n.T("removeBtn", ns: "settings") };
        panel.Children.Add(remove);
        target.SelectionChanged += (_, _) =>
        {
            if (target.SelectedItem is not ComboBoxItem { Tag: ValueTuple<string, int> selected }) { return; }
            var rows = data?[selected.Item1 == "roleId" ? "rolePermissions" : "userPermissions"]?.AsArray();
            foreach (var (permission, check) in checks)
            {
                check.IsChecked = rows?.Any(row => row?[selected.Item1]?.GetValue<int>() == selected.Item2 &&
                    row["permission"]?.GetValue<string>() == permission && row["allow"]?.GetValue<bool>() == true) == true;
            }
        };
        var dialog = NavigationDialog(L10n.T("permissionsTab", ns: "settings"), panel);
        dialog.PrimaryButtonText = L10n.T("saveChanges");
        dialog.IsPrimaryButtonEnabled = false;
        target.SelectionChanged += (_, _) => dialog.IsPrimaryButtonEnabled = target.SelectedItem is not null;
        if (await dialog.ShowAsync() != ContentDialogResult.Primary || target.SelectedItem is not ComboBoxItem { Tag: ValueTuple<string, int> selected }) { return; }
        var input = new JsonObject { ["channelId"] = channel.Id, [selected.Item1] = selected.Item2 };
        if (remove.IsChecked != true)
        {
            input["permissions"] = new JsonArray(checks.Where(pair => pair.Value.IsChecked == true).Select(pair => (JsonNode?)JsonValue.Create(pair.Key)).ToArray());
        }
        await _session.CallMutationAsync(remove.IsChecked == true ? "channels.deletePermissions" : "channels.updatePermissions", input);
    }
}
