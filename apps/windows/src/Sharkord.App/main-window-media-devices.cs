using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private (int ChannelId, string? Server, long Generation, bool MicrophoneMuted, bool Deafened)? _voiceBeforePreview;
    private object? _activePreviewContext;
    private int _previewOperation;

    private void InvalidateMediaPreview()
    {
        _previewOperation++;
        _voiceBeforePreview = null;
        _activePreviewContext = null;
    }

    private async Task StopMediaPreviewAsync()
    {
        var operation = ++_previewOperation;
        var previous = _voiceBeforePreview;
        _voiceBeforePreview = null;
        await RunMediaActionAsync("stopPreview");
        if (previous is { } voice && operation == _previewOperation &&
            _session.Phase == SessionPhase.Connected && voice.Generation == _session.HistoryGeneration &&
            voice.ChannelId == _session.CurrentVoiceChannelId && voice.Server == _session.ServerBaseUrl)
        {
            await ExecuteVoiceActionAsync("setOutputMuted", voice.Deafened);
            if (operation == _previewOperation && _session.Phase == SessionPhase.Connected && voice.Generation == _session.HistoryGeneration && voice.ChannelId == _session.CurrentVoiceChannelId && voice.Server == _session.ServerBaseUrl)
            {
                await ExecuteVoiceActionAsync("setMicrophoneMuted", voice.MicrophoneMuted);
            }
        }
    }

    private async Task ShowMediaDevicesAsync()
    {
        try
        {
            var content = await BuildMediaDeviceSettingsAsync();
            await new ContentDialog
            {
                Title = L10n.T("devicesTab", ns: "settings"), Content = content,
                CloseButtonText = L10n.T("close", ns: "windows"), XamlRoot = RootGrid.XamlRoot
            }.ShowAsync();
        }
        catch (Exception error) { VoiceErrorText.Text = error.Message; }
    }

    private async Task<FrameworkElement> BuildMediaDeviceSettingsAsync()
    {
        await WaitForVoiceWorkerAsync();
        var devices = await CallMediaAsync("devices") as JsonArray ?? [];
        var panel = new StackPanel { Spacing = 10, MinWidth = 360, Margin = new Thickness(16) };
        var previewContext = new object();
        var meter = new ProgressBar { Minimum = 0, Maximum = 100, Height = 8 };
        var meterTimer = DispatcherQueue.CreateTimer();
        var mediaHost = new Grid { Height = 180 };
        mediaHost.Loaded += (_, _) =>
        {
            _activePreviewContext = previewContext;
            if (VoiceMediaWebView.Parent == VoiceChannelPanel)
            {
                VoiceChannelPanel.Children.Remove(VoiceMediaWebView);
                mediaHost.Children.Add(VoiceMediaWebView);
                Grid.SetRow(VoiceMediaWebView, 0);
            }
        };
        mediaHost.Unloaded += async (_, _) =>
        {
            if (ReferenceEquals(_activePreviewContext, previewContext))
            {
                _activePreviewContext = null;
                await StopMediaPreviewAsync();
            }
            if (VoiceMediaWebView.Parent == mediaHost)
            {
                mediaHost.Children.Remove(VoiceMediaWebView);
                VoiceChannelPanel.Children.Add(VoiceMediaWebView);
                Grid.SetRow(VoiceMediaWebView, 1);
            }
        };
        panel.Children.Add(mediaHost);
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        if (_session.CurrentVoiceChannelId is not null) { panel.Children.Add(new TextBlock { Text = L10n.T("voiceChannelActiveInfo", ns: "settings"), TextWrapping = TextWrapping.Wrap }); }
        AddDeviceChoice(panel, devices, "audioinput", "microphoneId", "microphoneLabel", "defaultMicrophone");
        AddDeviceChoice(panel, devices, "audiooutput", "speakerId", "playbackLabel", "defaultOutput");
        AddDeviceChoice(panel, devices, "videoinput", "cameraId", "webcamLabel", "defaultWebcam");
        AddMediaToggle(panel, "echoCancellation", "echoCancellationLabel", true);
        AddMediaToggle(panel, "autoGainControl", "autoGainControlLabel", true);
        AddMediaChoice(panel, "noiseMode", L10n.T("noiseSuppressionLabel", ns: "settings"),
        [
            ("off", L10n.T("noiseSuppressionNone", ns: "settings")),
            ("standard", L10n.T("noiseSuppressionStandardName", ns: "settings")),
            ("rnnoise", L10n.T("noiseSuppressionRnnoiseName", ns: "settings")),
            ("dtln", L10n.T("noiseSuppressionDtlnName", ns: "settings"))
        ], "rnnoise");
        panel.Children.Add(BuildNoiseSuppressionSettings());
        AddMediaToggle(panel, "noiseGateEnabled", "noiseGateLabel", false);
        AddNoiseGateThreshold(panel);
        AddMediaNumbers(panel, "height", "cameraResolution", [360, 720, 1080], 720);
        AddMediaNumbers(panel, "frameRate", "cameraFrameRate", [15, 30, 60], 30);
        AddMediaToggle(panel, "mirrorOwnVideo", "mirrorOwnVideoLabel", false);
        AddMediaNumbers(panel, "screenHeight", "screenResolution", [720, 1080, 1440, 2160], 1080);
        AddMediaNumbers(panel, "screenFrameRate", "screenFrameRate", [15, 30, 60], 30);
        AddMediaChoice(panel, "screenCodec", L10n.T("selectCodecPlaceholder", ns: "settings"),
        [
            ("auto", L10n.T("automatic", ns: "media")),
            ("video/VP8", "VP8"),
            ("video/VP9", "VP9"),
            ("video/H264", "H264"),
            ("video/AV1", "AV1")
        ], "auto");
        AddMediaChoice(panel, "screenCursor", L10n.T("screenCursorLabel", ns: "settings"),
        [
            ("always", L10n.T("screenCursorAlways", ns: "settings")),
            ("motion", L10n.T("screenCursorMotion", ns: "settings")),
            ("never", L10n.T("screenCursorNever", ns: "settings"))
        ], "always");
        AddScreenBitrate(panel);
        var simulcast = AddMediaToggle(panel, "simulcast", "simulcastUserLabel", false);
        simulcast.IsEnabled = _session.Settings?.WebRtcSimulcastEnabled == true;
        if (!simulcast.IsEnabled) { panel.Children.Add(new TextBlock { Text = L10n.T("simulcastDisabledByServerDesc", ns: "settings"), TextWrapping = TextWrapping.Wrap }); }
        var controls = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var microphone = new Button { Content = L10n.T("startTestBtn", ns: "settings") };
        var camera = new Button { Content = L10n.T("startVideoPreviewBtn", ns: "settings") };
        var stop = new Button { Content = L10n.T("stopTestBtn", ns: "settings") };
        microphone.Click += async (_, _) => await PreviewMediaDeviceAsync("audio", status, previewContext);
        camera.Click += async (_, _) => await PreviewMediaDeviceAsync("video", status, previewContext);
        stop.Click += async (_, _) => await StopMediaPreviewAsync();
        controls.Children.Add(microphone);
        controls.Children.Add(camera);
        controls.Children.Add(stop);
        panel.Children.Add(controls);
        panel.Children.Add(meter);
        // the meter only reads while this dialog owns the media webview, so a stray tick
        // after it closed cannot keep the worker busy.
        meterTimer.Interval = TimeSpan.FromMilliseconds(100);
        var meterBusy = false;
        meterTimer.Tick += async (_, _) =>
        {
            if (meterBusy || !ReferenceEquals(_activePreviewContext, previewContext)) { return; }
            meterBusy = true;
            try
            {
                meter.Value = await CallMediaAsync("level") is JsonValue { } reading && reading.TryGetValue<double>(out var level) ? Math.Clamp(level, 0, 100) : 0;
            }
            catch (Exception) { meter.Value = 0; }
            finally { meterBusy = false; }
        };
        mediaHost.Loaded += (_, _) => meterTimer.Start();
        mediaHost.Unloaded += (_, _) => { meterTimer.Stop(); meter.Value = 0; };
        var save = new Button { Content = L10n.T("saveChanges", ns: "common") };
        save.Click += async (_, _) =>
        {
            try
            {
                await ApplyMediaOptionsAsync(_session.CurrentVoiceChannelId);
                var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "cove");
                Directory.CreateDirectory(folder);
                await File.WriteAllTextAsync(Path.Combine(folder, "media-settings.json"), _mediaOptions.ToJsonString());
                status.Text = L10n.T("deviceSettingsSaved", ns: "settings");
            }
            catch (Exception error) { status.Text = error.Message; }
        };
        panel.Children.Add(save);
        panel.Children.Add(status);
        return new ScrollViewer { Content = panel, MaxHeight = 520, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private async Task PreviewMediaDeviceAsync(string kind, TextBlock status, object context)
    {
        var operation = ++_previewOperation;
        var channelId = _session.CurrentVoiceChannelId;
        var server = _session.ServerBaseUrl;
        var generation = _session.HistoryGeneration;
        bool IsCurrent() => operation == _previewOperation && ReferenceEquals(_activePreviewContext, context) &&
            _session.Phase == SessionPhase.Connected && generation == _session.HistoryGeneration &&
            channelId == _session.CurrentVoiceChannelId && server == _session.ServerBaseUrl;
        try
        {
            if (!IsCurrent()) { return; }
            await ApplyMediaOptionsAsync(_session.CurrentVoiceChannelId);
            if (!IsCurrent()) { return; }
            if (channelId is { } id)
            {
                _voiceBeforePreview ??= (id, server, generation, _microphoneMuted, _deafened);
                await ExecuteVoiceActionAsync("setMicrophoneMuted", true);
                if (!IsCurrent()) { return; }
                await ExecuteVoiceActionAsync("setOutputMuted", true);
                if (!IsCurrent()) { return; }
                _microphoneMuted = true;
                _deafened = true;
                status.Text = L10n.T("mutedDuringTest", ns: "settings");
            }
            if (!IsCurrent()) { return; }
            await CallMediaAsync("preview", kind);
        }
        catch (Exception error) { status.Text = error.Message; }
    }

    private void AddDeviceChoice(StackPanel panel, JsonArray devices, string kind, string option, string label, string defaultLabel)
    {
        var choice = new ComboBox { Header = L10n.T(label, ns: "settings"), HorizontalAlignment = HorizontalAlignment.Stretch };
        choice.Items.Add(new ComboBoxItem { Content = L10n.T(defaultLabel, ns: "settings"), Tag = "" });
        choice.SelectedIndex = 0;
        var index = 1;
        foreach (var device in devices.OfType<JsonObject>().Where(device => device.GetString("kind") == kind && !string.IsNullOrEmpty(device.GetString("deviceId"))))
        {
            var name = device.GetString("label");
            var item = new ComboBoxItem { Content = string.IsNullOrWhiteSpace(name) ? $"{L10n.T(label, ns: "settings")} {index++}" : name, Tag = device.GetString("deviceId")! };
            choice.Items.Add(item);
            if ((string)item.Tag == _mediaOptions.GetString(option)) { choice.SelectedItem = item; }
        }
        if (choice.SelectedIndex == 0) { _mediaOptions[option] = ""; }
        choice.SelectionChanged += (_, _) => { if (choice.SelectedItem is ComboBoxItem { Tag: string id }) { _mediaOptions[option] = id; } };
        panel.Children.Add(choice);
    }

    private CheckBox AddMediaToggle(StackPanel panel, string option, string label, bool fallback)
    {
        var toggle = new CheckBox { Content = L10n.T(label, ns: "settings"), IsChecked = _mediaOptions[option]?.GetValue<bool>() ?? fallback };
        toggle.Checked += (_, _) => _mediaOptions[option] = true;
        toggle.Unchecked += (_, _) => _mediaOptions[option] = false;
        panel.Children.Add(toggle);
        return toggle;
    }

    private void AddMediaChoice(StackPanel panel, string option, string header, (string Value, string Label)[] choices, string fallback)
    {
        var choice = new ComboBox { Header = header, HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var (value, label) in choices)
        {
            var item = new ComboBoxItem { Content = label, Tag = value };
            choice.Items.Add(item);
            if (value == (_mediaOptions.GetString(option) ?? fallback)) { choice.SelectedItem = item; }
        }
        choice.SelectionChanged += (_, _) => { if (choice.SelectedItem is ComboBoxItem { Tag: string value }) { _mediaOptions[option] = value; } };
        panel.Children.Add(choice);
    }

    private void AddNoiseGateThreshold(StackPanel panel)
    {
        var threshold = new Slider
        {
            Header = L10n.T("noiseGateThresholdLabel", ns: "media"),
            Minimum = -70,
            Maximum = 0,
            StepFrequency = 1,
            Value = _mediaOptions["noiseGateThresholdDb"]?.GetValue<double>() ?? -48,
            IsThumbToolTipEnabled = true
        };
        threshold.ValueChanged += (_, args) => _mediaOptions["noiseGateThresholdDb"] = args.NewValue;
        panel.Children.Add(threshold);
    }

    private void AddScreenBitrate(StackPanel panel)
    {
        // the server states its ceiling in bits per second, the slider works in kbps.
        var maximum = Math.Max(6000, (_session.Settings?.WebRtcMaxBitrate ?? 10_000_000) / 1000);
        var slider = new Slider
        {
            Header = L10n.T("maxBitrateLabel", ns: "settings"),
            Minimum = 200,
            Maximum = maximum,
            StepFrequency = 100,
            Value = Math.Clamp(_mediaOptions["screenBitrate"]?.GetValue<double>() ?? 6000, 200, maximum),
            IsThumbToolTipEnabled = true
        };
        slider.ValueChanged += (_, args) => _mediaOptions["screenBitrate"] = args.NewValue;
        panel.Children.Add(slider);
    }

    private void AddMediaNumbers(StackPanel panel, string option, string label, int[] values, int fallback)
    {
        var choice = new ComboBox { Header = L10n.T(label, ns: "media"), ItemsSource = values, SelectedItem = _mediaOptions.GetInt(option) ?? fallback };
        choice.SelectionChanged += (_, _) => { if (choice.SelectedItem is int value) { _mediaOptions[option] = value; } };
        panel.Children.Add(choice);
    }
}
