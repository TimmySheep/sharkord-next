using System.Globalization;
using Sharkord.Core;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private async Task RestoreLastSelectedChannelAsync()
    {
        if (!ReadPreference("app.autoJoinLastChannel", defaultValue: true) ||
            _session.ServerBaseUrl is not { } serverBaseUrl)
        {
            return;
        }

        try
        {
            var values = Windows.Storage.ApplicationData.Current.LocalSettings.Values;
            var settingKey = LastChannelPreference.SettingKey(serverBaseUrl);
            if (!values.TryGetValue(settingKey, out var savedValue))
            {
                return;
            }

            int? savedChannelId = savedValue switch
            {
                int id => id,
                string text when int.TryParse(
                    text,
                    NumberStyles.None,
                    CultureInfo.InvariantCulture,
                    out var parsedId
                ) => parsedId,
                _ => null
            };
            if (savedChannelId is not { } channelId ||
                _session.Channel(channelId) is not { } channel ||
                !LastChannelPreference.CanRestoreChannel(channel.IsText, channel.IsDm, channel.IsVoice))
            {
                return;
            }

            await _session.SelectChannelAsync(channel.Id);
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.last_channel.restore_failed", exception);
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
            Windows.Storage.ApplicationData.Current.LocalSettings.Values[
                LastChannelPreference.SettingKey(serverBaseUrl)
            ] = channelId;
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.last_channel.save_failed", exception);
        }
    }
}
