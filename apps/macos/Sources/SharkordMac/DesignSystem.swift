import SharkordCore
import SwiftUI

/// Visual tokens shared by every screen. The accent and avatar palette are taken from the
/// web client's CSS variables (`--sidebar-primary`, `--chart-*`) so the native app reads as
/// the same product rather than a different one.
enum Theme {
    static let accent = Color(red: 0x14 / 255, green: 0x47 / 255, blue: 0xE6 / 255)
    static let sidebar = Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x14 / 255)
    static let panel = Color(red: 0x12 / 255, green: 0x15 / 255, blue: 0x1D / 255)
    static let elevated = Color(red: 0x1A / 255, green: 0x1E / 255, blue: 0x28 / 255)

    static let avatarPalette: [Color] = [
        Color(red: 0x14 / 255, green: 0x47 / 255, blue: 0xE6 / 255),
        Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255),
        Color(red: 0xDB / 255, green: 0x27 / 255, blue: 0x77 / 255),
        Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255),
        Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255)
    ]

    static func color(for user: SharkordUser?) -> Color {
        guard let hex = user?.profileColor, let color = Color(hex: hex) else {
            guard let id = user?.id else {
                return avatarPalette[0]
            }

            return avatarPalette[abs(id) % avatarPalette.count]
        }

        return color
    }
}

extension Color {
    /// Parses `#rgb` / `#rrggbb`, the only colour format the server stores.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "#", with: "")

        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        guard value.count == 6, let number = UInt64(value, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}

/// Small circular avatar: the user's file avatar when there is one, otherwise their
/// initial on their profile colour.
struct AvatarView: View {
    @EnvironmentObject private var session: SharkordSession

    let user: SharkordUser?
    var size: CGFloat = 36
    var showsPresence: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            image
                .frame(width: size, height: size)
                .clipShape(Circle())

            if showsPresence {
                Circle()
                    .fill(presenceColor)
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(Circle().stroke(Theme.panel, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
    }

    @ViewBuilder
    private var image: some View {
        if
            let avatar = user?.avatar,
            let url = session.publicFileURL(for: avatar)
        {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initial
                }
            }
        } else {
            initial
        }
    }

    private var initial: some View {
        ZStack {
            Theme.color(for: user)

            Text(String(user?.name.prefix(1) ?? "?").uppercased())
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var presenceColor: Color {
        switch user?.status {
        case .online:
            return .green
        case .idle:
            return .orange
        default:
            return .gray
        }
    }
}

/// Uppercase section label, matching the iOS shell's "eyebrow" style.
struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}
