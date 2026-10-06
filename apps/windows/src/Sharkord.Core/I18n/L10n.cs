using System.Globalization;
using System.Reflection;
using System.Text.Json;

namespace Sharkord.Core.I18n;

/// <summary>
/// looks up UI strings in the flat <c>locales/&lt;lang&gt;/&lt;ns&gt;.json</c> tables embedded in this
/// assembly. the layout is the one the macOS client uses, so both native clients share one
/// translation set and one re-sync path from the web client.
///
/// this lives in Core rather than in the WinUI shell on purpose: Core is plain <c>net8.0</c>,
/// so the lookup and every locale table can be compiled and tested on macOS and Linux. The
/// WinUI project cannot build there at all.
/// </summary>
public static class L10n
{
    /// <summary>
    /// the languages the native clients ship. the code is the locale directory name, so it
    /// must match <c>Resources/locales/&lt;code&gt;</c> on the macOS side exactly.
    /// </summary>
    public static readonly IReadOnlyList<(string Code, string NativeName)> SupportedLanguages =
    [
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("cs", "Čeština"),
        ("ru", "Русский"),
        ("zh", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("pt-BR", "Português")
    ];

    public const string DefaultLanguage = "en";

    private static readonly Dictionary<(string Language, string Namespace), Dictionary<string, string>> Cache = new();
    private static readonly object CacheLock = new();
    private static string? _override;

    /// <summary>raised when <see cref="Language"/> changes, so open windows can re-render.</summary>
    public static event Action? LanguageChanged;

    /// <summary>
    /// the language strings are looked up in. defaults to the system language; setting it
    /// overrides that for the rest of the process, which is what a language picker calls.
    /// unsupported codes are ignored, same as the macOS client does.
    /// </summary>
    public static string Language
    {
        get => _override ?? SystemLanguage();
        set
        {
            var canonical = Canonicalise(value);

            if (canonical is null || canonical == Language)
            {
                return;
            }

            _override = canonical;
            LanguageChanged?.Invoke();
        }
    }

    /// <summary>goes back to following the system language.</summary>
    public static void UseSystemLanguage()
    {
        if (_override is null)
        {
            return;
        }

        _override = null;
        LanguageChanged?.Invoke();
    }

    /// <summary>
    /// looks up <paramref name="key"/> in <paramref name="ns"/>.json, for the current language
    /// and then for english. returns the key itself when neither has it, which is what i18next
    /// does too, so a missing translation shows up instead of rendering as empty text.
    /// </summary>
    /// <param name="key">flat key, dots address nested source objects, e.g. <c>oidcError.expired</c>.</param>
    /// <param name="ns">namespace, matching the source file name without extension.</param>
    /// <param name="args">values for the <c>{{name}}</c> placeholders in the template.</param>
    public static string T(string key, string ns = "common", params (string Key, object? Value)[] args)
    {
        foreach (var language in new[] { Language, DefaultLanguage })
        {
            if (Strings(language, ns).TryGetValue(key, out var template))
            {
                return Interpolate(template, args);
            }
        }

        return key;
    }

    /// <summary>
    /// resolves the language from the OS. script subtags win over region ones, so a
    /// zh-TW or zh-HK machine gets traditional chinese while zh-CN gets simplified.
    /// </summary>
    private static string SystemLanguage()
    {
        var culture = CultureInfo.CurrentUICulture;

        if (Canonicalise(culture.Name) is { } exact)
        {
            return exact;
        }

        if (culture.TwoLetterISOLanguageName.Equals("zh", StringComparison.OrdinalIgnoreCase))
        {
            var isTraditional = culture.Name.StartsWith("zh-Hant", StringComparison.OrdinalIgnoreCase)
                || culture.Name.EndsWith("-TW", StringComparison.OrdinalIgnoreCase)
                || culture.Name.EndsWith("-HK", StringComparison.OrdinalIgnoreCase)
                || culture.Name.EndsWith("-MO", StringComparison.OrdinalIgnoreCase);

            return isTraditional ? "zh-Hant" : "zh";
        }

        // the only portuguese table we ship is brazilian portuguese
        if (culture.TwoLetterISOLanguageName.Equals("pt", StringComparison.OrdinalIgnoreCase))
        {
            return "pt-BR";
        }

        return Canonicalise(culture.TwoLetterISOLanguageName) ?? DefaultLanguage;
    }

    private static string? Canonicalise(string? code)
    {
        if (string.IsNullOrEmpty(code))
        {
            return null;
        }

        foreach (var (supported, _) in SupportedLanguages)
        {
            if (string.Equals(supported, code, StringComparison.OrdinalIgnoreCase))
            {
                return supported;
            }
        }

        return null;
    }

    private static Dictionary<string, string> Strings(string language, string ns)
    {
        var cacheKey = (language, ns);

        lock (CacheLock)
        {
            if (Cache.TryGetValue(cacheKey, out var cached))
            {
                return cached;
            }
        }

        var loaded = Load(language, ns);

        lock (CacheLock)
        {
            Cache[cacheKey] = loaded;
        }

        return loaded;
    }

    /// <summary>
    /// test seam: installs a partial table so the english fallback can be asserted without
    /// shipping a locale that is deliberately incomplete. the app never calls this.
    /// </summary>
    internal static void OverrideStrings(string language, string ns, IReadOnlyDictionary<string, string> strings)
    {
        lock (CacheLock)
        {
            Cache[(language, ns)] = new Dictionary<string, string>(strings);
        }
    }

    /// <summary>test seam: drops every table, so one test cannot leak one into the next.</summary>
    internal static void ResetStringsCache()
    {
        lock (CacheLock)
        {
            Cache.Clear();
        }
    }

    /// <summary>test seam: the keys a table actually defines, used to assert language parity.</summary>
    internal static IReadOnlyCollection<string> Keys(string language, string ns)
    {
        return Strings(language, ns).Keys.ToArray();
    }

    private static Dictionary<string, string> Load(string language, string ns)
    {
        var assembly = typeof(L10n).Assembly;

        using var stream = OpenTable(assembly, language, ns);

        if (stream is null)
        {
            return new();
        }

        using var document = JsonDocument.Parse(stream);
        var result = new Dictionary<string, string>();
        Flatten(document.RootElement, "", result);
        return result;
    }

    /// <summary>
    /// locates one table. the tail is matched rather than the whole name rebuilt because
    /// msbuild rewrites '-' in a resource name to '_', so pt-BR and zh-Hant are embedded as
    /// <c>pt_BR</c> and <c>zh_Hant</c>. reconstructing the name would silently miss both and
    /// they would quietly render english forever.
    /// </summary>
    private static Stream? OpenTable(Assembly assembly, string language, string ns)
    {
        var tail = $".locales.{language}.{ns}.json";

        foreach (var name in assembly.GetManifestResourceNames())
        {
            if (name.EndsWith(tail, StringComparison.Ordinal)
                || name.EndsWith(tail.Replace('-', '_'), StringComparison.Ordinal))
            {
                return assembly.GetManifestResourceStream(name);
            }
        }

        return null;
    }

    /// <summary>
    /// the source tables nest groups under one key (see <c>connect.oidcError.*</c>); lookups use
    /// the dotted path so callers never have to know which files group and which do not.
    /// </summary>
    private static void Flatten(JsonElement element, string prefix, Dictionary<string, string> into)
    {
        foreach (var property in element.EnumerateObject())
        {
            var key = prefix.Length == 0 ? property.Name : $"{prefix}.{property.Name}";

            if (property.Value.ValueKind == JsonValueKind.Object)
            {
                Flatten(property.Value, key, into);
            }
            else if (property.Value.ValueKind == JsonValueKind.String)
            {
                into[key] = property.Value.GetString() ?? "";
            }
        }
    }

    private static string Interpolate(string template, (string Key, object? Value)[] args)
    {
        if (args.Length == 0 || !template.Contains("{{", StringComparison.Ordinal))
        {
            return template;
        }

        var result = template;

        foreach (var (key, value) in args)
        {
            result = result.Replace($"{{{{{key}}}}}", Convert.ToString(value, CultureInfo.CurrentCulture) ?? "", StringComparison.Ordinal);
        }

        return result;
    }
}
