using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Sharkord.Core;
using Windows.System;

namespace Sharkord.App;

public sealed partial class MainWindow : Window
{
    private readonly SharkordSession _session;
    private readonly ObservableCollection<ChannelItem> _channels = [];
    private readonly ObservableCollection<string> _messages = [];

    public MainWindow(SharkordSession session)
    {
        _session = session;
        InitializeComponent();

        ChannelList.ItemsSource = _channels;
        MessageList.ItemsSource = _messages;

        _session.Changed += OnSessionChanged;
    }

    private void OnSessionChanged()
    {
        DispatcherQueue.TryEnqueue(Refresh);
    }

    private void Refresh()
    {
        ConnectButton.IsEnabled = _session.Phase != SessionPhase.Connecting;
        ConnectProgress.IsActive = _session.Phase == SessionPhase.Connecting;
        ConnectError.Text = _session.Phase == SessionPhase.Failed ? _session.LastError ?? "" : "";

        if (_session.Phase != SessionPhase.Connected)
        {
            ChatPanel.Visibility = Visibility.Collapsed;
            ConnectPanel.Visibility = Visibility.Visible;
            return;
        }

        ConnectPanel.Visibility = Visibility.Collapsed;
        ChatPanel.Visibility = Visibility.Visible;
        ServerNameText.Text = _session.ServerName;

        SyncChannels();

        var selected = _session.SelectedChannelId is { } id ? _session.Channel(id) : null;
        ChannelTitle.Text = selected is null ? "" : $"# {selected.Name}";

        _messages.Clear();

        if (selected is not null && _session.MessagesByChannel.TryGetValue(selected.Id, out var list))
        {
            foreach (var message in list)
            {
                var author = message.UserId is { } userId ? _session.User(userId)?.Name : null;
                var text = MessageHtml.ToPlainText(message.Content ?? "");
                _messages.Add($"{(author ?? "System")}: {text}");
            }
        }
    }

    private void SyncChannels()
    {
        var desired = _session.TextChannels.ToList();

        if (_channels.Count == desired.Count && _channels.Zip(desired).All(pair => pair.First.Id == pair.Second.Id))
        {
            return;
        }

        _channels.Clear();

        foreach (var channel in desired)
        {
            _channels.Add(new ChannelItem(channel.Id, $"# {channel.Name}"));
        }
    }

    private async void OnConnectClick(object sender, RoutedEventArgs e)
    {
        await _session.ConnectAsync(
            HostBox.Text,
            IdentityBox.Text,
            PasswordBox.Password,
            ServerPasswordBox.Password,
            InviteBox.Text
        );

        Refresh();
    }

    private async void OnChannelSelected(object sender, SelectionChangedEventArgs e)
    {
        if (ChannelList.SelectedItem is ChannelItem item)
        {
            await _session.SelectChannelAsync(item.Id);
        }
    }

    private async void OnSendClick(object sender, RoutedEventArgs e)
    {
        await SendComposer();
    }

    private async void OnComposerKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter && !e.KeyStatus.IsMenuKeyDown)
        {
            e.Handled = true;
            await SendComposer();
        }
    }

    private async Task SendComposer()
    {
        if (_session.SelectedChannelId is not { } channelId)
        {
            return;
        }

        var text = ComposerBox.Text;

        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        ComposerBox.Text = string.Empty;

        try
        {
            await _session.SendMessageAsync(channelId, text);
        }
        catch (Exception exception)
        {
            ConnectError.Text = exception.Message;
        }
    }

    private sealed record ChannelItem(int Id, string Name);
}
