using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;
using Sharkord.Core.I18n;
using Xunit;

namespace Sharkord.Core.Tests;

/// <summary>
/// guards the localisation tables and, more importantly, that the WinUI shell actually uses
/// them. These Core tests run cross-platform; the WinUI runtime is not loaded by the test
/// host, so source-contract checks do not replace a visual launch test.
///
/// Every test here mutates process-wide state in <see cref="L10n"/>, so they stay in a
/// single class on purpose: xunit runs the members of one class sequentially but runs
/// classes in parallel.
/// </summary>
public class L10nTests
{
    private static readonly string[] WindowsKeys =
    [
        "pushToTalkTitle",
        "pushToTalkDescription",
        "pushToTalkReady",
        "pushToTalkUnavailable",
        "tagline",
        "serverAddress",
        "serverPassword",
        "inviteCode",
        "messagePlaceholder",
        "send",
        "systemUser",
        "languageLabel",
        "systemLanguage",
        "addReaction",
        "directMessages",
        "textChannels",
        "voiceChannels",
        "joinVoice",
        "leaveVoice",
        "muteMic",
        "unmuteMic",
        "deafen",
        "undeafen",
        "webcam",
        "voiceConnecting",
        "voiceNoPermission",
        "shareScreen",
        "stopScreenShare",
        "mediaLocalUser",
        "mediaScreen",
        "mediaCamera",
        "exportLogs",
        "logFileType",
        "logsExportSuccessTitle",
        "logsExportSuccessMessage",
        "logsExportFailureTitle",
        "logsExportFailureMessage",
        "close",
        "typingUsers",
        "unreadMessages",
        "newMessages",
        "attachFiles",
        "messageActions",
        "online",
        "offline",
        "attachmentLimit",
        "attachmentSizeLimit",
        "removeAttachment"
    ];

    private static readonly string[] KeyboardShortcutMacKeys =
    [
        "keyboardShortcutsDescription",
        "keyboardShortcutSendTitle",
        "keyboardShortcutSendDescription",
        "keyboardShortcutSendUnsetDescription",
        "keyboardShortcutMuteMicrophoneTitle",
        "keyboardShortcutMuteMicrophoneDescription",
        "keyboardShortcutUnmuteMicrophoneTitle",
        "keyboardShortcutUnmuteMicrophoneDescription",
        "keyboardShortcutMuteVoiceAudioTitle",
        "keyboardShortcutMuteVoiceAudioDescription",
        "keyboardShortcutUnmuteVoiceAudioTitle",
        "keyboardShortcutUnmuteVoiceAudioDescription",
        "keyboardShortcutPress",
        "keyboardShortcutNotSet",
        "keyboardShortcutClear",
        "keyboardShortcutCaptureHint",
        "keyboardShortcutConflict",
        "keyboardShortcutModifierRequired",
        "keyboardShortcutReturnReserved",
        "keyboardShortcutReservedForPushToTalk"
    ];

    public static IEnumerable<object[]> Languages =>
        L10n.SupportedLanguages.Select(language => new object[] { language.Code });

    public L10nTests()
    {
        L10n.ResetStringsCache();
        L10n.UseSystemLanguage();
        L10n.Language = "en";
    }

    [Fact]
    public void ShipsTheLanguagesTheClientsAgreeOn()
    {
        Assert.Equal(
            ["en", "de", "es", "fr", "it", "cs", "ru", "zh", "zh-Hant", "pt-BR"],
            L10n.SupportedLanguages.Select(language => language.Code).ToArray()
        );

        // the two chinese tables have to stay tellable apart in a future language picker
        Assert.Equal("简体中文", L10n.SupportedLanguages.Single(language => language.Code == "zh").NativeName);
        Assert.Equal("繁體中文", L10n.SupportedLanguages.Single(language => language.Code == "zh-Hant").NativeName);
    }

    [Theory]
    [MemberData(nameof(Languages))]
    public void EveryLanguageTranslatesEveryWindowsString(string language)
    {
        L10n.Language = language;

        foreach (var key in WindowsKeys)
        {
            var value = L10n.T(key, ns: "windows");

            Assert.NotEqual(key, value);
            Assert.False(string.IsNullOrWhiteSpace(value));
        }
    }

    [Theory]
    [MemberData(nameof(Languages))]
    public void EveryLanguageTranslatesEveryWindowsKeyboardShortcutString(string language)
    {
        L10n.Language = language;

        foreach (var key in KeyboardShortcutMacKeys)
        {
            var value = L10n.T(key, ns: "macos");

            Assert.NotEqual(key, value);
            Assert.False(string.IsNullOrWhiteSpace(value));
        }
    }

