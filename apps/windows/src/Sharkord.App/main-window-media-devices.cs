using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private (bool MicrophoneMuted, bool Deafened)? _voiceBeforePreview;

    private async Task StopMediaPreviewAsync()
    {
        await RunMediaActionAsync("stopPreview");
        if (_voiceBeforePreview is { } previous && _session.CurrentVoiceChannelId is not null)
        {
            await ExecuteVoiceActionAsync("setOutputMuted", previous.Deafened);
            await ExecuteVoiceActionAsync("setMicrophoneMuted", previous.MicrophoneMuted);
        }
        _voiceBeforePreview = null;
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
        var mediaHost = new Grid { Height = 180 };
        mediaHost.Loaded += (_, _) =>
        {
            if (VoiceMediaWebView.Parent == VoiceChannelPanel)
            {
                VoiceChannelPanel.Children.Remove(VoiceMediaWebView);
                mediaHost.Children.Add(VoiceMediaWebView);
                Grid.SetRow(VoiceMediaWebView, 0);
            }
        };
        mediaHost.Unloaded += async (_, _) =>
        {
            await StopMediaPreviewAsync();
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
        var mode = new ComboBox { Header = L10n.T("noiseSuppressionLabel", ns: "settings") };
        foreach (var (value, label) in new[] { ("off", "noiseSuppressionNone"), ("standard", "noiseSuppressionStandardName"), ("rnnoise", "noiseSuppressionRnnoiseName") })
        {
            var choice = new ComboBoxItem { Content = L10n.T(label, ns: "settings"), Tag = value };
            mode.Items.Add(choice);
            if (value == (_mediaOptions.GetString("noiseMode") ?? "rnnoise")) { mode.SelectedItem = choice; }
        }
        mode.SelectionChanged += (_, _) => { if (mode.SelectedItem is ComboBoxItem { Tag: string value }) { _mediaOptions["noiseMode"] = value; } };
        panel.Children.Add(mode);
        panel.Children.Add(BuildNoiseSuppressionSettings());
        AddMediaNumbers(panel, "height", "cameraResolution", [360, 720, 1080], 720);
        AddMediaNumbers(panel, "frameRate", "cameraFrameRate", [15, 30, 60], 30);
        AddMediaNumbers(panel, "screenHeight", "screenResolution", [720, 1080, 1440, 2160], 1080);
        AddMediaNumbers(panel, "screenFrameRate", "screenFrameRate", [15, 30, 60], 30);
        var simulcast = AddMediaToggle(panel, "simulcast", "simulcastUserLabel", false);
        simulcast.IsEnabled = _session.Settings?.WebRtcSimulcastEnabled == true;
        if (!simulcast.IsEnabled) { panel.Children.Add(new TextBlock { Text = L10n.T("simulcastDisabledByServerDesc", ns: "settings"), TextWrapping = TextWrapping.Wrap }); }
        var controls = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var microphone = new Button { Content = L10n.T("startTestBtn", ns: "settings") };
        var camera = new Button { Content = L10n.T("startVideoPreviewBtn", ns: "settings") };
        var stop = new Button { Content = L10n.T("stopTestBtn", ns: "settings") };
        microphone.Click += async (_, _) => await PreviewMediaDeviceAsync("audio", status);
        camera.Click += async (_, _) => await PreviewMediaDeviceAsync("video", status);
        stop.Click += async (_, _) => await StopMediaPreviewAsync();
        controls.Children.Add(microphone);
        controls.Children.Add(camera);
        controls.Children.Add(stop);
        panel.Children.Add(controls);
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

    private async Task PreviewMediaDeviceAsync(string kind, TextBlock status)
    {
        try
        {
            await ApplyMediaOptionsAsync(_session.CurrentVoiceChannelId);
            if (_session.CurrentVoiceChannelId is not null)
            {
                _voiceBeforePreview ??= (_microphoneMuted, _deafened);
                await ExecuteVoiceActionAsync("setMicrophoneMuted", true);
                await ExecuteVoiceActionAsync("setOutputMuted", true);
                _microphoneMuted = true;
                _deafened = true;
                status.Text = L10n.T("mutedDuringTest", ns: "settings");
            }
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

    private void AddMediaNumbers(StackPanel panel, string option, string label, int[] values, int fallback)
    {
        var choice = new ComboBox { Header = L10n.T(label, ns: "media"), ItemsSource = values, SelectedItem = _mediaOptions.GetInt(option) ?? fallback };
        choice.SelectionChanged += (_, _) => { if (choice.SelectedItem is int value) { _mediaOptions[option] = value; } };
        panel.Children.Add(choice);
    }
}
