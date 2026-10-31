namespace Sharkord.Core;

public sealed partial class SharkordSession
{
    public bool ShouldShowWelcomeProfile { get; private set; }
    public void DismissWelcomeProfile() => ShouldShowWelcomeProfile = false;
}
