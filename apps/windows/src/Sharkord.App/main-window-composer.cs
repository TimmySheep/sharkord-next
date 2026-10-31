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
    private readonly Dictionary<(int ChannelId, int? ParentId), ChannelDraft> _channelDrafts = [];
    private int? _replyToMessageId;
    private SharkordMessage? _editingMessage;
    private string _textBeforeEdit = "";
    private string _originalEditText = "";
    private bool _sendingComposer;
    private bool _uploadingAttachments;
    private int _composerGeneration;
    private int? _lastTypingChannelId;
    private int? _lastTypingParentId;
    private long _lastTypingSignalAt;

    private bool CanSendMessage() =>
        _session.SelectedChannelId is { } id && _session.Channel(id) is { } channel && (channel.IsText || _session.IsVoiceTextSelected) &&
        _session.HasPermission("SEND_MESSAGES") && _session.HasChannelPermission(id, "SEND_MESSAGES");

    private bool CanAttachFiles() =>
        CanSendMessage() && _editingMessage is null && _session.SelectedChannelId is { } id && CanAttachToChannel(id);

    private bool CanUseComposer() => _editingMessage is null ? CanSendMessage() : CanEditMessage(_editingMessage);

    private void RefreshComposerPermissions()
    {
        var allowed = CanUseComposer() && !_sendingComposer;
        ComposerBox.IsEnabled = allowed;
        SendButton.IsEnabled = allowed && !_uploadingAttachments && _removingAttachments.Count == 0;
        ComposerEmojiButton.IsEnabled = allowed;
        ComposerFormatButton.IsEnabled = allowed;
        LabelControl(ComposerFormatButton, L10n.T("formatMessage", ns: "windows"));
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
            if (_lastTypingChannelId == id && _lastTypingParentId == _threadParent?.Id && now - _lastTypingSignalAt < 2000)
            {
                return;
            }
            _lastTypingChannelId = id;
            _lastTypingParentId = _threadParent?.Id;
            _lastTypingSignalAt = now;
            _session.SignalTyping(id, _threadParent?.Id);
        }
    }

    private void BeginEdit(SharkordMessage message)
    {
        if (!CanEditMessage(message) || message.ChannelId != _session.SelectedChannelId || _sendingComposer)
        {
            return;
        }
        CancelComposerContext();
        _textBeforeEdit = ComposerBox.Text;
        _editingMessage = message;
        _originalEditText = MessageHtml.ToComposerText(message.Content ?? "");
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
        var last = _messages.Select(row => row.Source).LastOrDefault(message =>
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
            _channelDrafts[(id, _displayedThreadParentId)] = new ChannelDraft(_editingMessage is null ? ComposerBox.Text : _textBeforeEdit, _pendingAttachments.ToArray());
        }
    }

    private void RestoreChannelDraft()
    {
        CancelComposerContext();
        _pendingAttachments.Clear();
        ComposerBox.Text = "";
        if (_displayedChannelId is { } id && _channelDrafts.TryGetValue((id, _displayedThreadParentId), out var draft))
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
        if (!CanUseComposer() || _sendingComposer || _uploadingAttachments || _removingAttachments.Count > 0 || _session.SelectedChannelId is not { } channelId)
        {
            return;
        }
        if (_editingMessage is null && _pendingAttachments.Count > 0)
        {
            if (!CanAttachToChannel(channelId)) { ChatErrorText.Text = L10n.T("uploadsDisabled"); return; }
            var maximum = _session.Settings?.StorageMaxFilesPerMessage ?? int.MaxValue;
            if (_pendingAttachments.Count > maximum)
            {
                ChatErrorText.Text = L10n.T("attachmentLimit", ns: "windows", ("count", maximum));
                return;
            }
        }
        var text = ComposerBox.Text;
        var generation = _composerGeneration;
        var parentId = _threadParent?.Id;
        var editing = _editingMessage;
        if (string.IsNullOrWhiteSpace(text) && (_pendingAttachments.Count == 0 || editing is not null))
        {
            return;
        }
        if (FormatComposerText(text.Trim()).Length > ProtocolDefaults.MessageMaxLength)
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
                    await _session.EditFormattedMessageAsync(editing.Id, FormatComposerText(text));
                }
            }
            else
            {
                await _session.SendFormattedMessageAsync(channelId, FormatComposerText(text), _replyToMessageId,
                    _pendingAttachments.Select(file => file.Id).ToArray(), parentMessageId: parentId);
            }

            if (generation != _composerGeneration)
            {
                return;
            }
            if (editing is null)
            {
                _channelDrafts.Remove((channelId, parentId));
            }
            if (_displayedChannelId == channelId && _displayedThreadParentId == parentId)
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
        if (!CanAttachFiles() || _uploadingAttachments) { return; }
        var channelId = _session.SelectedChannelId;
        var parentId = _threadParent?.Id;
        var generation = _composerGeneration;
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        try
        {
            var files = await picker.PickMultipleFilesAsync();
            if (_session.SelectedChannelId != channelId || _threadParent?.Id != parentId || generation != _composerGeneration) { return; }
            await AddStorageFilesAsync(files);
        }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }

    [Microsoft.UI.Xaml.Data.Bindable]
    public sealed record PendingAttachment(string Id, string Name, Microsoft.UI.Xaml.Media.Imaging.BitmapImage? Preview = null)
    {
        public string RemoveLabel => L10n.T("removeAttachment", ns: "windows", ("name", Name));
    }

    private sealed record ChannelDraft(string Text, IReadOnlyList<PendingAttachment> Attachments);
}
