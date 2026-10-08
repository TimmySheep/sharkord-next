import Foundation

public struct SharkordHTTPError: Error, Sendable, LocalizedError {
    public let status: Int
    public let message: String

    public var errorDescription: String? {
        message
    }

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }
}

/// The non tRPC half of the server: `GET /info`, `POST /login`, `POST /upload` and the
/// `/public` file route. These are plain HTTP and share the same origin as the WebSocket.
public struct SharkordHTTPClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// The tRPC WebSocket lives on the same origin. `?connectionParams=1` is required,
    /// otherwise the server creates the request context before the token arrives.
    public var webSocketURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()

        switch baseURL.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        default:
            components.scheme = "ws"
        }

        components.path = "/"
        components.queryItems = [URLQueryItem(name: "connectionParams", value: "1")]
        components.fragment = nil

        return components.url ?? baseURL
    }

    public func serverInfo() async throws -> SharkordServerInfo {
        do {
            return try await get("/info")
        } catch {
            ClientLogStore.shared.recordError("http.server_info.failed", error: error)
            throw error
        }
    }

    public func login(identity: String, password: String, invite: String? = nil) async throws -> SharkordLoginResult {
        var body: [String: JSONValue] = [
            "identity": .string(identity),
            "password": .string(password)
        ]

        if let invite, !invite.isEmpty {
            body["invite"] = .string(invite)
        }

        do {
            return try await post("/login", body: .object(body))
        } catch {
            ClientLogStore.shared.recordError("http.login.failed", error: error)
            throw error
        }
    }

    public func upload(
        data: Data,
        fileName: String,
        mimeType: String,
        token: String
    ) async throws -> SharkordTempFile {
        var request = URLRequest(url: baseURL.appendingPathComponent("upload"))
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "x-token")
        request.setValue(fileName, forHTTPHeaderField: "x-file-name")
        request.setValue(mimeType, forHTTPHeaderField: "x-file-type")
        request.setValue(String(data.count), forHTTPHeaderField: "content-length")
        request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")

        do {
            let (responseData, response) = try await session.upload(for: request, from: data)
            try validate(response, data: responseData)
            return try decoder.decode(SharkordTempFile.self, from: responseData)
        } catch {
            ClientLogStore.shared.recordError("http.upload.failed", error: error)
            throw error
        }
    }

    /// Attachments and avatars are served from `/public/<file name>`, with `accessToken`
    /// and `expires` only when the server has signed URLs enabled.
    public func publicFileURL(for file: SharkordFile) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("public").appendingPathComponent(file.name),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        if let token = file._accessToken, let expires = file._accessTokenExpiresAt {
            components.queryItems = [
                URLQueryItem(name: "accessToken", value: token),
                URLQueryItem(name: "expires", value: String(expires))
            ]
        }

        return components.url
    }

    // MARK: - plumbing

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: JSONValue) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        return try decoder.decode(T.self, from: data)
    }

    /// The server answers failures as `{ "error": "..." }` or `{ "errors": { field: "..." } }`.
    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(http.statusCode) else {
            throw SharkordHTTPError(
                status: http.statusCode,
                message: Self.errorMessage(from: data) ?? "Request failed (\(http.statusCode))"
            )
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return nil
        }

        if let message = value["error"]?.stringValue {
            return message
        }

        if let errors = value["errors"], case .object(let fields) = errors {
            return fields.values.compactMap(\.stringValue).first
        }

        return nil
    }
}
