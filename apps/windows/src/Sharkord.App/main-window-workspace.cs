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
    private IReadOnlyList<SharkordCategory>? _treeCategories;
    private IReadOnlyList<SharkordChannel>? _treeChannels;
    private IReadOnlyList<SharkordUser>? _treeUsers;
    private IReadOnlyList<DirectMessageConversation>? _treeConversations;
    private long _treeUnreadRevision = -1;
    private IReadOnlyDictionary<int, ChannelPermissionEntry>? _treePermissions;
    private string? _treeLanguage;
    private IReadOnlyList<SharkordUser>? _displayedMembers;
    private string? _membersLanguage;
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
        _treeChannels = null;
        _displayedMembers = null;
        _renderedMessageUsers = null;
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
        LocaliseNavigationControls();
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

    private bool ChannelTreeChanged()
    {
        var categories = _session.Categories;
        var channels = _session.Channels;
        var users = _session.Users;
        var conversations = _session.DirectMessages;
        var unreadRevision = _session.UnreadRevision;
        var language = L10n.Language;
        if (ReferenceEquals(_treePermissions, _session.ChannelPermissions) && ReferenceEquals(categories, _treeCategories) && ReferenceEquals(channels, _treeChannels) &&
            ReferenceEquals(users, _treeUsers) && ReferenceEquals(conversations, _treeConversations) &&
            unreadRevision == _treeUnreadRevision && language == _treeLanguage)
        {
            return false;
        }
        _treePermissions = _session.ChannelPermissions;
        _treeCategories = categories;
        _treeChannels = channels;
        _treeUsers = users;
        _treeConversations = conversations;
        _treeUnreadRevision = unreadRevision;
        _treeLanguage = language;
        return true;
    }

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
        var users = _session.Users;
        var language = L10n.Language;
        if (ReferenceEquals(users, _displayedMembers) && language == _membersLanguage)
        {
            return;
        }
        var existing = _members.ToDictionary(member => member.Id);
        var desired = new List<MemberItem>();
        foreach (var user in users.Where(user => !user.Banned)
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
        _displayedMembers = users;
        _membersLanguage = language;
        MembersTitle.Text = L10n.T("membersHeader", ns: "sidebar", ("count", desired.Count));
    }

    private static bool IsOnline(SharkordUser user) =>
        !string.IsNullOrWhiteSpace(user.Status) && !string.Equals(user.Status, "offline", StringComparison.OrdinalIgnoreCase);

    private void OnTypingTimerTick(object? sender, object e) => RefreshTypingIndicator();

    private void RefreshTypingIndicator()
    {
        IReadOnlyList<SharkordUser> users = [];
        if (_session.SelectedChannelId is { } channelId)
        {
            users = _threadParent is { } parent ? _session.ThreadTypingUsers(channelId, parent.Id) : _session.TypingUsers(channelId);
        }
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