    [Theory]
    [MemberData(nameof(Languages))]
    public void EveryLanguageCarriesTheSameKeys(string language)
    {
        Assert.Equal(L10n.Keys("en", "windows").Order().ToArray(), L10n.Keys(language, "windows").Order().ToArray());
    }

    [Theory]
    [InlineData("de", "serverPassword", "Serverpasswort (optional)")]
    [InlineData("zh", "serverPassword", "服务器密码（可选）")]
    [InlineData("zh-Hant", "serverPassword", "伺服器密碼（選填）")]
    [InlineData("fr", "messagePlaceholder", "Message")]
    [InlineData("it", "send", "Invia")]
    [InlineData("ru", "systemUser", "Система")]
    [InlineData("zh-Hant", "systemLanguage", "跟隨系統")]
    [InlineData("de", "addReaction", "Reaktion hinzufügen")]
    public void TranslatesPerLanguage(string language, string key, string expected)
    {
        L10n.Language = language;

        Assert.Equal(expected, L10n.T(key, ns: "windows"));
    }

    [Fact]
    public void ReusesTheSharedConnectLabelsInsteadOfCopyingThem()
    {
        // identityLabel / passwordLabel / connectBtn name the same fields the web client
        // shows on its connect screen, so they are read from the shared namespace rather
        // than duplicated into windows.json where they would drift
        Assert.Equal("Identity", L10n.T("identityLabel", ns: "connect"));
        Assert.Equal("Password", L10n.T("passwordLabel", ns: "connect"));
        Assert.Equal("Connect", L10n.T("connectBtn", ns: "connect"));
    }

    [Fact]
    public void InterpolatesPlaceholders()
    {
        Assert.Equal("Invite code: ABC123", L10n.T("inviteCode", "connect", ("code", "ABC123")));

        // and the placeholder survives translation in every table, not just the english one
        foreach (var (language, _) in L10n.SupportedLanguages)
        {
            L10n.Language = language;
            var value = L10n.T("inviteCode", "connect", ("code", "ABC123"));

            Assert.Contains("ABC123", value);
            Assert.DoesNotContain("{{code}}", value);
        }
    }

    [Fact]
    public void FallsBackToEnglishWhileALanguageIsBehind()
    {
        // translations land after the english strings, so a language is briefly incomplete.
        // the seam reproduces that state instead of shipping a locale that is incomplete on
        // purpose, which is what this would otherwise need as a fixture.
        L10n.OverrideStrings("de", "windows", new Dictionary<string, string> { ["tagline"] = "Nativer Windows-Client" });
        L10n.Language = "de";

        Assert.Equal("Nativer Windows-Client", L10n.T("tagline", ns: "windows"));
        Assert.Equal("Send", L10n.T("send", ns: "windows"));
    }

    [Fact]
    public void ReturnsTheKeyWhenNothingHasIt()
    {
        L10n.Language = "de";

        Assert.Equal("thisKeyDoesNotExist", L10n.T("thisKeyDoesNotExist"));
        Assert.Equal("missing.nested", L10n.T("missing.nested", ns: "settings"));
    }

    [Fact]
    public void AddressesNestedSourceObjectsWithDottedKeys()
    {
        // connect.json groups its oidc failures under one object; the lookup flattens that
        // so callers never have to know which files group and which do not
        Assert.NotEqual("oidcError.expired", L10n.T("oidcError.expired", ns: "connect"));
    }

    [Fact]
    public void IgnoresUnsupportedLanguageCodes()
    {
        L10n.Language = "kl";

        Assert.Equal("en", L10n.Language);
    }

    [Fact]
    public void RaisesLanguageChangedOnlyForRealChanges()
    {
        var raised = 0;
        void Handler() => raised++;

        L10n.LanguageChanged += Handler;

        try
        {
            L10n.Language = "de";
            L10n.Language = "de";
            L10n.Language = "kl";

            Assert.Equal(1, raised);
        }
        finally
        {
            L10n.LanguageChanged -= Handler;
        }
    }

    [Fact]
    public void CanPinTheSystemLanguageAsAnExplicitPreference()
    {
        var originalCulture = CultureInfo.CurrentUICulture;

        try
        {
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("en-US");
            L10n.UseSystemLanguage();
            L10n.Language = "en";
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("de-DE");

            Assert.Equal("en", L10n.Language);
        }
        finally
        {
            CultureInfo.CurrentUICulture = originalCulture;
            L10n.UseSystemLanguage();
        }
    }

