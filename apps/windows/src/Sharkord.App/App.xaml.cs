using Microsoft.UI.Xaml;
using Sharkord.Core;

namespace Sharkord.App;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, args) =>
            ClientLogStore.Shared.RecordError("app.unhandled_exception", args.Exception);
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        ClientLogStore.Shared.RecordInfo("app.launched", $"windows.{Environment.OSVersion.Version.Major}");
        _window = new MainWindow(new SharkordSession());
        _window.Activate();
    }
}
