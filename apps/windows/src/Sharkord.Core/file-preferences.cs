using System.Text.Json;
using System.Text.Json.Nodes;

namespace Sharkord.Core;

// preferences contain presentation choices only; credentials use the Windows credential vault
public sealed class FilePreferences(string path)
{
    private static readonly object Gate = new();
    public static FilePreferences Local { get; } = new(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sharkord", "preferences.json"));

    public T Get<T>(string key, T fallback)
    {
        lock (Gate)
        {
            try { return Read()[key] is { } value ? value.Deserialize<T>() ?? fallback : fallback; }
            catch (JsonException) { return fallback; }
            catch (InvalidOperationException) { return fallback; }
        }
    }

    public void Set<T>(string key, T value)
    {
        lock (Gate)
        {
            var data = Read();
            data[key] = JsonSerializer.SerializeToNode(value);
            Write(data);
        }
    }

    public void Remove(string key)
    {
        lock (Gate)
        {
            var data = Read();
            if (data.Remove(key)) { Write(data); }
        }
    }

    private JsonObject Read()
    {
        try { return JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? []; }
        catch (IOException) { return []; }
        catch (JsonException) { return []; }
    }

    private void Write(JsonObject data)
    {
        var target = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        var temporary = $"{target}.tmp";
        try { File.WriteAllText(temporary, data.ToJsonString()); File.Move(temporary, target, true); }
        finally { if (File.Exists(temporary)) { File.Delete(temporary); } }
    }
}
