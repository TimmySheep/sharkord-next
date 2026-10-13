using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;
using WinRT.Interop;
using Windows.Storage.Pickers;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private FrameworkElement BuildGeneralAppSettings()
    {
        var autoJoin = CreatePreferenceToggle(
            "app.autoJoinLastChannel",
            "autoJoinLastChannelLabel",
            defaultValue: true
        );
        var appearance = new TextBlock
        {
            Text = $"{L10n.T("appearanceLabel", ns: "macos")}: {L10n.T("appearanceDark", ns: "macos")}",
            TextWrapping = TextWrapping.Wrap
        };

        var content = new StackPanel { Spacing = 12, Margin = new Thickness(20) };
        content.Children.Add(autoJoin);
        content.Children.Add(new TextBlock
        {
            Text = L10n.T("autoJoinLastChannelDesc", ns: "settings"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        });
        content.Children.Add(appearance);

        var pushToTalk = new ToggleSwitch
        {
            Header = L10n.T("pushToTalkTitle", ns: "windows"),
            IsOn = _pushToTalkEnabled
        };
        pushToTalk.Toggled += OnPushToTalkToggled;
        _pushToTalkStatusText = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        };
        content.Children.Add(pushToTalk);
        content.Children.Add(new TextBlock
        {
            Text = L10n.T("pushToTalkDescription", ns: "windows"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        });
        content.Children.Add(_pushToTalkStatusText);
        RefreshPushToTalkStatus();
        return content;
    }

    private FrameworkElement BuildNotificationSettings()
    {
        var content = new StackPanel { Spacing = 8, Margin = new Thickness(20) };
        content.Children.Add(new TextBlock
        {
            Text = L10n.T("notificationsDesc", ns: "settings"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        });
        AddPreferenceToggle(content, "notify.allMessages", "allMessagesLabel", "allMessagesDesc", false);
        AddPreferenceToggle(content, "notify.mentionsOnly", "mentionsOnlyLabel", "mentionsOnlyDesc", true);
        AddPreferenceToggle(content, "notify.dms", "dmNotificationsLabel", "dmNotificationsDesc", true);
        AddPreferenceToggle(content, "notify.replies", "repliesNotificationsLabel", "repliesNotificationsDesc", true);

        var systemSettings = new Button { Content = L10n.T("openSystemSettings", ns: "macos") };
        systemSettings.Click += async (_, _) =>
        {
            try
            {
                await Windows.System.Launcher.LaunchUriAsync(new Uri("ms-settings:notifications"));
            }
            catch (Exception exception)
            {
                ClientLogStore.Shared.RecordError("notifications.open_settings_failed", exception);
            }
        };
        content.Children.Add(systemSettings);
        return new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private void AddPreferenceToggle(
        StackPanel content,
        string settingKey,
        string labelKey,
        string descriptionKey,
        bool defaultValue
    )
    {
        content.Children.Add(CreatePreferenceToggle(settingKey, labelKey, defaultValue));
        content.Children.Add(new TextBlock
        {
            Text = L10n.T(descriptionKey, ns: "settings"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75,
            Margin = new Thickness(0, -4, 0, 8)
        });
    }

    private CheckBox CreatePreferenceToggle(string settingKey, string labelKey, bool defaultValue)
    {
        var toggle = new CheckBox
        {
            Content = L10n.T(labelKey, ns: "settings"),
            IsChecked = ReadPreference(settingKey, defaultValue)
        };
        toggle.Checked += (_, _) => SavePreference(settingKey, true);
        toggle.Unchecked += (_, _) => SavePreference(settingKey, false);
        return toggle;
    }

    private static bool ReadPreference(string settingKey, bool defaultValue)
    {
        try
        {
            var values = Windows.Storage.ApplicationData.Current.LocalSettings.Values;
            return values.TryGetValue(settingKey, out var value) && value is bool stored
                ? stored
                : defaultValue;
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.read_failed", exception);
            return defaultValue;
        }
    }

    private static void SavePreference(string settingKey, bool value)
    {
        try
        {
            Windows.Storage.ApplicationData.Current.LocalSettings.Values[settingKey] = value;
        }
        catch (Exception exception)
        {
            ClientLogStore.Shared.RecordError("preferences.save_failed", exception);
        }
    }

    private FrameworkElement BuildProfileSettings()
    {
        var ownUser = _session.OwnUser;
        string? avatarFileId = null;
        string? bannerFileId = null;
        var name = new TextBox
        {
            Header = L10n.T("usernameLabel", ns: "settings"),
            Text = ownUser?.Name ?? ""
        };
        var profileColor = new TextBox
        {
            Header = L10n.T("profileColorLabel", ns: "settings"),
            Text = ownUser?.ProfileColor ?? "#262626"
        };
        var bio = new TextBox
        {
            Header = L10n.T("bioLabel", ns: "settings"),
            Text = ownUser?.Bio ?? "",
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 100
        };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var avatarUpload = new Button { Content = L10n.T("changeImage", ns: "common") };
        avatarUpload.Click += async (_, _) =>
        {
            avatarUpload.IsEnabled = false;
            try
            {
                if (await PickAndUploadProfileImageAsync() is { } fileId)
                {
                    avatarFileId = fileId;
                }
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                avatarUpload.IsEnabled = true;
            }
        };
        var avatarRemove = new Button { Content = L10n.T("removeImage", ns: "common") };
        avatarRemove.Click += (_, _) => avatarFileId = "";
        var bannerUpload = new Button { Content = L10n.T("changeImage", ns: "common") };
        bannerUpload.Click += async (_, _) =>
        {
            bannerUpload.IsEnabled = false;
            try
            {
                if (await PickAndUploadProfileImageAsync() is { } fileId)
                {
                    bannerFileId = fileId;
                }
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                bannerUpload.IsEnabled = true;
            }
        };
        var bannerRemove = new Button { Content = L10n.T("removeImage", ns: "common") };
        bannerRemove.Click += (_, _) => bannerFileId = "";
        var save = new Button
        {
            Content = L10n.T("saveChanges", ns: "settings"),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        save.Click += async (_, _) =>
        {
            save.IsEnabled = false;
            try
            {
                await _session.CallMutationAsync("users.update", new JsonObject
                {
                    ["name"] = name.Text,
                    ["profileColor"] = profileColor.Text,
                    ["bio"] = bio.Text
                });
                if (avatarFileId is not null)
                {
                    await _session.CallMutationAsync("users.changeAvatar", ProfileImageInput(avatarFileId));
                }
                if (bannerFileId is not null)
                {
                    await _session.CallMutationAsync("users.changeBanner", ProfileImageInput(bannerFileId));
                }
                status.Text = L10n.T("profileUpdated", ns: "settings");
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                save.IsEnabled = true;
            }
        };

        var form = new StackPanel { Spacing = 12, Margin = new Thickness(20) };
        form.Children.Add(new TextBlock
        {
            Text = L10n.T("avatarLabel", ns: "settings"),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        form.Children.Add(avatarUpload);
        form.Children.Add(avatarRemove);
        form.Children.Add(new TextBlock
        {
            Text = L10n.T("bannerLabel", ns: "settings"),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        form.Children.Add(bannerUpload);
        form.Children.Add(bannerRemove);
        form.Children.Add(name);
        form.Children.Add(profileColor);
        form.Children.Add(bio);
        form.Children.Add(status);
        form.Children.Add(save);
        return new ScrollViewer { Content = form, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private async Task<string?> PickAndUploadProfileImageAsync()
    {
        var picker = new FileOpenPicker();
        foreach (var extension in new[] { ".png", ".jpg", ".jpeg", ".webp" })
        {
            picker.FileTypeFilter.Add(extension);
        }
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync();
        if (file is null)
        {
            return null;
        }

        return await _session.UploadAttachmentAsync(
            await File.ReadAllBytesAsync(file.Path),
            file.Name,
            file.ContentType
        );
    }

    private static JsonObject ProfileImageInput(string fileId)
    {
        var input = new JsonObject();
        if (!string.IsNullOrEmpty(fileId))
        {
            input["fileId"] = fileId;
        }

        return input;
    }

    private FrameworkElement BuildPasswordSettings()
    {
        var current = new PasswordBox { Header = L10n.T("currentPasswordLabel", ns: "settings") };
        var next = new PasswordBox { Header = L10n.T("newPasswordLabel", ns: "settings") };
        var confirm = new PasswordBox { Header = L10n.T("confirmNewPasswordLabel", ns: "settings") };
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var save = new Button
        {
            Content = L10n.T("saveChanges", ns: "settings"),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        save.Click += async (_, _) =>
        {
            save.IsEnabled = false;
            try
            {
                await _session.CallMutationAsync("users.updatePassword", new JsonObject
                {
                    ["currentPassword"] = current.Password,
                    ["newPassword"] = next.Password,
                    ["confirmNewPassword"] = confirm.Password
                });
                current.Password = "";
                next.Password = "";
                confirm.Password = "";
                status.Text = L10n.T("passwordUpdated", ns: "settings");
            }
            catch (Exception exception)
            {
                status.Text = exception.Message;
            }
            finally
            {
                save.IsEnabled = true;
            }
        };

        var form = new StackPanel { Spacing = 12, Margin = new Thickness(20) };
        form.Children.Add(current);
        form.Children.Add(next);
        form.Children.Add(confirm);
        form.Children.Add(status);
        form.Children.Add(save);
        return form;
    }

    private StackPanel BuildNoiseSuppressionSettings()
    {
        var title = new TextBlock
        {
            Text = L10n.T("noiseSuppressionLabel", ns: "settings"),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        };
        var description = new TextBlock
        {
            Text = L10n.T("noiseSuppressionMixDescription", ns: "settings"),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.7
        };
        var value = new TextBlock
        {
            Text = $"{_noiseSuppressionMix:0}%",
            HorizontalAlignment = HorizontalAlignment.Right
        };
        var slider = new Slider
        {
            Minimum = 0,
            Maximum = 100,
            StepFrequency = 1,
            Value = _noiseSuppressionMix,
            IsThumbToolTipEnabled = true
        };
        slider.ValueChanged += async (_, args) =>
        {
            _noiseSuppressionMix = Math.Clamp(args.NewValue, 0, 100);
            value.Text = $"{_noiseSuppressionMix:0}%";
            try
            {
                Windows.Storage.ApplicationData.Current.LocalSettings.Values["voice.noiseSuppressionMix"] =
                    _noiseSuppressionMix;
            }
            catch (Exception exception)
            {
                ClientLogStore.Shared.RecordError("preferences.noise_suppression.save_failed", exception);
            }
            if (_voiceWorkerReady)
            {
                var script = $"window.coveVoice?.setNoiseSuppressionMix({JsonSerializer.Serialize(_noiseSuppressionMix / 100)})";
                try
                {
                    await VoiceMediaWebView.ExecuteScriptAsync(script);
                }
                catch (Exception exception)
                {
                    ClientLogStore.Shared.RecordError("voice.noise_suppression.apply_failed", exception);
                }
            }
        };

        var content = new StackPanel { Spacing = 10, Margin = new Thickness(20) };
        content.Children.Add(title);
        content.Children.Add(description);
        content.Children.Add(slider);
        content.Children.Add(value);
        return content;
    }

}
