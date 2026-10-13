namespace Sharkord.Core;

public sealed class PushToTalkState
{
    private bool _isPressed;
    private bool _shouldRestoreMuted;

    public bool Press(bool canPublishAudio, bool microphoneMuted)
    {
        if (_isPressed)
        {
            return false;
        }

        _isPressed = true;
        _shouldRestoreMuted = canPublishAudio && microphoneMuted;
        return _shouldRestoreMuted;
    }

    public bool Release()
    {
        if (!_isPressed)
        {
            return false;
        }

        _isPressed = false;
        var shouldMute = _shouldRestoreMuted;
        _shouldRestoreMuted = false;
        return shouldMute;
    }
}