    [Fact]
    public void EveryStringTheWindowUsesResolves()
    {
        foreach (var (key, ns) in WindowCallSites())
        {
            Assert.True(
                L10n.T(key, ns: ns) != key,
                $"{ns}.{key} is used by the window but no table defines it"
            );
        }
    }

    [Fact]
    public void WindowXamlCarriesNoHardcodedText()
    {
        // a new control that hardcodes english is invisible until someone runs the app in
        // another language, which only happens on a Windows machine
        var xaml = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml"));
        var allowed = new[] { "cove", "localhost:4991" };

        Assert.Contains("x:Name=\"LanguageBox\"", xaml);
        Assert.Contains("SelectionChanged=\"OnLanguageSelectionChanged\"", xaml);

        foreach (Match match in Regex.Matches(xaml, "(?:Text|Header|Content|PlaceholderText|Title)=\"([^\"]+)\""))
        {
            // a value starting with '{' is a markup extension like {Binding}, not prose
            if (match.Groups[1].Value.StartsWith('{'))
            {
                continue;
            }

            Assert.Contains(match.Groups[1].Value, allowed);
        }
    }

    [Fact]
    public void WinUiMessageTemplateWiresReactionDisplayAndActions()
    {
        var xaml = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml"));
        var code = File.ReadAllText(SourceFile("Sharkord.App/main-window-reactions.cs"));

        Assert.Contains("ItemsSource=\"{Binding Reactions}\"", xaml);
        Assert.Contains("Click=\"OnReactionClick\"", xaml);
        Assert.Contains("Click=\"OnAddReactionClick\"", xaml);
        Assert.Contains(".ReactionGroups(message)", code);
        Assert.Contains("_session.ToggleReactionAsync", code);
    }

    [Fact]
    public void WinUiConnectScreenUsesDarkServerBrandingAndKeepsAppearanceScoped()
    {
        var xaml = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml"));
        var code = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml.cs"));

        Assert.Contains("x:Name=\"ConnectScreen\"", xaml);
        Assert.Contains("RequestedTheme=\"Dark\"", xaml);
        Assert.Contains("TextChanged=\"OnHostTextChanged\"", xaml);
        Assert.Contains("ImageFailed=\"OnServerLogoFailed\"", xaml);
        Assert.Contains("x:Name=\"LoginLanguageBox\"", xaml);
        Assert.Contains("x:Name=\"LoginExportLogsButton\"", xaml);
        Assert.Contains("new SharkordHttpClient(baseUrl, _serverPreviewHttpClient)", code);
        Assert.Contains("client.GetInfoAsync(cancellation.Token)", code);
        Assert.Contains("ConnectScreen.Visibility = isConnected ? Visibility.Collapsed : Visibility.Visible;", code);
        Assert.Contains("TopActionsPanel.Visibility = isConnected ? Visibility.Visible : Visibility.Collapsed;", code);
        Assert.Contains("foreach (var languageBox in new[] { LanguageBox, LoginLanguageBox })", code);
    }

    [Fact]
    public void WinUiUsesCoveBrandingAndIcon()
    {
        var xaml = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml"));
        var code = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml.cs"));
        var project = File.ReadAllText(SourceFile("Sharkord.App/Sharkord.App.csproj"));
        var iconPath = SourceFile("Sharkord.App/Assets/cove.ico");
        var darkIconPath = SourceFile("Sharkord.App/Assets/cove-dark.ico");

        Assert.Contains("Title=\"cove\"", xaml);
        Assert.Contains("x:Name=\"RootGrid\"", xaml);
        Assert.Contains("RootGrid.ActualThemeChanged += OnRootThemeChanged;", code);
        Assert.Contains("RootGrid.ActualTheme == ElementTheme.Dark ? \"cove-dark.ico\" : \"cove.ico\"", code);
        Assert.Contains("<AssemblyName>cove</AssemblyName>", project);
        Assert.Contains("<AssemblyTitle>cove</AssemblyTitle>", project);
        Assert.Contains("<Product>cove</Product>", project);
        Assert.Contains("<ApplicationIcon>Assets\\cove.ico</ApplicationIcon>", project);
        Assert.Contains("<Content Include=\"Assets\\cove-dark.ico\">", project);
        Assert.Contains("<CopyToPublishDirectory>PreserveNewest</CopyToPublishDirectory>", project);
        Assert.Contains("<ExcludeFromSingleFile>true</ExcludeFromSingleFile>", project);
        Assert.Contains("Name=\"CopyCoveIconToPublishDirectory\" AfterTargets=\"Publish\"", project);
        Assert.Contains("SourceFiles=\"$(MSBuildProjectDirectory)\\Assets\\cove-dark.ico\"", project);
        Assert.True(File.Exists(iconPath));
        Assert.True(File.Exists(darkIconPath));
    }

