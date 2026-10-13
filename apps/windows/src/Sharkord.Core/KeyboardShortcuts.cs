namespace Sharkord.Core;

[Flags]
public enum KeyboardShortcutModifiers
{
    None = 0,
    Control = 1,
    Alt = 2,
    Shift = 4,
    Windows = 8
}

public enum KeyboardShortcutAction
{
    SendMessage,
    MuteMicrophone,
    UnmuteMicrophone,
    MuteVoiceAudio,
    UnmuteVoiceAudio
}

public enum KeyboardShortcutAssignmentError
{
    ModifierRequired,
    ReturnReservedForNewline,
    ReservedForPushToTalk,
    AlreadyAssigned
}

public sealed record KeyboardShortcutBinding(int KeyCode, KeyboardShortcutModifiers Modifiers)
{
    public static KeyboardShortcutBinding ReturnKey { get; } = new(13, KeyboardShortcutModifiers.None);

    public bool IsReturnKey => KeyCode is 13 or 108;

    public bool HasPrimaryModifier =>
        (Modifiers & (KeyboardShortcutModifiers.Control | KeyboardShortcutModifiers.Alt | KeyboardShortcutModifiers.Windows)) != 0;

    public bool ConflictsWithPushToTalk => KeyCode == 124;

    public string DisplayString
    {
        get
        {
            var parts = new List<string>();

            if (Modifiers.HasFlag(KeyboardShortcutModifiers.Control))
            {
                parts.Add("Ctrl");
            }

            if (Modifiers.HasFlag(KeyboardShortcutModifiers.Alt))
            {
                parts.Add("Alt");
            }

            if (Modifiers.HasFlag(KeyboardShortcutModifiers.Shift))
            {
                parts.Add("Shift");
            }

            if (Modifiers.HasFlag(KeyboardShortcutModifiers.Windows))
            {
                parts.Add("Win");
            }

            parts.Add(KeyLabel(KeyCode));
            return string.Join("+", parts);
        }
    }

    public bool Matches(int keyCode, KeyboardShortcutModifiers modifiers) =>
        (KeyCode == keyCode || IsReturnKey && (keyCode is 13 or 108)) && Modifiers == modifiers;

    public bool HasSameTrigger(KeyboardShortcutBinding other) =>
        (KeyCode == other.KeyCode || IsReturnKey && other.IsReturnKey) && Modifiers == other.Modifiers;

    public static string KeyLabel(int keyCode)
    {
        if (keyCode is >= 48 and <= 57 or >= 65 and <= 90)
        {
            return ((char)keyCode).ToString();
        }

        if (keyCode is >= 112 and <= 135)
        {
            return $"F{keyCode - 111}";
        }

        return keyCode switch
        {
            8 => "Backspace",
            9 => "Tab",
            13 => "Enter",
            27 => "Escape",
            32 => "Space",
            33 => "Page Up",
            34 => "Page Down",
            35 => "End",
            36 => "Home",
            37 => "Left",
            38 => "Up",
            39 => "Right",
            40 => "Down",
            46 => "Delete",
            108 => "Enter",
            _ => $"Key {keyCode}"
        };
    }
}

public sealed record KeyboardShortcutPreferences
{
    public KeyboardShortcutBinding? SendMessage { get; init; } = KeyboardShortcutBinding.ReturnKey;
    public KeyboardShortcutBinding? MuteMicrophone { get; init; }
    public KeyboardShortcutBinding? UnmuteMicrophone { get; init; }
    public KeyboardShortcutBinding? MuteVoiceAudio { get; init; }
    public KeyboardShortcutBinding? UnmuteVoiceAudio { get; init; }

    public KeyboardShortcutBinding? BindingFor(KeyboardShortcutAction action) => action switch
    {
        KeyboardShortcutAction.SendMessage => SendMessage,
        KeyboardShortcutAction.MuteMicrophone => MuteMicrophone,
        KeyboardShortcutAction.UnmuteMicrophone => UnmuteMicrophone,
        KeyboardShortcutAction.MuteVoiceAudio => MuteVoiceAudio,
        KeyboardShortcutAction.UnmuteVoiceAudio => UnmuteVoiceAudio,
        _ => null
    };

    public KeyboardShortcutAction? ActionFor(int keyCode, KeyboardShortcutModifiers modifiers)
    {
        foreach (var action in Enum.GetValues<KeyboardShortcutAction>())
        {
            if (BindingFor(action)?.Matches(keyCode, modifiers) == true)
            {
                return action;
            }
        }

        return null;
    }

    public KeyboardShortcutAssignmentError? TryAssign(
        KeyboardShortcutBinding? binding,
        KeyboardShortcutAction action,
        out KeyboardShortcutPreferences updated
    )
    {
        updated = this;

        if (binding is not null)
        {
            if (binding.ConflictsWithPushToTalk)
            {
                return KeyboardShortcutAssignmentError.ReservedForPushToTalk;
            }

            if (action == KeyboardShortcutAction.SendMessage && binding.IsReturnKey &&
                binding.Modifiers == KeyboardShortcutModifiers.Shift)
            {
                return KeyboardShortcutAssignmentError.ReturnReservedForNewline;
            }

            var bareReturnSend = action == KeyboardShortcutAction.SendMessage &&
                binding.IsReturnKey && binding.Modifiers == KeyboardShortcutModifiers.None;
            if (!binding.HasPrimaryModifier && !bareReturnSend)
            {
                return KeyboardShortcutAssignmentError.ModifierRequired;
            }

            if (Enum.GetValues<KeyboardShortcutAction>().Any(other =>
                    other != action && BindingFor(other)?.HasSameTrigger(binding) == true))
            {
                return KeyboardShortcutAssignmentError.AlreadyAssigned;
            }
        }

        updated = action switch
        {
            KeyboardShortcutAction.SendMessage => this with { SendMessage = binding },
            KeyboardShortcutAction.MuteMicrophone => this with { MuteMicrophone = binding },
            KeyboardShortcutAction.UnmuteMicrophone => this with { UnmuteMicrophone = binding },
            KeyboardShortcutAction.MuteVoiceAudio => this with { MuteVoiceAudio = binding },
            KeyboardShortcutAction.UnmuteVoiceAudio => this with { UnmuteVoiceAudio = binding },
            _ => this
        };

        return null;
    }
}
