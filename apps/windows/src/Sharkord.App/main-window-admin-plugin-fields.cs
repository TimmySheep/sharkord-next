using System.Globalization;
using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Sharkord.Core;
using Sharkord.Core.I18n;

namespace Sharkord.App;

public sealed partial class MainWindow
{
    private FrameworkElement CreatePluginField(JsonNode definition, JsonNode? value, out Func<JsonNode?> read, bool setting = false, bool secretSet = false)
    {
        var name = definition["name"]?.AsString() ?? definition["key"]?.AsString() ?? "";
        var wireType = definition["type"]?.AsString() ?? "string";
        var type = definition["sensitive"]?.AsBool() == true && wireType != "boolean" ? "secret" : wireType;
        var required = definition["required"]?.AsBool() == true;
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock { Text = name, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        if (definition["description"]?.AsString() is { } description) { panel.Children.Add(new TextBlock { Text = description, TextWrapping = TextWrapping.Wrap, Opacity = .8 }); }
        Func<JsonNode?> getter;
        if (type == "boolean")
        {
            var check = new CheckBox { IsChecked = value?.AsBool() ?? definition["defaultValue"]?.AsBool() ?? false };
            panel.Children.Add(check);
            getter = () => JsonValue.Create(check.IsChecked == true);
        }
        else if (type == "number")
        {
            var number = new NumberBox { Value = double.NaN, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact };
            var initial = value ?? definition["defaultValue"];
            if (initial is not null && double.TryParse(initial.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var numeric)) { number.Value = numeric; }
            panel.Children.Add(number);
            getter = () => PluginFormValue.Parse(type, double.IsNaN(number.Value) ? "" : number.Value.ToString(CultureInfo.InvariantCulture), required: required || setting);
        }
        else if (type == "enum")
        {
            var select = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch, SelectedValuePath = "Tag" };
            foreach (var option in definition["options"] as JsonArray ?? [])
            {
                select.Items.Add(new ComboBoxItem { Content = option?["label"]?.AsString() ?? option?["value"]?.AsString() ?? "", Tag = option?["value"]?.AsString() ?? "" });
            }
            select.SelectedValue = value?.AsString() ?? definition["defaultValue"]?.AsString();
            panel.Children.Add(select);
            getter = () => PluginFormValue.Parse("string", select.SelectedValue as string ?? "", required: true);
        }
        else if (type == "secret")
        {
            var password = new PasswordBox { PlaceholderText = L10n.T(secretSet ? "secretSetPlaceholder" : "secretUnsetPlaceholder", ns: "settings") };
            panel.Children.Add(password);
            var clear = new CheckBox { Content = L10n.T("clearSecret", ns: "admin") };
            if (setting) { panel.Children.Add(clear); }
            getter = () => clear.IsChecked == true ? JsonValue.Create("") : PluginFormValue.Parse(wireType, password.Password, required: required);
        }
        else
        {
            var text = new TextBox { Text = value?.AsString() ?? definition["defaultValue"]?.AsString() ?? "", TextWrapping = TextWrapping.Wrap, AcceptsReturn = setting };
            panel.Children.Add(text);
            getter = () => setting ? JsonValue.Create(text.Text) : PluginFormValue.Parse(type, text.Text, required: required);
        }
        read = () =>
        {
            try { return getter(); }
            catch (FormatException) { throw new ArgumentException(L10n.T("invalidField", ns: "admin", ("name", name))); }
        };
        return panel;
    }

    private async Task<FrameworkElement> BuildPluginFieldsAsync(string pluginId)
    {
        var response = await _session.CallQueryAsync("plugins.getSettings", new JsonObject { ["pluginId"] = pluginId });
        var definitions = response?["definitions"] as JsonArray ?? [];
        var values = response?["values"] as JsonObject ?? [];
        var secrets = (response?["secretsSet"] as JsonArray ?? []).Select(node => node?.AsString()).OfType<string>().ToHashSet();
        var secretKeys = definitions.Where(definition => definition?["type"]?.AsString() == "secret").Select(definition => definition?["key"]?.AsString()).OfType<string>().ToHashSet();
        var panel = new StackPanel { Spacing = 12, Margin = new Thickness(12) };
        var readers = new Dictionary<string, Func<JsonNode?>>();
        foreach (var definition in definitions.OfType<JsonObject>())
        {
            var key = definition["key"]?.AsString() ?? "";
            panel.Children.Add(CreatePluginField(definition, values[key], out var read, setting: true, secretSet: secrets.Contains(key)));
            readers[key] = read;
        }
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var save = new Button { Content = L10n.T("saveChanges") };
        save.Click += async (_, _) =>
        {
            save.IsEnabled = false;
            try
            {
                var changes = readers.Select(pair => (Key: pair.Key, Value: pair.Value())).Where(pair => pair.Value is not null && !JsonNode.DeepEquals(pair.Value, values[pair.Key])).ToArray();
                foreach (var change in changes)
                {
                    await _session.CallMutationAsync("plugins.updateSetting", new JsonObject { ["pluginId"] = pluginId, ["key"] = change.Key, ["value"] = change.Value });
                    if (!secretKeys.Contains(change.Key)) { values[change.Key] = change.Value!.DeepClone(); }
                }
                status.Text = L10n.T("pluginSettingsSaved", ns: "settings");
            }
            catch (Exception exception) { status.Text = exception.Message; }
            finally { save.IsEnabled = true; }
        };
        panel.Children.Add(save); panel.Children.Add(status);
        return new ScrollViewer { Content = panel };
    }

}
