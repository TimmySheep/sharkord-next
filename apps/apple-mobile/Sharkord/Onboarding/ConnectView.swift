import SwiftUI

/// the first screen: server address, account, password. the real `POST /login` plus websocket handshake
/// belongs here later, so the field set and the disabled state are already shaped for it.
struct ConnectView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            BrandBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    brandHeader
                    introduction
                    connectCard
                    previewCard
                    footerNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var brandHeader: some View {
        HStack(spacing: 13) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [.sharkordBlue, .sharkordBlueSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: .sharkordBlue.opacity(0.18), radius: 12, y: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sharkord")
                    .font(.headline.weight(.semibold))
                Text("iPhone · iPad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "number")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.sharkordBlue)
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.top, 4)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "自托管 · 原生客户端")

            Text("频道，随时进入。")
                .font(.system(size: 35, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)

            Text("连接你的 Sharkord 服务器，在 iPhone 和 iPad 上进入文字与语音频道。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接服务器")
                        .font(.title3.weight(.semibold))
                    Text("使用你自己的 Sharkord 实例")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(Color.sharkordBlue)
            }

            VStack(spacing: 14) {
                SharkordField(
                    title: "服务器地址",
                    placeholder: "https://chat.example.com",
                    symbol: "server.rack",
                    text: $model.serverAddress,
                    keyboardType: .URL
                )

                SharkordField(
                    title: "账号",
                    placeholder: "登录身份",
                    symbol: "person",
                    text: $model.account,
                    capitalization: .never
                )

                SharkordField(
                    title: "密码",
                    placeholder: "可选",
                    symbol: "lock",
                    text: $model.password,
                    secure: true
                )
            }

            SharkordPrimaryButton(
                title: "连接功能开发中",
                symbol: "arrow.right",
                enabled: false,
                action: {}
            )
            .accessibilityHint("当前版本只提供界面骨架，登录与握手将在后续接入")

            Text("骨架阶段不保存密码，也不发起任何网络请求。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .sharkordGlassCard()
    }

    private var previewCard: some View {
        Button {
            model.enterSampleWorkspace()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.3.group")
                    .font(.headline)
                    .foregroundStyle(Color.sharkordBlue)
                    .frame(width: 42, height: 42)
                    .background(
                        Color.sharkordBlue.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("预览离线工作区")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("看频道列表、消息、成员和设置的原生布局")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .sharkordGlassCard(cornerRadius: 20)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footerNote: some View {
        Label {
            Text("这是第一版骨架：界面与导航已就位，服务器通信尚未接入。")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 3)
    }
}

#Preview {
    NavigationStack {
        ConnectView(model: AppModel())
    }
}
