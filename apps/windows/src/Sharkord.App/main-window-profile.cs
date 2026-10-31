using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private void OnMemberProfileClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is MemberItem member && sender is FrameworkElement anchor) { ShowProfile(member.Source, anchor); }
    }

    private void OnMessageProfileClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: MessageItem row } anchor && row.Source.UserId is { } id && _session.User(id) is { } user)
        {
            ShowProfile(user, anchor);
        }
    }

    private void ShowProfile(SharkordUser user, FrameworkElement anchor)
    {
        var panel = new StackPanel { Width = 300, Spacing = 12 };
        if (AvatarImage(user.Banner) is { } banner)
        {
            panel.Children.Add(new Image { Source = banner, Height = 90, Stretch = Stretch.UniformToFill });
        }
        panel.Children.Add(new PersonPicture { DisplayName = user.Name, ProfilePicture = AvatarImage(user.Avatar), Width = 64, Height = 64, HorizontalAlignment = HorizontalAlignment.Left });
        panel.Children.Add(new TextBlock { Text = user.Name, FontSize = 20, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = L10n.T(IsOnline(user) ? "online" : "offline", ns: "windows") });
        if (user.Banned) { panel.Children.Add(new TextBlock { Text = L10n.T("bannedBadge") }); }
        foreach (var role in _session.Roles.Where(role => user.RoleIds?.Contains(role.Id) == true))
        {
            panel.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(6), Padding = new Thickness(8, 4, 8, 4),
                Child = new TextBlock { Text = role.Name }, Background = new SolidColorBrush(Microsoft.UI.Colors.DimGray)
            });
        }
        if (!string.IsNullOrWhiteSpace(user.Bio)) { panel.Children.Add(new TextBlock { Text = user.Bio, TextWrapping = TextWrapping.Wrap }); }
        panel.Children.Add(new TextBlock { Text = L10n.T("memberSince", ns: "common", ("date", DateTimeOffset.FromUnixTimeMilliseconds(user.CreatedAt).LocalDateTime.ToString("d"))), FontSize = 12 });
        var flyout = new Flyout { Content = new ScrollViewer { Content = panel, MaxHeight = 600 } };
        if (_session.CanOpenDirectMessage(user))
        {
            var dm = new Button { Content = L10n.T("directMessage"), HorizontalAlignment = HorizontalAlignment.Stretch };
            dm.Click += async (_, _) =>
            {
                flyout.Hide();
                try { CloseThread(); await _session.OpenDirectMessageAsync(user.Id); Refresh(); }
                catch (Exception exception) { ChatErrorText.Text = exception.Message; }
            };
            panel.Children.Add(dm);
        }
        flyout.ShowAt(anchor);
    }
}
