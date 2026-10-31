using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Sharkord.Core.I18n;
using Xunit;

namespace Sharkord.Core.Tests;

public sealed class AdminLocaleTests
{
    [Fact]
    public void NewAccountAndAdminTablesHaveMatchingKeysAndPlaceholdersInAllTenLanguages()
    {
        foreach (var table in new[] { "account", "admin" })
        {
            var english = Read("en", table);
            foreach (var (language, _) in L10n.SupportedLanguages)
            {
                var localized = Read(language, table);
                Assert.Equal(english.Select(pair => pair.Key).Order(), localized.Select(pair => pair.Key).Order());
                foreach (var (key, value) in english)
                {
                    Assert.False(string.IsNullOrWhiteSpace(localized[key]?.GetValue<string>()));
                    Assert.Equal(Placeholders(value!.GetValue<string>()), Placeholders(localized[key]!.GetValue<string>()));
                }
            }
        }
    }

    private static string[] Placeholders(string value) => Regex.Matches(value, @"\{\{\w+\}\}").Select(match => match.Value).Order().ToArray();
    private static JsonObject Read(string language, string table, [CallerFilePath] string source = "") =>
        JsonNode.Parse(File.ReadAllText(Path.GetFullPath(Path.Combine(Path.GetDirectoryName(source)!, "../../src/Sharkord.Core/I18n/locales", language, $"{table}.json"))))!.AsObject();
}
