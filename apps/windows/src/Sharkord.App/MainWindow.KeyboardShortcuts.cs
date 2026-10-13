using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private const int ControlKey = 0x11;
    private const int MenuKey = 0x12;
    private const int ShiftKey = 0x10;
    private const int LeftWindowsKey = 0x5B;
    private const int RightWindowsKey = 0x5C;
    private const string KeyboardShortcutPreferenceKey = "keyboard.shortcuts";

    private KeyboardShortcutPreferences _keyboardShortcutPreferences = new();
    private KeyboardShortcutAction? _recordingShortcutAction;
    private readonly PushToTalkState _pushToTalkState = new();
    private GlobalPushToTalkHook? _pushToTalkHook;
    private bool _pushToTalkEnabled;
    private TextBlock? _pushToTalkStatusText;
    private readonly Dictionary<KeyboardShortcutAction, TextBlock> _shortcutDescriptionLabels = [];
    private readonly Dictionary<KeyboardShortcutAction, Button> _shortcutRecordButtons = [];
    private readonly Dictionary<KeyboardShortcutAction, Button> _shortcutClearButtons = [];
    private readonly Dictionary<KeyboardShortcutAction, TextBlock> _shortcutStatusLabels = [];
    private readonly Dictionary<KeyboardShortcutAction, string?> _shortcutAssignmentErrors = [];

    private FrameworkElement BuildKeyboardShortcutSettings()
    {
        _shortcutDescriptionLabels.Clear();
        _shortcutRecordButtons.Clear();
        _shortcutClearButtons.Clear();
        _shortcutStatusLabels.Clear();
        _shortcutAssignmentErrors.Clear();

        var content = new StackPanel { Spacing = 10, Margin = new Thickness(20) };
        content.Children.Add(new TextBlock
        {
            Text = L10n.T("keyboardShortcutsDescription", ns: "macos"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        });

        foreach (var action in Enum.GetValues<KeyboardShortcutAction>())
        {
            content.Children.Add(CreateKeyboardShortcutRow(action));
        }

        return new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private FrameworkElement CreateKeyboardShortcutRow(KeyboardShortcutAction action)
    {
        var title = new TextBlock
        {
            Text = L10n.T(ShortcutTitleKey(action), ns: "macos"),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        };
        var description = new TextBlock
        {
            Text = ShortcutDescription(action),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        };
        var status = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(
                Windows.UI.Color.FromArgb(255, 190, 70, 70)
            )
        };
        var record = new Button();
        var clear = new Button { Content = L10n.T("keyboardShortcutClear", ns: "macos") };

        record.Click += (_, _) => BeginShortcutRecording(action, record);
        record.AddHandler(
            UIElement.KeyDownEvent,
            new KeyEventHandler(OnShortcutCaptureKeyDown),
            handledEventsToo: true
        );
        clear.Click += (_, _) => AssignShortcut(action, null);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        buttons.Children.Add(record);
        buttons.Children.Add(clear);

        var row = new StackPanel { Spacing = 6, Margin = new Thickness(0, 10, 0, 10) };
        row.Children.Add(title);
        row.Children.Add(description);
        row.Children.Add(status);

        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        row.Children.Add(buttons);

        _shortcutDescriptionLabels[action] = description;
        _shortcutRecordButtons[action] = record;
        _shortcutClearButtons[action] = clear;
        _shortcutStatusLabels[action] = status;
        RefreshKeyboardShortcutRows();
        return row;
    }

    private void BeginShortcutRecording(KeyboardShortcutAction action, Button button)
    {
        _recordingShortcutAction = action;
        _shortcutAssignmentErrors[action] = null;
        RefreshKeyboardShortcutRows();
        button.Focus(FocusState.Programmatic);
    }

    private void OnShortcutCaptureKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (_recordingShortcutAction is not { } action)
        {
            return;
        }

        var keyCode = (int)e.Key;
        if (keyCode == 27)
        {
            _recordingShortcutAction = null;
            _shortcutAssignmentErrors[action] = null;
            RefreshKeyboardShortcutRows();
            e.Handled = true;
            return;
        }

        if (keyCode is 8 or 46)
        {
            AssignShortcut(action, null);
            e.Handled = true;
            return;
        }

        if (keyCode is 16 or 17 or 18 or 91 or 92)
        {
            return;
        }

        AssignShortcut(action, new KeyboardShortcutBinding(keyCode, ReadShortcutModifiers()));
        e.Handled = true;
    }

    private void AssignShortcut(KeyboardShortcutAction action, KeyboardShortcutBinding? binding)
    {
        var error = _keyboardShortcutPreferences.TryAssign(binding, action, out var updated);
        if (error is not null)
        {
            _shortcutAssignmentErrors[action] = ShortcutAssignmentErrorMessage(action, binding, error.Value);
            RefreshKeyboardShortcutRows();
            return;
        }

        _keyboardShortcutPreferences = updated;
        _recordingShortcutAction = null;
        _shortcutAssignmentErrors[action] = null;
        SaveKeyboardShortcutPreferences(updated);
        RefreshKeyboardShortcutRows();
    }

    private string? ShortcutAssignmentErrorMessage(
        KeyboardShortcutAction action,
        KeyboardShortcutBinding? binding,
        KeyboardShortcutAssignmentError error
    )
    {
        return error switch
        {
            KeyboardShortcutAssignmentError.ModifierRequired =>
                L10n.T("keyboardShortcutModifierRequired", ns: "macos"),
            KeyboardShortcutAssignmentError.ReturnReservedForNewline =>
                L10n.T("keyboardShortcutReturnReserved", ns: "macos"),
            KeyboardShortcutAssignmentError.ReservedForPushToTalk =>
                L10n.T("keyboardShortcutReservedForPushToTalk", ns: "macos"),
            KeyboardShortcutAssignmentError.AlreadyAssigned =>
                L10n.T(
                    "keyboardShortcutConflict",
                    ns: "macos",
                    ("action", L10n.T(ShortcutTitleKey(FindConflictingAction(action, binding)), ns: "macos"))
                ),
            _ => null
        };
    }

    private KeyboardShortcutAction FindConflictingAction(
        KeyboardShortcutAction action,
        KeyboardShortcutBinding? binding
    ) => Enum.GetValues<KeyboardShortcutAction>().FirstOrDefault(other =>
        other != action && binding is not null &&
        _keyboardShortcutPreferences.BindingFor(other)?.HasSameTrigger(binding) == true);

    private void RefreshKeyboardShortcutRows()
    {
        foreach (var action in _shortcutDescriptionLabels.Keys.ToArray())
        {
            var current = _keyboardShortcutPreferences.BindingFor(action);
            var isRecording = _recordingShortcutAction == action;
            _shortcutDescriptionLabels[action].Text = ShortcutDescription(action);
            _shortcutRecordButtons[action].Content = isRecording
                ? L10n.T("keyboardShortcutPress", ns: "macos")
                : current?.DisplayString ?? L10n.T("keyboardShortcutNotSet", ns: "macos");
            _shortcutRecordButtons[action].IsEnabled = _recordingShortcutAction is null || isRecording;
            _shortcutClearButtons[action].Visibility = current is null
                ? Visibility.Collapsed
                : Visibility.Visible;
            _shortcutClearButtons[action].IsEnabled = _recordingShortcutAction is null;
            _shortcutStatusLabels[action].Text = _shortcutAssignmentErrors.GetValueOrDefault(action)
                ?? (isRecording ? L10n.T("keyboardShortcutCaptureHint", ns: "macos") : "");
        }
    }

    private string ShortcutDescription(KeyboardShortcutAction action)
    {
        if (action == KeyboardShortcutAction.SendMessage)
        {
            return _keyboardShortcutPreferences.SendMessage is { } binding
                ? L10n.T("keyboardShortcutSendDescription", ns: "macos", ("shortcut", binding.DisplayString))
                : L10n.T("keyboardShortcutSendUnsetDescription", ns: "macos");
        }

        return L10n.T(ShortcutDescriptionKey(action), ns: "macos");
    }

    private static string ShortcutTitleKey(KeyboardShortcutAction action) => action switch
    {
        KeyboardShortcutAction.SendMessage => "keyboardShortcutSendTitle",
        KeyboardShortcutAction.MuteMicrophone => "keyboardShortcutMuteMicrophoneTitle",
        KeyboardShortcutAction.UnmuteMicrophone => "keyboardShortcutUnmuteMicrophoneTitle",
        KeyboardShortcutAction.MuteVoiceAudio => "keyboardShortcutMuteVoiceAudioTitle",
        KeyboardShortcutAction.UnmuteVoiceAudio => "keyboardShortcutUnmuteVoiceAudioTitle",
        _ => "keyboardShortcutsTitle"
    };

    private static string ShortcutDescriptionKey(KeyboardShortcutAction action) => action switch
    {
        KeyboardShortcutAction.MuteMicrophone => "keyboardShortcutMuteMicrophoneDescription",
        KeyboardShortcutAction.UnmuteMicrophone => "keyboardShortcutUnmuteMicrophoneDescription",
        KeyboardShortcutAction.MuteVoiceAudio => "keyboardShortcutMuteVoiceAudioDescription",
        KeyboardShortcutAction.UnmuteVoiceAudio => "keyboardShortcutUnmuteVoiceAudioDescription",
        _ => "keyboardShortcutSendDescription"
    };

    private async void OnRootKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Handled)
        {
            return;
        }

        var action = _keyboardShortcutPreferences.ActionFor((int)e.Key, ReadShortcutModifiers());
        if (action is null || !CanPerformKeyboardShortcut(action.Value))
        {
            return;
        }

        e.Handled = true;
        if (e.KeyStatus.WasKeyDown)
        {
            return;
        }

        await ExecuteKeyboardShortcutAsync(action.Value);
    }

    private async void OnComposerKeyDown(object sender, KeyRoutedEventArgs e)
    {
        var action = _keyboardShortcutPreferences.ActionFor((int)e.Key, ReadShortcutModifiers());
        if (action is null || !CanPerformKeyboardShortcut(action.Value))
        {
            return;
        }

        e.Handled = true;
        if (e.KeyStatus.WasKeyDown)
        {
            return;
        }

        await ExecuteKeyboardShortcutAsync(action.Value);
    }

    private bool CanPerformKeyboardShortcut(KeyboardShortcutAction action)
    {
        if (action == KeyboardShortcutAction.SendMessage)
        {
            return ComposerBox.FocusState != FocusState.Unfocused;
        }

        if (_session.CurrentVoiceChannelId is null || _voiceMediaStatus != "connected")
        {
            return false;
        }

        return action is not (KeyboardShortcutAction.MuteMicrophone or KeyboardShortcutAction.UnmuteMicrophone)
            || _canPublishAudio;
    }

    private async Task ExecuteKeyboardShortcutAsync(KeyboardShortcutAction action)
    {
        switch (action)
        {
            case KeyboardShortcutAction.SendMessage:
                await SendComposer();
                break;
            case KeyboardShortcutAction.MuteMicrophone:
                await SetMicrophoneMutedAsync(true);
                break;
            case KeyboardShortcutAction.UnmuteMicrophone:
                await SetMicrophoneMutedAsync(false);
                break;
            case KeyboardShortcutAction.MuteVoiceAudio:
                _deafened = true;
                await ExecuteVoiceActionAsync("setOutputMuted", true);
                RefreshVoiceControls();
                break;
            case KeyboardShortcutAction.UnmuteVoiceAudio:
                _deafened = false;
                await ExecuteVoiceActionAsync("setOutputMuted", false);
                RefreshVoiceControls();
                break;
        }
    }

    private async Task SetMicrophoneMutedAsync(bool muted)
    {
        if (!_canPublishAudio || _voiceMediaStatus != "connected")
        {
            return;
        }

        _microphoneMuted = muted;
        await ExecuteVoiceActionAsync("setMicrophoneMuted", muted);
        if (!muted && _deafened)
        {
            _deafened = false;
            await ExecuteVoiceActionAsync("setOutputMuted", false);
        }

        RefreshVoiceControls();
    }

    private void EnablePushToTalk()
    {
        _pushToTalkEnabled = true;
        try
        {
            var hook = new GlobalPushToTalkHook();
            hook.KeyStateChanged += OnPushToTalkKeyStateChanged;
            hook.Start();
            _pushToTalkHook = hook;
            _pushToTalkEnabled = true;
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("voice.push_to_talk.enable_failed", exception);
        }

        SavePreference("voice.pushToTalkEnabled", _pushToTalkEnabled);
        RefreshPushToTalkStatus();
    }

    private async Task DisablePushToTalkAsync()
    {
        _pushToTalkHook?.Dispose();
        _pushToTalkHook = null;
        var shouldRestoreMute = _pushToTalkState.Release();
        _pushToTalkEnabled = false;
        SavePreference("voice.pushToTalkEnabled", false);
        if (shouldRestoreMute)
        {
            await SetMicrophoneMutedAsync(true);
        }

        RefreshPushToTalkStatus();
    }

    private void OnPushToTalkKeyStateChanged(bool isPressed)
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            if (isPressed)
            {
                var shouldUnmute = _pushToTalkState.Press(
                    _canPublishAudio && _voiceMediaStatus == "connected",
                    _microphoneMuted
                );
                if (shouldUnmute)
                {
                    await SetMicrophoneMutedAsync(false);
                }

                return;
            }

            if (_pushToTalkState.Release())
            {
                await SetMicrophoneMutedAsync(true);
            }
        });
    }

    private void RefreshPushToTalkStatus()
    {
        if (_pushToTalkStatusText is null)
        {
            return;
        }

        if (!_pushToTalkEnabled)
        {
            _pushToTalkStatusText.Text = "";
        }
        else if (_pushToTalkHook is null)
        {
            _pushToTalkStatusText.Text = L10n.T("pushToTalkUnavailable", ns: "windows");
        }
        else
        {
            _pushToTalkStatusText.Text = L10n.T("pushToTalkReady", ns: "windows");
        }
    }

    private async void OnPushToTalkToggled(object sender, RoutedEventArgs e)
    {
        if (sender is not ToggleSwitch toggle)
        {
            return;
        }

        if (toggle.IsOn)
        {
            EnablePushToTalk();
            return;
        }

        await DisablePushToTalkAsync();
    }

    private async void OnMainWindowClosed(object sender, WindowEventArgs e)
    {
        _pushToTalkHook?.Dispose();
        _pushToTalkHook = null;
        if (_pushToTalkState.Release() && _voiceWorkerReady)
        {
            try
            {
                await VoiceMediaWebView.ExecuteScriptAsync("window.coveVoice?.setMicrophoneMuted(true)");
            }
            catch (Exception exception)
            {
                ClientLogStore.Shared.RecordError("voice.push_to_talk.release_failed", exception);
            }
        }
    }

    private static KeyboardShortcutPreferences ReadKeyboardShortcutPreferences()
    {
        try
        {
            var values = Windows.Storage.ApplicationData.Current.LocalSettings.Values;
            if (!values.TryGetValue(KeyboardShortcutPreferenceKey, out var stored) || stored is not string json ||
                JsonSerializer.Deserialize<KeyboardShortcutPreferences>(json) is not { } loaded)
            {
                return new KeyboardShortcutPreferences();
            }

            var validated = new KeyboardShortcutPreferences();
            foreach (var action in Enum.GetValues<KeyboardShortcutAction>())
            {
                if (validated.TryAssign(loaded.BindingFor(action), action, out var updated) is null)
                {
                    validated = updated;
                }
            }

            return validated;
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.keyboard_shortcuts.read_failed", exception);
            return new KeyboardShortcutPreferences();
        }
    }

    private static void SaveKeyboardShortcutPreferences(KeyboardShortcutPreferences preferences)
    {
        try
        {
            Windows.Storage.ApplicationData.Current.LocalSettings.Values[KeyboardShortcutPreferenceKey] =
                JsonSerializer.Serialize(preferences);
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.keyboard_shortcuts.save_failed", exception);
        }
    }

    private static KeyboardShortcutModifiers ReadShortcutModifiers()
    {
        var modifiers = KeyboardShortcutModifiers.None;
        if (IsKeyDown(ControlKey))
        {
            modifiers |= KeyboardShortcutModifiers.Control;
        }

        if (IsKeyDown(MenuKey))
        {
            modifiers |= KeyboardShortcutModifiers.Alt;
        }

        if (IsKeyDown(ShiftKey))
        {
            modifiers |= KeyboardShortcutModifiers.Shift;
        }

        if (IsKeyDown(LeftWindowsKey) || IsKeyDown(RightWindowsKey))
        {
            modifiers |= KeyboardShortcutModifiers.Windows;
        }

        return modifiers;
    }

    private static bool IsKeyDown(int keyCode) => (GetKeyState(keyCode) & 0x8000) != 0;

    [DllImport("user32.dll")]
    private static extern short GetKeyState(int keyCode);
}