    [Fact]
    public void WinUiExposesDiagnosticLogExport()
    {
        var xaml = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml"));
        var code = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml.cs"));

        Assert.Contains("x:Name=\"ExportLogsButton\"", xaml);
        Assert.Contains("Click=\"OnExportLogsClick\"", xaml);
        Assert.Contains("FileSavePicker", code);
        Assert.Contains("ClientLogStore.Shared.ExportLogsAsync", code);
    }

    [Fact]
    public void WinUiExposesPersistentContinuousNoiseSuppressionControl()
    {
        var xaml = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml"));
        var code = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Settings.Local.cs"));
        var project = File.ReadAllText(SourceFile("Sharkord.Core/Sharkord.Core.csproj"));

        Assert.Contains("x:Name=\"SettingsButton\" Click=\"OnSettingsClick\"", xaml);
        Assert.Contains("Minimum = 0", code);
        Assert.Contains("Maximum = 100", code);
        Assert.Contains("voice.noiseSuppressionMix", code);
        Assert.Contains("setNoiseSuppressionMix", code);
        Assert.Contains("macos/Resources/locales/**/*.json", project);
        Assert.Equal("Noise Suppression", L10n.T("noiseSuppressionLabel", ns: "settings"));
    }

    [Fact]
    public void WinUiServerSettingsArePermissionGatedAndDoNotClearAnUnchangedPassword()
    {
        var code = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Settings.Navigation.cs"));
        var serverSettings = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Settings.Server.cs"));
        var session = File.ReadAllText(SourceFile("Sharkord.Core/SharkordSession.cs"));

        Assert.Contains("_session.HasPermission(\"MANAGE_SETTINGS\")", code);
        Assert.Contains("_session.HasPermission(\"MANAGE_STORAGE\")", code);
        Assert.Contains("_session.HasPermission(\"MANAGE_USERS\")", code);
        Assert.Contains("_session.HasPermission(\"MANAGE_INVITES\")", code);
        Assert.Contains("_session.HasPermission(\"MANAGE_ROLES\")", code);
        Assert.Contains("_session.HasPermission(\"MANAGE_EMOJIS\")", code);
        Assert.Contains("_session.HasPermission(\"MANAGE_PLUGINS\")", code);
        Assert.Contains("_session.HasPermission(\"MANAGE_UPDATES\")", code);
        Assert.Contains("BuildGeneralServerSettingsAsync", code);
        Assert.Contains("if (!string.IsNullOrEmpty(password.Password))", serverSettings);
        Assert.Contains("GetAdminSettingsAsync", session);
        Assert.Contains("UpdateAdminSettingsAsync", session);
        Assert.Contains("CallQueryAsync(\"others.getSettings\"", session);
        Assert.Contains("CallMutationAsync(\"others.updateSettings\"", session);
    }

