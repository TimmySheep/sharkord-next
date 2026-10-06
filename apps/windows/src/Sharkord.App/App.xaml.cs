using Microsoft.UI.Xaml;
using Sharkord.Core;

namespace Sharkord.App;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow(new SharkordSession());
        _window.Activate();
    }
}
