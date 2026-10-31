using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private readonly DispatcherTimer _typingTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly ObservableCollection<MemberItem> _members = [];
    private string? _channelTreeSignature;
    private bool _membersVisible;
    private SharkordUser? _displayedOwnUser;
    private bool _workspaceConnected;

    private void ResetDesktopWorkspace()
    {
        if (!_workspaceConnected)
        {
            return;
        }
        _workspaceConnected = false;
        _composerGeneration++;
        CancelComposerContext();
        ComposerBox.Text = "";
        _pendingAttachments.Clear();
        _channelDrafts.Clear();
        _displayedChannelId = null;
        _unreadMessageId = null;
        _newMessageId = null;
        _pendingUnreadCount = 0;
        _channelTreeSignature = null;
        _displayedOwnUser = null;
        MessagePresentation.Reconcile(_messages, [], row => row.Id);
    }

    private void InitializeDesktopControls()
    {
        MemberList.ItemsSource = _members;
        PendingAttachmentList.ItemsSource = _pendingAttachments;
        _membersVisible = ReadPreference("app.showMembers", false);
        SetMemberListVisibility();
        _typingTimer.Tick += OnTypingTimerTick;
        _typingTimer.Start();
        Closed += (_, _) =>
        {
            _typingTimer.Stop();
            _typingTimer.Tick -= OnTypingTimerTick;
        };
    }

    private void LocaliseDesktopControls()
    {
        SettingsButton.Content = new FontIcon { Glyph = "\uE713", FontSize = 16 };
        LabelControl(SettingsButton, L10n.T("settingsButton", ns: "macos"));
        MembersButton.Content = L10n.T("membersButton", ns: "macos");
        LabelControl(MembersButton, L10n.T("toggleParticipants"));
        LabelControl(AttachButton, L10n.T("attachFiles", ns: "windows"));
        LabelControl(ComposerEmojiButton, L10n.T("emojiTab"));
        LabelControl(CancelComposerButton, L10n.T("cancel"));
        LoadOlderButton.Content = L10n.T("loadEarlierMessages", ns: "macos");
        LabelControl(MessageList, L10n.T("channelsLabel", ns: "macos"));
        LabelControl(ComposerBox, L10n.T("messagePlaceholder", ns: "windows"));
        AutomationProperties.SetLiveSetting(TypingText, AutomationLiveSetting.Polite);
    }

    private static void LabelControl(FrameworkElement control, string label)
    {
        AutomationProperties.SetName(control, label);
        ToolTipService.SetToolTip(control, label);
    }

    private string ChannelTreeSignature() => string.Join("|",
        L10n.Language,
        string.Join(";", _session.Categories.Select(category => $"{category.Id}:{category.Name}:{category.Position}")),
        string.Join(";", _session.Channels.Select(channel =>
            $"{channel.Id}:{channel.Name}:{channel.Type}:{channel.CategoryId}:{channel.Position}:{_session.UnreadCount(channel.Id)}")),
        string.Join(";", _session.DirectMessages.Select(dm => $"{dm.ChannelId}:{_session.User(dm.UserId)?.Name}"))
    );

    private void RefreshDesktopControls()
    {
        if (!ReferenceEquals(_displayedOwnUser, _session.OwnUser))
        {
            _displayedOwnUser = _session.OwnUser;
            OwnNameText.Text = _displayedOwnUser?.Name ?? "";
            OwnAvatar.DisplayName = OwnNameText.Text;
            OwnAvatar.ProfilePicture = AvatarImage(_displayedOwnUser?.Avatar);
        }
        RefreshUserVoiceControls();
        RefreshTypingIndicator();
        RefreshComposerPermissions();
        RefreshMembers();
    }

    private BitmapImage? AvatarImage(SharkordFile? file) =>
        file is not null && _session.PublicFileUrl(file) is { } url ? new BitmapImage(url) : null;

    private void RefreshUserVoiceControls()
    {
        var connected = _session.CurrentVoiceChannelId is not null && _voiceMediaStatus == "connected";
        UserMicrophoneButton.IsEnabled = connected && _canPublishAudio;
        UserDeafenButton.IsEnabled = connected;
        UserMicrophoneIcon.Glyph = _microphoneMuted ? "\uE198" : "\uE720";
        UserDeafenIcon.Glyph = _deafened ? "\uE74F" : "\uE7F6";
        LabelControl(UserMicrophoneButton, L10n.T(_microphoneMuted ? "unmuteMic" : "muteMic", ns: "windows"));
        LabelControl(UserDeafenButton, L10n.T(_deafened ? "undeafen" : "deafen", ns: "windows"));
    }

    private void OnMembersClick(object sender, RoutedEventArgs e)
    {
        _membersVisible = !_membersVisible;
        SavePreference("app.showMembers", _membersVisible);
        SetMemberListVisibility();
        RefreshMembers();
    }

    private void SetMemberListVisibility()
    {
        MemberPanel.Visibility = _membersVisible ? Visibility.Visible : Visibility.Collapsed;
        MemberColumn.Width = new GridLength(_membersVisible ? 220 : 0);
    }

    private void RefreshMembers()
    {
        if (!_membersVisible)
        {
            return;
        }
        var existing = _members.ToDictionary(member => member.Id);
        var desired = new List<MemberItem>();
        foreach (var user in _session.Users.Where(user => !user.Banned)
                     .OrderBy(user => IsOnline(user) ? 0 : 1).ThenBy(user => user.Name, StringComparer.CurrentCultureIgnoreCase))
        {
            if (existing.TryGetValue(user.Id, out var row) && ReferenceEquals(row.Source, user) && row.Language == L10n.Language)
            {
                desired.Add(row);
            }
            else
            {
                desired.Add(new MemberItem(user, AvatarImage(user.Avatar)));
            }
        }
        MessagePresentation.Reconcile(_members, desired, member => member.Id);
        MembersTitle.Text = L10n.T("membersHeader", ns: "sidebar", ("count", desired.Count));
    }

    private static bool IsOnline(SharkordUser user) =>
        !string.IsNullOrWhiteSpace(user.Status) && !string.Equals(user.Status, "offline", StringComparison.OrdinalIgnoreCase);

    private void OnTypingTimerTick(object? sender, object e) => RefreshTypingIndicator();

    private void RefreshTypingIndicator()
    {
        var users = _session.SelectedChannelId is { } channelId ? _session.TypingUsers(channelId) : [];
        TypingText.Text = users.Count == 0 ? "" : L10n.T("typingUsers", ns: "windows", ("names", string.Join(", ", users.Select(user => user.Name))));
    }

    [Microsoft.UI.Xaml.Data.Bindable]
    public sealed class MemberItem(SharkordUser source, BitmapImage? avatar)
    {
        public SharkordUser Source { get; } = source;
        public int Id => Source.Id;
        public string Name => Source.Name;
        public BitmapImage? Avatar { get; } = avatar;
        public string Language { get; } = L10n.Language;
        public string Status { get; } = L10n.T(IsOnline(source) ? "online" : "offline", ns: "windows");
    }
}
