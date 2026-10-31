using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage.Streams;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private SessionPhase _lastSoundPhase;
    private int? _lastSoundVoiceChannel;
    private Dictionary<int, VoiceUserState> _previousVoiceSounds = [];
    private (bool Muted, bool Deafened, bool Camera, bool Screen)? _previousOwnSounds;

    private async Task PlayEventSoundAsync(string name, bool preview = false)
    {
        if (!preview && (_deafened || !ReadPreference("sounds.enabled", true) || !ReadPreference($"sounds.{name}", true))) { return; }
        var stream = new InMemoryRandomAccessStream();
        MediaPlayer? player = null;
        try
        {
            using (var writer = new DataWriter(stream))
            {
                writer.WriteBytes(EventSounds.Wave(name));
                await writer.StoreAsync();
                writer.DetachStream();
            }
            stream.Seek(0);
            player = new MediaPlayer { Source = MediaSource.CreateFromStream(stream, "audio/wav") };
            player.MediaEnded += (_, _) => { player.Dispose(); stream.Dispose(); };
            player.MediaFailed += (_, _) => { player.Dispose(); stream.Dispose(); };
            player.Play();
        }
        catch (Exception error)
        {
            player?.Dispose(); stream.Dispose();
            ClientLogStore.Shared.RecordError("sounds.play", error);
        }
    }

    private FrameworkElement BuildEventSoundSettings()
    {
        var panel = new StackPanel { Spacing = 10, Margin = new Thickness(20) };
        var enabled = new CheckBox { Content = L10n.T("soundsTitle", ns: "dialogs"), IsChecked = ReadPreference("sounds.enabled", true) };
        enabled.Checked += (_, _) => SavePreference("sounds.enabled", true);
        enabled.Unchecked += (_, _) => SavePreference("sounds.enabled", false);
        panel.Children.Add(enabled);
        foreach (var name in EventSounds.Names)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
            var toggle = new CheckBox { Content = name, IsChecked = ReadPreference($"sounds.{name}", true), MinWidth = 310 };
            toggle.Checked += (_, _) => SavePreference($"sounds.{name}", true);
            toggle.Unchecked += (_, _) => SavePreference($"sounds.{name}", false);
            var play = new Button { Content = L10n.T("playSound", ns: "dialogs") };
            play.Click += async (_, _) => await PlayEventSoundAsync(name, preview: true);
            row.Children.Add(toggle); row.Children.Add(play); panel.Children.Add(row);
        }
        return new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private void RefreshSoundEvents()
    {
        if (_lastSoundPhase == SessionPhase.Connected && _session.Phase != SessionPhase.Connected) { _ = PlayEventSoundAsync("server_disconnected"); }
        _lastSoundPhase = _session.Phase;
        var channel = _voiceMediaStatus == "connected" ? _session.CurrentVoiceChannelId : null;
        if (channel != _lastSoundVoiceChannel)
        {
            if (_lastSoundVoiceChannel is not null) { _ = PlayEventSoundAsync("own_user_left_voice_channel"); }
            if (channel is not null) { _ = PlayEventSoundAsync("own_user_joined_voice_channel"); }
            _lastSoundVoiceChannel = channel;
            _previousVoiceSounds = channel is { } id ? _session.GetVoiceUsers(id).ToDictionary(user => user.UserId, user => user.State) : [];
            _previousOwnSounds = null;
        }
        if (channel is not { } voiceId) { return; }
        var own = (Muted: _microphoneMuted, Deafened: _deafened, Camera: _webcamEnabled, Screen: _mediaState["screenSharing"]?.GetValue<bool>() ?? false);
        if (_previousOwnSounds is { } previous)
        {
            if (previous.Muted != own.Muted) { _ = PlayEventSoundAsync(own.Muted ? "own_user_muted_mic" : "own_user_unmuted_mic"); }
            if (previous.Deafened != own.Deafened) { _ = PlayEventSoundAsync(own.Deafened ? "own_user_muted_sound" : "own_user_unmuted_sound"); }
            if (previous.Camera != own.Camera) { _ = PlayEventSoundAsync(own.Camera ? "own_user_started_webcam" : "own_user_stopped_webcam"); }
            if (previous.Screen != own.Screen) { _ = PlayEventSoundAsync(own.Screen ? "own_user_started_screenshare" : "own_user_stopped_screenshare"); }
        }
        _previousOwnSounds = own;
        var current = _session.GetVoiceUsers(voiceId).ToDictionary(user => user.UserId, user => user.State);
        foreach (var user in current.Where(user => user.Key != _session.OwnUserId))
        {
            if (!_previousVoiceSounds.TryGetValue(user.Key, out var old)) { _ = PlayEventSoundAsync("remote_user_joined_voice_channel"); }
            else if (old.SharingScreen != user.Value.SharingScreen) { _ = PlayEventSoundAsync(user.Value.SharingScreen ? "remote_user_started_screenshare" : "remote_user_stopped_screenshare"); }
        }
        foreach (var id in _previousVoiceSounds.Keys.Where(id => id != _session.OwnUserId && !current.ContainsKey(id))) { _ = PlayEventSoundAsync("remote_user_left_voice_channel"); }
        _previousVoiceSounds = current;
    }
}
