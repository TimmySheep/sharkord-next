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
using Microsoft.UI.Windowing;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.System;
using WinRT.Interop;

namespace Sharkord.App;

public sealed partial class MainWindow : Window
{
    private readonly SharkordSession _session;
    private readonly ObservableCollection<MessageItem> _messages = [];
    private readonly Dictionary<string, bool> _expandedChannelGroups = [];
    private string? _languagePreference;
    private bool _isUpdatingLanguagePicker;
    private bool _voiceWebViewInitialized;
    private bool _voiceWorkerReady;
    private bool _canPublishAudio;
    private bool _microphoneMuted = true;
    private bool _deafened;
    private bool _webcamEnabled;
    private string _voiceMediaStatus = "idle";

    private static readonly string[] QuickReactionShortcodes =
    [
        "thumbsup",
        "heart",
        "joy",
        "tada",
        "thinking_face",
        "eyes"
    ];

    private static readonly IReadOnlyDictionary<string, string> ReactionGlyphs =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["thumbsup"] = "👍",
            ["heart"] = "❤️",
            ["joy"] = "😂",
            ["tada"] = "🎉",
            ["thinking_face"] = "🤔",
            ["eyes"] = "👀"
        };

    public MainWindow(SharkordSession session)
    {
        _session = session;
        InitializeComponent();

        RootGrid.ActualThemeChanged += OnRootThemeChanged;
        SetWindowIconForCurrentTheme();
        Closed += (_, _) => RootGrid.ActualThemeChanged -= OnRootThemeChanged;

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

        ApplyLocalisation();
        L10n.LanguageChanged += ApplyLocalisation;
        Closed += (_, _) => L10n.LanguageChanged -= ApplyLocalisation;

        _session.Changed += OnSessionChanged;
        _session.VoiceProducerChanged += OnVoiceProducerChanged;
        Closed += (_, _) =>
        {
            _session.Changed -= OnSessionChanged;
            _session.VoiceProducerChanged -= OnVoiceProducerChanged;
        };
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
        TaglineText.Text = L10n.T("tagline", ns: "windows");
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
            LanguageBox.Header = L10n.T("languageLabel", ns: "windows");
            LanguageBox.Items.Clear();
            LanguageBox.Items.Add(new ComboBoxItem
            {
                Content = L10n.T("systemLanguage", ns: "windows"),
                Tag = "system"
            });

            foreach (var language in L10n.SupportedLanguages)
            {
                LanguageBox.Items.Add(new ComboBoxItem { Content = language.NativeName, Tag = language.Code });
            }

            var selectedTag = _languagePreference ?? "system";
            LanguageBox.SelectedItem = LanguageBox.Items
                .OfType<ComboBoxItem>()
                .First(item => string.Equals(item.Tag as string, selectedTag, StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            _isUpdatingLanguagePicker = false;
        }
    }

    private void OnLanguageSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isUpdatingLanguagePicker || LanguageBox.SelectedItem is not ComboBoxItem item)
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
            Debug.WriteLine($"Could not save the language preference: {exception.Message}");
        }
    }

    private void OnSessionChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_session.Phase != SessionPhase.Connected && _voiceWebViewInitialized)
            {
                _ = VoiceMediaWebView.ExecuteScriptAsync("window.coveVoice?.stop()");
                _voiceMediaStatus = "idle";
                _microphoneMuted = true;
                _deafened = false;
                _webcamEnabled = false;
            }

            Refresh();
        });
    }

    private void Refresh()
    {
        ConnectButton.IsEnabled = _session.Phase != SessionPhase.Connecting;
        ConnectProgress.IsActive = _session.Phase == SessionPhase.Connecting;
        ConnectError.Text = _session.Phase == SessionPhase.Failed ? _session.LastError ?? "" : "";

        if (_session.Phase != SessionPhase.Connected)
        {
            ChatPanel.Visibility = Visibility.Collapsed;
            ConnectPanel.Visibility = Visibility.Visible;
            return;
        }

        ConnectPanel.Visibility = Visibility.Collapsed;
        ChatPanel.Visibility = Visibility.Visible;
        ServerNameText.Text = _session.ServerName;

        SyncChannels();

        var selected = _session.SelectedChannelId is { } id ? _session.Channel(id) : null;
        var selectedVoice = selected?.IsVoice == true;
        TextChannelPanel.Visibility = selectedVoice ? Visibility.Collapsed : Visibility.Visible;
        VoiceChannelPanel.Visibility = selectedVoice ? Visibility.Visible : Visibility.Collapsed;
        VoiceChannelTitle.Text = selectedVoice ? $"◖  {selected!.Name}" : "";
        ChannelTitle.Text = selected is null || selectedVoice ? "" : $"# {selected.Name}";

        if (selectedVoice)
        {
            VoiceStatusText.Text = _voiceMediaStatus == "connecting"
                ? L10n.T("voiceConnecting", ns: "windows")
                : "";
            RefreshVoiceControls();
            return;
        }

        _messages.Clear();

        if (selected is not null && _session.MessagesByChannel.TryGetValue(selected.Id, out var list))
        {
            foreach (var message in list)
            {
                var author = message.UserId is { } userId ? _session.User(userId)?.Name : null;
                var text = MessageHtml.ToPlainText(message.Content ?? "");
                var byline = author ?? L10n.T("systemUser", ns: "windows");
                var reactions = _session
                    .ReactionGroups(message)
                    .Select(group =>
                    {
                        var display = ReactionGlyphs.TryGetValue(group.Emoji, out var glyph)
                            ? glyph
                            : $":{group.Emoji}:";

                        return new ReactionItem(message.Id, group.Emoji, $"{display} {group.Count}", group.Mine);
                    })
                    .ToList();

                _messages.Add(
                    new MessageItem(
                        message.Id,
                        $"{byline}: {text}",
                        reactions,
                        L10n.T("addReaction", ns: "windows"),
                        "+"
                    )
                );
            }
        }
    }

    private void SyncChannels()
    {
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
            _session.TextChannels.OrderBy(channel => channel.Position).ToList()
        );
        AddChannelSection(
            "voice",
            L10n.T("voiceChannels", ns: "windows"),
            _session.Channels.Where(channel => channel.IsVoice && !channel.IsDm)
                .OrderBy(channel => channel.Position)
                .ToList()
        );
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
        var marker = channel.IsVoice ? "◖  " : channel.IsDm ? "●  " : "#  ";

        return new TreeViewNode
        {
            Content = new ChannelTreeItem($"{marker}{label}", channel.Id, null),
            IsSelected = channel.Id == _session.SelectedChannelId
        };
    }

    private async void OnConnectClick(object sender, RoutedEventArgs e)
    {
        await _session.ConnectAsync(
            HostBox.Text,
            IdentityBox.Text,
            PasswordBox.Password,
            ServerPasswordBox.Password,
            InviteBox.Text
        );

        Refresh();
    }

    private async void OnChannelInvoked(TreeView sender, TreeViewItemInvokedEventArgs e)
    {
        if (e.InvokedItem is TreeViewNode { Content: ChannelTreeItem { ChannelId: { } channelId } })
        {
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
            VoiceErrorText.Text = exception.Message;
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
                VoiceErrorText.Text = message["error"]?.GetValue<string>() ?? "";
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
            response["error"] = exception.Message;
        }

        VoiceMediaWebView.CoreWebView2?.PostWebMessageAsJson(response.ToJsonString());
    }

    private void OnVoiceProducerChanged(VoiceProducerEvent producer, bool added)
    {
        if (producer.RemoteId == _session.OwnUserId)
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
        if (_session.SelectedChannelId is not { } channelId || _session.Channel(channelId) is not { IsVoice: true })
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
            var script = $"window.coveVoice?.start({channelId}, JSON.parse({JsonSerializer.Serialize(capabilities.ToJsonString())}), {JsonSerializer.Serialize(canProduceAudio)}, {JsonSerializer.Serialize(canShareScreen)}, {screenShareLabels}).catch(() => {{}})";
            await VoiceMediaWebView.ExecuteScriptAsync(script);
            _microphoneMuted = true;
            _deafened = false;
            _webcamEnabled = false;
            RefreshVoiceControls();
        }
        catch (Exception exception)
        {
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
                    VoiceErrorText.Text = $"{exception.Message}\n{leaveError.Message}";
                }
            }

            RefreshVoiceControls();
        }
    }

    private async Task WaitForVoiceWorkerAsync()
    {
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
        _microphoneMuted = !_microphoneMuted;
        if (_deafened && !_microphoneMuted)
        {
            _deafened = false;
        }

        await ExecuteVoiceActionAsync("setMicrophoneMuted", _microphoneMuted);
        RefreshVoiceControls();
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
        var inSelectedVoice = selected?.IsVoice == true && _session.CurrentVoiceChannelId == selected.Id;
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
        VoiceChannelTitle.Text = selected?.IsVoice == true ? $"◖  {selected.Name}" : "";
        if (selected?.IsVoice != true)
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

    private async void OnReactionClick(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleButton button && button.DataContext is ReactionItem reaction)
        {
            await ToggleReactionAsync(reaction.MessageId, reaction.Emoji);
        }
    }

    private void OnAddReactionClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.DataContext is not MessageItem message)
        {
            return;
        }

        var menu = new MenuFlyout();

        foreach (var shortcode in QuickReactionShortcodes)
        {
            var item = new MenuFlyoutItem { Text = ReactionGlyphs[shortcode], Tag = shortcode };
            item.Click += async (menuSender, _) =>
            {
                if (menuSender is MenuFlyoutItem selected && selected.Tag is string emoji)
                {
                    await ToggleReactionAsync(message.Id, emoji);
                }
            };
            menu.Items.Add(item);
        }

        menu.ShowAt(button);
    }

    private async Task ToggleReactionAsync(int messageId, string emoji)
    {
        ChatErrorText.Text = "";

        try
        {
            await _session.ToggleReactionAsync(messageId, emoji);
        }
        catch (Exception exception)
        {
            ChatErrorText.Text = exception.Message;
            Refresh();
        }
    }

    private async void OnComposerKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter && !e.KeyStatus.IsMenuKeyDown)
        {
            e.Handled = true;
            await SendComposer();
        }
    }

    private async Task SendComposer()
    {
        if (_session.SelectedChannelId is not { } channelId)
        {
            return;
        }

        var text = ComposerBox.Text;

        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        ComposerBox.Text = string.Empty;
        ChatErrorText.Text = "";

        try
        {
            await _session.SendMessageAsync(channelId, text);
        }
        catch (Exception exception)
        {
            ChatErrorText.Text = exception.Message;
        }
    }

    private static string LanguagePreferencePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Sharkord",
        "language"
    );

    private sealed record MessageItem(
        int Id,
        string Text,
        IReadOnlyList<ReactionItem> Reactions,
        string AddReactionLabel,
        string AddReactionGlyph
    );

    private sealed record ReactionItem(int MessageId, string Emoji, string Label, bool Mine);
    private sealed record ChannelTreeItem(string Name, int? ChannelId, string? GroupKey);
}
