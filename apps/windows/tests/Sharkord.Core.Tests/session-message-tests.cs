using System.Reflection;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class SessionMessageTests
{
    // exercise the subscription reducer without a live server or exposing a public mutation API
    private static readonly Action<SharkordSession, SharkordMessage, bool> Upsert =
        typeof(SharkordSession).GetMethod("Upsert", BindingFlags.Instance | BindingFlags.NonPublic)!
            .CreateDelegate<Action<SharkordSession, SharkordMessage, bool>>();

    private static readonly Action<SharkordSession, JoinResult> ApplyJoin =
        typeof(SharkordSession).GetMethod("Apply", BindingFlags.Instance | BindingFlags.NonPublic)!
            .CreateDelegate<Action<SharkordSession, JoinResult>>();

    [Fact]
    public async Task MessageRevisionChangesOnlyWhenThatChannelsHistoryChanges()
    {
        await using var session = new SharkordSession();
        var message = new SharkordMessage { Id = 1, ChannelId = 7, CreatedAt = 100 };
        Assert.Equal(0, session.GetMessagesRevision(7));
        Upsert(session, message, false);
        var snapshot = session.GetMessagesSnapshot(7, out var revision);
        Assert.True(revision > 0);
        Assert.Same(message, Assert.Single(snapshot));

        Upsert(session, message, false);
        Upsert(session, new SharkordMessage { Id = 2, ChannelId = 8 }, false);
        session.MarkAsRead(7);
        Assert.Equal(revision, session.GetMessagesRevision(7));

        Upsert(session, new SharkordMessage { Id = 1, ChannelId = 7, CreatedAt = 100, Content = "edited" }, false);
        Assert.True(session.GetMessagesRevision(7) > revision);
        await session.DisconnectAsync();
        Assert.Equal(0, session.GetMessagesRevision(7));
        Assert.Empty(session.GetMessagesSnapshot(7));
    }

    [Fact]
    public async Task OutOfOrderMessagesUseTimestampThenIdWithoutDuplicatingUpdatesOrThreads()
    {
        await using var session = new SharkordSession();
        Upsert(session, new SharkordMessage { Id = 3, ChannelId = 7, CreatedAt = 100 }, false);
        Upsert(session, new SharkordMessage { Id = 2, ChannelId = 7, CreatedAt = 200 }, false);
        Upsert(session, new SharkordMessage { Id = 1, ChannelId = 7, CreatedAt = 100 }, false);
        var edited = new SharkordMessage { Id = 3, ChannelId = 7, CreatedAt = 100, Content = "edited" };
        Upsert(session, edited, false);
        Upsert(session, new SharkordMessage { Id = 4, ChannelId = 7, CreatedAt = 300, ParentMessageId = 1 }, false);

        var messages = session.GetMessagesSnapshot(7);
        Assert.Equal(new[] { 1, 3, 2 }, messages.Select(message => message.Id));
        Assert.Same(edited, messages[1]);
    }

    [Fact]
    public async Task JoinLoadsUnreadCountsAndRejoinReplacesThem()
    {
        await using var session = new SharkordSession();
        ApplyJoin(session, new JoinResult { ReadStates = new() { ["7"] = 4, ["8"] = 2 } });

        Assert.Equal(4, session.UnreadCount(7));
        Assert.Equal(2, session.UnreadCount(8));

        ApplyJoin(session, new JoinResult { ReadStates = new() { ["8"] = 3 } });

        Assert.Equal(0, session.UnreadCount(7));
        Assert.Equal(3, session.UnreadCount(8));
    }

    [Fact]
    public async Task StartingANewLoginDropsThePreviousServersHistoryEvenIfLoginFails()
    {
        await using var session = new SharkordSession();
        ApplyJoin(session, new JoinResult { OwnUserId = 1, Users = [new() { Id = 1, Name = "old server" }] });
        Upsert(session, new SharkordMessage { Id = 1, ChannelId = 7, Content = "old server message" }, false);

        await session.ConnectAsync("http://127.0.0.1:1", "user", "password", cancellationToken: new CancellationToken(true));

        Assert.Equal(SessionPhase.Failed, session.Phase);
        Assert.Empty(session.GetMessagesSnapshot(7));
        Assert.Empty(session.Users);
        Assert.Equal(0, session.OwnUserId);
    }

    [Fact]
    public async Task SnapshotRemainsStableWhenSubscriptionChangesTheChannel()
    {
        await using var session = new SharkordSession();
        var first = new SharkordMessage { Id = 1, ChannelId = 7, CreatedAt = 100, Content = "first" };
        Upsert(session, first, false);
        var snapshot = session.GetMessagesSnapshot(7);

        Upsert(session, new SharkordMessage { Id = 1, ChannelId = 7, CreatedAt = 100, Content = "edited" }, false);
        Upsert(session, new SharkordMessage { Id = 2, ChannelId = 7, CreatedAt = 200 }, false);

        Assert.Same(first, Assert.Single(snapshot));
        var current = session.GetMessagesSnapshot(7);
        Assert.Equal(2, current.Count);
        Assert.Equal("edited", current[0].Content);
        Assert.Empty(session.GetMessagesSnapshot(99));
    }

    [Fact]
    public async Task SnapshotCanBeReadWhileSubscriptionAddsMessages()
    {
        await using var session = new SharkordSession();
        var writer = Task.Run(() =>
        {
            for (var id = 1; id <= 500; id++)
            {
                Upsert(session, new SharkordMessage { Id = id, ChannelId = 7, CreatedAt = id }, false);
            }
        });

        for (var read = 0; read < 100; read++)
        {
            var snapshot = session.GetMessagesSnapshot(7);
            Assert.Equal(Enumerable.Range(1, snapshot.Count), snapshot.Select(message => message.Id));
        }

        await writer;
        Assert.Equal(500, session.GetMessagesSnapshot(7).Count);
    }
}
