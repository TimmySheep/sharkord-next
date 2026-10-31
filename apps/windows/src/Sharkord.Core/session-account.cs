namespace Sharkord.Core;

public sealed partial class SharkordSession
{
    public bool ShouldShowWelcomeProfile { get; private set; }
    public async Task RefreshServerInfoAsync(CancellationToken cancellationToken = default)
    {
        var http = _http ?? throw new InvalidOperationException("Not connected");
        ServerInfo = await http.GetInfoAsync(cancellationToken).ConfigureAwait(false);
        Notify();
    }

    public void DismissWelcomeProfile() => ShouldShowWelcomeProfile = false;
}
