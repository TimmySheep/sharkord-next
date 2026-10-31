using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Windowing;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Sharkord.App;

public sealed partial class MainWindow : Window
{
    private readonly SharkordSession _session;
    private readonly ObservableCollection<MessageItem> _messages = [];
    private readonly Dictionary<string, bool> _expandedChannelGroups = [];
    private readonly HttpClient _serverPreviewHttpClient = new();
    private string? _languagePreference;
    private bool _isUpdatingLanguagePicker;
    private CancellationTokenSource? _serverPreviewCancellation;
    private bool _windowIsActive;
    private bool _voiceWebViewInitialized;
    private bool _voiceWebViewInitializing;
    private int _refreshQueued;
    private bool _voiceWorkerReady;
    private bool _canPublishAudio;
    private bool _microphoneMuted = true;
    private bool _deafened;
    private bool _webcamEnabled;
    private string _voiceMediaStatus = "idle";
    private double _noiseSuppressionMix = 100;

    public MainWindow(SharkordSession session)
    {
        _session = session;
        InitializeComponent();
        ResetServerBranding();
        _noiseSuppressionMix = ReadNoiseSuppressionMix();
        _keyboardShortcutPreferences = ReadKeyboardShortcutPreferences();
        _pushToTalkEnabled = ReadPreference("voice.pushToTalkEnabled", defaultValue: false);
        RootGrid.RequestedTheme = ElementTheme.Dark;
        RootGrid.AddHandler(
            UIElement.KeyDownEvent,
            new KeyEventHandler(OnRootKeyDown),
            handledEventsToo: true
        );

        RootGrid.ActualThemeChanged += OnRootThemeChanged;
        SetWindowIconForCurrentTheme();
        Closed += (_, _) => RootGrid.ActualThemeChanged -= OnRootThemeChanged;
        Activated += (_, args) => _windowIsActive = args.WindowActivationState != WindowActivationState.Deactivated;

        _languagePreference = ReadLanguagePreference();
        if (_languagePreference is null)
        {
            L10n.UseSystemLanguage();
        }
        else
        {
            L10n.Language = _languagePreference;
        }

        MessageList.ItemsSource = _messages;
        InitializeDesktopControls();
        InitializeNativeVoiceControls();

        ApplyLocalisation();
        L10n.LanguageChanged += ApplyLocalisation;
        Closed += (_, _) => L10n.LanguageChanged -= ApplyLocalisation;
        Closed += OnMainWindowClosed;
        Closed += (_, _) =>
        {
            _serverPreviewCancellation?.Cancel();
            _serverPreviewHttpClient.Dispose();
        };

        _session.Changed += OnSessionChanged;
        _session.VoiceProducerChanged += OnVoiceProducerChanged;
        _session.IncomingMessage += OnIncomingMessage;
        Closed += (_, _) =>
        {
            _session.Changed -= OnSessionChanged;
            _session.VoiceProducerChanged -= OnVoiceProducerChanged;
            _session.IncomingMessage -= OnIncomingMessage;
        };

        if (_pushToTalkEnabled)
        {
            EnablePushToTalk();
        }
    }

    private void OnRootThemeChanged(FrameworkElement sender, object args)
    {
        SetWindowIconForCurrentTheme();
    }

    private void SetWindowIconForCurrentTheme()
    {
        var windowHandle = WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(windowHandle);
        var iconName = RootGrid.ActualTheme == ElementTheme.Dark ? "cove-dark.ico" : "cove.ico";
        AppWindow.GetFromWindowId(windowId).SetIcon(
            Path.Combine(AppContext.BaseDirectory, "Assets", iconName)
        );
    }

