import SwiftUI
import UIKit

extension Color {
    /// sharkord's `--sidebar-primary` in dark mode (`oklch(0.488 0.243 264.376)`) resolved to sRGB.
    static let sharkordBlue = Color(red: 20.0 / 255.0, green: 71.0 / 255.0, blue: 230.0 / 255.0)

    /// the same blue mixed 40 percent toward white, for accents that sit on tinted backgrounds.
    static let sharkordBlueSoft = Color(red: 114.0 / 255.0, green: 145.0 / 255.0, blue: 240.0 / 255.0)
}

/// avatar palette taken straight from the web client's `--chart-*` tokens so the native app reads as the same product.
let avatarPalette: [Color] = [
    Color(red: 20.0 / 255.0, green: 71.0 / 255.0, blue: 230.0 / 255.0),
    Color(red: 0.0 / 255.0, green: 188.0 / 255.0, blue: 125.0 / 255.0),
    Color(red: 254.0 / 255.0, green: 154.0 / 255.0, blue: 0.0 / 255.0),
    Color(red: 173.0 / 255.0, green: 70.0 / 255.0, blue: 255.0 / 255.0),
    Color(red: 0.0 / 255.0, green: 150.0 / 255.0, blue: 137.0 / 255.0),
    Color(red: 16.0 / 255.0, green: 78.0 / 255.0, blue: 100.0 / 255.0)
]

struct BrandBackground: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
                }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                }
        }
    }
}

extension View {
    func sharkordGlassCard(cornerRadius: CGFloat = 26) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

struct SectionEyebrow: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

/// carries the banner that keeps a mock screen from being read as a real session.
struct OfflineNotice: View {
    var body: some View {
        Label {
            Text("离线示例 · 不连接服务器，不发送真实消息")
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "eye")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharkordGlassCard(cornerRadius: 16)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// icon led input shared by the connect screen; kept here because more than one screen needs it.
struct SharkordField: View {
    let title: String
    let placeholder: String
    let symbol: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Group {
                    if secure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(capitalization)
                            .autocorrectionDisabled()
                    }
                }
                .font(.body)
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
            }
        }
    }
}

/// full width call to action, used by the connect screen and the voice join button.
struct SharkordPrimaryButton: View {
    let title: String
    let symbol: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol)
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 17)
            .frame(minHeight: 54)
            .foregroundStyle(.white)
            .background(Color.sharkordBlue, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// circular initials avatar with a stable colour, so the same member keeps the same colour across screens.
struct AvatarView: View {
    let name: String
    var diameter: CGFloat = 34
    var isSpeaking = false

    private var paletteIndex: Int {
        let sum = name.unicodeScalars.reduce(Int(0)) { $0 + Int($1.value) }
        return sum % avatarPalette.count
    }

    private var initials: String {
        String(name.prefix(1))
    }

    var body: some View {
        Text(initials)
            .font(.system(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(avatarPalette[paletteIndex], in: Circle())
            .overlay {
                if isSpeaking {
                    Circle()
                        .strokeBorder(Color.green, lineWidth: 2)
                        .padding(-2)
                }
            }
            .accessibilityHidden(true)
    }
}
