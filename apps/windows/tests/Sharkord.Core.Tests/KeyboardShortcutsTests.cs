using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class KeyboardShortcutsTests
{
    [Fact]
    public void DefaultSendShortcutIsUnmodifiedEnter()
    {
        var preferences = new KeyboardShortcutPreferences();
        var sendMessage = preferences.SendMessage!;

        Assert.True(sendMessage.Matches(13, KeyboardShortcutModifiers.None));
        Assert.False(sendMessage.Matches(13, KeyboardShortcutModifiers.Shift));
        Assert.Equal(
            KeyboardShortcutAction.SendMessage,
            preferences.ActionFor(108, KeyboardShortcutModifiers.None)
        );
    }

    [Fact]
    public void RejectsUnmodifiedVoiceKeysShiftEnterAndThePushToTalkKey()
    {
        var preferences = new KeyboardShortcutPreferences();

        Assert.Equal(
            KeyboardShortcutAssignmentError.ModifierRequired,
            preferences.TryAssign(
                new KeyboardShortcutBinding(77, KeyboardShortcutModifiers.None),
                KeyboardShortcutAction.MuteMicrophone,
                out _
            )
        );
        Assert.Equal(
            KeyboardShortcutAssignmentError.ReturnReservedForNewline,
            preferences.TryAssign(
                new KeyboardShortcutBinding(13, KeyboardShortcutModifiers.Shift),
                KeyboardShortcutAction.SendMessage,
                out _
            )
        );
        Assert.Equal(
            KeyboardShortcutAssignmentError.ReservedForPushToTalk,
            preferences.TryAssign(
                new KeyboardShortcutBinding(124, KeyboardShortcutModifiers.Control),
                KeyboardShortcutAction.MuteMicrophone,
                out _
            )
        );
    }

    [Fact]
    public void RejectsConflictsAndAllowsClearingAnAssignment()
    {
        var preferences = new KeyboardShortcutPreferences();
        var mute = new KeyboardShortcutBinding(77, KeyboardShortcutModifiers.Control);

        Assert.Null(preferences.TryAssign(mute, KeyboardShortcutAction.MuteMicrophone, out var assigned));
        Assert.Equal(
            KeyboardShortcutAssignmentError.AlreadyAssigned,
            assigned.TryAssign(mute, KeyboardShortcutAction.UnmuteMicrophone, out _)
        );
        Assert.Null(assigned.TryAssign(null, KeyboardShortcutAction.MuteMicrophone, out var cleared));
        Assert.Null(cleared.MuteMicrophone);
    }

    [Fact]
    public void DisplaysModifiersAndFindsOnlyExactBindings()
    {
        var binding = new KeyboardShortcutBinding(
            77,
            KeyboardShortcutModifiers.Control | KeyboardShortcutModifiers.Shift
        );

        Assert.Equal("Ctrl+Shift+M", binding.DisplayString);
        Assert.True(binding.Matches(77, KeyboardShortcutModifiers.Control | KeyboardShortcutModifiers.Shift));
        Assert.False(binding.Matches(77, KeyboardShortcutModifiers.Control));

        var windowsBinding = new KeyboardShortcutBinding(77, KeyboardShortcutModifiers.Windows);
        Assert.Equal("Win+M", windowsBinding.DisplayString);
        Assert.True(windowsBinding.HasPrimaryModifier);
    }

    [Fact]
    public void TreatsMainAndNumpadEnterAsTheSameTrigger()
    {
        var binding = KeyboardShortcutBinding.ReturnKey;

        Assert.True(binding.Matches(108, KeyboardShortcutModifiers.None));
        Assert.True(binding.HasSameTrigger(new KeyboardShortcutBinding(108, KeyboardShortcutModifiers.None)));
    }
}
