using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private SharkordMessage? _threadParent;
    private bool _showDmVoice;
    private int? _displayedThreadParentId;
    private int? _jumpTargetId;
    private int _threadOpenRequest;
    private long _displayedHistoryGeneration = -1;

    private bool CanEditMessage(SharkordMessage message) =>
        message.Editable == true && _session.CanManageMessage(message);

    private void LocaliseNavigationControls()
    {
        LabelControl(NavigationButton, L10n.T("searchTitle", ns: "dialogs"));
        LabelControl(CloseThreadButton, L10n.T("close"));
        LabelControl(ReturnToPresentButton, L10n.T("viewingOlderMessages"));
    }

    private void RefreshNavigationControls()
    {
        if (_displayedHistoryGeneration != _session.HistoryGeneration ||
            (_threadParent is not null && _threadParent.ChannelId != _session.SelectedChannelId))
        {
            _threadParent = null;
            _displayedHistoryGeneration = _session.HistoryGeneration;
        }
        CloseThreadButton.Visibility = _threadParent is null ? Visibility.Collapsed : Visibility.Visible;
        ReturnToPresentButton.Visibility = _threadParent is null && _session.SelectedChannelId is { } id && _session.HasNewerMessages(id)
            ? Visibility.Visible : Visibility.Collapsed;
        if (_jumpTargetId is { } targetId && _messages.FirstOrDefault(row => row.Id == targetId) is { } target)
        {
            MessageList.ScrollIntoView(target);
            _jumpTargetId = null;
        }
    }

    private void CloseThread()
    {
        _threadParent = null;
        _threadOpenRequest++;
        _showDmVoice = false;
    }

    private void OnCloseThreadClick(object sender, RoutedEventArgs e)
    {
        CloseThread();
        Refresh();
    }

    private async void OnReturnToPresentClick(object sender, RoutedEventArgs e)
    {
        if (_session.SelectedChannelId is not { } channelId) { return; }
        try { await _session.ReturnToPresentAsync(channelId); }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }

    private async Task JumpToMessageAsync(int channelId, int messageId)
    {
        CloseThread();
        PrepareChannelSelection(channelId);
        try
        {
            var targetNode = await _session.CallQueryAsync("messages.getOne", new JsonObject { ["messageId"] = messageId });
            var target = targetNode?.Deserialize<SharkordMessage>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
            var rootId = target?.ParentMessageId ?? messageId;
            await _session.JumpToMessageAsync(channelId, rootId);
            if (target?.ParentMessageId is not null)
            {
                var parent = _session.GetMessagesSnapshot(channelId).FirstOrDefault(message => message.Id == rootId);
                if (parent is not null)
                {
                    await OpenThreadAsync(parent);
                    while (_threadParent?.Id == parent.Id &&
                        !_session.GetThreadMessagesSnapshot(parent.Id).Any(message => message.Id == messageId) &&
                        _session.HasMoreThreadMessages(parent.Id))
                    {
                        await _session.LoadThreadAsync(parent.Id, more: true);
                    }
                }
            }
            _jumpTargetId = messageId;
            Refresh();
            RefreshNavigationControls();
        }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }

    private async Task OpenThreadAsync(SharkordMessage parent)
    {
        if (parent.ParentMessageId is not null) { return; }
        var request = ++_threadOpenRequest;
        try
        {
            await _session.LoadThreadAsync(parent.Id);
            if (request != _threadOpenRequest || _session.SelectedChannelId != parent.ChannelId) { return; }
            _threadParent = parent;
            Refresh();
        }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }

    private async void OnThreadClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: MessageItem row }) { await OpenThreadAsync(row.Source); }
    }

    private async void OnReplyPreviewClick(object sender, RoutedEventArgs e)
    {
        if (sender is HyperlinkButton { DataContext: MessageItem row } && row.Source.ReplyToMessageId is { } id)
        {
            if (_threadParent is not null && _messages.FirstOrDefault(message => message.Id == id) is { } target)
            {
                MessageList.ScrollIntoView(target);
                return;
            }
            await JumpToMessageAsync(row.Source.ChannelId, id);
        }
    }

    private void OnNavigationClick(object sender, RoutedEventArgs e)
    {
        var menu = new MenuFlyout();
        AddNavigationAction(menu, L10n.T("searchTitle", ns: "dialogs"), ShowSearchAsync, _session.Settings?.EnableSearch == true);
        AddNavigationAction(menu, L10n.T("pinnedMessagesTitle"), ShowPinsAsync, _session.SelectedChannelId is not null);
        AddNavigationAction(menu, L10n.T("channelsLabel", ns: "macos"), () => ShowSelectionAsync(false));
        AddNavigationAction(menu, L10n.T("directMessage"), () => ShowSelectionAsync(true), _session.Settings?.DirectMessagesEnabled == true);
        if (_session.SelectedChannelId is { } selectedId && _session.Channel(selectedId) is { IsDm: true, SupportsVoice: true })
        {
            var label = _showDmVoice ? L10n.T("messageChannel", ns: "common", ("name", ChannelTitle.Text)) : L10n.T("joinVoice", ns: "windows");
            AddNavigationAction(menu, label, () =>
            {
                _showDmVoice = !_showDmVoice;
                Refresh();
                return Task.CompletedTask;
            });
        }
        AddChannelManagement(menu);
        menu.ShowAt(NavigationButton);
    }

    private void AddNavigationAction(MenuFlyout menu, string title, Func<Task> action, bool enabled = true)
    {
        var item = new MenuFlyoutItem { Text = title, IsEnabled = enabled };
        item.Click += async (_, _) =>
        {
            try { await action(); }
            catch (Exception exception) { ChatErrorText.Text = exception.Message; }
        };
        menu.Items.Add(item);
    }

    private async Task ShowSelectionAsync(bool users)
    {
        var filter = new TextBox { PlaceholderText = L10n.T(users ? "searchUser" : "channelsLabel", ns: users ? "sidebar" : "macos") };
        var results = new StackPanel { Spacing = 4 };
        var content = new StackPanel { Width = 460, Spacing = 12 };
        content.Children.Add(filter);
        content.Children.Add(new ScrollViewer { Content = results, MaxHeight = 440 });
        var dialog = NavigationDialog(users ? L10n.T("directMessage") : L10n.T("channelsLabel", ns: "macos"), content);
        void Render()
        {
            results.Children.Clear();
            if (users)
            {
                foreach (var user in _session.Users.Where(_session.CanOpenDirectMessage)
                    .Where(user => user.Name.Contains(filter.Text.Trim(), StringComparison.CurrentCultureIgnoreCase)))
                {
                    var button = new Button { Content = user.Name, HorizontalAlignment = HorizontalAlignment.Stretch };
                    button.Click += async (_, _) =>
                    {
                        dialog.Hide();
                        try { CloseThread(); await _session.OpenDirectMessageAsync(user.Id); Refresh(); }
                        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
                    };
                    results.Children.Add(button);
                }
            }
            else
            {
                foreach (var channel in _session.Channels.Where(_session.CanViewChannel)
                    .Where(channel => channel.Name.Contains(filter.Text.Trim(), StringComparison.CurrentCultureIgnoreCase)))
                {
                    var button = new Button { Content = channel.Name, HorizontalAlignment = HorizontalAlignment.Stretch };
                    button.Click += async (_, _) =>
                    {
                        dialog.Hide();
                        CloseThread();
                        PrepareChannelSelection(channel.Id);
                        await _session.SelectChannelAsync(channel.Id);
                    };
                    results.Children.Add(button);
                }
            }
        }
        filter.TextChanged += (_, _) => Render();
        Render();
        await dialog.ShowAsync();
    }

    private ContentDialog NavigationDialog(string title, object content) => new()
    {
        XamlRoot = RootGrid.XamlRoot, Title = title, Content = content,
        CloseButtonText = L10n.T("close"), DefaultButton = ContentDialogButton.Close
    };

    private async Task ShowSearchAsync()
    {
        var input = new TextBox { PlaceholderText = L10n.T("searchPlaceholder", ns: "dialogs"), MaxLength = 24 };
        var hint = new TextBlock { Text = L10n.T("searchHint", ns: "dialogs"), TextWrapping = TextWrapping.Wrap };
        var results = new StackPanel { Spacing = 6 };
        var content = new StackPanel { Width = 520, Spacing = 12 };
        content.Children.Add(input);
        content.Children.Add(hint);
        content.Children.Add(new ScrollViewer { Content = results, MaxHeight = 440 });
        var dialog = NavigationDialog(L10n.T("searchTitle", ns: "dialogs"), content);
        var generation = 0;
        var closed = false;
        input.TextChanged += async (_, _) =>
        {
            var request = ++generation;
            var query = input.Text.Trim();
            results.Children.Clear();
            if (query.Length < 2) { hint.Text = L10n.T("searchHint", ns: "dialogs"); return; }
            try
            {
                await Task.Delay(250);
                if (closed || request != generation) { return; }
                var result = await _session.SearchAsync(query);
                if (closed || request != generation || _session.Settings?.EnableSearch != true) { return; }
                hint.Text = result?["truncated"]?.GetValue<bool>() == true ? L10n.T("searchTruncated", ns: "dialogs") : "";
                foreach (var message in result?["messages"]?.AsArray() ?? [])
                {
                    if (message is null) { continue; }
                    var parsed = message.Deserialize<SharkordMessage>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
                    if (parsed is null) { continue; }
                    AddResult($"# {message["channelName"]} · {MessageHtml.ToPlainText(parsed.Content ?? "")}",
                        parsed.ChannelId, parsed.Id);
                }
                foreach (var file in result?["files"]?.AsArray() ?? [])
                {
                    if (file?["messageId"]?.GetValue<int>() is not { } messageId || file["channelId"]?.GetValue<int>() is not { } channelId) { continue; }
                    AddResult($"# {file["channelName"]} · {file["file"]?["originalName"]}", channelId, messageId);
                }
            }
            catch (Exception exception)
            {
                if (!closed && request == generation) { hint.Text = exception.Message; }
            }
        };
        void AddResult(string text, int channelId, int messageId)
        {
            var button = new Button { Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap }, HorizontalAlignment = HorizontalAlignment.Stretch };
            button.Click += async (_, _) => { dialog.Hide(); await JumpToMessageAsync(channelId, messageId); };
            results.Children.Add(button);
        }
        await dialog.ShowAsync();
        closed = true;
        generation++;
    }

    private async Task ShowPinsAsync()
    {
        if (_session.SelectedChannelId is not { } channelId) { return; }
        try
        {
            var messages = await _session.GetPinnedMessagesAsync(channelId);
            var results = new StackPanel { Width = 500, Spacing = 8 };
            var dialog = NavigationDialog(L10n.T("pinnedMessagesTitle"), new ScrollViewer { Content = results, MaxHeight = 480 });
            if (messages.Count == 0) { results.Children.Add(new TextBlock { Text = L10n.T("noPinnedMessages") }); }
            foreach (var message in messages)
            {
                var button = new Button
                {
                    Content = new TextBlock { Text = MessageHtml.ToPlainText(message.Content ?? ""), TextWrapping = TextWrapping.Wrap },
                    HorizontalAlignment = HorizontalAlignment.Stretch
                };
                button.Click += async (_, _) => { dialog.Hide(); await JumpToMessageAsync(channelId, message.Id); };
                results.Children.Add(button);
            }
            await dialog.ShowAsync();
        }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }
}
