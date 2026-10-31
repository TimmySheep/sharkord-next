using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class EmojiPicker : UserControl
{
    private readonly List<EmojiChoice> _choices = [];
    private readonly List<string> _recents;
    public event Action<EmojiChoice>? Chosen;

    public EmojiPicker(SharkordSession session, bool reactions = false)
    {
        InitializeComponent();
        SearchBox.PlaceholderText = L10n.T("searchAllEmojis");
        KindBox.Items.Add(L10n.T("recentEmojis", ns: "windows"));
        KindBox.Items.Add(L10n.T("emojiTab"));
        KindBox.Items.Add(L10n.T("customTab"));
        _choices.AddRange(EmojiCatalog.All.Concat(EmojiCatalog.Tones).Where(emoji => !reactions || EmojiCatalog.ReactionShortcode(emoji) is not null).Select(emoji => new EmojiChoice(
            $"{emoji.Name} · {string.Join(", ", emoji.Shortcodes)}", reactions ? EmojiCatalog.ReactionShortcode(emoji)! : emoji.Shortcodes[0], emoji.Emoji, null, emoji.Shortcodes)));
        _choices.AddRange(session.Emojis.Where(emoji => emoji.File is not null && (!reactions || emoji.Name.Length <= 32)).Select(emoji => new EmojiChoice(
            emoji.Name, emoji.Name, "", session.PublicFileUrl(emoji.File!), [emoji.Name])));
        _recents = ReadRecents();
        KindBox.SelectedIndex = _recents.Count > 0 ? 0 : 1;
        Render();
    }

    private void OnSearchChanged(object sender, TextChangedEventArgs e) => Render();
    private void OnKindChanged(object sender, SelectionChangedEventArgs e) => Render();

    private void Render()
    {
        if (_recents is null || EmojiGrid is null) { return; }
        var needle = SearchBox.Text.Trim();
        IEnumerable<EmojiChoice> source = _choices;
        if (needle.Length > 0)
        {
            source = source.Where(emoji => emoji.Name.Contains(needle, StringComparison.CurrentCultureIgnoreCase) ||
                emoji.Aliases.Any(alias => alias.Contains(needle, StringComparison.OrdinalIgnoreCase)));
        }
        else if (KindBox.SelectedIndex == 0)
        {
            source = _recents.Select(code => _choices.FirstOrDefault(emoji => emoji.Shortcode == code)).OfType<EmojiChoice>();
        }
        else if (KindBox.SelectedIndex == 2) { source = source.Where(emoji => emoji.ImageUrl is not null); }
        else { source = source.Where(emoji => emoji.ImageUrl is null); }
        EmojiGrid.ItemsSource = source.ToArray();
    }

    private void OnEmojiClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not EmojiChoice emoji) { return; }
        _recents.Remove(emoji.Shortcode);
        _recents.Insert(0, emoji.Shortcode);
        if (_recents.Count > 32) { _recents.RemoveRange(32, _recents.Count - 32); }
        try { Directory.CreateDirectory(Path.GetDirectoryName(RecentsPath)!); File.WriteAllText(RecentsPath, JsonSerializer.Serialize(_recents)); }
        catch (Exception exception) { ClientLogStore.Shared.RecordError("emoji.recents.failed", exception); }
        Chosen?.Invoke(emoji);
    }

    private static string RecentsPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sharkord", "emoji-recents.json");
    private static List<string> ReadRecents()
    {
        try { return JsonSerializer.Deserialize<List<string>>(File.ReadAllText(RecentsPath))?.Take(32).ToList() ?? []; }
        catch { return []; }
    }
}

[Microsoft.UI.Xaml.Data.Bindable]
public sealed class EmojiChoice(string name, string shortcode, string glyph, Uri? imageUrl, string[] aliases)
{
    public string Name { get; } = name;
    public string Shortcode { get; } = shortcode;
    public string Glyph { get; } = glyph;
    public Uri? ImageUrl { get; } = imageUrl;
    public string[] Aliases { get; } = aliases;
    public BitmapImage? Image => ImageUrl is null ? null : new BitmapImage(ImageUrl);
    public Visibility ImageVisibility => ImageUrl is null ? Visibility.Collapsed : Visibility.Visible;
    public Visibility GlyphVisibility => ImageUrl is null ? Visibility.Visible : Visibility.Collapsed;
}
