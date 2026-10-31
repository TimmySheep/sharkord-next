using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private readonly ObservableCollection<PendingAttachment> _pendingAttachments = [];
    private readonly Dictionary<int, ChannelDraft> _channelDrafts = [];
    private int? _replyToMessageId;
    private SharkordMessage? _editingMessage;
    private string _textBeforeEdit = "";
    private string _originalEditText = "";
    private bool _sendingComposer;
    private bool _uploadingAttachments;
    private Flyout? _composerEmojiFlyout;
    private int _composerGeneration;
    private int? _lastTypingChannelId;
    private long _lastTypingSignalAt;

    private bool CanSendMessage() =>
        _session.SelectedChannelId is { } id && _session.Channel(id) is { IsText: true } &&
        _session.HasPermission("SEND_MESSAGES") && _session.HasChannelPermission(id, "SEND_MESSAGES");

    private bool CanAttachFiles() =>
        CanSendMessage() && _session.HasPermission("UPLOAD_FILES") &&
        _session.Settings?.StorageUploadEnabled != false && _editingMessage is null &&
        (_session.SelectedChannelId is not { } id || _session.Channel(id)?.IsDm != true ||
         _session.Settings?.StorageFileSharingInDirectMessages != false);

    private bool CanUseComposer() => MessagePresentation.CanCompose(_editingMessage, _session.OwnUserId, CanSendMessage());

    private void RefreshComposerPermissions()
    {
        var allowed = CanUseComposer() && !_sendingComposer;
        ComposerBox.IsEnabled = allowed;
        SendButton.IsEnabled = allowed && !_uploadingAttachments;
        ComposerEmojiButton.IsEnabled = allowed;
        AttachButton.IsEnabled = allowed && CanAttachFiles() && !_uploadingAttachments;
        PendingAttachmentList.Visibility = _editingMessage is null ? Visibility.Visible : Visibility.Collapsed;
        ComposerBox.PlaceholderText = allowed
            ? L10n.T("messagePlaceholder", ns: "windows")
            : L10n.T("messageNotAllowed", ns: "macos");
    }

    private void OnComposerTextChanged(object sender, TextChangedEventArgs e)
    {
        if (_session.SelectedChannelId is { } id && _editingMessage is null && ComposerBox.Text.Length > 0 && CanSendMessage())
        {
            var now = Environment.TickCount64;
            if (_lastTypingChannelId == id && now - _lastTypingSignalAt < 2000)
            {
                return;
            }
            _lastTypingChannelId = id;
            _lastTypingSignalAt = now;
            _session.SignalTyping(id);
        }
    }

    private void BeginEdit(SharkordMessage message)
    {
        if (!MessagePresentation.CanEdit(message, _session.OwnUserId) || message.ChannelId != _session.SelectedChannelId || _sendingComposer)
        {
            return;
        }
        CancelComposerContext();
        _textBeforeEdit = ComposerBox.Text;
        _editingMessage = message;
        _originalEditText = MessageHtml.ToPlainText(message.Content ?? "");
        ComposerBox.Text = _originalEditText;
        ComposerBox.SelectionStart = ComposerBox.Text.Length;
        ComposerContextText.Text = $"{L10n.T("editMessage")} · {L10n.T("pressEnterToSave")}";
        ComposerContext.Visibility = Visibility.Visible;
        RefreshComposerPermissions();
        ComposerBox.Focus(FocusState.Programmatic);
    }

    private void EditLastOwnMessage()
    {
        if (ComposerBox.Text.Length > 0 || _session.SelectedChannelId is not { } channelId)
        {
            return;
        }
        var last = _session.GetMessagesSnapshot(channelId).LastOrDefault(message =>
            MessagePresentation.CanEdit(message, _session.OwnUserId));
        if (last is not null)
        {
            BeginEdit(last);
        }
    }

    private void OnCancelComposerClick(object sender, RoutedEventArgs e) => CancelComposerContext();

    private void CancelComposerContext()
    {
        if (_editingMessage is not null)
        {
            _editingMessage = null;
            ComposerBox.Text = _textBeforeEdit;
        }
        _replyToMessageId = null;
        ComposerContext.Visibility = Visibility.Collapsed;
        RefreshComposerPermissions();
    }

    private void SaveChannelDraft()
    {
        if (_displayedChannelId is { } id)
        {
            _channelDrafts[id] = new ChannelDraft(ComposerBox.Text, _pendingAttachments.ToArray());
        }
    }

    private void RestoreChannelDraft()
    {
        CancelComposerContext();
        _pendingAttachments.Clear();
        ComposerBox.Text = "";
        if (_displayedChannelId is { } id && _channelDrafts.TryGetValue(id, out var draft))
        {
            ComposerBox.Text = draft.Text;
            foreach (var attachment in draft.Attachments)
            {
                _pendingAttachments.Add(attachment);
            }
        }
        RefreshComposerPermissions();
    }

    private async Task SendDesktopComposerAsync()
    {
        if (!CanUseComposer() || _sendingComposer || _uploadingAttachments || _session.SelectedChannelId is not { } channelId)
        {
            return;
        }
        var text = ComposerBox.Text;
        var generation = _composerGeneration;
        var editing = _editingMessage;
        if (string.IsNullOrWhiteSpace(text) && (_pendingAttachments.Count == 0 || editing is not null))
        {
            return;
        }
        if (MessageHtml.FromPlainText(text.Trim()).Length > ProtocolDefaults.MessageMaxLength)
        {
            ChatErrorText.Text = L10n.T("messageTooLong", ns: "common", ("max", ProtocolDefaults.MessageMaxLength));
            return;
        }

        _sendingComposer = true;
        RefreshComposerPermissions();
        ChatErrorText.Text = "";
        try
        {
            if (editing is not null)
            {
                // opening and saving a rich message unchanged must not discard its original markup.
                if (text != _originalEditText)
                {
                    await _session.EditMessageAsync(editing.Id, text);
                }
            }
            else
            {
                await _session.SendMessageAsync(channelId, text, _replyToMessageId,
                    _pendingAttachments.Select(file => file.Id).ToArray());
            }

            if (generation != _composerGeneration)
            {
                return;
            }
            if (editing is null)
            {
                _channelDrafts.Remove(channelId);
            }
            if (_displayedChannelId == channelId)
            {
                CancelComposerContext();
                if (editing is null)
                {
                    ComposerBox.Text = "";
                    _pendingAttachments.Clear();
                }
                ComposerBox.Focus(FocusState.Programmatic);
            }
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("chat.composer.failed", exception);
            ChatErrorText.Text = exception.Message;
        }
        finally
        {
            _sendingComposer = false;
            RefreshComposerPermissions();
        }
    }

    private async void OnAttachClick(object sender, RoutedEventArgs e)
    {
        if (!CanAttachFiles() || _uploadingAttachments || _session.SelectedChannelId is not { } channelId)
        {
            return;
        }
        var picker = new FileOpenPicker();
        var generation = _composerGeneration;
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        _uploadingAttachments = true;
        RefreshComposerPermissions();
        ChatErrorText.Text = "";
        try
        {
            var files = await picker.PickMultipleFilesAsync();
            var maximumFiles = _session.Settings?.StorageMaxFilesPerMessage ?? int.MaxValue;
            if (files.Count + _pendingAttachments.Count > maximumFiles)
            {
                ChatErrorText.Text = L10n.T("attachmentLimit", ns: "windows", ("count", maximumFiles));
                return;
            }
            foreach (var file in files)
            {
                if (_session.SelectedChannelId != channelId || generation != _composerGeneration)
                {
                    return;
                }
                var properties = await file.GetBasicPropertiesAsync();
                if (_session.Settings?.StorageUploadMaxFileSize is > 0 and var maximumSize && properties.Size > (ulong)maximumSize)
                {
                    ChatErrorText.Text = L10n.T("attachmentSizeLimit", ns: "windows", ("size", maximumSize / 1024d / 1024d));
                    return;
                }
                var id = await _session.UploadAttachmentAsync(
                    await File.ReadAllBytesAsync(file.Path), file.Name, file.ContentType
                );
                var pending = new PendingAttachment(id, file.Name);
                if (generation != _composerGeneration)
                {
                    return;
                }
                if (_displayedChannelId == channelId)
                {
                    _pendingAttachments.Add(pending);
                }
                else if (_channelDrafts.TryGetValue(channelId, out var draft))
                {
                    _channelDrafts[channelId] = draft with { Attachments = [.. draft.Attachments, pending] };
                }
            }
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("chat.attachment_upload.failed", exception);
            ChatErrorText.Text = exception.Message;
        }
        finally
        {
            _uploadingAttachments = false;
            RefreshComposerPermissions();
        }
    }

    private void OnRemoveAttachmentClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: PendingAttachment attachment } && !_sendingComposer)
        {
            _pendingAttachments.Remove(attachment);
        }
    }

    private void OnComposerEmojiClick(object sender, RoutedEventArgs e)
    {
        var panel = new VariableSizedWrapGrid { MaximumRowsOrColumns = 6, Orientation = Orientation.Horizontal, Margin = new Thickness(8) };
        foreach (var glyph in ReactionGlyphs.Values.Concat(new[] { "😀", "😊", "😎", "🥳", "😭", "🔥", "✅", "🙌", "💯", "👋", "🚀", "🤝" }))
        {
            var button = new Button { Content = glyph, Tag = glyph, FontSize = 22, Width = 44, Height = 44 };
            button.Click += OnInsertEmojiClick;
            panel.Children.Add(button);
        }
        _composerEmojiFlyout = new Flyout { Content = panel };
        _composerEmojiFlyout.ShowAt(ComposerEmojiButton);
    }

    private void OnInsertEmojiClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string glyph })
        {
            var selectionStart = ComposerBox.SelectionStart;
            ComposerBox.SelectedText = glyph;
            _composerEmojiFlyout?.Hide();
            ComposerBox.Focus(FocusState.Programmatic);
            ComposerBox.SelectionStart = selectionStart + glyph.Length;
            ComposerBox.SelectionLength = 0;
        }
    }

    [Microsoft.UI.Xaml.Data.Bindable]
    public sealed record PendingAttachment(string Id, string Name)
    {
        public string RemoveLabel => L10n.T("removeAttachment", ns: "windows", ("name", Name));
    }

    private sealed record ChannelDraft(string Text, IReadOnlyList<PendingAttachment> Attachments);
}
