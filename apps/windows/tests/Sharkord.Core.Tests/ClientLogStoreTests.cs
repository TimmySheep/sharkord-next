using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class ClientLogStoreTests
{
    [Fact]
    public async Task ExportIncludesDiagnosticCodesButNotExceptionMessages()
    {
        var directory = Path.Combine(Path.GetTempPath(), "cove-client-log-" + Guid.NewGuid().ToString("N"));
        var exportPath = Path.Combine(directory, "export.log");
        var store = new ClientLogStore(directory);

        store.RecordInfo("session.connect.started");
        store.RecordError(
            "trpc.query.users.list",
            new TrpcClientError("FORBIDDEN", "Bearer do-not-export-this-secret")
        );
        await store.ExportLogsAsync(exportPath);

        var contents = await File.ReadAllTextAsync(exportPath);
        Assert.Contains("event=session.connect.started", contents);
        Assert.Contains("code=trpc.FORBIDDEN", contents);
        Assert.DoesNotContain("do-not-export-this-secret", contents);
    }
}
