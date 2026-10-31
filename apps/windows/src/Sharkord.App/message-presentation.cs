using System.Collections.ObjectModel;
using Sharkord.Core;

namespace Sharkord.App;

internal static class MessagePresentation
{
    internal static int? UnreadBoundary(IReadOnlyList<SharkordMessage> messages, int unreadCount, int ownUserId)
    {
        int? boundary = null;
        for (var index = messages.Count - 1; index >= 0 && unreadCount > 0; index--)
        {
            if (messages[index].UserId != ownUserId)
            {
                boundary = messages[index].Id;
                unreadCount--;
            }
        }
        return boundary;
    }

    internal static bool IsContinuation(SharkordMessage? previous, SharkordMessage current, bool hasDivider) =>
        !hasDivider && previous is not null && current.UserId is not null &&
        previous.UserId == current.UserId && previous.ChannelId == current.ChannelId &&
        previous.PluginId == current.PluginId && previous.ReplyToMessageId is null &&
        current.ReplyToMessageId is null && current.CreatedAt >= previous.CreatedAt &&
        current.CreatedAt - previous.CreatedAt < TimeSpan.FromMinutes(1).TotalMilliseconds &&
        DateTimeOffset.FromUnixTimeMilliseconds(previous.CreatedAt).LocalDateTime.Date ==
        DateTimeOffset.FromUnixTimeMilliseconds(current.CreatedAt).LocalDateTime.Date;

    internal static bool CanEdit(SharkordMessage message, int ownUserId) =>
        message.UserId == ownUserId && message.Editable == true;

    internal static bool CanCompose(SharkordMessage? editing, int ownUserId, bool canSend) =>
        editing is null ? canSend : CanEdit(editing, ownUserId);

    internal static void Reconcile<T>(ObservableCollection<T> rows, IReadOnlyList<T> desired, Func<T, int> id)
    {
        HashSet<int>? desiredIds = null;
        for (var index = 0; index < desired.Count; index++)
        {
            var row = desired[index];
            if (index < rows.Count && id(rows[index]) != id(row))
            {
                desiredIds ??= desired.Select(id).ToHashSet();
                while (index < rows.Count && !desiredIds.Contains(id(rows[index])))
                {
                    rows.RemoveAt(index);
                }
            }
            if (index < rows.Count && id(rows[index]) == id(row))
            {
                if (!EqualityComparer<T>.Default.Equals(rows[index], row))
                {
                    rows[index] = row;
                }
                continue;
            }

            var existing = -1;
            for (var next = index + 1; next < rows.Count; next++)
            {
                if (id(rows[next]) == id(row))
                {
                    existing = next;
                    break;
                }
            }
            if (existing >= 0)
            {
                rows.Move(existing, index);
                if (!EqualityComparer<T>.Default.Equals(rows[index], row))
                {
                    rows[index] = row;
                }
            }
            else
            {
                rows.Insert(index, row);
            }
        }

        while (rows.Count > desired.Count)
        {
            rows.RemoveAt(rows.Count - 1);
        }
    }
}
