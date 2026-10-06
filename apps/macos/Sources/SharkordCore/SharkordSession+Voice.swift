import Foundation

/// Voice signalling. The control plane is complete: join, leave, mute state, reactions,
/// moderator moves and the mediasoup transport handshake. Actually moving media needs a
/// WebRTC stack, which is the one piece this client does not have yet.
extension SharkordSession {
    // MARK: presence and state

    @discardableResult
    public func joinVoice(
        channelId: Int,
        micMuted: Bool = false,
        soundMuted: Bool = false
    ) async throws -> JSONValue {
        let capabilities = try await call(
            "voice.join",
            method: .mutation,
            input: .object([
                "channelId": .int(channelId),
                "state": .object([
                    "micMuted": .bool(micMuted),
                    "soundMuted": .bool(soundMuted)
                ])
            ])
        )

        applyVoiceJoin(VoiceJoinEvent(
            channelId: channelId,
            userId: ownUserId,
            state: VoiceUserState(micMuted: micMuted, soundMuted: soundMuted)
        ))

        return capabilities
    }

    public func leaveVoice() async throws {
        guard let channelId = currentVoiceChannelId else {
            return
        }

        _ = try await call("voice.leave", method: .mutation)

        applyVoiceLeave(VoiceLeaveEvent(channelId: channelId, userId: ownUserId))
    }

    /// Fields the viewer lacks channel permission for are dropped server side.
    public func updateVoiceState(
        micMuted: Bool? = nil,
        soundMuted: Bool? = nil,
        webcamEnabled: Bool? = nil,
        sharingScreen: Bool? = nil
    ) async throws {
        var input: [String: JSONValue] = [:]

        if let micMuted {
            input["micMuted"] = .bool(micMuted)
        }

        if let soundMuted {
            input["soundMuted"] = .bool(soundMuted)
        }

        if let webcamEnabled {
            input["webcamEnabled"] = .bool(webcamEnabled)
        }

        if let sharingScreen {
            input["sharingScreen"] = .bool(sharingScreen)
        }

        _ = try await call("voice.updateState", method: .mutation, input: .object(input))
    }

    public func sendVoiceReaction(emoji: String) async throws {
        _ = try await call(
            "voice.sendReaction",
            method: .mutation,
            input: .object(["emoji": .string(emoji)])
        )
    }

    public func moveUser(userId: Int, to channelId: Int) async throws {
        _ = try await call(
            "voice.moveUser",
            method: .mutation,
            input: .object([
                "userId": .int(userId),
                "channelId": .int(channelId)
            ])
        )
    }

    // MARK: mediasoup transports

    @discardableResult
    public func createProducerTransport() async throws -> VoiceTransportParams {
        try await call("voice.createProducerTransport", method: .mutation)
            .decode(VoiceTransportParams.self)
    }

    @discardableResult
    public func createConsumerTransport() async throws -> VoiceTransportParams {
        try await call("voice.createConsumerTransport", method: .mutation)
            .decode(VoiceTransportParams.self)
    }

    public func connectProducerTransport(dtlsParameters: JSONValue) async throws {
        _ = try await call(
            "voice.connectProducerTransport",
            method: .mutation,
            input: .object(["dtlsParameters": dtlsParameters])
        )
    }

    public func connectConsumerTransport(dtlsParameters: JSONValue) async throws {
        _ = try await call(
            "voice.connectConsumerTransport",
            method: .mutation,
            input: .object(["dtlsParameters": dtlsParameters])
        )
    }

    @discardableResult
    public func produce(
        transportId: String,
        kind: ProducibleKind,
        rtpParameters: JSONValue,
        qualityLayers: [(spatialLayer: Int, label: String)]? = nil
    ) async throws -> String {
        var input: [String: JSONValue] = [
            "transportId": .string(transportId),
            "kind": .string(kind.rawValue),
            "rtpParameters": rtpParameters
        ]

        if let qualityLayers {
            input["qualityLayers"] = .array(
                qualityLayers.map {
                    .object([
                        "spatialLayer": .int($0.spatialLayer),
                        "label": .string($0.label)
                    ])
                }
            )
        }

        return try await call("voice.produce", method: .mutation, input: .object(input))
            .stringValue ?? ""
    }

    @discardableResult
    public func consume(
        kind: StreamKind,
        remoteId: Int,
        rtpCapabilities: JSONValue
    ) async throws -> ConsumeResult {
        try await call(
            "voice.consume",
            method: .mutation,
            input: .object([
                "kind": .string(kind.rawValue),
                "remoteId": .int(remoteId),
                "rtpCapabilities": rtpCapabilities
            ])
        ).decode(ConsumeResult.self)
    }

    public func closeProducer(kind: StreamKind) async throws {
        _ = try await call(
            "voice.closeProducer",
            method: .mutation,
            input: .object(["kind": .string(kind.rawValue)])
        )
    }

    public func setConsumerQuality(
        remoteId: Int,
        kind: StreamKind,
        spatialLayer: Int?
    ) async throws {
        let quality: JSONValue = spatialLayer.map { .object(["mode": .string("layer"), "spatialLayer": .int($0)]) }
            ?? .object(["mode": .string("auto")])

        _ = try await call(
            "voice.setConsumerQuality",
            method: .mutation,
            input: .object([
                "remoteId": .int(remoteId),
                "kind": .string(kind.rawValue),
                "quality": quality
            ])
        )
    }

    @discardableResult
    public func getProducers() async throws -> RemoteProducerIds {
        try await call("voice.getProducers", method: .query).decode(RemoteProducerIds.self)
    }
}
