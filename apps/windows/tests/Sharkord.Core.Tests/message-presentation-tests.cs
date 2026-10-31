using Sharkord.App;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class MessagePresentationTests
{
    [Fact]
    public void ConsecutiveMessagesGroupWithinOneMinute()
    {
        var previous = new SharkordMessage { UserId = 1, ChannelId = 2, CreatedAt = 1_800_000 };
        var current = new SharkordMessage { UserId = 1, ChannelId = 2, CreatedAt = 1_830_000 };
        Assert.True(MessagePresentation.IsContinuation(previous, current, false));
        Assert.False(MessagePresentation.IsContinuation(previous, current, true));
    }

    [Theory]
    [InlineData(2, 2, 1_860_000, null)]
    [InlineData(1, 3, 1_860_000, null)]
    [InlineData(1, 2, 2_160_000, null)]
    [InlineData(1, 2, 1_860_000, 12)]
    public void DifferentAuthorChannelGapOrReplyStartsAGroup(int userId, int channelId, long createdAt, int? replyId)
    {
        var previous = new SharkordMessage { UserId = 1, ChannelId = 2, CreatedAt = 1_800_000 };
        var current = new SharkordMessage { UserId = userId, ChannelId = channelId, CreatedAt = createdAt, ReplyToMessageId = replyId };
        Assert.False(MessagePresentation.IsContinuation(previous, current, false));
    }

    [Fact]
    public void OnlyOwnEditableMessagesCanBeEdited()
    {
        Assert.True(MessagePresentation.CanEdit(new SharkordMessage { UserId = 1, Editable = true }, 1));
        Assert.False(MessagePresentation.CanEdit(new SharkordMessage { UserId = 2 }, 1));
        Assert.False(MessagePresentation.CanEdit(new SharkordMessage { UserId = 1, Editable = false }, 1));
        Assert.False(MessagePresentation.CanEdit(new SharkordMessage { UserId = 1 }, 1));
        Assert.False(MessagePresentation.CanEdit(new SharkordMessage(), 1));
    }

    [Fact]
    public void PreviousRepliesPluginsAndMinuteBoundaryBreakGrouping()
    {
        var current = new SharkordMessage { UserId = 1, ChannelId = 2, CreatedAt = 1_830_000 };
        Assert.False(MessagePresentation.IsContinuation(
            new SharkordMessage { UserId = 1, ChannelId = 2, CreatedAt = 1_800_000, ReplyToMessageId = 9 }, current, false));
        Assert.False(MessagePresentation.IsContinuation(
            new SharkordMessage { UserId = 1, ChannelId = 2, CreatedAt = 1_800_000, PluginId = "plugin" }, current, false));
        Assert.False(MessagePresentation.IsContinuation(
            new SharkordMessage { UserId = 1, ChannelId = 2, CreatedAt = 1_770_000 }, current, false));
    }

    [Fact]
    public void ReconciliationPreservesUnchangedRowsAndNeverResetsCollection()
    {
        var first = new SharkordMessage { Id = 1 };
        var second = new SharkordMessage { Id = 2 };
        var rows = new System.Collections.ObjectModel.ObservableCollection<SharkordMessage> { first, second };
        var actions = new List<System.Collections.Specialized.NotifyCollectionChangedAction>();
        rows.CollectionChanged += (_, e) => actions.Add(e.Action);
        var replacement = new SharkordMessage { Id = 2, Content = "edited" };
        MessagePresentation.Reconcile(rows, new[] { first, replacement, new SharkordMessage { Id = 3 } }, row => row.Id);
        Assert.Same(first, rows[0]);
        Assert.Same(replacement, rows[1]);
        Assert.Equal(3, rows.Count);
        Assert.DoesNotContain(System.Collections.Specialized.NotifyCollectionChangedAction.Reset, actions);
    }

    [Fact]
    public void EarlierPagesAndDeletesKeepExistingRows()
    {
        var second = new SharkordMessage { Id = 2 };
        var third = new SharkordMessage { Id = 3 };
        var rows = new System.Collections.ObjectModel.ObservableCollection<SharkordMessage> { second, third };
        var first = new SharkordMessage { Id = 1 };
        MessagePresentation.Reconcile(rows, new[] { first, second, third }, row => row.Id);
        Assert.Same(second, rows[1]);
        Assert.Same(third, rows[2]);
        MessagePresentation.Reconcile(rows, new[] { first, third }, row => row.Id);
        Assert.Equal(new[] { 1, 3 }, rows.Select(row => row.Id));
        Assert.Same(third, rows[1]);
    }
}
