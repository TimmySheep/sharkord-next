using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private void AddServerBrandingControls(StackPanel panel, TextBlock status)
    {
        var image = new Image { Source = AvatarImage(_session.ServerInfo?.Logo), Width = 96, Height = 96, HorizontalAlignment = HorizontalAlignment.Left };
        var upload = new Button { Content = L10n.T("uploadLogo", ns: "admin") };
        var remove = new Button { Content = L10n.T("removeImage") };
        upload.Click += async (_, _) =>
        {
            var picker = new FileOpenPicker();
            foreach (var extension in new[] { ".png", ".jpg", ".jpeg", ".gif", ".webp" }) { picker.FileTypeFilter.Add(extension); }
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            try
            {
                var file = await picker.PickSingleFileAsync();
                if (file is null) { return; }
                var id = await _session.UploadAttachmentAsync(await File.ReadAllBytesAsync(file.Path), file.Name, file.ContentType);
                await _session.CallMutationAsync("others.changeLogo", new JsonObject { ["fileId"] = id });
                await _session.RefreshServerInfoAsync();
                image.Source = AvatarImage(_session.ServerInfo?.Logo);
                status.Text = L10n.T("settingsUpdated", ns: "settings");
            }
            catch (Exception exception) { status.Text = exception.Message; }
        };
        remove.Click += async (_, _) =>
        {
            try
            {
                await _session.CallMutationAsync("others.changeLogo", new JsonObject());
                await _session.RefreshServerInfoAsync();
                image.Source = AvatarImage(_session.ServerInfo?.Logo);
                status.Text = L10n.T("settingsUpdated", ns: "settings");
            }
            catch (Exception exception) { status.Text = exception.Message; }
        };
        panel.Children.Add(image); panel.Children.Add(upload); panel.Children.Add(remove);
    }

}
