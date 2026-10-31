import AppKit
import SharkordCore
import SwiftUI

/// shared dark workspace surfaces, following the desktop taskbook's Discord palette
enum Theme {
    static let accent = Color(red: 0x58 / 255, green: 0x65 / 255, blue: 0xF2 / 255)
    static let sidebar = Color(red: 0x2B / 255, green: 0x2D / 255, blue: 0x31 / 255)
    static let panel = Color(red: 0x31 / 255, green: 0x33 / 255, blue: 0x38 / 255)
    static let deep = Color(red: 0x1E / 255, green: 0x1F / 255, blue: 0x22 / 255)
    static let elevated = Color.primary.opacity(0.045)
    static let input = Color(red: 0x38 / 255, green: 0x3A / 255, blue: 0x40 / 255)
    static let hover = Color.white.opacity(0.055)
    static let selected = Color.white.opacity(0.10)

    static let avatarPalette: [Color] = [
        accent,
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

struct WorkspaceRowBackground: ViewModifier {
    var isSelected = false
    @State private var hovering = false

    private var fill: Color {
        if isSelected { return Theme.selected }
        if hovering { return Theme.hover }
        return .clear
    }

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .onHover { hovering = $0 }
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

    /// The `#rrggbb` form the server stores, for colour pickers round tripping a role or
    /// profile colour.
    var hexString: String {
        let components = NSColor(self).usingColorSpace(.sRGB)

        let red = Int(((components?.redComponent ?? 0) * 255).rounded())
        let green = Int(((components?.greenComponent ?? 0) * 255).rounded())
        let blue = Int(((components?.blueComponent ?? 0) * 255).rounded())

        return String(format: "#%02X%02X%02X", red, green, blue)
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
