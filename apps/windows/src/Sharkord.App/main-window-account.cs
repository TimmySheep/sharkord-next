using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private bool _restoredAccount;
    private bool _showingWelcome;

    private void InitializeAccountControls()
    {
        RememberLoginBox.Content = L10n.T("rememberLogin", ns: "account");
        RememberLoginBox.IsChecked = false;
        RootGrid.Loaded += OnAccountRootLoaded;
    }

    private void LocaliseAccountControls() => RememberLoginBox.Content = L10n.T("rememberLogin", ns: "account");

    private void OnAccountRootLoaded(object sender, RoutedEventArgs e)
    {
        if (_restoredAccount) { return; }
        _restoredAccount = true;
        try
        {
            var server = FilePreferences.Local.Get("account.lastServer", "");
            if (server.Length == 0) { return; }
            HostBox.Text = server;
            IdentityBox.Text = FilePreferences.Local.Get("account.lastIdentity", "");
            if (!FilePreferences.Local.Get("account.automaticLogin", false)) { return; }
            var saved = WindowsCredentialStore.Read(server);
            if (saved is null) { return; }
            IdentityBox.Text = saved.Identity;
            PasswordBox.Password = saved.Password;
            RememberLoginBox.IsChecked = true;
            OnConnectClick(ConnectButton, new RoutedEventArgs());
        }
        catch (Exception exception) { ConnectError.Text = L10n.T("credentialFailure", ns: "account"); ClientLogStore.Shared.RecordError("account.restore.failed", exception); }
    }

    private void RememberConnectedAccount(string identity, string password, bool remember)
    {
        if (_session.ServerBaseUrl is not { } server) { return; }
        try
        {
            FilePreferences.Local.Set("account.lastServer", server);
            FilePreferences.Local.Set("account.lastIdentity", identity);
            if (remember) { WindowsCredentialStore.Save(server, identity, password); }
            else { WindowsCredentialStore.Remove(server); }
            FilePreferences.Local.Set("account.automaticLogin", remember);
        }
        catch (Exception exception)
        {
            try { FilePreferences.Local.Set("account.automaticLogin", false); } catch (IOException) { }
            ConnectError.Text = L10n.T("credentialFailure", ns: "account");
            ClientLogStore.Shared.RecordError("account.remember.failed", exception);
        }
        PasswordBox.Password = "";
        ServerPasswordBox.Password = "";
    }

    private void AddAccountActions(MenuFlyout menu)
    {
        AddNavigationAction(menu, L10n.T("logout", ns: "account"), DisconnectAccountAsync);
    }

    private async Task DisconnectAccountAsync()
    {
        var server = _session.ServerBaseUrl;
        try { FilePreferences.Local.Set("account.automaticLogin", false); }
        catch (Exception exception) { ClientLogStore.Shared.RecordError("account.forget_preference.failed", exception); }
        if (server is not null)
        {
            try { WindowsCredentialStore.Remove(server); }
            catch (Exception exception) { ClientLogStore.Shared.RecordError("account.forget.failed", exception); }
        }
        if (_session.CurrentVoiceChannelId is not null) { await LeaveVoiceAsync(); }
        await _session.DisconnectAsync();
        PasswordBox.Password = "";
        ServerPasswordBox.Password = "";
        RememberLoginBox.IsChecked = false;
        ResetDesktopWorkspace();
        Refresh();
    }

    private void RefreshWelcomeProfile()
    {
        if (_showingWelcome || !_session.ShouldShowWelcomeProfile || RootGrid.XamlRoot is null || _session.Phase != SessionPhase.Connected) { return; }
        _showingWelcome = true;
        DispatcherQueue.TryEnqueue(async () =>
        {
            try
            {
                if (_session.Phase != SessionPhase.Connected || !_session.ShouldShowWelcomeProfile) { return; }
                var dialog = NavigationDialog(L10n.T("welcomeProfileSetupTitle", ns: "dialogs", ("serverName", _session.ServerName)), BuildProfileSettings());
                await dialog.ShowAsync();
                _session.DismissWelcomeProfile();
            }
            catch (Exception exception) { ChatErrorText.Text = exception.Message; }
            finally { _showingWelcome = false; }
        });
    }
}
