using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private readonly Dictionary<string, TaskCompletionSource<JsonNode?>> _mediaCalls = [];
    private readonly Dictionary<int, (string Emoji, long Until)> _voiceReactions = [];
    private readonly StackPanel _voiceRoster = new() { Spacing = 6 };
    private readonly StackPanel _voiceExtras = new() { Orientation = Orientation.Horizontal, Spacing = 8 };
    private readonly Button _screenShareControl = new();
    private JsonObject _mediaState = new();
    private string? _renderedVoiceState;
    private bool _mediaFullscreen;
    private JsonObject _mediaOptions = new();
    private int? _reactionChannelId;

    private void InitializeNativeVoiceControls()
    {
        var panel = VoiceChannelPanel.Children.OfType<StackPanel>().Single();
        var devices = new Button();
        devices.Click += async (_, _) => await ShowMediaDevicesAsync();
        var reaction = new Button();
        reaction.Click += OnVoiceReactionClick;
        _screenShareControl.Click += async (_, _) => await RunMediaActionAsync("screen");
        _voiceExtras.Children.Add(devices);
        _voiceExtras.Children.Add(_screenShareControl);
        _voiceExtras.Children.Add(reaction);
        panel.Children.Add(_voiceExtras);
        panel.Children.Add(new ScrollViewer { Content = _voiceRoster, MaxHeight = 340, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        _session.VoiceReactionReceived += OnVoiceReaction;
        _session.VoiceMoveRequested += OnVoiceMoveRequested;
        var reactionTimer = DispatcherQueue.CreateTimer();
        reactionTimer.Interval = TimeSpan.FromSeconds(1);
        reactionTimer.Tick += (_, _) =>
        {
            var expired = _voiceReactions.Where(entry => entry.Value.Until <= Environment.TickCount64).Select(entry => entry.Key).ToArray();
            foreach (var userId in expired) { _voiceReactions.Remove(userId); }
            if (expired.Length > 0) { RefreshNativeVoiceControls(); }
        };
        reactionTimer.Start();
        Closed += (_, _) =>
        {
            reactionTimer.Stop();
            _session.VoiceReactionReceived -= OnVoiceReaction;
            _session.VoiceMoveRequested -= OnVoiceMoveRequested;
            foreach (var call in _mediaCalls.Values) { call.TrySetCanceled(); }
        };
        try
        {
            var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "cove", "media-settings.json");
            if (File.Exists(path)) { _mediaOptions = JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? new(); }
        }
        catch (Exception error) { ClientLogStore.Shared.RecordError("media.preferences.read", error); }
    }

    private bool HandleNativeMediaMessage(JsonObject message)
    {
        if (message.GetString("type") == "mediaResult" && message.GetString("id") is { } id)
        {
            if (_mediaCalls.Remove(id, out var call))
            {
                if (message.GetString("error") is { } error) { call.TrySetException(new InvalidOperationException(error)); }
                else { call.TrySetResult(message["result"]?.DeepClone()); }
            }
            return true;
        }
        if (message.GetString("type") != "mediaState") { return false; }
        if (message.GetInt("channelId") != _session.CurrentVoiceChannelId) { return true; }
        _mediaState = message;
        _microphoneMuted = message["microphoneMuted"]?.GetValue<bool>() ?? true;
        _deafened = message["outputMuted"]?.GetValue<bool>() ?? false;
        _webcamEnabled = message["webcamEnabled"]?.GetValue<bool>() ?? false;
        RefreshNativeVoiceControls();
        RefreshUserVoiceControls();
        return true;
    }

    private async Task<JsonNode?> CallMediaAsync(string action, params object?[] arguments)
    {
        await WaitForVoiceWorkerAsync();
        var id = Guid.NewGuid().ToString("N");
        var completion = new TaskCompletionSource<JsonNode?>(TaskCreationOptions.RunContinuationsAsynchronously);
        _mediaCalls[id] = completion;
        try
        {
            var script = $"(async()=>{{try{{const result=await window.coveMedia[{JsonSerializer.Serialize(action)}](...{JsonSerializer.Serialize(arguments)});chrome.webview.postMessage({{type:'mediaResult',id:'{id}',result:result??null}});}}catch(error){{chrome.webview.postMessage({{type:'mediaResult',id:'{id}',error:String(error.message??error)}});}}}})()";
            await VoiceMediaWebView.ExecuteScriptAsync(script);
            return await completion.Task.WaitAsync(TimeSpan.FromSeconds(20));
        }
        finally { _mediaCalls.Remove(id); }
    }

    private async Task RunMediaActionAsync(string action, params object?[] arguments)
    {
        try { await CallMediaAsync(action, arguments); VoiceErrorText.Text = ""; }
        catch (Exception error) { VoiceErrorText.Text = error.Message; ClientLogStore.Shared.RecordError("media.control", error); }
    }

    private async Task ApplyMediaOptionsAsync(int? channelId = null)
    {
        var options = _mediaOptions.DeepClone().AsObject();
        options["simulcast"] = _session.Settings?.WebRtcSimulcastEnabled == true && options["simulcast"]?.GetValue<bool>() == true;
        var external = new JsonObject();
        if (channelId is { } id)
        {
            foreach (var stream in _session.GetExternalStreams(id)) { external[stream.Key.ToString()] = stream.Value.Tracks?.DeepClone(); }
        }
        options["externalStreams"] = external;
        await CallMediaAsync("options", options);
    }

    private void RefreshNativeVoiceControls()
    {
        RefreshSoundEvents();
        var channelId = _session.SelectedChannelId;
        if (_reactionChannelId != channelId) { _voiceReactions.Clear(); }
        var connected = channelId is not null && channelId == _session.CurrentVoiceChannelId && _voiceMediaStatus == "connected";
        ((Button)_voiceExtras.Children[0]).Content = L10n.T("devicesTab", ns: "settings");
        ((Button)_voiceExtras.Children[2]).Content = L10n.T("addReaction");
        ((Button)_voiceExtras.Children[2]).IsEnabled = connected && _session.HasPermission("SEND_VOICE_REACTION");
        _screenShareControl.Content = L10n.T(_mediaState["screenSharing"]?.GetValue<bool>() == true ? "stopScreenShare" : "shareScreen", ns: "windows");
        _screenShareControl.IsEnabled = connected && _session.HasPermission("SHARE_SCREEN") && _session.HasChannelPermission(channelId!.Value, "SHARE_SCREEN");
        var users = channelId is { } selected ? _session.GetVoiceUsers(selected) : [];
        var speaking = (connected ? _mediaState["speaking"] as JsonArray ?? [] : new JsonArray()).Select(value => value.AsInt() ?? -1).Select(id => id == 0 ? _session.OwnUserId : id).ToHashSet();
        var activeReactions = _voiceReactions.Where(entry => entry.Value.Until > Environment.TickCount64).ToDictionary();
        var streams = connected ? _mediaState["streams"] as JsonArray ?? [] : new JsonArray();
        var signature = JsonSerializer.Serialize(new { channelId, connected, users, speaking, activeReactions, streams, language = L10n.Language });
        if (signature == _renderedVoiceState) { return; }
        _renderedVoiceState = signature;
        _voiceRoster.Children.Clear();
        foreach (var participant in users)
        {
            var user = _session.Users.FirstOrDefault(user => user.Id == participant.UserId);
            var states = new List<string>();
            if (participant.State.MicMuted) { states.Add(L10n.T("muteMic", ns: "windows")); }
            if (participant.State.SoundMuted) { states.Add(L10n.T("deafen", ns: "windows")); }
            if (participant.State.WebcamEnabled) { states.Add(L10n.T("webcamLabel", ns: "settings")); }
            if (participant.State.SharingScreen) { states.Add(L10n.T("screenSharingLabel", ns: "settings")); }
            if (speaking.Contains(participant.UserId)) { states.Add(L10n.T("speaking", ns: "media")); }
            if (activeReactions.TryGetValue(participant.UserId, out var reaction)) { states.Add(EmojiCatalog.Glyph(reaction.Emoji)); }
            var row = new Button
            {
                Content = $"{user?.Name ?? participant.UserId.ToString()}  {string.Join(" · ", states)}",
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                BorderBrush = new SolidColorBrush(speaking.Contains(participant.UserId) ? Colors.LimeGreen : Colors.Transparent),
                BorderThickness = new Thickness(2)
            };
            row.Click += async (_, _) => await ShowVoiceParticipantAsync(participant.UserId);
            _voiceRoster.Children.Add(row);
        }
        foreach (var stream in streams.OfType<JsonObject>())
        {
            var key = stream.GetString("key")!;
            var remoteId = stream.GetInt("remoteId") ?? 0;
            var label = _session.Users.FirstOrDefault(user => user.Id == remoteId)?.Name ?? remoteId.ToString();
            if (stream.GetString("kind")?.StartsWith("external_", StringComparison.Ordinal) == true)
            {
                label = _session.GetExternalStreams(channelId!.Value).FirstOrDefault(entry => entry.Key == remoteId).Value?.Title ?? label;
            }
            var button = new Button { Content = $"{label} · {MediaKindLabel(stream.GetString("kind"))}", Tag = key };
            button.Click += async (_, _) => await ShowStreamControlsAsync(stream);
            _voiceRoster.Children.Add(button);
        }
    }

    private static string MediaKindLabel(string? kind) => kind switch
    {
        "audio" or "external_audio" => L10n.T("microphoneLabel", ns: "settings"),
        "screen_audio" => L10n.T("screenAudio", ns: "media"),
        "screen" => L10n.T("screenSharingLabel", ns: "settings"),
        _ => L10n.T("webcamLabel", ns: "settings")
    };

    private void OnVoiceReaction(int channelId, int userId, string emoji) => DispatcherQueue.TryEnqueue(() =>
    {
        if (_session.SelectedChannelId != channelId) { return; }
        _reactionChannelId = channelId;
        _voiceReactions[userId] = (emoji, Environment.TickCount64 + 4000);
        RefreshNativeVoiceControls();
    });

    private void OnVoiceMoveRequested(int from, int target) => DispatcherQueue.TryEnqueue(async () =>
    {
        if (_session.CurrentVoiceChannelId != from) { return; }
        try { await _session.SelectChannelAsync(target); OnJoinVoiceClick(this, new RoutedEventArgs()); }
        catch (Exception error) { VoiceErrorText.Text = error.Message; }
    });

    private void OnVoiceReactionClick(object sender, RoutedEventArgs args)
    {
        if (sender is not FrameworkElement anchor || _session.CurrentVoiceChannelId is not { } channelId) { return; }
        ShowEmojiPicker(anchor, async emoji =>
        {
            if (_session.CurrentVoiceChannelId != channelId || !_session.HasPermission("SEND_VOICE_REACTION")) { return; }
            try { await _session.CallMutationAsync("voice.sendReaction", new JsonObject { ["emoji"] = emoji.Shortcode }); }
            catch (Exception error) { VoiceErrorText.Text = error.Message; }
        }, reactions: true);
    }

    private async Task ShowVoiceParticipantAsync(int userId)
    {
        var panel = new StackPanel { Spacing = 12, MinWidth = 320 };
        AddRemoteVolume(panel, userId, "audio", L10n.T("userVolume", ns: "sidebar"));
        AddRemoteVolume(panel, userId, "screen_audio", L10n.T("screenAudio", ns: "media"));
        if (_session.HasPermission("MOVE_MEMBERS") && _session.SelectedChannelId is { } selected && _session.Channel(selected)?.IsDm == false)
        {
            var destinations = new ComboBox { Header = L10n.T("moveTo", ns: "macos"), DisplayMemberPath = "Name", ItemsSource = _session.Channels.Where(channel => channel.IsVoice && !channel.IsDm && channel.Id != selected && _session.CanViewChannel(channel) && _session.HasChannelPermission(channel.Id, "JOIN")).ToArray() };
            panel.Children.Add(destinations);
            var move = new Button { Content = L10n.T("moveTo", ns: "macos") };
            var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
            move.Click += async (_, _) =>
            {
                if (destinations.SelectedItem is not SharkordChannel target) { return; }
                try { await _session.CallMutationAsync("voice.moveUser", new JsonObject { ["userId"] = userId, ["channelId"] = target.Id }); status.Text = target.Name; }
                catch (Exception error) { status.Text = error.Message; }
            };
            panel.Children.Add(move);
            panel.Children.Add(status);
        }
        await new ContentDialog { Title = _session.Users.FirstOrDefault(user => user.Id == userId)?.Name ?? "", Content = panel, CloseButtonText = L10n.T("close", ns: "windows"), XamlRoot = RootGrid.XamlRoot }.ShowAsync();
    }

    private void AddRemoteVolume(StackPanel panel, int userId, string kind, string label)
    {
        var volume = new Slider { Header = label, Minimum = 0, Maximum = 100, Value = 100, StepFrequency = 1 };
        volume.ValueChanged += async (_, args) => await RunMediaActionAsync("volume", userId, kind, args.NewValue / 100);
        panel.Children.Add(volume);
    }

    private async Task ShowStreamControlsAsync(JsonObject stream)
    {
        var key = stream.GetString("key")!;
        var panel = new StackPanel { Spacing = 10, MinWidth = 340 };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        if (stream["video"]?.GetValue<bool>() == true)
        {
            var quality = new ComboBox { Header = L10n.T("quality", ns: "media") };
            quality.Items.Add(new ComboBoxItem { Content = L10n.T("automatic", ns: "media"), Tag = -1 });
            foreach (var layer in (stream["qualityLayers"] as JsonArray ?? []).OfType<JsonObject>())
            {
                quality.Items.Add(new ComboBoxItem { Content = layer.GetString("label") ?? layer.GetInt("spatialLayer")?.ToString(), Tag = layer.GetInt("spatialLayer") ?? 0 });
            }
            quality.SelectedIndex = 0;
            quality.IsEnabled = quality.Items.Count > 1 && _session.Settings?.WebRtcSimulcastEnabled == true;
            quality.SelectionChanged += async (_, _) =>
            {
                if (quality.SelectedItem is ComboBoxItem { Tag: int layer }) { await RunMediaActionAsync("quality", key, layer); }
            };
            panel.Children.Add(quality);
            var pin = new CheckBox { Content = L10n.T("pinStream", ns: "media") };
            pin.Checked += async (_, _) => await RunMediaActionAsync("pin", key);
            pin.Unchecked += async (_, _) => await RunMediaActionAsync("pin", (object?)null);
            panel.Children.Add(pin);
            var zoom = new Slider { Header = L10n.T("zoom", ns: "media"), Minimum = 1, Maximum = 4, Value = 1, StepFrequency = 0.25 };
            zoom.ValueChanged += async (_, args) => await RunMediaActionAsync("zoom", key, args.NewValue);
            panel.Children.Add(zoom);
            var fullscreen = new Button { Content = L10n.T("fullscreen", ns: "media") };
            fullscreen.Click += (_, _) =>
            {
                _mediaFullscreen = !_mediaFullscreen;
                AppWindow.SetPresenter(_mediaFullscreen ? AppWindowPresenterKind.FullScreen : AppWindowPresenterKind.Overlapped);
                VoiceChannelPanel.RowDefinitions[1].Height = new GridLength(_mediaFullscreen ? 600 : 240);
            };
            panel.Children.Add(fullscreen);
            var picture = new Button { Content = L10n.T("pictureInPicture", ns: "media"), IsEnabled = _mediaState["pictureInPicture"]?.GetValue<bool>() == true };
            picture.Click += async (_, _) => await RunMediaActionAsync("picture", key);
            panel.Children.Add(picture);
        }
        else { AddRemoteVolume(panel, stream.GetInt("remoteId")!.Value, stream.GetString("kind")!, L10n.T("userVolume", ns: "sidebar")); }
        var statistics = new Button { Content = L10n.T("statistics", ns: "media") };
        statistics.Click += async (_, _) =>
        {
            try { status.Text = (await CallMediaAsync("statistics", key))?.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) ?? ""; }
            catch (Exception error) { status.Text = error.Message; }
        };
        panel.Children.Add(statistics);
        panel.Children.Add(status);
        await new ContentDialog { Title = MediaKindLabel(stream.GetString("kind")), Content = panel, CloseButtonText = L10n.T("close", ns: "windows"), XamlRoot = RootGrid.XamlRoot }.ShowAsync();
    }
}
