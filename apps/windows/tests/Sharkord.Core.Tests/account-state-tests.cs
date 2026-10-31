using System.Reflection;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public sealed class AccountStateTests
{
    [Fact]
    public void CredentialTargetsNormalizeServerPathsWithoutContainingIdentityOrPassword()
    {
        Assert.Equal(WindowsCredentialStore.Target("https://example.com/"), WindowsCredentialStore.Target("https://example.com"));
        Assert.NotEqual(WindowsCredentialStore.Target("https://example.com"), WindowsCredentialStore.Target("https://another.invalid"));
        Assert.DoesNotContain("example.com", WindowsCredentialStore.Target("https://example.com"));
    }

    [Fact]
    public async Task WelcomeProfileFollowsJoinAndCanBeDismissedWithoutChangingServerData()
    {
        await using var session = new SharkordSession();
        var apply = typeof(SharkordSession).GetMethod("Apply", BindingFlags.Instance | BindingFlags.NonPublic)!;
        apply.Invoke(session, [new JoinResult { ShowWelcomeDialog = true }]);
        Assert.True(session.ShouldShowWelcomeProfile);
        session.DismissWelcomeProfile();
        Assert.False(session.ShouldShowWelcomeProfile);
        apply.Invoke(session, [new JoinResult { ShowWelcomeDialog = false }]);
        Assert.False(session.ShouldShowWelcomeProfile);
    }

    [Fact]
    public void CredentialInteropLayoutAndDiagnosticFormattingKeepSecretsOutOfText()
    {
        var credential = typeof(WindowsCredentialStore).GetNestedType("Credential", BindingFlags.NonPublic)!;
        Assert.Equal(IntPtr.Size == 8 ? 80 : 52, System.Runtime.InteropServices.Marshal.SizeOf(credential));
        var stored = new SavedCredential("test identity", "test-only secret");
        Assert.DoesNotContain("test-only secret", stored.ToString()!);
    }
}
