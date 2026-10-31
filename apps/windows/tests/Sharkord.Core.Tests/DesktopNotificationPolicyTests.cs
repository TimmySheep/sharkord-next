using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public sealed class DesktopNotificationPolicyTests
{
    [Fact]
    public void OwnMessagesAndVisibleMessagesNeverNotify()
    {
        var preferences = new DesktopNotificationPreferences(true, false, true, true);

        Assert.False(DesktopNotificationPolicy.ShouldNotify(
            new SharkordMessage { UserId = 1 },
            new SharkordChannel(),
            ownUserId: 1,
            isVisible: false,
            preferences: preferences
        ));
        Assert.False(DesktopNotificationPolicy.ShouldNotify(
            new SharkordMessage { UserId = 2 },
            new SharkordChannel(),
            ownUserId: 1,
            isVisible: true,
            preferences: preferences
        ));
    }

    [Fact]
    public void DirectMessagesUseTheirDedicatedPreference()
    {
        var message = new SharkordMessage { UserId = 2 };
        var channel = new SharkordChannel { IsDm = true };

        Assert.True(DesktopNotificationPolicy.ShouldNotify(
            message,
            channel,
            ownUserId: 1,
            isVisible: false,
            preferences: new DesktopNotificationPreferences(false, true, true, false)
        ));
        Assert.False(DesktopNotificationPolicy.ShouldNotify(
            message,
            channel,
            ownUserId: 1,
            isVisible: false,
            preferences: new DesktopNotificationPreferences(true, false, false, true)
        ));
    }

    [Fact]
    public void MentionOnlyAndAllMessagePreferencesMatchTheDesktopPolicy()
    {
        var channel = new SharkordChannel();
        var mentioned = new SharkordMessage { UserId = 2, Content = "<span data-user-id=\"1\">Timmy</span>" };
        var regular = new SharkordMessage { UserId = 2, Content = "<p>hello</p>" };

        Assert.True(DesktopNotificationPolicy.ShouldNotify(
            mentioned,
            channel,
            ownUserId: 1,
            isVisible: false,
            preferences: new DesktopNotificationPreferences(false, true, false, false)
        ));
        Assert.False(DesktopNotificationPolicy.ShouldNotify(
            regular,
            channel,
            ownUserId: 1,
            isVisible: false,
            preferences: new DesktopNotificationPreferences(true, true, false, false)
        ));
        Assert.True(DesktopNotificationPolicy.ShouldNotify(
            regular,
            channel,
            ownUserId: 1,
            isVisible: false,
            preferences: new DesktopNotificationPreferences(true, false, false, false)
        ));
    }

    [Fact]
    public void RepliesNotifyOnlyWhenTheyTargetTheCurrentUser()
    {
        var channel = new SharkordChannel();
        var replyToOwnMessage = new SharkordMessage
        {
            UserId = 2,
            ReplyToMessageId = 10,
            ReplyTo = new SharkordReplyPreview { UserId = 1 }
        };
        var replyToOtherMessage = new SharkordMessage
        {
            UserId = 2,
            ReplyToMessageId = 11,
            ReplyTo = new SharkordReplyPreview { UserId = 3 }
        };
        var preferences = new DesktopNotificationPreferences(false, false, false, true);

        Assert.True(DesktopNotificationPolicy.ShouldNotify(
            replyToOwnMessage,
            channel,
            ownUserId: 1,
            isVisible: false,
            preferences: preferences
        ));
        Assert.False(DesktopNotificationPolicy.ShouldNotify(
            replyToOtherMessage,
            channel,
            ownUserId: 1,
            isVisible: false,
            preferences: preferences
        ));
    }

    [Fact]
    public void HtmlMessageContentIsReducedToPlainText()
    {
        Assert.Equal("hello & welcome", DesktopNotificationPolicy.PlainText("<p>hello &amp; welcome</p>"));
    }
}
