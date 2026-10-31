using System.Security;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private void OnIncomingMessage(SharkordMessage message)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            TrackNewMessage(message);
            if (message.UserId == _session.OwnUserId) { _ = PlayEventSoundAsync("message_sent"); }
            ShowNotificationIfNeeded(message);
        });
    }

    private void ShowNotificationIfNeeded(SharkordMessage message)
    {
        var channel = _session.Channel(message.ChannelId);
        var author = message.UserId is { } userId
            ? _session.Users.FirstOrDefault(user => user.Id == userId)?.Name
            : null;
        if (channel is null || string.IsNullOrWhiteSpace(author))
        {
            return;
        }

        var preferences = new DesktopNotificationPreferences(
            ReadPreference("notify.allMessages", false),
            ReadPreference("notify.mentionsOnly", true),
            ReadPreference("notify.dms", true),
            ReadPreference("notify.replies", true)
        );
        var isVisible = _windowIsActive && _session.SelectedChannelId == message.ChannelId;
        if (!DesktopNotificationPolicy.ShouldNotify(message, channel, _session.OwnUserId, isVisible, preferences))
        {
            return;
        }

        var title = channel.IsDm
            ? L10n.T("notificationDirectMessageTitle", ns: "macos", ("author", author))
            : L10n.T("notificationChannelTitle", ns: "macos", ("author", author), ("channel", channel.Name));
        _ = PlayEventSoundAsync("message_received");
        var body = DesktopNotificationPolicy.PlainText(message.Content ?? "");
        if (body.Length == 0)
        {
            body = L10n.T("notificationAttachmentBody", ns: "macos");
        }

        try
        {
            var xml = new XmlDocument();
            xml.LoadXml(
                $"<toast><visual><binding template=\"ToastGeneric\"><text>{EscapeToastText(title)}</text>"
                + $"<text>{EscapeToastText(body[..Math.Min(body.Length, 240)])}</text></binding></visual></toast>"
            );
            ToastNotificationManager.CreateToastNotifier().Show(new ToastNotification(xml));
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("notifications.show_failed", exception);
        }
    }

    private static string EscapeToastText(string value) => SecurityElement.Escape(value) ?? "";
}
