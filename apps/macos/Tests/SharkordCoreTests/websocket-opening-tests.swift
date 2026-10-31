import Foundation
import Network
import Testing
@testable import SharkordCore

struct WebSocketOpeningTests {
    @Test func rejectedUpgradeFinishesConnect() async throws {
        let server = try OpeningServer(rejectUpgrade: true)
        let port = try await server.start()
        defer { server.stop() }
        let client = TRPCWebSocketClient(configuration: .init(
            url: URL(string: "ws://127.0.0.1:\(port)/")!, token: "test", connectTimeout: 2
        ))
        do {
            try await client.connect()
            Issue.record("rejected upgrade unexpectedly connected")
        } catch {
            #expect((error as? TRPCClientError)?.code != "CONNECT_TIMEOUT")
        }
        #expect(await client.isOpen == false)
    }

    @Test func stalledUpgradeHasDeadline() async throws {
        let server = try OpeningServer(rejectUpgrade: false)
        let port = try await server.start()
        defer { server.stop() }
        let client = TRPCWebSocketClient(configuration: .init(
            url: URL(string: "ws://127.0.0.1:\(port)/")!, token: "test", connectTimeout: 0.1
        ))
        do {
            try await client.connect()
            Issue.record("stalled upgrade unexpectedly connected")
        } catch {
            #expect((error as? TRPCClientError)?.code == "CONNECT_TIMEOUT")
        }
        #expect(await client.isOpen == false)
    }

    @Test func cancelledOpeningFinishes() async throws {
        let server = try OpeningServer(rejectUpgrade: false)
        let port = try await server.start()
        defer { server.stop() }
        let client = TRPCWebSocketClient(configuration: .init(
            url: URL(string: "ws://127.0.0.1:\(port)/")!, token: "test", connectTimeout: 2
        ))
        let opening = Task { try await client.connect() }
        try await Task.sleep(nanoseconds: 50_000_000)
        opening.cancel()
        do {
            try await opening.value
            Issue.record("cancelled opening unexpectedly connected")
        } catch {
            #expect((error as? TRPCClientError)?.code != "CONNECT_TIMEOUT")
        }
        #expect(await client.isOpen == false)
    }
}

// loopback only: no credentials, external server or TLS trust changes
private final class OpeningServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "websocket-opening-tests")
    private let rejectUpgrade: Bool
    private var connections: [NWConnection] = []

    init(rejectUpgrade: Bool) throws {
        listener = try NWListener(using: .tcp, on: .any)
        self.rejectUpgrade = rejectUpgrade
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connections.append(connection)
                connection.start(queue: queue)
                if rejectUpgrade {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                        let data = Data("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
                    }
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
        }
    }
}
