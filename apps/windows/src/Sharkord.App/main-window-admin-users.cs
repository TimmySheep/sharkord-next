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
    private async Task ShowUserModerationAsync(int userId, string name)
    {
        var info = await _session.CallQueryAsync("users.getInfo", new JsonObject { ["userId"] = userId });
        var user = info?["user"];
        var panel = new StackPanel { Width = 650, Spacing = 12 };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        panel.Children.Add(new TextBlock { Text = user?["bio"]?.GetValue<string>() ?? "", TextWrapping = TextWrapping.Wrap });
        if (user?["identity"]?.GetValue<string>() is { } identity) { panel.Children.Add(new TextBlock { Text = identity, IsTextSelectionEnabled = true }); }
        var storage = info?["storage"];
        panel.Children.Add(new TextBlock { Text = $"{L10n.T("storageTab", ns: "settings")}: {FormatBytes(storage?["usedStorage"]?.GetValue<long>() ?? 0)}" });
        panel.Children.Add(new TextBlock { Text = L10n.T("rolesSection", ns: "settings"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        foreach (var role in _session.Roles)
        {
            var check = new CheckBox { Content = role.Name, IsChecked = _session.User(userId)?.RoleIds?.Contains(role.Id) == true };
            check.IsEnabled = (role.Id != 1 || _session.OwnUser?.RoleIds?.Contains(1) == true) && (role.Permissions ?? []).All(_session.HasPermission);
            check.Click += async (_, _) =>
            {
                check.IsEnabled = false;
                try
                {
                    await _session.CallMutationAsync(check.IsChecked == true ? "users.addRole" : "users.removeRole", new JsonObject { ["userId"] = userId, ["roleId"] = role.Id });
                    status.Text = "";
                }
                catch (Exception exception) { check.IsChecked = check.IsChecked != true; status.Text = exception.Message; }
                finally { check.IsEnabled = true; }
            };
            panel.Children.Add(check);
        }
        panel.Children.Add(status);
        var messages = (info?["messages"] as JsonArray)?.OfType<JsonObject>().ToArray() ?? [];
        var history = new StackPanel { Spacing = 8 };
        panel.Children.Add(new TextBlock { Text = L10n.T("messagesTitle", ns: "admin"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        panel.Children.Add(history);
        var more = new Button { Content = L10n.T("loadMore", ns: "admin") };
        var shown = 0;
        var dialog = NavigationDialog(name, new ScrollViewer { Content = panel, MaxHeight = 540 });
        void AppendMessages()
        {
            foreach (var message in messages.Skip(shown).Take(40))
            {
                var id = message["id"]?.AsInt() ?? 0;
                var channelId = message["channelId"]?.AsInt() ?? 0;
                var row = new StackPanel { Spacing = 4 };
                row.Children.Add(new TextBlock { Text = MessageHtml.ToPlainText(message["content"]?.GetValue<string>() ?? ""), TextWrapping = TextWrapping.Wrap });
                var jump = new Button { Content = L10n.T("jumpToMessage", ns: "dialogs") };
                jump.Click += async (_, _) => { dialog.Hide(); CloseSettingsOverlay(); await JumpToMessageAsync(channelId, id); };
                row.Children.Add(jump);
                if (_session.HasPermission("MANAGE_MESSAGES"))
                {
                    var delete = new Button { Content = L10n.T("deleteLabel") };
                    delete.Click += async (_, _) =>
                    {
                        if (delete.Tag is not true) { delete.Tag = true; delete.Content = L10n.T("confirm"); return; }
                        try { await _session.DeleteMessageAsync(id); row.Visibility = Visibility.Collapsed; }
                        catch (Exception exception) { status.Text = exception.Message; }
                    };
                    row.Children.Add(delete);
                }
                foreach (var link in MessageLinks(MessageHtml.Parse(message["content"]?.GetValue<string>() ?? "")))
                {
                    var open = new HyperlinkButton { Content = link, IsTextScaleFactorEnabled = true };
                    open.Click += async (_, _) => await OpenExternalFileAsync(new Uri(link));
                    row.Children.Add(open);
                }
                history.Children.Add(row);
            }
            shown = Math.Min(messages.Length, shown + 40);
            more.Visibility = shown < messages.Length ? Visibility.Visible : Visibility.Collapsed;
        }
        more.Click += (_, _) => AppendMessages();
        panel.Children.Add(more);
        AppendMessages();
        panel.Children.Add(new TextBlock { Text = L10n.T("filesTitle", ns: "admin"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        var files = (info?["files"] as JsonArray)?.ToArray() ?? [];
        var fileRows = new StackPanel { Spacing = 4 };
        var moreFiles = new Button { Content = L10n.T("loadMore", ns: "admin") };
        var filesShown = 0;
        void AppendFiles()
        {
            foreach (var value in files.Skip(filesShown).Take(40))
            {
                if (value.DeserializeObject<SharkordFile>() is not { } file || _session.PublicFileUrl(file) is not { } url) { continue; }
                var open = new HyperlinkButton { Content = $"{file.OriginalName} · {FormatBytes(file.Size)}" };
                open.Click += async (_, _) => await OpenExternalFileAsync(url);
                var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                row.Children.Add(open);
                if (_session.HasPermission("MANAGE_MESSAGES") || userId == _session.OwnUserId)
                {
                    var remove = new Button { Content = L10n.T("deleteLabel") };
                    remove.Click += async (_, _) =>
                    {
                        if (remove.Tag is not true) { remove.Tag = true; remove.Content = L10n.T("confirm"); return; }
                        try { await _session.CallMutationAsync("files.delete", new JsonObject { ["fileId"] = file.Id }); row.Visibility = Visibility.Collapsed; }
                        catch (Exception exception) { status.Text = exception.Message; }
                    };
                    row.Children.Add(remove);
                }
                fileRows.Children.Add(row);
            }
            filesShown = Math.Min(files.Length, filesShown + 40);
            moreFiles.Visibility = filesShown < files.Length ? Visibility.Visible : Visibility.Collapsed;
        }
        moreFiles.Click += (_, _) => AppendFiles();
        panel.Children.Add(fileRows); panel.Children.Add(moreFiles);
        AppendFiles();
        panel.Children.Add(new TextBlock { Text = L10n.T("loginsTitle", ns: "admin"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        foreach (var login in info?["logins"] as JsonArray ?? [])
        {
            var when = login?["createdAt"]?.GetValue<long>() ?? 0;
            panel.Children.Add(new TextBlock { Text = $"{DateTimeOffset.FromUnixTimeMilliseconds(when).LocalDateTime:g} · {login?["ip"]?.GetValue<string>() ?? ""}", TextWrapping = TextWrapping.Wrap });
        }
        await dialog.ShowAsync();
    }

    private static IEnumerable<string> MessageLinks(IEnumerable<MessagePart> parts) => parts
        .SelectMany(part => MessageLinks(part.Children).Concat(part.Kind == MessagePartKind.Link && part.Target is { } target ? [target] : Array.Empty<string>()));
}
