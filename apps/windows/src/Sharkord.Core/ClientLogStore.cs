using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Sharkord.Core;

/// <summary>
/// writes a bounded, credential-free diagnostic history to the current user's profile.
/// </summary>
public sealed class ClientLogStore
{
    private const int MaximumFileSize = 1_048_576;
    private const int RetainedArchives = 3;
    private static readonly Regex UnsafeCharacters = new("[^a-zA-Z0-9._-]", RegexOptions.Compiled);
    private static readonly HashSet<string> KnownTrpcCodes = new(StringComparer.Ordinal)
    {
        "AUDIO_FORMAT",
        "BAD_GATEWAY",
        "BAD_REQUEST",
        "CLIENT_CLOSED_REQUEST",
        "CONFLICT",
        "DISCONNECTED",
        "ENCODING",
        "FORBIDDEN",
        "GATEWAY_TIMEOUT",
        "INTERNAL_SERVER_ERROR",
        "METHOD_NOT_SUPPORTED",
        "NOT_FOUND",
        "NOT_IMPLEMENTED",
        "PAYLOAD_TOO_LARGE",
        "PRECONDITION_FAILED",
        "PROTOCOL",
        "RECONNECT",
        "SERVICE_UNAVAILABLE",
        "TIMEOUT",
        "TOO_MANY_REQUESTS",
        "UNAUTHORIZED",
        "UNPROCESSABLE_CONTENT",
        "UNPROCESSABLE_ENTITY"
    };
    public static ClientLogStore Shared { get; } = new();

    private readonly object _gate = new();

    public string DirectoryPath { get; }

    public string CurrentLogPath => Path.Combine(DirectoryPath, "cove.log");

    public ClientLogStore(string? directoryPath = null)
    {
        DirectoryPath = directoryPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Cove",
            "Logs"
        );
    }

    public void RecordInfo(string eventName, string? code = null) => Append("INFO", eventName, null, code);

    public void RecordFailure(string eventName, string? code = null) => Append("ERROR", eventName, null, code);

    public void RecordError(string eventName, Exception exception)
    {
        if (exception is OperationCanceledException)
        {
            return;
        }

        var code = exception switch
        {
            TrpcClientError trpc => TrpcCode(trpc.Code),
            SharkordHttpError http => $"http.{http.Status.ToString(CultureInfo.InvariantCulture)}",
            _ => $"{exception.GetType().Name}.{exception.HResult.ToString(CultureInfo.InvariantCulture)}"
        };

        Append("ERROR", eventName, exception.GetType().Name, code);
    }

    public async Task ExportLogsAsync(string destinationPath, CancellationToken cancellationToken = default)
    {
        string contents;
        lock (_gate)
        {
            var paths = Enumerable.Range(1, RetainedArchives)
                .Reverse()
                .Select(ArchivePath)
                .Append(CurrentLogPath)
                .Where(File.Exists);
            contents = string.Join(Environment.NewLine, paths.Select(File.ReadAllText));
        }

        await File.WriteAllTextAsync(destinationPath, contents, new UTF8Encoding(false), cancellationToken)
            .ConfigureAwait(false);
    }

    private void Append(string level, string eventName, string? errorType, string? code)
    {
        lock (_gate)
        {
            try
            {
                Directory.CreateDirectory(DirectoryPath);

                var fields = new List<string>
                {
                    DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    $"level={SafeField(level)}",
                    $"event={SafeField(eventName)}"
                };
                if (errorType is not null)
                {
                    fields.Add($"error={SafeField(errorType)}");
                }
                if (code is not null)
                {
                    fields.Add($"code={SafeField(code)}");
                }

                var line = string.Join(" ", fields) + "\n";
                RotateIfNeeded(Encoding.UTF8.GetByteCount(line));
                File.AppendAllText(CurrentLogPath, line, new UTF8Encoding(false));
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                Debug.WriteLine($"Cove could not write a diagnostic log entry ({exception.GetType().Name}).");
            }
        }
    }

    private void RotateIfNeeded(int incomingSize)
    {
        if (!File.Exists(CurrentLogPath) || new FileInfo(CurrentLogPath).Length + incomingSize <= MaximumFileSize)
        {
            return;
        }

        var oldestPath = ArchivePath(RetainedArchives);
        if (File.Exists(oldestPath))
        {
            File.Delete(oldestPath);
        }

        for (var index = RetainedArchives - 1; index >= 1; index--)
        {
            var sourcePath = ArchivePath(index);
            if (File.Exists(sourcePath))
            {
                File.Move(sourcePath, ArchivePath(index + 1));
            }
        }

        File.Move(CurrentLogPath, ArchivePath(1));
    }

    private string ArchivePath(int index) => Path.Combine(DirectoryPath, $"cove.{index}.log");

    private static string TrpcCode(string code)
    {
        var normalized = code.ToUpperInvariant();
        return KnownTrpcCodes.Contains(normalized) || int.TryParse(normalized, out _)
            ? $"trpc.{normalized}"
            : "trpc.unknown";
    }

    private static string SafeField(string value)
    {
        var sanitized = UnsafeCharacters.Replace(value, string.Empty);
        return sanitized.Length == 0 ? "unknown" : sanitized[..Math.Min(sanitized.Length, 96)];
    }
}
