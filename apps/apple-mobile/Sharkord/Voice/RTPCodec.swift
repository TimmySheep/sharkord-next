import Foundation
import SharkordCore

/// mediasoup speaks JSON documents for every capability and parameter blob (router
/// capabilities, ice parameters, rtp parameters). The shared core carries them as
/// `JSONValue`, the mediasoup client library wants JSON strings, so this is the single
/// place that converts between the two.
enum RTPCodec {
    static func string(from value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    static func value(from string: String) -> JSONValue {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .null
        }
        return value
    }

    /// Key under which a remote stream is tracked locally: one remote user can hold one
    /// consumer per stream kind.
    static func consumerKey(remoteId: Int, kind: StreamKind) -> String {
        "\(remoteId)-\(kind.rawValue)"
    }
}
