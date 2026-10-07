using System.Collections.ObjectModel;
using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.System;

namespace Sharkord.App;

public sealed partial class MainWindow : Window
{
    private readonly SharkordSession _session;
    private readonly ObservableCollection<ChannelItem> _channels = [];
    private readonly ObservableCollection<MessageItem> _messages = [];
    private string? _languagePreference;
    private bool _isUpdatingLanguagePicker;

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

    public MainWindow(SharkordSession session)
    {
        _session = session;
        InitializeComponent();

        _languagePreference = ReadLanguagePreference();
        if (_languagePreference is null)
        {
            L10n.UseSystemLanguage();
        }
        else
        {
            L10n.Language = _languagePreference;
        }

        ChannelList.ItemsSource = _channels;
        MessageList.ItemsSource = _messages;

        ApplyLocalisation();
        L10n.LanguageChanged += ApplyLocalisation;
        Closed += (_, _) => L10n.LanguageChanged -= ApplyLocalisation;

        _session.Changed += OnSessionChanged;
    }

    /// <summary>
    /// every user-facing literal in this window is assigned here, so a language change only
    /// has to re-run this one method. see <see cref="I18n.L10n"/> for the tables.
    /// </summary>
    private void ApplyLocalisation()
    {
        TaglineText.Text = L10n.T("tagline", ns: "windows");
        RefreshLanguagePicker();
        HostBox.Header = L10n.T("serverAddress", ns: "windows");
        IdentityBox.Header = L10n.T("identityLabel", ns: "connect");
        PasswordBox.Header = L10n.T("passwordLabel", ns: "connect");
        ServerPasswordBox.Header = L10n.T("serverPassword", ns: "windows");
        InviteBox.Header = L10n.T("inviteCode", ns: "windows");
        ConnectButton.Content = L10n.T("connectBtn", ns: "connect");
        ComposerBox.PlaceholderText = L10n.T("messagePlaceholder", ns: "windows");
        SendButton.Content = L10n.T("send", ns: "windows");

        // messages embed the localised system author name, so they have to be rebuilt too
        Refresh();
    }

    private void RefreshLanguagePicker()
    {
        _isUpdatingLanguagePicker = true;

        try
        {
            LanguageBox.Header = L10n.T("languageLabel", ns: "windows");
            LanguageBox.Items.Clear();
            LanguageBox.Items.Add(new ComboBoxItem
            {
                Content = L10n.T("systemLanguage", ns: "windows"),
                Tag = "system"
            });

            foreach (var language in L10n.SupportedLanguages)
            {
                LanguageBox.Items.Add(new ComboBoxItem { Content = language.NativeName, Tag = language.Code });
            }

            var selectedTag = _languagePreference ?? "system";
            LanguageBox.SelectedItem = LanguageBox.Items
                .OfType<ComboBoxItem>()
                .First(item => string.Equals(item.Tag as string, selectedTag, StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            _isUpdatingLanguagePicker = false;
        }
    }

    private void OnLanguageSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isUpdatingLanguagePicker || LanguageBox.SelectedItem is not ComboBoxItem item)
        {
            return;
        }

        var selectedLanguage = item.Tag as string;
        _languagePreference = selectedLanguage == "system" ? null : selectedLanguage;
        SaveLanguagePreference(_languagePreference);

        if (_languagePreference is null)
        {
            L10n.UseSystemLanguage();
            return;
        }

        L10n.Language = _languagePreference;
    }

    private static string? ReadLanguagePreference()
    {
        try
        {
            if (!File.Exists(LanguagePreferencePath))
            {
                return null;
            }

            var saved = File.ReadAllText(LanguagePreferencePath).Trim();
            if (saved.Equals("system", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            foreach (var language in L10n.SupportedLanguages)
            {
                if (language.Code.Equals(saved, StringComparison.OrdinalIgnoreCase))
                {
                    return language.Code;
                }
            }

            return null;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Could not read the saved language preference: {exception.Message}");
            return null;
        }
    }

    private static void SaveLanguagePreference(string? language)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LanguagePreferencePath)!);
            File.WriteAllText(LanguagePreferencePath, language ?? "system");
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Could not save the language preference: {exception.Message}");
        }
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
                var byline = author ?? L10n.T("systemUser", ns: "windows");
                var reactions = _session
                    .ReactionGroups(message)
                    .Select(group =>
                    {
                        var display = ReactionGlyphs.TryGetValue(group.Emoji, out var glyph)
                            ? glyph
                            : $":{group.Emoji}:";

                        return new ReactionItem(message.Id, group.Emoji, $"{display} {group.Count}", group.Mine);
                    })
                    .ToList();

                _messages.Add(
                    new MessageItem(
                        message.Id,
                        $"{byline}: {text}",
                        reactions,
                        L10n.T("addReaction", ns: "windows"),
                        "+"
                    )
                );
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

    private async void OnReactionClick(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleButton button && button.DataContext is ReactionItem reaction)
        {
            await ToggleReactionAsync(reaction.MessageId, reaction.Emoji);
        }
    }

    private void OnAddReactionClick(object sender, RoutedEventArgs e)
    {
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
        ChatErrorText.Text = "";

        try
        {
            await _session.ToggleReactionAsync(messageId, emoji);
        }
        catch (Exception exception)
        {
            ChatErrorText.Text = exception.Message;
            Refresh();
        }
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
        ChatErrorText.Text = "";

        try
        {
            await _session.SendMessageAsync(channelId, text);
        }
        catch (Exception exception)
        {
            ChatErrorText.Text = exception.Message;
        }
    }

    private static string LanguagePreferencePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Sharkord",
        "language"
    );

    private sealed record MessageItem(
        int Id,
        string Text,
        IReadOnlyList<ReactionItem> Reactions,
        string AddReactionLabel,
        string AddReactionGlyph
    );

    private sealed record ReactionItem(int MessageId, string Emoji, string Label, bool Mine);
    private sealed record ChannelItem(int Id, string Name);
}
