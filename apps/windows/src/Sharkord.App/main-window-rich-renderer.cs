using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private void OnRichMessageLoaded(object sender, RoutedEventArgs e)
    {
        if (sender is RichTextBlock body) { RenderRichMessage(body); }
    }

    private void OnRichMessageDataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        if (sender is RichTextBlock body) { RenderRichMessage(body); }
    }

    private void RenderRichMessage(RichTextBlock body)
    {
        body.Blocks.Clear();
        if (body.DataContext is not MessageItem row) { return; }
        var paragraph = new Paragraph();
        var first = true;
        foreach (var part in MessageHtml.Parse(row.Source.Content ?? ""))
        {
            if (!first && part.Kind is MessagePartKind.Paragraph or MessagePartKind.CodeBlock) { paragraph.Inlines.Add(new LineBreak()); }
            AddRichPart(paragraph.Inlines, part);
            first = false;
        }
        body.Blocks.Add(paragraph);
    }

    private void AddRichPart(InlineCollection inlines, MessagePart part)
    {
        if (part.Kind == MessagePartKind.Break) { inlines.Add(new LineBreak()); return; }
        if (part.Kind == MessagePartKind.Text) { inlines.Add(new Run { Text = part.Text }); return; }
        if (part.Kind == MessagePartKind.Spoiler)
        {
            var button = new Button { Content = L10n.T("revealSpoiler", ns: "windows"), Padding = new Thickness(4, 0, 4, 0) };
            button.Click += (_, _) => button.Content = new TextBlock { Text = part.Text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
            inlines.Add(new InlineUIContainer { Child = button });
            return;
        }
        if (part.Kind == MessagePartKind.Mention && part.Id is { } userId)
        {
            var user = _session.User(userId);
            var button = new HyperlinkButton { Content = $"@{user?.Name ?? L10n.T("unknownUser")}", Padding = new Thickness(2, 0, 2, 0), IsEnabled = user is not null };
            button.Click += (_, _) => { if (user is not null) { ShowProfile(user, button); } };
            inlines.Add(new InlineUIContainer { Child = button });
            return;
        }
        if (part.Kind == MessagePartKind.Channel && part.Id is { } channelId)
        {
            var channel = _session.Channel(channelId);
            var button = new HyperlinkButton { Content = $"#{channel?.Name ?? L10n.T("unknownChannel")}", Padding = new Thickness(2, 0, 2, 0), IsEnabled = channel is not null && _session.CanViewChannel(channel) };
            button.Click += async (_, _) =>
            {
                try { CloseThread(); PrepareChannelSelection(channelId); await _session.SelectChannelAsync(channelId); }
                catch (Exception exception) { ChatErrorText.Text = exception.Message; }
            };
            inlines.Add(new InlineUIContainer { Child = button });
            return;
        }
        if (part.Kind == MessagePartKind.Emoji && part.Target is { } name)
        {
            var custom = _session.Emojis.FirstOrDefault(emoji => emoji.Name == name);
            if (custom?.File is { } file && _session.PublicFileUrl(file) is { } emojiUrl)
            {
                inlines.Add(new InlineUIContainer { Child = new Image { Source = new BitmapImage(emojiUrl), Width = 22, Height = 22, VerticalAlignment = VerticalAlignment.Center } });
                return;
            }
            var glyph = EmojiCatalog.Glyph(name);
            if (glyph != name) { inlines.Add(new Run { Text = glyph, FontFamily = new FontFamily("Segoe UI Emoji") }); return; }
        }
        if (part.Kind == MessagePartKind.Image)
        {
            if (ResolveMessageImage(part.Target) is { } url)
            {
                var image = new Image { Source = new BitmapImage(url), MaxWidth = part.IsEmojiImage ? 22 : 300, MaxHeight = part.IsEmojiImage ? 22 : 180, Stretch = Stretch.Uniform };
                var button = new Button { Content = image, Padding = new Thickness(0) };
                LabelControl(button, L10n.T("imagePreviewOpen", ns: "macos"));
                button.Click += async (_, _) => await ShowImageViewerAsync(url);
                inlines.Add(new InlineUIContainer { Child = button });
            }
            else if (part.Text.Length > 0) { inlines.Add(new Run { Text = part.Text }); }
            return;
        }
        if (part.Kind == MessagePartKind.Link && part.Target is { } href && MessageHtml.IsSafeLink(href))
        {
            var link = new Hyperlink();
            foreach (var child in part.Children) { AddRichPart(link.Inlines, child); }
            link.Click += async (_, _) => await OpenExternalFileAsync(new Uri(href));
            inlines.Add(link);
            return;
        }
        if (part.Kind == MessagePartKind.CodeBlock)
        {
            var code = new TextBlock { Text = RichPartText(part), FontFamily = new FontFamily("Consolas"), TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, MaxWidth = 680 };
            inlines.Add(new InlineUIContainer { Child = new Border { Child = code, Padding = new Thickness(10), Background = new SolidColorBrush(Microsoft.UI.Colors.Black), CornerRadius = new CornerRadius(4) } });
            return;
        }
        var span = new Span();
        if (part.Kind == MessagePartKind.Bold) { span.FontWeight = Microsoft.UI.Text.FontWeights.Bold; }
        if (part.Kind == MessagePartKind.Italic) { span.FontStyle = Windows.UI.Text.FontStyle.Italic; }
        if (part.Kind == MessagePartKind.Underline) { span.TextDecorations = Windows.UI.Text.TextDecorations.Underline; }
        if (part.Kind == MessagePartKind.Strike) { span.TextDecorations = Windows.UI.Text.TextDecorations.Strikethrough; }
        if (part.Kind == MessagePartKind.Code) { span.FontFamily = new FontFamily("Consolas"); }
        foreach (var child in part.Children) { AddRichPart(span.Inlines, child); }
        inlines.Add(span);
    }

    private static string RichPartText(MessagePart part) =>
        part.Text + string.Concat(part.Children.Select(child => child.Kind == MessagePartKind.Break ? "\n" : RichPartText(child)));

    private Uri? ResolveMessageImage(string? value)
    {
        var safe = MessageHtml.SafeImageReference(value);
        if (safe is null) { return null; }
        if (safe.StartsWith('/') && _session.ServerBaseUrl is { } server) { return new Uri(new Uri(server), safe); }
        return Uri.TryCreate(safe, UriKind.Absolute, out var uri) ? uri : null;
    }
}
