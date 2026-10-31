namespace Sharkord.Core;

public sealed record DesktopNotificationPreferences(
    bool AllMessages,
    bool MentionsOnly,
    bool DirectMessages,
    bool Replies
);

public static class DesktopNotificationPolicy
{
    public static bool ShouldNotify(
        SharkordMessage message,
        SharkordChannel channel,
        int ownUserId,
        bool isVisible,
        DesktopNotificationPreferences preferences
    )
    {
        if (message.UserId == ownUserId || isVisible)
        {
            return false;
        }

        if (channel.IsDm)
        {
            return preferences.DirectMessages;
        }

        if (preferences.MentionsOnly)
        {
            return HasMention(message.Content ?? "", ownUserId);
        }

        if (preferences.AllMessages)
        {
            return true;
        }

        return preferences.Replies
            && message.ReplyToMessageId is not null
            && message.ReplyTo?.UserId == ownUserId;
    }

    public static bool HasMention(string content, int userId)
    {
        var doubleQuoted = $"data-user-id=\"{userId}\"";
        var singleQuoted = $"data-user-id='{userId}'";
        return content.Contains(doubleQuoted, StringComparison.OrdinalIgnoreCase)
            || content.Contains(singleQuoted, StringComparison.OrdinalIgnoreCase);
    }

    public static string PlainText(string html) => MessageHtml.ToPlainText(html).Trim();
}