    /// <summary>
    /// every user-facing literal in this window is assigned here, so a language change only
    /// has to re-run this one method. see <see cref="I18n.L10n"/> for the tables.
    /// </summary>
    private void ApplyLocalisation()
    {
        ExportLogsButton.Content = L10n.T("exportLogs", ns: "windows");
        LoginExportLogsButton.Content = L10n.T("exportLogs", ns: "windows");
        GitHubLink.Content = "GitHub";
        SharkordLink.Content = "Sharkord";
        LocaliseDesktopControls();
        AdvancedOptionsText.Text = L10n.T("advancedOptions", ns: "macos");
        RefreshLanguagePicker();
        HostBox.Header = L10n.T("serverAddress", ns: "windows");
        IdentityBox.Header = L10n.T("identityLabel", ns: "connect");
        PasswordBox.Header = L10n.T("passwordLabel", ns: "connect");
        ServerPasswordBox.Header = L10n.T("serverPassword", ns: "windows");
        InviteBox.Header = L10n.T("inviteCode", ns: "windows");
        ConnectButton.Content = L10n.T("connectBtn", ns: "connect");
        ComposerBox.PlaceholderText = L10n.T("messagePlaceholder", ns: "windows");
        SendButton.Content = L10n.T("send", ns: "windows");
        JoinVoiceButton.Content = L10n.T("joinVoice", ns: "windows");
        LeaveVoiceButton.Content = L10n.T("leaveVoice", ns: "windows");
        DeafenButton.Content = L10n.T(_deafened ? "undeafen" : "deafen", ns: "windows");
        WebcamButton.Content = L10n.T("webcam", ns: "windows");
        RefreshVoiceControls();

        // messages embed the localised system author name, so they have to be rebuilt too
        Refresh();
    }

    private void RefreshLanguagePicker()
    {
        _isUpdatingLanguagePicker = true;

        try
        {
            foreach (var languageBox in new[] { LanguageBox, LoginLanguageBox })
            {
                languageBox.Header = L10n.T("languageLabel", ns: "windows");
                languageBox.Items.Clear();
                languageBox.Items.Add(new ComboBoxItem
                {
                    Content = L10n.T("systemLanguage", ns: "windows"),
                    Tag = "system"
                });

                foreach (var language in L10n.SupportedLanguages)
                {
                    languageBox.Items.Add(new ComboBoxItem { Content = language.NativeName, Tag = language.Code });
                }

                var selectedTag = _languagePreference ?? "system";
                languageBox.SelectedItem = languageBox.Items
                    .OfType<ComboBoxItem>()
                    .First(item => string.Equals(item.Tag as string, selectedTag, StringComparison.OrdinalIgnoreCase));
            }
        }
        finally
        {
            _isUpdatingLanguagePicker = false;
        }
    }

    private void OnLanguageSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (
            _isUpdatingLanguagePicker
            || sender is not ComboBox languageBox
            || languageBox.SelectedItem is not ComboBoxItem item
        )
        {
            return;
        }

        var selectedLanguage = item.Tag as string;
        _languagePreference = selectedLanguage == "system" ? null : selectedLanguage;
        SaveLanguagePreference(_languagePreference);

        if (_languagePreference is null)
        {
            L10n.UseSystemLanguage();
            return;
        }

