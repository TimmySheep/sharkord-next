import SwiftUI

/// holds every screen state for the shell. nothing here talks to a server yet: the sample workspace is
/// local data, so the wiring between screens can be reviewed before any protocol work lands.
@MainActor
final class AppModel: ObservableObject {
    enum Phase {
        case onboarding
        case workspace
    }

    @Published var phase: Phase = .onboarding
    @Published var serverAddress = "https://chat.example.com"
    @Published var account = ""
    @Published var password = ""
    @Published var selectedChannelID: String?

    @Published private(set) var categories: [ServerCategory] = AppModel.sampleCategories
    @Published private(set) var messagesByChannel: [String: [ChatMessage]] = AppModel.sampleMessages
    @Published private(set) var members: [WorkspaceMember] = AppModel.sampleMembers
    @Published private(set) var liveActivityRunning = false

    /// the seam between the UI and the Dynamic Island. nothing in the session layer calls it yet.
    let liveActivityController = LiveActivityController()

    var serverDisplayName: String {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: trimmed)?.host() else { return trimmed }
        return host
    }

    var accountDisplayName: String {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "访客" : trimmed
    }

    func channel(withID id: String) -> ServerChannel? {
        for category in categories {
            for channel in category.channels where channel.id == id {
                return channel
            }
        }
        return nil
    }

    func member(withID id: String) -> WorkspaceMember? {
        members.first { $0.id == id }
    }

    func enterSampleWorkspace() {
        selectedChannelID = nil
        phase = .workspace
    }

    func leaveWorkspace() {
        selectedChannelID = nil
        phase = .onboarding
    }

    func send(_ body: String, to channelID: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = ChatMessage(
            id: "local-\(UUID().uuidString)",
            authorID: "local",
            body: trimmed,
            sentAt: Date()
        )
        messagesByChannel[channelID, default: []].append(message)
    }

    /// preview hook for the framework: starts an activity carrying sample data, so the widget can be
    /// checked before any session exists. replaced by the real join event in the voice phase.
    func startPreviewLiveActivity() {
        let started = liveActivityController.start(
            serverAddress: serverDisplayName,
            channelName: "大厅",
            topic: "闲聊 · 示例数据",
            participantCount: 3
        )
        liveActivityRunning = started
    }

    func stopPreviewLiveActivity() {
        liveActivityRunning = false
        Task { await liveActivityController.end() }
    }

    static let sampleCategories: [ServerCategory] = [
        ServerCategory(
            id: "cat-info",
            name: "信息",
            channels: [
                ServerChannel(
                    id: "ch-rules",
                    name: "规则",
                    kind: .text,
                    topic: "服务器规则与公告",
                    voiceMemberIDs: []
                ),
                ServerChannel(
                    id: "ch-updates",
                    name: "更新",
                    kind: .text,
                    topic: "版本发布与变更",
                    voiceMemberIDs: []
                )
            ]
        ),
        ServerCategory(
            id: "cat-dev",
            name: "开发",
            channels: [
                ServerChannel(
                    id: "ch-web",
                    name: "web",
                    kind: .text,
                    topic: "参考客户端",
                    voiceMemberIDs: []
                ),
                ServerChannel(
                    id: "ch-native",
                    name: "原生客户端",
                    kind: .text,
                    topic: "iOS / macOS / Windows",
                    voiceMemberIDs: []
                )
            ]
        ),
        ServerCategory(
            id: "cat-voice",
            name: "语音",
            channels: [
                ServerChannel(
                    id: "vc-lounge",
                    name: "大厅",
                    kind: .voice,
                    topic: "闲聊",
                    voiceMemberIDs: ["m-timmy", "m-luna", "m-echo"]
                ),
                ServerChannel(
                    id: "vc-pair",
                    name: "结对",
                    kind: .voice,
                    topic: "一起写代码",
                    voiceMemberIDs: ["m-mika"]
                )
            ]
        )
    ]

    static let sampleMembers: [WorkspaceMember] = [
        WorkspaceMember(id: "m-timmy", name: "Timmy", roleName: "Owner", isOnline: true, isSpeaking: false),
        WorkspaceMember(id: "m-luna", name: "Luna", roleName: "管理员", isOnline: true, isSpeaking: true),
        WorkspaceMember(id: "m-echo", name: "Echo", roleName: "成员", isOnline: true, isSpeaking: false),
        WorkspaceMember(id: "m-mika", name: "Mika", roleName: "成员", isOnline: true, isSpeaking: false),
        WorkspaceMember(id: "m-ori", name: "Ori", roleName: "成员", isOnline: false, isSpeaking: false),
        WorkspaceMember(id: "m-nova", name: "Nova", roleName: "成员", isOnline: false, isSpeaking: false)
    ]

    static let sampleMessages: [String: [ChatMessage]] = [
        "ch-rules": [
            ChatMessage(
                id: "msg-rules-1",
                authorID: "m-timmy",
                body: "欢迎。这里的一切默认公开，别贴密钥和连接串。",
                sentAt: Date().addingTimeInterval(-7200)
            ),
            ChatMessage(
                id: "msg-rules-2",
                authorID: "m-luna",
                body: "语音频道目前是占位界面，接入 mediasoup 之后再启用。",
                sentAt: Date().addingTimeInterval(-5400)
            )
        ],
        "ch-updates": [
            ChatMessage(
                id: "msg-updates-1",
                authorID: "m-luna",
                body: "仓库基线仍是上游 c611bb4，还没有行为改动。",
                sentAt: Date().addingTimeInterval(-3600)
            )
        ],
        "ch-web": [
            ChatMessage(
                id: "msg-web-1",
                authorID: "m-echo",
                body: "Web 客户端缺 service worker 和 viewport-fit，先做 PWA。",
                sentAt: Date().addingTimeInterval(-2400)
            ),
            ChatMessage(
                id: "msg-web-2",
                authorID: "m-timmy",
                body: "同意，移动端优先。",
                sentAt: Date().addingTimeInterval(-2200)
            )
        ],
        "ch-native": [
            ChatMessage(
                id: "msg-native-1",
                authorID: "m-timmy",
                body: "第一版 iOS 只搭框架，功能可以不正常。",
                sentAt: Date().addingTimeInterval(-4800)
            ),
            ChatMessage(
                id: "msg-native-2",
                authorID: "m-luna",
                body: "界面参考 webspeak 的玻璃卡片和连续圆角。",
                sentAt: Date().addingTimeInterval(-4500)
            ),
            ChatMessage(
                id: "msg-native-3",
                authorID: "m-echo",
                body: "协议层走 tRPC over WebSocket，先实现 handshake 再谈状态同步。",
                sentAt: Date().addingTimeInterval(-3000)
            ),
            ChatMessage(
                id: "msg-native-4",
                authorID: "m-timmy",
                body: "语音放 Phase 2，先把文字频道跑通。",
                sentAt: Date().addingTimeInterval(-1800)
            )
        ]
    ]
}
