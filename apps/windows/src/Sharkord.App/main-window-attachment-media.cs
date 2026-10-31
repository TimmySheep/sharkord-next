using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.ApplicationModel.DataTransfer;
using Windows.Media.Core;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private void OnAttachmentLoaded(object sender, RoutedEventArgs e)
    {
        if (sender is StackPanel panel) { RenderAttachment(panel); }
    }

    private void OnAttachmentDataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        if (sender is StackPanel panel) { RenderAttachment(panel); }
    }

    private void RenderAttachment(StackPanel panel)
    {
        panel.Children.Clear();
        if (panel.DataContext is not AttachmentItem attachment || attachment.Url is not { } url) { return; }
        if (attachment.MimeType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
        {
            var button = new Button
            {
                Content = new Image { Source = new BitmapImage(url), MaxWidth = 320, MaxHeight = 220, Stretch = Stretch.Uniform },
                Padding = new Thickness(0), HorizontalAlignment = HorizontalAlignment.Left
            };
            LabelControl(button, L10n.T("imagePreviewOpen", ns: "macos"));
            button.Click += async (_, _) => await ShowImageViewerAsync(url);
            panel.Children.Add(button);
        }
        else if (attachment.MimeType.StartsWith("audio/", StringComparison.OrdinalIgnoreCase) || attachment.MimeType.StartsWith("video/", StringComparison.OrdinalIgnoreCase))
        {
            var media = new MediaPlayerElement
            {
                Source = MediaSource.CreateFromUri(url), AreTransportControlsEnabled = true, AutoPlay = false,
                MaxWidth = 520, Height = attachment.MimeType.StartsWith("audio/", StringComparison.OrdinalIgnoreCase) ? 90 : 280
            };
            media.Unloaded += (_, _) => { media.MediaPlayer?.Pause(); media.Source = null; };
            panel.Children.Add(media);
        }
        var open = new HyperlinkButton { Content = attachment.Name, HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(0) };
        open.Click += async (_, _) => await OpenExternalFileAsync(url);
        panel.Children.Add(open);
        panel.Children.Add(new TextBlock { Text = $"{attachment.MimeType} · {attachment.Size / 1024d:N1} KB", FontSize = 11, Opacity = .7 });
    }

    private async Task OpenExternalFileAsync(Uri uri)
    {
        if (!MessageHtml.IsSafeLink(uri.AbsoluteUri)) { return; }
        try { await Windows.System.Launcher.LaunchUriAsync(uri); }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }

    private async Task ShowImageViewerAsync(Uri uri)
    {
        var image = new Image { Source = new BitmapImage(uri), Stretch = Stretch.Uniform, MaxWidth = 1200, MaxHeight = 900 };
        var scroll = new ScrollViewer
        {
            Content = image, ZoomMode = ZoomMode.Enabled, MinZoomFactor = .25f, MaxZoomFactor = 8,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollMode = ScrollMode.Enabled, VerticalScrollMode = ScrollMode.Enabled, Width = 720, Height = 480
        };
        var toolbar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var zoomIn = new Button { Content = "+" };
        LabelControl(zoomIn, L10n.T("imageViewerZoomIn", ns: "macos"));
        zoomIn.Click += (_, _) => scroll.ChangeView(null, null, Math.Min(8, scroll.ZoomFactor * 1.25f));
        var zoomOut = new Button { Content = "−" };
        LabelControl(zoomOut, L10n.T("imageViewerZoomOut", ns: "macos"));
        zoomOut.Click += (_, _) => scroll.ChangeView(null, null, Math.Max(.25f, scroll.ZoomFactor / 1.25f));
        var reset = new Button { Content = L10n.T("imageViewerResetZoom", ns: "macos") };
        reset.Click += (_, _) => scroll.ChangeView(0, 0, 1);
        var copy = new Button { Content = L10n.T("imageViewerCopyLink", ns: "macos") };
        copy.Click += (_, _) => { var data = new DataPackage(); data.SetText(uri.AbsoluteUri); Clipboard.SetContent(data); };
        toolbar.Children.Add(zoomIn); toolbar.Children.Add(zoomOut); toolbar.Children.Add(reset); toolbar.Children.Add(copy);
        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(toolbar); content.Children.Add(scroll);
        var dialog = NavigationDialog(L10n.T("imagePreviewOpen", ns: "macos"), content);
        try { await dialog.ShowAsync(); }
        catch (Exception exception) { ChatErrorText.Text = exception.Message; }
    }
}
