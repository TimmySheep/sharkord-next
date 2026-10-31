using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Sharkord.Core;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private static readonly string[] QuickReactionShortcodes =
    [
        "thumbsup",
        "heart",
        "joy",
        "tada",
        "thinking_face",
        "eyes"
    ];

    private static readonly IReadOnlyDictionary<string, string> ReactionGlyphs =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["thumbsup"] = "👍",
            ["heart"] = "❤️",
            ["joy"] = "😂",
            ["tada"] = "🎉",
            ["thinking_face"] = "🤔",
            ["eyes"] = "👀"
        };

    private IReadOnlyList<ReactionItem> BuildReactionItems(SharkordMessage message) => _session
        .ReactionGroups(message)
        .Select(group =>
        {
            var display = ReactionGlyphs.TryGetValue(group.Emoji, out var glyph) ? glyph : $":{group.Emoji}:";
            return new ReactionItem(message.Id, group.Emoji, $"{display} {group.Count}", group.Mine);
        })
        .ToArray();

    private async void OnReactionClick(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleButton button && button.DataContext is ReactionItem reaction)
        {
            await ToggleReactionAsync(reaction.MessageId, reaction.Emoji);
        }
    }

    private void OnAddReactionClick(object sender, RoutedEventArgs e)
    {
        if (!_session.HasPermission("REACT_TO_MESSAGES")) { return; }
        if (sender is not Button button || button.DataContext is not MessageItem message)
        {
            return;
        }

        var menu = new MenuFlyout();

        foreach (var shortcode in QuickReactionShortcodes)
        {
            var item = new MenuFlyoutItem { Text = ReactionGlyphs[shortcode], Tag = shortcode };
            item.Click += async (menuSender, _) =>
            {
                if (menuSender is MenuFlyoutItem selected && selected.Tag is string emoji)
                {
                    await ToggleReactionAsync(message.Id, emoji);
                }
            };
            menu.Items.Add(item);
        }

        menu.ShowAt(button);
    }

    private async Task ToggleReactionAsync(int messageId, string emoji)
    {
        if (!_session.HasPermission("REACT_TO_MESSAGES")) { Refresh(); return; }
        ChatErrorText.Text = "";

        try
        {
            await _session.ToggleReactionAsync(messageId, emoji);
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("chat.reaction.failed", exception);
            ChatErrorText.Text = exception.Message;
            Refresh();
        }
    }

    [Microsoft.UI.Xaml.Data.Bindable]
    public sealed record ReactionItem(int MessageId, string Emoji, string Label, bool Mine);
}
