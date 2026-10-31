using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private CancellationTokenSource? _attachmentUploadCancellation;

    private void OnCancelUploadClick(object sender, RoutedEventArgs e) => _attachmentUploadCancellation?.Cancel();

    private void OnComposerDragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = CanAttachFiles() && !_uploadingAttachments && e.DataView.Contains(StandardDataFormats.StorageItems)
            ? DataPackageOperation.Copy : DataPackageOperation.None;
    }

    private async void OnComposerDrop(object sender, DragEventArgs e)
    {
        if (!CanAttachFiles() || _uploadingAttachments || !e.DataView.Contains(StandardDataFormats.StorageItems)) { return; }
        try
        {
            var items = await e.DataView.GetStorageItemsAsync();
            await AddStorageFilesAsync(items.OfType<StorageFile>().ToArray());
        }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }

    private async void OnComposerPaste(object sender, TextControlPasteEventArgs e)
    {
        if (!CanAttachFiles() || _uploadingAttachments) { return; }
        var channelId = _session.SelectedChannelId;
        var parentId = _threadParent?.Id;
        var generation = _composerGeneration;
        var clipboard = Clipboard.GetContent();
        if (!clipboard.Contains(StandardDataFormats.StorageItems) && !clipboard.Contains(StandardDataFormats.Bitmap)) { return; }
        e.Handled = true;
        try
        {
            if (clipboard.Contains(StandardDataFormats.StorageItems))
            {
                var items = await clipboard.GetStorageItemsAsync();
                await AddStorageFilesAsync(items.OfType<StorageFile>().ToArray());
                return;
            }
            var reference = await clipboard.GetBitmapAsync();
            using var source = await reference.OpenReadAsync();
            var decoder = await BitmapDecoder.CreateAsync(source);
            using var bitmap = await decoder.GetSoftwareBitmapAsync();
            using var encoded = new InMemoryRandomAccessStream();
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, encoded);
            encoder.SetSoftwareBitmap(bitmap);
            await encoder.FlushAsync();
            var data = await ReadStorageStreamAsync(encoded, CancellationToken.None);
            if (_session.SelectedChannelId != channelId || _threadParent?.Id != parentId || generation != _composerGeneration) { return; }
            await UploadSourcesAsync([new UploadSource($"clipboard-{DateTime.UtcNow:yyyyMMdd-HHmmss}.png", "image/png", data.LongLength, _ => Task.FromResult(data))]);
        }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }

    private async Task AddStorageFilesAsync(IReadOnlyList<StorageFile> files)
    {
        var channelId = _session.SelectedChannelId;
        var parentId = _threadParent?.Id;
        var generation = _composerGeneration;
        var sources = new List<UploadSource>();
        foreach (var file in files)
        {
            var properties = await file.GetBasicPropertiesAsync();
            sources.Add(new UploadSource(file.Name, string.IsNullOrWhiteSpace(file.ContentType) ? "application/octet-stream" : file.ContentType, (long)properties.Size, async token =>
            {
                using var stream = await file.OpenReadAsync();
                return await ReadStorageStreamAsync(stream, token);
            }));
        }
        if (_session.SelectedChannelId != channelId || _threadParent?.Id != parentId || generation != _composerGeneration) { return; }
        await UploadSourcesAsync(sources);
    }

    private static async Task<byte[]> ReadStorageStreamAsync(IRandomAccessStream stream, CancellationToken token)
    {
        if (stream.Size > int.MaxValue) { throw new IOException(L10n.T("attachmentSizeLimit", ns: "windows", ("size", int.MaxValue / 1024d / 1024d))); }
        using var reader = new DataReader(stream.GetInputStreamAt(0));
        await reader.LoadAsync((uint)stream.Size).AsTask(token);
        var data = new byte[(int)stream.Size];
        reader.ReadBytes(data);
        return data;
    }

    private bool CanAttachToChannel(int channelId) =>
        _session.Channel(channelId) is not null && _session.HasPermission("SEND_MESSAGES") &&
        _session.HasChannelPermission(channelId, "SEND_MESSAGES") && _session.HasPermission("UPLOAD_FILES") &&
        _session.Settings?.StorageUploadEnabled != false &&
        (_session.Channel(channelId)?.IsDm != true || _session.Settings?.StorageFileSharingInDirectMessages != false);

    private async Task UploadSourcesAsync(IReadOnlyList<UploadSource> files)
    {
        if (files.Count == 0 || !CanAttachFiles() || _uploadingAttachments || _session.SelectedChannelId is not { } channelId) { return; }
        var maximumFiles = _session.Settings?.StorageMaxFilesPerMessage ?? int.MaxValue;
        if (files.Count + _pendingAttachments.Count > maximumFiles)
        {
            ChatErrorText.Text = L10n.T("attachmentLimit", ns: "windows", ("count", maximumFiles));
            return;
        }
        var maximumSize = _session.Settings?.StorageUploadMaxFileSize;
        if (maximumSize is > 0 && files.Any(file => file.Size > maximumSize))
        {
            ChatErrorText.Text = L10n.T("attachmentSizeLimit", ns: "windows", ("size", maximumSize / 1024d / 1024d));
            return;
        }
        var parentId = _threadParent?.Id;
        var generation = _composerGeneration;
        _attachmentUploadCancellation?.Dispose();
        _attachmentUploadCancellation = new CancellationTokenSource();
        var cancellation = _attachmentUploadCancellation;
        var timer = Stopwatch.StartNew();
        _uploadingAttachments = true;
        UploadStatusPanel.Visibility = Visibility.Visible;
        CancelUploadButton.Content = L10n.T("cancel");
        RefreshComposerPermissions();
        ChatErrorText.Text = "";
        try
        {
            foreach (var file in files)
            {
                cancellation.Token.ThrowIfCancellationRequested();
                if (generation != _composerGeneration || !CanAttachToChannel(channelId)) { cancellation.Cancel(); cancellation.Token.ThrowIfCancellationRequested(); }
                var data = await file.Read(cancellation.Token);
                if (maximumSize is > 0 && data.LongLength > maximumSize)
                {
                    ChatErrorText.Text = L10n.T("attachmentSizeLimit", ns: "windows", ("size", maximumSize / 1024d / 1024d));
                    return;
                }
                var startingAt = timer.Elapsed.TotalSeconds;
                var progress = new Progress<long>(sent => DispatcherQueue.TryEnqueue(() =>
                {
                    if (!ReferenceEquals(_attachmentUploadCancellation, cancellation)) { return; }
                    if (generation != _composerGeneration) { cancellation.Cancel(); return; }
                    var percent = data.Length == 0 ? 100d : sent * 100d / data.Length;
                    UploadProgressBar.Value = percent;
                    var speed = sent / 1024d / Math.Max(.1, timer.Elapsed.TotalSeconds - startingAt);
                    UploadStatusText.Text = L10n.T("uploadProgress", ns: "windows", ("name", file.Name), ("percent", percent.ToString("F0")), ("speed", speed.ToString("F0")));
                }));
                var uploaded = await _session.UploadAttachmentWithProgressAsync(data, file.Name, file.MimeType, progress, cancellation.Token);
                if (generation != _composerGeneration) { return; }
                var preview = await AttachmentPreviewAsync(data, file.MimeType);
                var pending = new PendingAttachment(uploaded.Id, file.Name, preview);
                if (_displayedChannelId == channelId && _displayedThreadParentId == parentId) { _pendingAttachments.Add(pending); }
                else
                {
                    var key = (channelId, parentId);
                    var draft = _channelDrafts.GetValueOrDefault(key) ?? new ChannelDraft("", []);
                    _channelDrafts[key] = draft with { Attachments = [.. draft.Attachments, pending] };
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("chat.attachment_upload.failed", exception);
            ChatErrorText.Text = exception.Message;
        }
        finally
        {
            if (ReferenceEquals(_attachmentUploadCancellation, cancellation)) { _attachmentUploadCancellation = null; }
            cancellation.Dispose();
            _uploadingAttachments = false;
            UploadStatusPanel.Visibility = Visibility.Collapsed;
            RefreshComposerPermissions();
        }
    }

    private static async Task<Microsoft.UI.Xaml.Media.Imaging.BitmapImage?> AttachmentPreviewAsync(byte[] data, string mimeType)
    {
        if (!mimeType.StartsWith("image/", StringComparison.OrdinalIgnoreCase)) { return null; }
        try
        {
            using var stream = new InMemoryRandomAccessStream();
            using var writer = new DataWriter(stream.GetOutputStreamAt(0));
            writer.WriteBytes(data);
            await writer.StoreAsync();
            stream.Seek(0);
            var image = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage { DecodePixelWidth = 160 };
            await image.SetSourceAsync(stream);
            return image;
        }
        catch { return null; }
    }

    private readonly HashSet<string> _removingAttachments = [];

    private async void OnRemoveAttachmentClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: PendingAttachment attachment } || _sendingComposer || !_removingAttachments.Add(attachment.Id)) { return; }
        var key = (_displayedChannelId, _displayedThreadParentId);
        RefreshComposerPermissions();
        try
        {
            await _session.DeleteTemporaryAttachmentAsync(attachment.Id);
            if (key == (_displayedChannelId, _displayedThreadParentId)) { _pendingAttachments.Remove(attachment); }
            if (key.Item1 is { } channelId && _channelDrafts.TryGetValue((channelId, key.Item2), out var draft))
            {
                _channelDrafts[(channelId, key.Item2)] = draft with { Attachments = draft.Attachments.Where(file => file.Id != attachment.Id).ToArray() };
            }
        }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
        finally { _removingAttachments.Remove(attachment.Id); RefreshComposerPermissions(); }
    }

    private sealed record UploadSource(string Name, string MimeType, long Size, Func<CancellationToken, Task<byte[]>> Read);
}
