using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media.Imaging;
using Sharkord.Core;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private IReadOnlyList<ReactionItem> BuildReactionItems(SharkordMessage message) => _session.ReactionGroups(message).Select(group =>
    {
        var glyph = EmojiCatalog.Glyph(group.Emoji);
        var file = group.File ?? _session.Emojis.FirstOrDefault(emoji => emoji.Name == group.Emoji)?.File;
        var image = file is null ? null : _session.PublicFileUrl(file);
        var label = $"{glyph} {group.Count}";
        var names = (message.Reactions ?? []).Where(reaction => reaction.Emoji == group.Emoji)
            .Select(reaction => _session.User(reaction.UserId)?.Name).OfType<string>().Distinct();
        return new ReactionItem(message.Id, group.Emoji, label, group.Mine, image, group.Count, string.Join(", ", names));
    }).ToArray();

    private async void OnReactionClick(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleButton { DataContext: ReactionItem reaction }) { await ToggleReactionAsync(reaction.MessageId, reaction.Emoji); }
    }

    private void OnAddReactionClick(object sender, RoutedEventArgs e)
    {
        if (!_session.HasPermission("REACT_TO_MESSAGES") || sender is not Button { DataContext: MessageItem message } button) { return; }
        ShowEmojiPicker(button, async emoji => await ToggleReactionAsync(message.Id, emoji.Shortcode), reactions: true);
    }

    private async Task ToggleReactionAsync(int messageId, string emoji)
    {
        if (!_session.HasPermission("REACT_TO_MESSAGES")) { Refresh(); return; }
        ChatErrorText.Text = "";
        try { await _session.ToggleReactionAsync(messageId, emoji); }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("chat.reaction.failed", exception);
            ChatErrorText.Text = exception.Message;
            Refresh();
        }
    }

    [Microsoft.UI.Xaml.Data.Bindable]
    public sealed record ReactionItem(int MessageId, string Emoji, string Label, bool Mine, Uri? ImageUrl = null, int Count = 0, string Details = "")
    {
        public BitmapImage? Image => ImageUrl is null ? null : new BitmapImage(ImageUrl);
        public string Display => ImageUrl is null ? Label : Count.ToString();
        public Visibility ImageVisibility => ImageUrl is null ? Visibility.Collapsed : Visibility.Visible;
    }
}
