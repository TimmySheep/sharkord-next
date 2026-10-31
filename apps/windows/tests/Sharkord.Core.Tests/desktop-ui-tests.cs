using System.Runtime.CompilerServices;
using Xunit;

namespace Sharkord.Core.Tests;

public class DesktopUiTests
{
    [Fact]
    public void DiscordWorkspaceKeepsNativeVirtualizationAndAccessibleMessageActions()
    {
        var xaml = File.ReadAllText(Source("MainWindow.xaml"));
        Assert.Contains("#313338", xaml);
        Assert.Contains("#2B2D31", xaml);
        Assert.Contains("#1E1F22", xaml);
        Assert.Contains("#5865F2", xaml);
        Assert.Contains("<ListView x:Name=\"MessageList\"", xaml);
        Assert.Contains("<ItemsStackPanel", xaml);
        Assert.Contains("Click=\"OnEditMessageClick\"", xaml);
        Assert.Contains("Click=\"OnMessageMoreClick\"", xaml);
        Assert.Contains("Click=\"OnAttachClick\"", xaml);
        Assert.Contains("Click=\"OnComposerEmojiClick\"", xaml);
        Assert.Contains("x:Name=\"MemberPanel\"", xaml);
        Assert.Contains("x:Name=\"UserPanel\"", xaml);
        Assert.Contains("GotFocus=\"OnMessageGotFocus\"", xaml);
        Assert.Contains("ItemsUpdatingScrollMode=\"KeepItemsInView\"", xaml);
    }

    [Fact]
    public void ComposerUsesSessionOperationsAndKeepsKeyboardAndFailureRecovery()
    {
        var composer = File.ReadAllText(Source("main-window-composer.cs"));
        var shortcuts = File.ReadAllText(Source("MainWindow.KeyboardShortcuts.cs"));
        Assert.Contains("_session.UploadAttachmentAsync", composer);
        Assert.Contains("_session.SendMessageAsync(channelId, text, _replyToMessageId", composer);
        Assert.Contains("_session.EditMessageAsync", composer);
        Assert.Contains("_session.SignalTyping", composer);
        Assert.Contains("if (text != _originalEditText)", composer);
        Assert.Contains("_sendingComposer = false;", composer);
        Assert.Contains("Windows.System.VirtualKey.Escape", shortcuts);
        Assert.Contains("Windows.System.VirtualKey.Up", shortcuts);
        Assert.Contains("CancelComposerContext();", shortcuts);
        Assert.Contains("EditLastOwnMessage();", shortcuts);
    }

    private static string Source(string file, [CallerFilePath] string source = "") =>
        Path.GetFullPath(Path.Combine(Path.GetDirectoryName(source)!, "../../src/Sharkord.App", file));
}