    [Fact]
    public void WinUiAccountAndStorageSettingsUseTheExistingTrpcProcedures()
    {
        var localSettings = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Settings.Local.cs"));
        var serverSettings = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Settings.Server.cs"));
        var managementSettings = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Settings.Management.cs"));
        var session = File.ReadAllText(SourceFile("Sharkord.Core/SharkordSession.cs"));

        Assert.Contains("CallMutationAsync(\"users.update\"", localSettings);
        Assert.Contains("CallMutationAsync(\"users.updatePassword\"", localSettings);
        Assert.Contains("users.changeAvatar", localSettings);
        Assert.Contains("users.changeBanner", localSettings);
        Assert.DoesNotContain("app.appearance", localSettings);
        Assert.Contains("RootGrid.RequestedTheme = ElementTheme.Dark;", File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml.cs")));
        Assert.Contains("RequestedTheme=\"Dark\"", File.ReadAllText(SourceFile("Sharkord.App/App.xaml")));
        Assert.Contains("notify.allMessages", localSettings);
        Assert.Contains("notify.mentionsOnly", localSettings);
        Assert.Contains("app.autoJoinLastChannel", localSettings);
        Assert.Contains("DesktopNotificationPolicy.ShouldNotify", File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Notifications.cs")));
        Assert.Contains("CallQueryAsync(\"others.getStorageSettings\"", serverSettings);
        Assert.Contains("CallQueryAsync(\"users.getAll\"", managementSettings);
        Assert.Contains("CallQueryAsync(\"invites.getAll\"", managementSettings);
        Assert.Contains("users.ban", managementSettings);
        Assert.Contains("users.delete", managementSettings);
        Assert.Contains("invites.add", managementSettings);
        Assert.Contains("invites.delete", managementSettings);
        Assert.Contains("storageImageOptimizationEnabled", serverSettings);
        Assert.Contains("CallQueryAsync(\n        string path", session.ReplaceLineEndings("\n"));
        Assert.Contains("CallMutationAsync(\n        string path", session.ReplaceLineEndings("\n"));
    }

    [Fact]
    public void WinUiServerManagementSettingsUsePermissionCheckedProcedures()
    {
        var management = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Settings.Management.cs"));
        var integrations = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.Settings.Integrations.cs"));

        Assert.Contains("roles.getAll", management);
        Assert.Contains("roles.update", management);
        Assert.Contains("emojis.getAll", management);
        Assert.Contains("emojis.add", management);
        Assert.Contains("emojis.update", management);
        Assert.Contains("emojis.delete", management);
        Assert.Contains("plugins.get", integrations);
        Assert.Contains("plugins.toggle", integrations);
        Assert.Contains("others.getUpdate", integrations);
        Assert.Contains("others.updateServer", integrations);
    }

    [Fact]
    public void WindowsConnectScreenKeepsOptionalCredentialsInAdvancedOptions()
    {
        var xaml = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml"));

        Assert.Contains("x:Name=\"AdvancedOptionsExpander\"", xaml);
        Assert.Contains("x:Name=\"ServerPasswordBox\"", xaml);
        Assert.Contains("x:Name=\"InviteBox\"", xaml);
        Assert.Contains("x:Name=\"ConnectButton\"", xaml);
        Assert.Contains("x:Name=\"ConnectError\"", xaml);
    }

    [Fact]
    public void WindowsPersistsShortcutsAndLastChannelPerServerAndUsesGlobalPushToTalk()
    {
        var shortcuts = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.KeyboardShortcuts.cs"));
        var pttHook = File.ReadAllText(SourceFile("Sharkord.App/GlobalPushToTalkHook.cs"));
        var channelPreferences = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.ChannelPreferences.cs"));
        var channelKey = File.ReadAllText(SourceFile("Sharkord.Core/LastChannelPreference.cs"));
        var xaml = File.ReadAllText(SourceFile("Sharkord.App/MainWindow.xaml"));

        Assert.Contains("keyboard.shortcuts", shortcuts);
        Assert.Contains("SaveKeyboardShortcutPreferences", shortcuts);
        Assert.Contains("SetWindowsHookEx", pttHook);
        Assert.Contains("F13VirtualKey", pttHook);
        Assert.Contains("app.autoJoinLastChannel", channelPreferences);
        Assert.Contains("LastChannelPreference.SettingKey", channelPreferences);
        Assert.Contains("SHA256.HashData", channelKey);
        Assert.Contains("AcceptsReturn=\"True\"", xaml);
    }

    /// <summary>
    /// reads the call sites out of the window source the same way the macOS parity test
    /// does. a key renamed in the tables but not here would otherwise only surface as raw
    /// text at runtime.
    /// </summary>
    private static IEnumerable<(string Key, string Ns)> WindowCallSites()
    {
        var directory = Path.GetDirectoryName(SourceFile("Sharkord.App/MainWindow.xaml.cs"))!;
        var pattern = new Regex("L10n\\.T\\(\"([^\"]+)\"(?:\\s*,\\s*ns:\\s*\"([^\"]+)\")?");

        foreach (var file in Directory.EnumerateFiles(directory, "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                || file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            {
                continue;
            }

            foreach (Match match in pattern.Matches(File.ReadAllText(file)))
            {
                yield return (match.Groups[1].Value, match.Groups[2].Success ? match.Groups[2].Value : "common");
            }
        }
    }

    /// <summary>resolves a path inside the app project relative to this test file's own path.</summary>
    private static string SourceFile(string relative, [CallerFilePath] string thisFile = "")
    {
        var windowsRoot = Directory.GetParent(thisFile)!.Parent!.Parent!.FullName;

        return Path.Combine(windowsRoot, "src", relative);
    }
}
