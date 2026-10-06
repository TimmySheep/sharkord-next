import Foundation

public enum TRPCMethod: String, Sendable {
    case query
    case mutation
    case subscription
}

/// The error shape tRPC wraps failures in. `message` is user facing and may itself be a
/// JSON string for validation errors (the server mimics the zod format), so callers that
/// care should prefer `code` for branching.
public struct TRPCClientError: Error, Sendable, Equatable, LocalizedError {
    public let code: String
    public let message: String

    public var errorDescription: String? {
        message
    }

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// One request frame. This mirrors `@trpc/client`'s wsLink envelope exactly:
/// `{ "id": n, "method": "query"|"mutation"|"subscription", "params": { path, input, lastEventId } }`.
/// Missing optional fields are omitted rather than sent as null, which is what
/// `JSON.stringify` does to `undefined` on the reference client.
struct TRPCRequest: Sendable {
    let id: Int
    let method: TRPCMethod
    let path: String
    let input: JSONValue?
    var lastEventId: String?

    func json() -> JSONValue {
        var params: [String: JSONValue] = ["path": .string(path)]

        if let input {
            params["input"] = input
        }

        if let lastEventId {
            params["lastEventId"] = .string(lastEventId)
        }

        return .object([
            "id": .int(id),
            "method": .string(method.rawValue),
            "params": .object(params)
        ])
    }
}

/// What the client sends once, immediately after the socket opens, to hand its token to
/// the server. The server defers context creation until this arrives, which is why the
/// connection URL must carry `?connectionParams=1`.
enum TRPCConnectionParams {
    static func json(token: String) -> JSONValue {
        .object([
            "method": .string("connectionParams"),
            "data": .object(["token": .string(token)])
        ])
    }
}

/// A decoded server frame.
enum TRPCIncoming: Sendable {
    /// A `result` envelope. `type` is `data`, `started` or `stopped`.
    case result(id: Int?, type: String, data: JSONValue?, eventId: Int?)
    case failure(id: Int?, error: TRPCClientError)
    /// A server to client request, currently only `reconnect`.
    case serverRequest(method: String)
    case unsupported
}

enum TRPCResponseParser {
    static func parse(_ value: JSONValue) -> TRPCIncoming {
        guard case .object(let object) = value else {
            return .unsupported
        }

        if let method = object["method"]?.stringValue {
            return .serverRequest(method: method)
        }

        let id = object["id"]?.intValue

        if let error = object["error"] {
            return .failure(id: id, error: parseError(error))
        }

        guard let result = object["result"], case .object(let resultObject) = result else {
            return .unsupported
        }

        let type = resultObject["type"]?.stringValue ?? "data"

        return .result(
            id: id,
            type: type,
            data: resultObject["data"],
            eventId: resultObject["id"]?.intValue
        )
    }

    /// tRPC's error shape is `{ message, code: <jsonrpc number>, data: { code, httpStatus } }`.
    /// The app branches on the string code, so fall back to the numeric one as a string.
    private static func parseError(_ value: JSONValue) -> TRPCClientError {
        let message = value["message"]?.stringValue ?? "Request failed"
        let stringCode = value["data"]?["code"]?.stringValue
        let numericCode = value["code"]?.intValue

        let code: String
        if let stringCode {
            code = stringCode
        } else if let numericCode {
            code = String(numericCode)
        } else {
            code = "UNKNOWN"
        }

        return TRPCClientError(code: code, message: message)
    }
}
