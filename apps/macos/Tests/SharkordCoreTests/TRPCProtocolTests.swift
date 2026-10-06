import Foundation
import Testing

@testable import SharkordCore

/// Pins the exact frames the transport puts on the wire. The tRPC WebSocket envelope is
/// an implementation detail of `@trpc/client`, not a versioned spec, so these tests are
/// the guard that a native mirror still matches the reference client.
struct TRPCProtocolTests {
    private func encoded(_ value: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        // sortedKeys makes the comparison deterministic regardless of dictionary order
        let object = try JSONSerialization.jsonObject(with: data)
        let canonical = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )

        return String(decoding: canonical, as: UTF8.self)
    }

    @Test
    func queryWithoutInputOmitsInput() throws {
        let request = TRPCRequest(id: 1, method: .query, path: "others.handshake", input: nil)

        #expect(
            try encoded(request.json())
                == #"{"id":1,"method":"query","params":{"path":"others.handshake"}}"#
        )
    }

    @Test
    func mutationWithInputCarriesIt() throws {
        let request = TRPCRequest(
            id: 7,
            method: .mutation,
            path: "messages.send",
            input: .object([
                "channelId": .int(3),
                "content": .string("hi"),
                "files": .array([])
            ])
        )

        #expect(
            try encoded(request.json())
                == #"{"id":7,"method":"mutation","params":{"input":{"channelId":3,"content":"hi","files":[]},"path":"messages.send"}}"#
        )
    }

    @Test
    func connectionParamsFrameMatchesReferenceClient() throws {
        #expect(
            try encoded(TRPCConnectionParams.json(token: "abc"))
                == #"{"data":{"token":"abc"},"method":"connectionParams"}"#
        )
    }

    @Test
    func parsesDataResult() {
        let value: JSONValue = .object([
            "id": 2,
            "result": .object(["type": .string("data"), "data": .int(42)])
        ])

        guard case .result(let id, let type, let data, _) = TRPCResponseParser.parse(value) else {
            Issue.record("expected result")
            return
        }

        #expect(id == 2)
        #expect(type == "data")
        #expect(data?.intValue == 42)
    }

    @Test
    func parsesErrorWithStringCode() {
        let value: JSONValue = .object([
            "id": 3,
            "error": .object([
                "message": .string("You must be authenticated to perform this action."),
                "code": .int(-32001),
                "data": .object(["code": .string("UNAUTHORIZED")])
            ])
        ])

        guard case .failure(let id, let error) = TRPCResponseParser.parse(value) else {
            Issue.record("expected failure")
            return
        }

        #expect(id == 3)
        #expect(error.code == "UNAUTHORIZED")
        #expect(error.message == "You must be authenticated to perform this action.")
    }

    @Test
    func parsesStoppedSubscription() {
        let value: JSONValue = .object([
            "id": 4,
            "result": .object(["type": .string("stopped")])
        ])

        guard case .result(let id, let type, _, _) = TRPCResponseParser.parse(value) else {
            Issue.record("expected result")
            return
        }

        #expect(id == 4)
        #expect(type == "stopped")
    }

    @Test
    func parsesServerReconnectRequest() {
        guard case .serverRequest(let method) = TRPCResponseParser.parse(
            .object(["method": .string("reconnect")])
        ) else {
            Issue.record("expected server request")
            return
        }

        #expect(method == "reconnect")
    }

    @Test
    func messageHTMLKeepsLineStructure() {
        #expect(MessageHTML.fromPlainText("hello") == "<p>hello</p>")
        #expect(
            MessageHTML.fromPlainText("a\nb")
                == "<p>a</p><br class=\"hard-break\"><p>b</p>"
        )
        #expect(MessageHTML.fromPlainText("<b>") == "<p>&lt;b&gt;</p>")
    }

    @Test
    func plainTextRoundTrip() {
        let html = MessageHTML.fromPlainText("a\nb")
        #expect(MessageHTML.toPlainText(html) == "a\nb")
    }

    @Test
    func joinPayloadDecodesWithUnknownKeys() throws {
        let payload: JSONValue = .object([
            "categories": .array([]),
            "channels": .array([]),
            "users": .array([]),
            "roles": .array([]),
            "serverId": .string("x"),
            "serverName": .string("Test"),
            "ownUserId": .int(1),
            "publicSettings": .object([
                "name": .string("Test"),
                "serverId": .string("x")
            ]),
            // the real payload carries far more; unknown keys must be ignored
            "voiceMap": .object([:]),
            "externalStreamsMap": .object([:])
        ])

        let result = try payload.decode(JoinResult.self)

        #expect(result.serverName == "Test")
        #expect(result.ownUserId == 1)
    }
}
