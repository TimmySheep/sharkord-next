import Foundation

/// A minimal tRPC v11 WebSocket client, mirroring the wire format used by
/// `@trpc/client`'s wsLink (JSON text frames, one envelope per request, `PING`/`PONG`
/// keepalive, `connectionParams` as the first frame).
///
/// The framed protocol is not a versioned public spec, so this type is the single place
/// that knows it. If upstream ever changes the envelope, only this file and
/// `TRPCProtocol.swift` change. The unit tests pin the exact bytes.
public actor TRPCWebSocketClient {
    public struct Configuration: Sendable {
        public var url: URL
        public var token: String
        public var keepAliveInterval: TimeInterval
        public var pongTimeout: TimeInterval

        public init(
            url: URL,
            token: String,
            keepAliveInterval: TimeInterval = 30,
            pongTimeout: TimeInterval = 5
        ) {
            self.url = url
            self.token = token
            self.keepAliveInterval = keepAliveInterval
            self.pongTimeout = pongTimeout
        }
    }

    private final class Subscription {
        let continuation: AsyncThrowingStream<JSONValue, Error>.Continuation
        let path: String
        var lastEventId: String?

        init(
            continuation: AsyncThrowingStream<JSONValue, Error>.Continuation,
            path: String
        ) {
            self.continuation = continuation
            self.path = path
        }

        func finish(throwing error: Error? = nil) {
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }

        func yield(_ value: JSONValue) {
            continuation.yield(value)
        }
    }

    private let configuration: Configuration
    private let sessionDelegate: WebSocketSessionDelegate

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var receiveLoop: Task<Void, Never>?
    private var keepAliveLoop: Task<Void, Never>?
    private var watchdogLoop: Task<Void, Never>?

    private var nextId = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var subscriptions: [Int: Subscription] = [:]

    private var lastInboundAt = Date()
    private var isClosed = false

    /// Called on the actor when the socket drops or the server asks for a reconnect. The
    /// session layer owns reconnection policy, not the transport.
    private var disconnectHandler: (@Sendable (Error?) -> Void)?

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.sessionDelegate = WebSocketSessionDelegate()
    }

    public func setDisconnectHandler(_ handler: @escaping @Sendable (Error?) -> Void) {
        disconnectHandler = handler
    }

    // MARK: - connection lifecycle

    public func connect() async throws {
        guard task == nil else {
            return
        }

        isClosed = false

        sessionDelegate.onOpen = { [weak self] in
            Task { await self?.handleOpen() }
        }
        sessionDelegate.onClose = { [weak self] code, reason in
            Task { await self?.handleDisconnect(
                code: code,
                reason: reason,
                error: nil
            ) }
        }

        let session = URLSession(
            configuration: .default,
            delegate: sessionDelegate,
            delegateQueue: nil
        )
        // the server only defers context creation (and therefore waits for the
        // connectionParams frame) when this query parameter is present
        let task = session.webSocketTask(with: configuration.url)
        self.session = session
        self.task = task

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            openContinuation = continuation
            task.resume()
        }

        try await send(TRPCConnectionParams.json(token: configuration.token))

        lastInboundAt = Date()
        startReceiveLoop()
        startKeepAlive()
    }

    public func close() {
        isClosed = true
        receiveLoop?.cancel()
        keepAliveLoop?.cancel()
        watchdogLoop?.cancel()
        receiveLoop = nil
        keepAliveLoop = nil
        watchdogLoop = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        failAll(with: TRPCClientError(code: "DISCONNECTED", message: "Connection closed"))
    }

    public var isOpen: Bool {
        task != nil && !isClosed
    }

    // MARK: - requests

    public func query(_ path: String, input: JSONValue? = nil) async throws -> JSONValue {
        try await request(method: .query, path: path, input: input)
    }

    public func mutation(_ path: String, input: JSONValue? = nil) async throws -> JSONValue {
        try await request(method: .mutation, path: path, input: input)
    }

    public func subscribe(_ path: String, input: JSONValue? = nil) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.beginSubscription(path: path, input: input, continuation: continuation) }
        }
    }

    private func request(method: TRPCMethod, path: String, input: JSONValue?) async throws -> JSONValue {
        try await ensureConnected()

        let id = allocateId()
        let request = TRPCRequest(id: id, method: method, path: path, input: input)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { await self.transmit(request, id: id) }
        }
    }

    private func beginSubscription(
        path: String,
        input: JSONValue?,
        continuation: AsyncThrowingStream<JSONValue, Error>.Continuation
    ) async {
        do {
            try await ensureConnected()
        } catch {
            continuation.finish(throwing: error)
            return
        }

        let id = allocateId()
        let subscription = Subscription(continuation: continuation, path: path)
        subscriptions[id] = subscription

        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopSubscription(id: id) }
        }

        await transmit(TRPCRequest(id: id, method: .subscription, path: path, input: input), id: id)
    }

    private func stopSubscription(id: Int) async {
        _ = subscriptions.removeValue(forKey: id)
        try? await send(.object([
            "id": .int(id),
            "method": .string("subscription.stop")
        ]))
    }

    private func transmit(_ request: TRPCRequest, id: Int) async {
        do {
            try await send(request.json())
        } catch {
            if let pending = pending.removeValue(forKey: id) {
                pending.resume(throwing: error)
            }
            if let subscription = subscriptions.removeValue(forKey: id) {
                subscription.finish(throwing: error)
            }
        }
    }

    private func allocateId() -> Int {
        defer { nextId += 1 }

        return nextId
    }

    private func ensureConnected() async throws {
        if task != nil {
            return
        }

        try await connect()
    }

    // MARK: - sending

    private func send(_ value: JSONValue) async throws {
        guard let task else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        let data = try JSONEncoder().encode(value)

        guard let text = String(data: data, encoding: .utf8) else {
            throw TRPCClientError(code: "ENCODING", message: "Failed to encode frame")
        }

        try await task.send(.string(text))
    }

    private func sendPong() async {
        try? await task?.send(.string("PONG"))
    }

    // MARK: - receive loop

    private func startReceiveLoop() {
        receiveLoop?.cancel()
        receiveLoop = Task { [weak self] in
            guard let self else {
                return
            }

            await self.receiveForever()
        }
    }

    private func receiveForever() async {
        guard let task else {
            return
        }

        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message

            do {
                message = try await task.receive()
            } catch {
                await handleDisconnect(code: nil, reason: nil, error: error)
                return
            }

            lastInboundAt = Date()

            switch message {
            case .string(let text):
                await handleFrame(text)
            case .data(let data):
                await handleFrame(String(decoding: data, as: UTF8.self))
            @unknown default:
                break
            }
        }
    }

    private func handleFrame(_ text: String) async {
        if text == "PING" {
            await sendPong()
            return
        }

        if text == "PONG" {
            return
        }

        guard let data = text.data(using: .utf8) else {
            return
        }

        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return
        }

        if case .array(let values) = value {
            for item in values {
                handle(TRPCResponseParser.parse(item))
            }
            return
        }

        handle(TRPCResponseParser.parse(value))
    }

    private func handle(_ incoming: TRPCIncoming) {
        switch incoming {
        case .result(let id, let type, let data, let eventId):
            guard let id else {
                return
            }

            switch type {
            case "data":
                if let pending = pending.removeValue(forKey: id) {
                    pending.resume(returning: data ?? .null)
                    return
                }

                if let subscription = subscriptions[id] {
                    if let eventId {
                        subscription.lastEventId = String(eventId)
                    }
                    subscription.yield(data ?? .null)
                }
            case "stopped":
                subscriptions.removeValue(forKey: id)?.finish()
            default:
                // "started" and any future acknowledgement carry no payload
                break
            }
        case .failure(let id, let error):
            guard let id else {
                return
            }

            if let pending = pending.removeValue(forKey: id) {
                pending.resume(throwing: error)
            } else if let subscription = subscriptions.removeValue(forKey: id) {
                subscription.finish(throwing: error)
            }
        case .serverRequest(let method):
            if method == "reconnect" {
                Task {
                    await self.handleDisconnect(
                        code: nil,
                        reason: nil,
                        error: TRPCClientError(code: "RECONNECT", message: "Server requested reconnect")
                    )
                }
            }
        case .unsupported:
            break
        }
    }

    // MARK: - keepalive

    private func startKeepAlive() {
        keepAliveLoop?.cancel()
        keepAliveLoop = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                let interval = self.configuration.keepAliveInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                if Task.isCancelled {
                    return
                }

                try? await self.task?.send(.string("PING"))
            }
        }

        watchdogLoop?.cancel()
        watchdogLoop = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                let limit = self.configuration.keepAliveInterval + self.configuration.pongTimeout
                try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))

                if Task.isCancelled {
                    return
                }

                let idle = await Date().timeIntervalSince(self.lastInboundAt)

                if idle > limit {
                    await self.handleDisconnect(
                        code: nil,
                        reason: nil,
                        error: TRPCClientError(code: "TIMEOUT", message: "Keepalive timed out")
                    )
                    return
                }
            }
        }
    }

    // MARK: - teardown

    private func handleOpen() {
        openContinuation?.resume()
        openContinuation = nil
    }

    private func handleDisconnect(
        code: URLSessionWebSocketTask.CloseCode?,
        reason: Data?,
        error: Error?
    ) async {
        let wasConnected = task != nil
        receiveLoop?.cancel()
        keepAliveLoop?.cancel()
        watchdogLoop?.cancel()
        receiveLoop = nil
        keepAliveLoop = nil
        watchdogLoop = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil

        if let openContinuation {
            self.openContinuation = nil
            openContinuation.resume(throwing: error ?? TRPCClientError(
                code: "DISCONNECTED",
                message: "Connection closed before it opened"
            ))
            return
        }

        let disconnectError = error ?? TRPCClientError(
            code: "DISCONNECTED",
            message: reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Connection closed"
        )

        failAll(with: disconnectError)

        if wasConnected, !isClosed {
            disconnectHandler?(disconnectError)
        }
    }

    private func failAll(with error: Error) {
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()

        for (_, subscription) in subscriptions {
            subscription.finish(throwing: error)
        }
        subscriptions.removeAll()
    }
}

/// Bridges `URLSessionWebSocketDelegate` callbacks back onto the actor.
private final class WebSocketSessionDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        onOpen?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        onClose?(closeCode, reason)
    }
}
