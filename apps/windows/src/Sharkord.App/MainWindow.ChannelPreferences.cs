using Sharkord.Core;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task<bool> RestoreLastSelectedChannelAsync()
    {
        if (!ReadPreference("app.autoJoinLastChannel", defaultValue: true) ||
            _session.ServerBaseUrl is not { } serverBaseUrl)
        {
            return false;
        }

        try
        {
            var settingKey = LastChannelPreference.SettingKey(serverBaseUrl);
            var savedChannelId = FilePreferences.Local.Get<int?>(settingKey, null);
            if (savedChannelId is not { } channelId ||
                _session.Channel(channelId) is not { } channel ||
                !LastChannelPreference.CanRestoreChannel(channel.IsText, channel.IsDm, channel.IsVoice))
            {
                return false;
            }

            PrepareChannelSelection(channel.Id);
            await _session.SelectChannelAsync(channel.Id);
            return true;
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.last_channel.restore_failed", exception);
            return false;
        }
    }

    private void RememberLastSelectedChannel(int channelId)
    {
        if (_session.ServerBaseUrl is not { } serverBaseUrl ||
            _session.Channel(channelId) is not { } channel ||
            !LastChannelPreference.CanRestoreChannel(channel.IsText, channel.IsDm, channel.IsVoice))
        {
            return;
        }

        try
        {
            FilePreferences.Local.Set(LastChannelPreference.SettingKey(serverBaseUrl), channelId);
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.last_channel.save_failed", exception);
        }
    }
}
