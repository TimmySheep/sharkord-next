import SwiftUI

/// placeholder settings surface. rows are stubs on purpose: each one marks where a real value will
/// appear once the session layer exists.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OfflineNotice()

                accountCard
                serverCard
                aboutCard

                SharkordPrimaryButton(
                    title: "退出示例工作区",
                    symbol: "arrow.uturn.backward",
                    action: model.leaveWorkspace
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(title: "账户")

            HStack(spacing: 13) {
                AvatarView(name: model.accountDisplayName, diameter: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.accountDisplayName)
                        .font(.headline.weight(.semibold))
                    Text("本地会话，未连接服务器")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            stubRow(symbol: "key", title: "登录凭据", value: "未接入")
            stubRow(symbol: "bell", title: "通知", value: "未接入")
        }
        .padding(18)
        .sharkordGlassCard()
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(title: "服务器")

            stubRow(symbol: "server.rack", title: "地址", value: model.serverDisplayName)
            stubRow(symbol: "clock.arrow.circlepath", title: "握手状态", value: "未连接")
            stubRow(symbol: "waveform", title: "语音", value: "第二阶段")
        }
        .padding(18)
        .sharkordGlassCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(title: "关于")

            stubRow(symbol: "info.circle", title: "版本", value: "0.1.0 骨架")
            stubRow(symbol: "shippingbox", title: "协议", value: "尚未接入")
            stubRow(symbol: "checkmark.seal", title: "基线", value: "上游 c611bb4")
        }
        .padding(18)
        .sharkordGlassCard()
    }

    private func stubRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Color.sharkordBlue)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}
