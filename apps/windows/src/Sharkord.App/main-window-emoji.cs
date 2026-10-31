using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private void ShowEmojiPicker(FrameworkElement anchor, Action<EmojiChoice> onChosen, bool reactions = false)
    {
        var picker = new EmojiPicker(_session, reactions);
        var flyout = new Flyout { Content = picker };
        picker.Chosen += emoji => { flyout.Hide(); onChosen(emoji); };
        flyout.ShowAt(anchor);
    }

    private void OnComposerEmojiClick(object sender, RoutedEventArgs e)
    {
        ShowEmojiPicker(ComposerEmojiButton, emoji => InsertComposerText(emoji.ImageUrl is null ? emoji.Glyph : $":{emoji.Shortcode}:"));
    }

    private void InsertComposerText(string text)
    {
        var position = ComposerBox.SelectionStart;
        ComposerBox.SelectedText = text;
        ComposerBox.Focus(FocusState.Programmatic);
        ComposerBox.SelectionStart = position + text.Length;
        ComposerBox.SelectionLength = 0;
    }

    private string FormatComposerText(string text) => MessageHtml.FromComposerText(text, _session.Emojis
        .Where(emoji => emoji.File is not null).ToDictionary(emoji => emoji.Name, emoji => _session.PublicFileUrl(emoji.File!)!.AbsoluteUri));

    private void OnComposerFormatClick(object sender, RoutedEventArgs e)
    {
        var menu = new MenuFlyout();
        AddFormatAction(menu, "formatBold", "**", "**");
        AddFormatAction(menu, "formatItalic", "*", "*");
        AddFormatAction(menu, "formatCode", "`", "`");
        AddFormatAction(menu, "formatCodeBlock", "\n```\n", "\n```\n");
        AddFormatAction(menu, "formatSpoiler", "||", "||");
        var mention = new MenuFlyoutItem { Text = L10n.T("formatMention", ns: "windows") };
        mention.Click += (_, _) => ShowReferencePicker(true);
        var channel = new MenuFlyoutItem { Text = L10n.T("formatChannel", ns: "windows") };
        channel.Click += (_, _) => ShowReferencePicker(false);
        menu.Items.Add(mention); menu.Items.Add(channel);
        menu.ShowAt(ComposerFormatButton);
    }

    private void AddFormatAction(MenuFlyout menu, string key, string before, string after)
    {
        var item = new MenuFlyoutItem { Text = L10n.T(key, ns: "windows") };
        item.Click += (_, _) =>
        {
            var start = ComposerBox.SelectionStart;
            var selected = ComposerBox.SelectedText;
            ComposerBox.SelectedText = before + selected + after;
            ComposerBox.Focus(FocusState.Programmatic);
            ComposerBox.SelectionStart = start + before.Length;
            ComposerBox.SelectionLength = selected.Length;
        };
        menu.Items.Add(item);
    }

    private void ShowReferencePicker(bool users)
    {
        var input = new TextBox { PlaceholderText = L10n.T(users ? "formatMention" : "formatChannel", ns: "windows") };
        var results = new StackPanel { Spacing = 4 };
        var panel = new StackPanel { Width = 320, Spacing = 8 };
        panel.Children.Add(input);
        panel.Children.Add(new ScrollViewer { Content = results, MaxHeight = 300 });
        var flyout = new Flyout { Content = panel };
        void Render()
        {
            results.Children.Clear();
            IEnumerable<(string Name, int Id)> choices = _session.Channels.Where(channel => !channel.IsDm && _session.CanViewChannel(channel)).Select(channel => (channel.Name, channel.Id));
            if (users) { choices = _session.Users.Where(user => !user.Banned && user.Name != "__deleted_user__").Select(user => (user.Name, user.Id)); }
            foreach (var choice in choices.Where(choice => choice.Name.Contains(input.Text.Trim(), StringComparison.CurrentCultureIgnoreCase)))
            {
                var button = new Button { Content = choice.Name, HorizontalAlignment = HorizontalAlignment.Stretch };
                button.Click += (_, _) =>
                {
                    flyout.Hide();
                    var marker = users ? "@" : "#";
                    var kind = users ? "user" : "channel";
                    InsertComposerText($"{marker}[{choice.Name.Replace("]", ")")}]({kind}:{choice.Id}) ");
                };
                results.Children.Add(button);
            }
        }
        input.TextChanged += (_, _) => Render();
        Render();
        flyout.ShowAt(ComposerFormatButton);
    }
}
