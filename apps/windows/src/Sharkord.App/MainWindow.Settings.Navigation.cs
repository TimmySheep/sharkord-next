using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        var navigation = new NavigationView
        {
            PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
            IsSettingsVisible = false,
            IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
            Width = 860,
            Height = 600
        };
        navigation.SelectionChanged += OnSettingsNavigationSelectionChanged;

        if (_session.Phase == SessionPhase.Connected)
        {
            AddLazySettingsItem(navigation, "profileTab", () => Task.FromResult<FrameworkElement>(BuildProfileSettings()));
            AddLazySettingsItem(navigation, "passwordTab", () => Task.FromResult<FrameworkElement>(BuildPasswordSettings()));
        }

        AddLazySettingsItem(navigation, "notificationsTab", () => Task.FromResult<FrameworkElement>(BuildNotificationSettings()));
        AddLazySettingsItem(navigation, "othersTab", () => Task.FromResult<FrameworkElement>(BuildGeneralAppSettings()));
        AddLazySettingsItem(
            navigation,
            "keyboardShortcutsTab",
            () => Task.FromResult<FrameworkElement>(BuildKeyboardShortcutSettings()),
            titleNamespace: "macos"
        );
        AddLazySettingsItem(navigation, "devicesTab", BuildMediaDeviceSettingsAsync);

        if (_session.Phase == SessionPhase.Connected && _session.HasPermission("MANAGE_SETTINGS"))
        {
            AddLazySettingsItem(navigation, "generalTab", BuildGeneralServerSettingsAsync);
        }

        if (_session.Phase == SessionPhase.Connected && _session.HasPermission("MANAGE_STORAGE"))
        {
            AddLazySettingsItem(navigation, "storageTab", BuildStorageSettingsAsync);
        }

        if (_session.Phase == SessionPhase.Connected && _session.HasPermission("MANAGE_USERS"))
        {
            AddLazySettingsItem(navigation, "usersTab", BuildUserSettingsAsync);
        }

        if (_session.Phase == SessionPhase.Connected && _session.HasPermission("MANAGE_INVITES"))
        {
            AddLazySettingsItem(navigation, "invitesTab", BuildInviteSettingsAsync);
        }

        if (_session.Phase == SessionPhase.Connected && _session.HasPermission("MANAGE_ROLES"))
        {
            AddLazySettingsItem(navigation, "rolesTab", BuildRoleSettingsAsync);
        }

        if (_session.Phase == SessionPhase.Connected && _session.HasPermission("MANAGE_EMOJIS"))
        {
            AddLazySettingsItem(navigation, "emojisTab", BuildEmojiSettingsAsync);
        }

        if (_session.Phase == SessionPhase.Connected && _session.HasPermission("MANAGE_PLUGINS"))
        {
            AddLazySettingsItem(navigation, "pluginsTab", BuildPluginSettingsAsync);
        }

        if (_session.Phase == SessionPhase.Connected && _session.HasPermission("MANAGE_UPDATES"))
        {
            AddLazySettingsItem(navigation, "updatesTab", BuildUpdateSettingsAsync);
        }

        navigation.SelectedItem = navigation.MenuItems.FirstOrDefault();

        var dialog = new ContentDialog
        {
            Title = L10n.T("settingsButton", ns: "macos"),
            Content = navigation,
            CloseButtonText = L10n.T("close", ns: "windows"),
            XamlRoot = RootGrid.XamlRoot
        };
        await dialog.ShowAsync();
    }

    private static void AddLazySettingsItem(
        NavigationView navigation,
        string titleKey,
        Func<Task<FrameworkElement>> loadContent,
        string titleNamespace = "settings"
    )
    {
        navigation.MenuItems.Add(new NavigationViewItem
        {
            Content = L10n.T(titleKey, ns: titleNamespace),
            Tag = loadContent
        });
    }

    private async void OnSettingsNavigationSelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args
    )
    {
        if (args.SelectedItemContainer is not NavigationViewItem item)
        {
            return;
        }

        if (item.Tag is FrameworkElement cachedContent)
        {
            sender.Content = cachedContent;
            return;
        }

        if (item.Tag is not Func<Task<FrameworkElement>> loadContent)
        {
            return;
        }

        sender.Content = new ProgressRing { IsActive = true, Margin = new Thickness(20) };
        try
        {
            var content = await loadContent();
            item.Tag = content;
            sender.Content = content;
        }
        catch (Exception exception)
        {
            var content = new TextBlock
            {
                Text = exception.Message,
                TextWrapping = TextWrapping.Wrap,
                Padding = new Thickness(20)
            };
            item.Tag = content;
            sender.Content = content;
        }
    }

}
