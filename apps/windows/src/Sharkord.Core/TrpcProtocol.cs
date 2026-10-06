using System.Text.Json.Nodes;

namespace Sharkord.Core;

public enum TrpcMethod
{
    Query,
    Mutation,
    Subscription
}

/// <summary>
/// A tRPC failure. <see cref="Code"/> is the string code from the error payload
/// (UNAUTHORIZED, FORBIDDEN, ...) when present, otherwise the numeric JSON-RPC code.
/// </summary>
public sealed class TrpcClientError : Exception
{
    public string Code { get; }

    public TrpcClientError(string code, string message)
        : base(message)
    {
        Code = code;
    }
}

/// <summary>
/// One request frame. Mirrors `@trpc/client`'s wsLink envelope exactly:
/// `{ id, method, params: { path, input, lastEventId } }`. Absent optionals are omitted,
/// which is what `JSON.stringify` does to `undefined` on the reference client.
/// </summary>
public sealed record TrpcRequest(
    int Id,
    TrpcMethod Method,
    string Path,
    JsonNode? Input,
    string? LastEventId = null
)
{
    public JsonObject ToJson()
    {
        var parameters = new JsonObject { ["path"] = Path };

        if (Input is not null)
        {
            parameters["input"] = Input;
        }

        if (LastEventId is not null)
        {
            parameters["lastEventId"] = LastEventId;
        }

        return new JsonObject
        {
            ["id"] = Id,
            ["method"] = Method switch
            {
                TrpcMethod.Query => "query",
                TrpcMethod.Mutation => "mutation",
                _ => "subscription"
            },
            ["params"] = parameters
        };
    }
}

public static class TrpcConnectionParams
{
    public static JsonObject ToJson(string token) => new()
    {
        ["method"] = "connectionParams",
        ["data"] = new JsonObject { ["token"] = token }
    };
}

internal enum TrpcIncomingKind
{
    Result,
    Failure,
    ServerRequest,
    Unsupported
}

internal sealed record TrpcIncoming(
    TrpcIncomingKind Kind,
    int? Id,
    string? Type,
    JsonNode? Data,
    int? EventId,
    string? Method,
    TrpcClientError? Error
);

internal static class TrpcResponseParser
{
    public static TrpcIncoming Parse(JsonNode? value)
    {
        if (value is not JsonObject obj)
        {
            return new TrpcIncoming(TrpcIncomingKind.Unsupported, null, null, null, null, null, null);
        }

        var method = obj.GetString("method");

        if (method is not null)
        {
            return new TrpcIncoming(TrpcIncomingKind.ServerRequest, null, null, null, null, method, null);
        }

        var id = obj.GetInt("id");

        if (obj.TryGetPropertyValue("error", out var errorNode) && errorNode is JsonObject errorObject)
        {
            var message = errorObject.GetString("message") ?? "Request failed";
            var dataObject = errorObject["data"] as JsonObject;
            var stringCode = dataObject?.GetString("code");
            var numericCode = errorObject.GetInt("code");

            return new TrpcIncoming(
                TrpcIncomingKind.Failure,
                id,
                null,
                null,
                null,
                null,
                new TrpcClientError(stringCode ?? numericCode?.ToString() ?? "UNKNOWN", message)
            );
        }

        if (obj["result"] is not JsonObject result)
        {
            return new TrpcIncoming(TrpcIncomingKind.Unsupported, null, null, null, null, null, null);
        }

        return new TrpcIncoming(
            TrpcIncomingKind.Result,
            id,
            result.GetString("type") ?? "data",
            result.TryGetPropertyValue("data", out var data) ? data : null,
            result.GetInt("id"),
            null,
            null
        );
    }
}