        L10n.Language = _languagePreference;
    }

    private static double ReadNoiseSuppressionMix()
    {
        try
        {
            var settings = Windows.Storage.ApplicationData.Current.LocalSettings.Values;
            return settings.TryGetValue("voice.noiseSuppressionMix", out var value) && value is double mix
                ? Math.Clamp(mix, 0, 100)
                : 100;
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.noise_suppression.read_failed", exception);
            return 100;
        }
    }

    private static string? ReadLanguagePreference()
    {
        try
        {
            if (!File.Exists(LanguagePreferencePath))
            {
                return null;
            }

            var saved = File.ReadAllText(LanguagePreferencePath).Trim();
            if (saved.Equals("system", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            foreach (var language in L10n.SupportedLanguages)
            {
                if (language.Code.Equals(saved, StringComparison.OrdinalIgnoreCase))
                {
                    return language.Code;
                }
            }

            return null;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            ClientLogStore.Shared.RecordError("preferences.language.read", exception);
            Debug.WriteLine($"Could not read the saved language preference: {exception.Message}");
            return null;
        }
    }

    private static void SaveLanguagePreference(string? language)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LanguagePreferencePath)!);
            File.WriteAllText(LanguagePreferencePath, language ?? "system");
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            ClientLogStore.Shared.RecordError("preferences.language.save", exception);
            Debug.WriteLine($"Could not save the language preference: {exception.Message}");
        }
    }

    private async void OnExportLogsClick(object sender, RoutedEventArgs e)
    {
        var picker = new FileSavePicker
        {
            SuggestedStartLocation = PickerLocationId.Downloads,
            SuggestedFileName = $"cove-diagnostics-{DateTime.Now:yyyyMMdd-HHmmss}.log"
        };
        picker.FileTypeChoices.Add(
            L10n.T("logFileType", ns: "windows"),
            new List<string> { ".log" }
        );
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));

        try
        {
            var file = await picker.PickSaveFileAsync();
            if (file is null)
            {
                return;
            }

            ClientLogStore.Shared.RecordInfo("diagnostics.export");
            await ClientLogStore.Shared.ExportLogsAsync(file.Path);
            await ShowLogExportResultAsync(didExport: true);
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("diagnostics.export.failed", exception);
            await ShowLogExportResultAsync(didExport: false);
        }
    }

    private async Task ShowLogExportResultAsync(bool didExport)
    {
        var title = didExport ? "logsExportSuccessTitle" : "logsExportFailureTitle";
        var message = didExport ? "logsExportSuccessMessage" : "logsExportFailureMessage";
        var dialog = new ContentDialog
        {
            Title = L10n.T(title, ns: "windows"),
            Content = L10n.T(message, ns: "windows"),
            CloseButtonText = L10n.T("close", ns: "windows"),
            XamlRoot = RootGrid.XamlRoot
        };

        await dialog.ShowAsync();
    }

    private void OnSessionChanged()
    {
        if (Interlocked.Exchange(ref _refreshQueued, 1) != 0)
        {
            return;
        }
        if (!DispatcherQueue.TryEnqueue(() =>
        {
            Interlocked.Exchange(ref _refreshQueued, 0);
            if (_session.Phase != SessionPhase.Connected && _voiceWebViewInitialized)
            {
                _ = VoiceMediaWebView.ExecuteScriptAsync("window.coveVoice?.stop()");
                _voiceMediaStatus = "idle";
                _microphoneMuted = true;
                _deafened = false;
                _webcamEnabled = false;
            }

            Refresh();
        }))
        {
            Interlocked.Exchange(ref _refreshQueued, 0);
        }
    }

    private void Refresh()
    {
        ConnectButton.IsEnabled = _session.Phase != SessionPhase.Connecting;
        ConnectProgress.IsActive = _session.Phase == SessionPhase.Connecting;
        ConnectError.Text = _session.Phase == SessionPhase.Failed ? _session.LastError ?? "" : "";
        var isConnected = _session.Phase == SessionPhase.Connected;
        ConnectScreen.Visibility = isConnected ? Visibility.Collapsed : Visibility.Visible;
        TopActionsPanel.Visibility = isConnected ? Visibility.Visible : Visibility.Collapsed;

        if (!isConnected)
        {
            if (_session.Phase == SessionPhase.Disconnected)
            {
                ResetDesktopWorkspace();
            }
            ChatPanel.Visibility = Visibility.Collapsed;
            return;
        }

        _workspaceConnected = true;
        ChatPanel.Visibility = Visibility.Visible;
        ServerNameText.Text = _session.ServerName;

        SyncChannels();
        RefreshDesktopControls();

        var selected = _session.SelectedChannelId is { } id ? _session.Channel(id) : null;
        var selectedVoice = (selected?.IsVoice == true && !_session.IsVoiceTextSelected) || (selected?.IsDm == true && _showDmVoice);
        TextChannelPanel.Visibility = selectedVoice ? Visibility.Collapsed : Visibility.Visible;
        VoiceChannelPanel.Visibility = selectedVoice ? Visibility.Visible : Visibility.Collapsed;
        VoiceChannelTitle.Text = selectedVoice ? $"🔊  {selected!.Name}" : "";
        ChannelTitle.Text = selected is null || selectedVoice ? "" : $"# {selected.Name}";
        if (selected?.IsDm == true) { ChannelTitle.Text = _session.DirectMessagePartner(selected)?.Name ?? selected.Name; }
        if (_threadParent is not null) { ChannelTitle.Text = $"{L10n.T("thread")} · {ChannelTitle.Text}"; }
        RefreshNavigationControls();

        if (selectedVoice)
        {
            RootGrid.FindName(nameof(VoiceMediaWebView));
            VoiceStatusText.Text = _voiceMediaStatus == "connecting"
                ? L10n.T("voiceConnecting", ns: "windows")
                : "";
            RefreshVoiceControls();
            return;
        }

        SyncMessageRows(selected);
    }

    private void SyncChannels()
    {
        if (!ChannelTreeChanged())
        {
            ChannelList.SelectedNode = FindSelectedChannelNode(ChannelList.RootNodes);
            return;
        }
        ChannelList.RootNodes.Clear();

        var directMessages = _session.DirectMessageChannels.ToList();
        if (directMessages.Count > 0)
        {
            var dmChildren = directMessages.Select(channel => CreateChannelNode(
                channel,
                _session.DirectMessagePartner(channel)?.Name ?? channel.Name
            )).ToList();
            ChannelList.RootNodes.Add(CreateGroupNode("direct-messages", L10n.T("directMessages", ns: "windows"), dmChildren));
        }

        AddChannelSection(
            "text",
            L10n.T("textChannels", ns: "windows"),
            _session.TextChannels.Where(_session.CanViewChannel).OrderBy(channel => channel.Position).ToList()
        );
        AddChannelSection(
            "voice",
            L10n.T("voiceChannels", ns: "windows"),
            _session.Channels.Where(channel => channel.IsVoice && !channel.IsDm && _session.CanViewChannel(channel))
                .OrderBy(channel => channel.Position)
                .ToList()
        );

        ChannelList.SelectedNode = FindSelectedChannelNode(ChannelList.RootNodes);
    }

    private TreeViewNode? FindSelectedChannelNode(IEnumerable<TreeViewNode> nodes)
    {
        foreach (var node in nodes)
        {
            if (node.Content is ChannelTreeItem { ChannelId: { } id } && id == _session.SelectedChannelId)
            {
                return node;
            }

            if (FindSelectedChannelNode(node.Children) is { } selected)
            {
                return selected;
            }
        }

        return null;
    }

    private void AddChannelSection(string sectionKey, string title, IReadOnlyList<SharkordChannel> channels)
    {
        if (channels.Count == 0)
        {
            return;
        }

        var nodes = new List<TreeViewNode>();

        foreach (var category in _session.Categories.OrderBy(category => category.Position))
        {
            var categoryChannels = channels.Where(channel => channel.CategoryId == category.Id).ToList();
            if (categoryChannels.Count == 0)
            {
                continue;
            }

            var children = categoryChannels.Select(channel => CreateChannelNode(channel, channel.Name)).ToList();
            nodes.Add(CreateGroupNode($"{sectionKey}-category-{category.Id}", category.Name, children));
        }

        var uncategorized = channels.Where(channel => channel.CategoryId is null)
            .Select(channel => CreateChannelNode(channel, channel.Name));
        nodes.AddRange(uncategorized);
        ChannelList.RootNodes.Add(CreateGroupNode(sectionKey, title, nodes));
    }

    private TreeViewNode CreateGroupNode(string key, string title, IReadOnlyList<TreeViewNode> children)
    {
        if (!_expandedChannelGroups.TryGetValue(key, out var isExpanded))
        {
            isExpanded = children.Count <= 5;
            _expandedChannelGroups[key] = isExpanded;
        }

        var node = new TreeViewNode
        {
            Content = new ChannelTreeItem(title, null, key),
            IsExpanded = isExpanded
        };

        foreach (var child in children)
        {
            node.Children.Add(child);
        }

        return node;
    }

    private TreeViewNode CreateChannelNode(SharkordChannel channel, string label)
    {
        var marker = "#  ";
        if (channel.IsVoice)
        {
            marker = "🔊  ";
        }
        else if (channel.IsDm)
        {
            marker = "●  ";
        }
        var unread = _session.UnreadCount(channel.Id);
        if (unread > 0)
        {
            label = $"{label}  ({unread})";
        }

        return new TreeViewNode
        {
            Content = new ChannelTreeItem($"{marker}{label}", channel.Id, null)
        };
    }

    private async void OnConnectClick(object sender, RoutedEventArgs e)
    {
        ResetDesktopWorkspace();
        await _session.ConnectAsync(
            HostBox.Text,
            IdentityBox.Text,
            PasswordBox.Password,
            ServerPasswordBox.Password,
            InviteBox.Text
        );

        if (_session.Phase == SessionPhase.Connected)
        {
            var restored = await RestoreLastSelectedChannelAsync();
            if (!restored && _session.SelectedChannelId is { } channelId)
            {
                CloseThread();
            PrepareChannelSelection(channelId);
                await _session.SelectChannelAsync(channelId);
            }
        }

        Refresh();
    }

    private async void OnHostTextChanged(object sender, TextChangedEventArgs e)
    {
        _serverPreviewCancellation?.Cancel();
        ResetServerBranding();

        var cancellation = new CancellationTokenSource();
        _serverPreviewCancellation = cancellation;
        if (!TryNormalizePreviewHost(HostBox.Text, out var baseUrl))
        {
            cancellation.Dispose();
            _serverPreviewCancellation = null;
            return;
        }

        try
        {
            await Task.Delay(450, cancellation.Token);
            var client = new SharkordHttpClient(baseUrl, _serverPreviewHttpClient);
            var info = await client.GetInfoAsync(cancellation.Token);
            if (cancellation.IsCancellationRequested)
            {
                return;
            }

            ServerTitleText.Text = string.IsNullOrWhiteSpace(info.Name) ? "cove" : info.Name;
            ServerDescriptionText.Text = info.Description ?? "";
            ServerDescriptionText.Visibility = string.IsNullOrWhiteSpace(info.Description)
                ? Visibility.Collapsed
                : Visibility.Visible;

            if (info.Logo is not null)
            {
                ServerLogoImage.Source = new BitmapImage(client.PublicFileUrl(info.Logo));
                ServerLogoImage.Visibility = Visibility.Visible;
                ServerLogoFallback.Visibility = Visibility.Collapsed;
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception)
        {
        }
        finally
        {
            if (ReferenceEquals(_serverPreviewCancellation, cancellation))
            {
                _serverPreviewCancellation = null;
            }

            cancellation.Dispose();
        }
    }

    private static bool TryNormalizePreviewHost(string host, out Uri baseUrl)
    {
        baseUrl = null!;
        var trimmed = host.Trim();
        if (trimmed.Length == 0)
        {
            return false;
        }

        var withScheme = trimmed.Contains("://", StringComparison.Ordinal) ? trimmed : $"http://{trimmed}";
        if (!Uri.TryCreate(withScheme, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
            || string.IsNullOrEmpty(uri.Host))
        {
            return false;
        }

        baseUrl = uri;
        return true;
    }

    private void ResetServerBranding()
    {
        ServerTitleText.Text = "cove";
        ServerDescriptionText.Text = "";
        ServerDescriptionText.Visibility = Visibility.Collapsed;
        ServerLogoImage.Source = null;
        ServerLogoImage.Visibility = Visibility.Collapsed;
        ServerLogoFallback.Text = "c";
        ServerLogoFallback.Visibility = Visibility.Visible;
    }

    private void OnServerLogoFailed(object sender, ExceptionRoutedEventArgs e)
    {
        ServerLogoImage.Visibility = Visibility.Collapsed;
        ServerLogoFallback.Visibility = Visibility.Visible;
    }

    private async void OnChannelInvoked(TreeView sender, TreeViewItemInvokedEventArgs e)
    {
        if (e.InvokedItem is TreeViewNode { Content: ChannelTreeItem { ChannelId: { } channelId } })
        {
            CloseThread();
            PrepareChannelSelection(channelId);
            RememberLastSelectedChannel(channelId);
            await _session.SelectChannelAsync(channelId);
        }
    }

    private void OnChannelTreeExpanding(TreeView sender, TreeViewExpandingEventArgs e)
    {
        if (e.Node.Content is ChannelTreeItem { GroupKey: { } key })
        {
            _expandedChannelGroups[key] = true;
        }
    }

    private void OnChannelTreeCollapsed(TreeView sender, TreeViewCollapsedEventArgs e)
    {
        if (e.Node.Content is ChannelTreeItem { GroupKey: { } key })
        {
            _expandedChannelGroups[key] = false;
        }
    }

    private void OnVoiceMediaWebViewLoaded(object sender, RoutedEventArgs e)
    {
        if (_voiceWebViewInitialized)
        {
            return;
        }

        _ = InitializeVoiceWebViewAsync();
    }

    private async Task InitializeVoiceWebViewAsync()
    {
        if (_voiceWebViewInitialized || _voiceWebViewInitializing)
        {
            return;
        }
        _voiceWebViewInitializing = true;
        try
        {
            await VoiceMediaWebView.EnsureCoreWebView2Async();
            var core = VoiceMediaWebView.CoreWebView2;
            var mediaFolder = Path.Combine(AppContext.BaseDirectory, "Assets", "VoiceMedia");
            core.SetVirtualHostNameToFolderMapping(
                "cove.local",
                mediaFolder,
                CoreWebView2HostResourceAccessKind.Allow
            );
            core.NavigationStarting += (_, args) =>
            {
                if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri) ||
                    !uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
                    !uri.Host.Equals("cove.local", StringComparison.OrdinalIgnoreCase))
                {
                    args.Cancel = true;
                }
            };
            core.PermissionRequested += OnVoicePermissionRequested;
            core.WebMessageReceived += OnVoiceWebMessageReceived;
            core.Navigate("https://cove.local/index.html");
            _voiceWebViewInitialized = true;
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("voice.webview.initialize", exception);
            VoiceErrorText.Text = exception.Message;
        }
        finally
        {
            _voiceWebViewInitializing = false;
        }
    }

    private static void OnVoicePermissionRequested(
        object? sender,
        CoreWebView2PermissionRequestedEventArgs e
    )
    {
        var trustedOrigin = Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) &&
            uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) &&
            uri.Host.Equals("cove.local", StringComparison.OrdinalIgnoreCase);

        if (!trustedOrigin)
        {
            e.State = CoreWebView2PermissionState.Deny;
            e.Handled = true;
            return;
        }

        if (e.PermissionKind is CoreWebView2PermissionKind.Microphone or CoreWebView2PermissionKind.Camera)
        {
            e.State = CoreWebView2PermissionState.Allow;
            e.Handled = true;
        }
    }

    private void OnVoiceWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            if (JsonNode.Parse(e.WebMessageAsJson) is not JsonObject message)
            {
                return;
            }

            var type = message["type"]?.GetValue<string>();
            if (HandleNativeMediaMessage(message)) { return; }
            if (type == "ready")
            {
                _voiceWorkerReady = true;
                return;
            }

            if (type == "status")
            {
                _voiceMediaStatus = message["state"]?.GetValue<string>() ?? "idle";
                _canPublishAudio = message["canPublishAudio"]?.GetValue<bool>() ?? false;
                VoiceStatusText.Text = _voiceMediaStatus switch
                {
                    "connecting" => L10n.T("voiceConnecting", ns: "windows"),
                    "connected" => "",
                    _ => ""
                };
                var workerError = message["error"]?.GetValue<string>() ?? "";
                if (!string.IsNullOrEmpty(workerError) && workerError != VoiceErrorText.Text)
                {
                    ClientLogStore.Shared.RecordFailure("voice.media_worker.failed", "media_worker");
                }
                VoiceErrorText.Text = workerError;
                RefreshVoiceControls();
                return;
            }

            if (type == "rpc" && message["id"]?.GetValue<string>() is { } id &&
                message["path"]?.GetValue<string>() is { } path)
            {
                _ = HandleVoiceRpcAsync(id, path, message["input"]?.DeepClone());
            }
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("voice.webview.message", exception);
            VoiceErrorText.Text = exception.Message;
        }
    }

    private async Task HandleVoiceRpcAsync(string id, string path, JsonNode? input)
    {
        var response = new JsonObject { ["type"] = "rpcResponse", ["id"] = id };

        try
        {
            var result = await _session.CallVoiceMediaProcedureAsync(path, input);
            if (result is not null)
            {
                response["result"] = result.DeepClone();
            }
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("voice.procedure.failed", exception);
            response["error"] = exception.Message;
        }

        VoiceMediaWebView.CoreWebView2?.PostWebMessageAsJson(response.ToJsonString());
    }

    private void OnVoiceProducerChanged(VoiceProducerEvent producer, bool added)
    {
        if (producer.RemoteId == _session.OwnUserId && !producer.Kind.StartsWith("external_", StringComparison.Ordinal))
        {
            return;
        }

        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_voiceWorkerReady || VoiceMediaWebView.CoreWebView2 is not { } core)
            {
                return;
            }

            var change = new JsonObject
            {
                ["type"] = "producer",
                ["remoteId"] = producer.RemoteId,
                ["kind"] = producer.Kind,
                ["added"] = added
            };
            core.PostWebMessageAsJson(change.ToJsonString());
        });
    }

    private async void OnJoinVoiceClick(object sender, RoutedEventArgs e)
    {
        if (_session.SelectedChannelId is not { } channelId || _session.Channel(channelId) is not { SupportsVoice: true })
        {
            return;
        }

        try
        {
            VoiceErrorText.Text = "";
            _voiceMediaStatus = "connecting";
            VoiceStatusText.Text = L10n.T("voiceConnecting", ns: "windows");

            if (_session.CurrentVoiceChannelId is not null)
            {
                await LeaveVoiceAsync();
            }

            await WaitForVoiceWorkerAsync();
            await ApplyMediaOptionsAsync(channelId);
            var result = await _session.JoinVoiceAsync(channelId);
            var capabilities = result?["routerRtpCapabilities"]
                ?? throw new InvalidOperationException("The server did not return voice capabilities.");
            var canProduceAudio = _session.HasChannelPermission(channelId, "SPEAK");
            var canShareScreen = _session.HasPermission("SHARE_SCREEN") &&
                _session.HasChannelPermission(channelId, "SHARE_SCREEN");
            _canPublishAudio = canProduceAudio;
            var screenShareLabels = JsonSerializer.Serialize(new
            {
                share = L10n.T("shareScreen", ns: "windows"),
                stop = L10n.T("stopScreenShare", ns: "windows"),
                local = L10n.T("mediaLocalUser", ns: "windows"),
                screen = L10n.T("mediaScreen", ns: "windows"),
                camera = L10n.T("mediaCamera", ns: "windows")
            });
            var script = $"window.coveVoice?.start({channelId}, JSON.parse({JsonSerializer.Serialize(capabilities.ToJsonString())}), {JsonSerializer.Serialize(canProduceAudio)}, {JsonSerializer.Serialize(canShareScreen)}, {screenShareLabels}, {JsonSerializer.Serialize(_noiseSuppressionMix / 100)}).catch(() => {{}})";
            await VoiceMediaWebView.ExecuteScriptAsync(script);
            _microphoneMuted = true;
            _deafened = false;
            _webcamEnabled = false;
            RefreshVoiceControls();
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("voice.join.failed", exception);
            VoiceErrorText.Text = exception.Message;
            _voiceMediaStatus = "failed";
            if (_session.CurrentVoiceChannelId is not null)
            {
                try
                {
                    await _session.LeaveVoiceAsync();
                }
                catch (Exception leaveError)
                {
                    ClientLogStore.Shared.RecordError("voice.leave.failed", leaveError);
                    VoiceErrorText.Text = $"{exception.Message}\n{leaveError.Message}";
                }
            }

            RefreshVoiceControls();
        }
    }

    private async Task WaitForVoiceWorkerAsync()
    {
        RootGrid.FindName(nameof(VoiceMediaWebView));
        await InitializeVoiceWebViewAsync();
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(20);
        while (!_voiceWorkerReady && DateTime.UtcNow < deadline)
        {
            await Task.Delay(100);
        }

        if (!_voiceWorkerReady)
        {
            throw new TimeoutException("The voice media engine did not finish loading.");
        }
    }

    private async void OnMicrophoneClick(object sender, RoutedEventArgs e)
    {
        await SetMicrophoneMutedAsync(!_microphoneMuted);
    }

    private async void OnDeafenClick(object sender, RoutedEventArgs e)
    {
        _deafened = !_deafened;
        if (_deafened)
        {
            _microphoneMuted = true;
        }

        await ExecuteVoiceActionAsync("setOutputMuted", _deafened);
        RefreshVoiceControls();
    }

    private async void OnWebcamClick(object sender, RoutedEventArgs e)
    {
        _webcamEnabled = !_webcamEnabled;
        await ExecuteVoiceActionAsync("setWebcamEnabled", _webcamEnabled);
        RefreshVoiceControls();
    }

    private async Task ExecuteVoiceActionAsync(string action, bool value)
    {
        try
        {
            var script = $"window.coveVoice?.{action}({JsonSerializer.Serialize(value)}).catch(() => {{}})";
            await VoiceMediaWebView.ExecuteScriptAsync(script);
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("voice.control.failed", exception);
            VoiceErrorText.Text = exception.Message;
        }
    }

    private async void OnLeaveVoiceClick(object sender, RoutedEventArgs e)
    {
        await LeaveVoiceAsync();
    }

    private async Task LeaveVoiceAsync()
    {
        try
        {
            await VoiceMediaWebView.ExecuteScriptAsync("window.coveVoice?.stop()");
            await _session.LeaveVoiceAsync();
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("voice.leave.failed", exception);
            VoiceErrorText.Text = exception.Message;
        }

        _voiceMediaStatus = "idle";
        _canPublishAudio = false;
        _webcamEnabled = false;
        _microphoneMuted = true;
        _deafened = false;
        RefreshVoiceControls();
    }

    private void RefreshVoiceControls()
    {
        var selected = _session.SelectedChannelId is { } id ? _session.Channel(id) : null;
        var inSelectedVoice = selected?.SupportsVoice == true && _session.CurrentVoiceChannelId == selected.Id;
        var mediaConnected = inSelectedVoice && _voiceMediaStatus == "connected";

        JoinVoiceButton.Visibility = !inSelectedVoice || _voiceMediaStatus == "failed"
            ? Visibility.Visible
            : Visibility.Collapsed;
        var canJoinSelected = selected is not null &&
            _session.HasPermission("JOIN_VOICE_CHANNELS") && _session.HasChannelPermission(selected.Id, "JOIN");
        JoinVoiceButton.IsEnabled = canJoinSelected;
        var canPublish = mediaConnected && _canPublishAudio;
        MicrophoneButton.Visibility = canPublish ? Visibility.Visible : Visibility.Collapsed;
        DeafenButton.Visibility = mediaConnected ? Visibility.Visible : Visibility.Collapsed;
        WebcamButton.Visibility = mediaConnected && selected is not null &&
            _session.HasPermission("ENABLE_WEBCAM") && _session.HasChannelPermission(selected.Id, "WEBCAM")
                ? Visibility.Visible
                : Visibility.Collapsed;
        LeaveVoiceButton.Visibility = inSelectedVoice ? Visibility.Visible : Visibility.Collapsed;
        MicrophoneButton.Content = L10n.T(_microphoneMuted ? "unmuteMic" : "muteMic", ns: "windows");
        DeafenButton.Content = L10n.T(_deafened ? "undeafen" : "deafen", ns: "windows");
        RefreshUserVoiceControls();
        RefreshNativeVoiceControls();
        VoiceChannelTitle.Text = selected?.SupportsVoice == true ? $"🔊  {selected.Name}" : "";
        if (selected?.SupportsVoice != true)
        {
            return;
        }

        if (!canJoinSelected)
        {
            VoiceStatusText.Text = L10n.T("voiceNoPermission", ns: "windows");
            return;
        }

        VoiceStatusText.Text = _voiceMediaStatus == "connecting"
            ? L10n.T("voiceConnecting", ns: "windows")
            : "";
    }

    private async void OnSendClick(object sender, RoutedEventArgs e)
    {
        await SendComposer();
    }

    private async Task SendComposer()
    {
        await SendDesktopComposerAsync();
    }

    private static string LanguagePreferencePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Sharkord",
        "language"
    );

    [Microsoft.UI.Xaml.Data.Bindable]
    public sealed record ChannelTreeItem(string Name, int? ChannelId, string? GroupKey);
}
