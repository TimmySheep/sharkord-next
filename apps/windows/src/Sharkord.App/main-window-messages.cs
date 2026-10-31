using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private int? _displayedChannelId;
    private int _pendingUnreadCount;
    private int? _unreadMessageId;
    private int? _newMessageId;
    private bool _loadingOlder;
    private long _renderedMessagesRevision = -1;
    private IReadOnlyList<SharkordUser>? _renderedMessageUsers;
    private IReadOnlyList<SharkordRole>? _renderedMessageRoles;
    private string? _renderedMessageLanguage;
    private int? _renderedUnreadMarker;
    private int? _renderedNewMarker;

    private void PrepareChannelSelection(int channelId)
    {
        if (_displayedChannelId == channelId && _messages.Count > 0)
        {
            return;
        }

        _pendingUnreadCount = _session.UnreadCount(channelId);
        _unreadMessageId = null;
        _newMessageId = null;
        CancelComposerContext();
    }

    private void SyncMessageRows(SharkordChannel? channel)
    {
        var channelChanged = _displayedChannelId != channel?.Id || _displayedThreadParentId != _threadParent?.Id;
        if (channelChanged)
        {
            SaveChannelDraft();
            _displayedChannelId = channel?.Id;
            _displayedThreadParentId = _threadParent?.Id;
            RestoreChannelDraft();
        }

        var users = _session.Users;
        var language = L10n.Language;
        var revision = channel is null ? 0 : _session.GetMessagesRevision(channel.Id);
        if (_threadParent is not null) { revision = _session.ThreadRevision; }
        var usersUnchanged = ReferenceEquals(users, _renderedMessageUsers) && ReferenceEquals(_session.Roles, _renderedMessageRoles);
        LoadOlderButton.Content = _threadParent is null ? L10n.T("loadEarlierMessages", ns: "macos") : L10n.T("loadMoreReplies", ns: "windows");
        LoadOlderButton.Visibility = channel is not null && (_threadParent is { } thread ? _session.HasMoreThreadMessages(thread.Id) : _session.HasOlderMessages(channel.Id))
            ? Visibility.Visible : Visibility.Collapsed;
        if (!channelChanged && _pendingUnreadCount == 0 && revision == _renderedMessagesRevision &&
            usersUnchanged && language == _renderedMessageLanguage &&
            _unreadMessageId == _renderedUnreadMarker && _newMessageId == _renderedNewMarker)
        {
            return;
        }

        IReadOnlyList<SharkordMessage> source = [];
        if (channel is not null)
        {
            if (_threadParent is { } parent)
            {
                var updatedParent = _session.GetMessagesSnapshot(channel.Id).FirstOrDefault(message => message.Id == parent.Id) ?? parent;
                source = new[] { updatedParent }.Concat(_session.GetThreadMessagesSnapshot(parent.Id)).ToArray();
                revision = _session.ThreadRevision;
            }
            else { source = _session.GetMessagesSnapshot(channel.Id, out revision); }
        }
        if (_pendingUnreadCount > 0 && source.Count > 0)
        {
            _unreadMessageId = MessagePresentation.UnreadBoundary(source, _pendingUnreadCount, _session.OwnUserId);
            _pendingUnreadCount = 0;
        }

        Dictionary<int, MessageItem>? existing = null;
        var desired = new List<MessageItem>(source.Count);
        SharkordMessage? previous = null;
        foreach (var message in source)
        {
            var divider = "";
            if (message.Id == _unreadMessageId)
            {
                divider = L10n.T("unreadMessages", ns: "windows");
            }
            else if (message.Id == _newMessageId)
            {
                divider = L10n.T("newMessages", ns: "windows");
            }

            var continuation = MessagePresentation.IsContinuation(previous, message, divider.Length > 0);
            MessageItem? row;
            var index = desired.Count;
            if (index < _messages.Count && _messages[index].Id == message.Id)
            {
                row = _messages[index];
            }
            else if (index >= _messages.Count && existing is null)
            {
                row = null;
            }
            else
            {
                existing ??= _messages.ToDictionary(item => item.Id);
                existing.TryGetValue(message.Id, out row);
            }
            if (row is not null && ReferenceEquals(row.Source, message) && usersUnchanged &&
                row.Language == language && row.Continuation == continuation && row.DividerText == divider &&
                row.Replies == _session.ReplyCount(message) && row.CanManage == _session.CanManageMessage(message))
            {
                desired.Add(row);
                previous = message;
                continue;
            }

            var user = message.UserId is { } userId ? _session.User(userId) : null;
            var author = user?.Name ?? L10n.T("systemUser", ns: "windows");
            var avatarUrl = user?.Avatar is { } avatar ? _session.PublicFileUrl(avatar) : null;
            var reply = ReplyPreview(message);
            if (row is not null && ReferenceEquals(row.Source, message) &&
                row.Language == language && row.Continuation == continuation &&
                row.DividerText == divider && row.Author == author && row.AvatarUrl == avatarUrl &&
                row.ReplyText == reply && row.Replies == _session.ReplyCount(message) && row.CanManage == _session.CanManageMessage(message))
            {
                desired.Add(row);
            }
            else
            {
                desired.Add(new MessageItem(
                    message, author, avatarUrl, continuation, divider, reply,
                    BuildReactionItems(message), _session.OwnUserId,
                    (message.Files ?? []).Select(file => new AttachmentItem(
                        file.OriginalName, _session.PublicFileUrl(file), file.MimeType, file.Size
                    )).ToArray(), _session.CanManageMessage(message), _session.ReplyCount(message)
                ));
            }
            previous = message;
        }

        var wasAtBottom = IsMessageListAtBottom();
        MessagePresentation.Reconcile(_messages, desired, row => row.Id);
        _renderedMessagesRevision = revision;
        _renderedMessageUsers = users;
        _renderedMessageRoles = _session.Roles;
        _renderedMessageLanguage = language;
        _renderedUnreadMarker = _unreadMessageId;
        _renderedNewMarker = _newMessageId;
        if (_messages.Count > 0 && !_loadingOlder && (channelChanged || wasAtBottom))
        {
            var target = _messages.Last();
            if (channelChanged && _unreadMessageId is { } unreadId)
            {
                target = _messages.FirstOrDefault(row => row.Id == unreadId) ?? target;
            }
            MessageList.ScrollIntoView(target);
        }
    }

    private string ReplyPreview(SharkordMessage message)
    {
        if (message.ReplyToMessageId is null)
        {
            return "";
        }
        if (message.ReplyTo is not { } reply)
        {
            return L10n.T("originalMessageUnavailable");
        }
        var name = reply.UserId is { } id ? _session.User(id)?.Name : null;
        var text = MessageHtml.ToPlainText(reply.Content ?? "");
        return $"↪ {name ?? L10n.T("systemUser", ns: "windows")}: {text}";
    }

    private async void OnLoadOlderClick(object sender, RoutedEventArgs e)
    {
        if (_loadingOlder || _session.SelectedChannelId is not { } channelId)
        {
            return;
        }
        _loadingOlder = true;
        LoadOlderButton.IsEnabled = false;
        try
        {
            if (_threadParent is { } parent) { await _session.LoadThreadAsync(parent.Id, more: true); }
            else { await _session.LoadOlderAsync(channelId); }
        }
        catch (Exception exception)
        {
            ChatErrorText.Text = exception.Message;
        }
        finally
        {
            _loadingOlder = false;
            LoadOlderButton.IsEnabled = true;
        }
    }

    private bool IsMessageListAtBottom()
    {
        var scroll = FindVisualChild<ScrollViewer>(MessageList);
        return scroll is null || scroll.ScrollableHeight - scroll.VerticalOffset < 40;
    }

    private void TrackNewMessage(SharkordMessage message)
    {
        if (message.ChannelId == _session.SelectedChannelId && message.UserId != _session.OwnUserId &&
            _newMessageId is null && (!_windowIsActive || !IsMessageListAtBottom()))
        {
            _newMessageId = message.Id;
            SyncMessageRows(_session.Channel(message.ChannelId));
        }
    }

    private static T? FindVisualChild<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T match)
            {
                return match;
            }
            if (FindVisualChild<T>(child) is { } descendant)
            {
                return descendant;
            }
        }
        return null;
    }

    private static void ShowMessageToolbar(object sender, bool visible)
    {
        if (sender is FrameworkElement row && row.FindName("MessageToolbar") is Border toolbar)
        {
            toolbar.Opacity = visible ? 1 : 0;
            toolbar.IsHitTestVisible = visible;
        }
    }

    private void OnMessagePointerEntered(object sender, PointerRoutedEventArgs e) => ShowMessageToolbar(sender, true);
    private void OnMessageGotFocus(object sender, RoutedEventArgs e) => ShowMessageToolbar(sender, true);

    private void OnMessagePointerExited(object sender, PointerRoutedEventArgs e)
    {
        if (sender is FrameworkElement row && !ContainsKeyboardFocus(row))
        {
            ShowMessageToolbar(sender, false);
        }
    }

    private void OnMessageLostFocus(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement row && !ContainsKeyboardFocus(row))
        {
            ShowMessageToolbar(sender, false);
        }
    }

    private bool ContainsKeyboardFocus(FrameworkElement row)
    {
        var focused = FocusManager.GetFocusedElement(RootGrid.XamlRoot) as DependencyObject;
        while (focused is not null)
        {
            if (ReferenceEquals(focused, row))
            {
                return true;
            }
            focused = VisualTreeHelper.GetParent(focused);
        }
        return false;
    }

    private void OnEditMessageClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: MessageItem row })
        {
            BeginEdit(row.Source);
        }
    }

    private void OnReplyMessageClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: MessageItem row } && CanSendMessage())
        {
            CancelComposerContext();
            _replyToMessageId = row.Id;
            ComposerContextText.Text = L10n.T("replyingTo", ns: "common", ("username", row.Author));
            ComposerContext.Visibility = Visibility.Visible;
            ComposerBox.Focus(FocusState.Programmatic);
        }
    }

    private void OnMessageMoreClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.DataContext is not MessageItem row)
        {
            return;
        }
        var menu = new MenuFlyout();
        var delete = new MenuFlyoutItem { Text = L10n.T("deleteLabel"), Icon = new SymbolIcon(Symbol.Delete) };
        delete.Click += async (_, _) => await DeleteMessageWithConfirmationAsync(row.Source);
        if (_session.CanManageMessage(row.Source)) { menu.Items.Add(delete); }
        if (_session.HasPermission("PIN_MESSAGES"))
        {
            var pin = new MenuFlyoutItem { Text = L10n.T(row.Source.Pinned == true ? "unpinMessage" : "pinMessage") };
            pin.Click += async (_, _) =>
            {
                try { await _session.TogglePinAsync(row.Id); }
                catch (Exception exception) { ChatErrorText.Text = exception.Message; }
            };
            menu.Items.Add(pin);
        }
        if (row.Source.ParentMessageId is null)
        {
            var thread = new MenuFlyoutItem { Text = L10n.T("replyInThread") };
            thread.Click += async (_, _) => await OpenThreadAsync(row.Source);
            menu.Items.Add(thread);
        }
        menu.ShowAt(button);
    }

    private async Task DeleteMessageWithConfirmationAsync(SharkordMessage message)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Title = L10n.T("deleteMessageTitle"),
            Content = L10n.T("deleteMessageConfirm"),
            PrimaryButtonText = L10n.T("deleteLabel"),
            CloseButtonText = L10n.T("cancel"),
            DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }
        try
        {
            await _session.DeleteMessageAsync(message.Id);
        }
        catch (Exception exception)
        {
            ChatErrorText.Text = exception.Message;
        }
    }

    private async void OnAttachmentOpenClick(object sender, RoutedEventArgs e)
    {
        if (sender is HyperlinkButton { Tag: Uri url } && url.Scheme is "http" or "https")
        {
            try
            {
                await Windows.System.Launcher.LaunchUriAsync(url);
            }
            catch (Exception exception)
            {
                ChatErrorText.Text = exception.Message;
            }
        }
    }

    [Microsoft.UI.Xaml.Data.Bindable]
    public sealed class MessageItem
    {
        public SharkordMessage Source { get; }
        public int Id => Source.Id;
        public string Language { get; } = L10n.Language;
        public string Author { get; }
        public Uri? AvatarUrl { get; }
        public BitmapImage? Avatar { get; }
        public bool Continuation { get; }
        public string DividerText { get; }
        public string ReplyText { get; }
        public string Text { get; }
        public string Timestamp { get; }
        public string ShortTimestamp { get; }
        public IReadOnlyList<ReactionItem> Reactions { get; }
        public IReadOnlyList<AttachmentItem> Attachments { get; }
        public Visibility GroupHeaderVisibility => Continuation ? Visibility.Collapsed : Visibility.Visible;
        public Visibility ContinuationTimestampVisibility => Continuation ? Visibility.Visible : Visibility.Collapsed;
        public Thickness RowMargin => new(0, Continuation ? 0 : 16, 0, 0);
        public Visibility DividerVisibility => DividerText.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        public Visibility ReplyVisibility => Source.ReplyToMessageId is null ? Visibility.Collapsed : Visibility.Visible;
        public Visibility EditedVisibility => Source.EditedAt is null ? Visibility.Collapsed : Visibility.Visible;
        public Visibility EditVisibility { get; }
        public Visibility OwnVisibility { get; }
        public int Replies { get; }
        public bool CanManage { get; }
        public string ThreadLabel { get; }
        public Visibility ThreadVisibility { get; }
        public string AddReactionLabel { get; } = L10n.T("addReaction", ns: "windows");
        public string ReplyLabel { get; } = L10n.T("replyToMessage");
        public string EditLabel { get; } = L10n.T("editMessage");
        public string MoreLabel { get; } = L10n.T("messageActions", ns: "windows");
        public string EditedLabel { get; } = L10n.T("edited");

        public MessageItem(SharkordMessage message, string author, Uri? avatarUrl, bool continuation,
            string divider, string reply, IReadOnlyList<ReactionItem> reactions, int ownUserId,
            IReadOnlyList<AttachmentItem> attachments, bool canManage = false, int replies = 0)
        {
            Source = message;
            Replies = replies;
            CanManage = canManage;
            Author = author;
            AvatarUrl = avatarUrl;
            Avatar = avatarUrl is null ? null : new BitmapImage(avatarUrl);
            Continuation = continuation;
            DividerText = divider;
            ReplyText = reply;
            Text = MessageHtml.ToPlainText(message.Content ?? "");
            Timestamp = DateTimeOffset.FromUnixTimeMilliseconds(message.CreatedAt).LocalDateTime.ToString("g");
            ShortTimestamp = DateTimeOffset.FromUnixTimeMilliseconds(message.CreatedAt).LocalDateTime.ToString("t");
            Reactions = reactions;
            Attachments = attachments;
            ThreadLabel = L10n.T(replies == 1 ? "reply_one" : "reply_other", ns: "common", ("count", replies));
            ThreadVisibility = message.ParentMessageId is null && replies > 0 ? Visibility.Visible : Visibility.Collapsed;
            EditVisibility = message.Editable == true && canManage ? Visibility.Visible : Visibility.Collapsed;
            OwnVisibility = message.UserId == ownUserId ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    [Microsoft.UI.Xaml.Data.Bindable]
    public sealed record AttachmentItem(string Name, Uri? Url, string MimeType = "", long Size = 0);
}
