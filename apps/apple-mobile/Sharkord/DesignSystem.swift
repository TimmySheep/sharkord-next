import SwiftUI
import UIKit

/// adaptive platform surfaces with the existing blue accent and rounded controls.
enum SharkordTheme {
    static let background = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let field = Color(uiColor: .tertiarySystemGroupedBackground)
    static let pillNeutral = Color(uiColor: .tertiarySystemFill)
    static let segmentActive = Color(uiColor: .systemGray)

    static let accent = Color(red: 0.17, green: 0.36, blue: 0.91)
    static let accentSoft = Color(red: 0.36, green: 0.55, blue: 1.0)
    static let danger = Color(red: 0.88, green: 0.32, blue: 0.32)
    static let dangerDeep = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.36, green: 0.17, blue: 0.17, alpha: 1)
        }

        return UIColor(red: 1, green: 0.91, blue: 0.91, alpha: 1)
    })
    static let success = Color(red: 0.20, green: 0.78, blue: 0.35)

    static let badgeBackground = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.12, green: 0.16, blue: 0.28, alpha: 1)
        }

        return UIColor(red: 0.89, green: 0.92, blue: 1, alpha: 1)
    })

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(uiColor: .tertiaryLabel)
}

extension Color {
    /// the brand blue used across every call to action; kept under this name so avatar and
    /// reaction styling keep reading as the same product colour.
    static let sharkordBlue = SharkordTheme.accent
    static let sharkordBlueSoft = SharkordTheme.accentSoft
}

/// avatar palette taken straight from the web client's `--chart-*` tokens so the native app
/// reads as the same product.
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
        SharkordTheme.background
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// flat dark card: solid fill, large continuous corners, no border or blur.
struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                SharkordTheme.card,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

extension View {
    func sharkordCard(cornerRadius: CGFloat = 26, padding: CGFloat = 18) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

/// oversized left aligned screen title, the loudest element on every screen.
struct ScreenTitle: View {
    let text: String
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            if let trailing {
                trailing
            }
        }
    }
}

/// small grey label with a leading icon, used to name list groups.
struct SectionLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(SharkordTheme.textSecondary)
    }
}

/// bold card heading with a tinted leading icon, as used inside settings and share cards.
struct CardHeading: View {
    let icon: String
    let text: String
    var tint: Color = SharkordTheme.textPrimary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(SharkordTheme.textPrimary)
        }
    }
}

/// rounded tinted square with a glyph inside, the row icon from the reference design.
struct IconBadge: View {
    let symbol: String
    var tint: Color = SharkordTheme.accentSoft
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                SharkordTheme.badgeBackground,
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// capsule status pill with a leading dot: green online, red seats, grey idle.
struct StatusPill: View {
    let text: String
    var color: Color = SharkordTheme.success

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(color.opacity(0.16), in: Capsule())
    }
}

/// icon led input shared by the connect screen and the message composer.
struct SharkordField: View {
    let title: String
    let placeholder: String
    let symbol: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(SharkordTheme.textPrimary)

            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .frame(width: 22)
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
                .foregroundStyle(SharkordTheme.textPrimary)
                .textFieldStyle(.plain)
                .tint(SharkordTheme.accentSoft)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .background(
                SharkordTheme.field,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }
}

/// full width call to action: bold label on the left, trailing glyph on the right.
struct SharkordPrimaryButton: View {
    let title: String
    let symbol: String
    var enabled = true
    var tint: Color = SharkordTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol)
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 22)
            .frame(minHeight: 64)
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// wide neutral pill, the secondary action style.
struct SharkordSecondaryButton: View {
    let title: String
    let symbol: String
    var tint: Color = SharkordTheme.textPrimary
    var background: Color = SharkordTheme.field
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .foregroundStyle(tint)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// one call control pill: label plus glyph, coloured per state (accent on, danger off,
/// neutral disabled).
struct ControlPill: View {
    let title: String
    let symbol: String
    var background: Color = SharkordTheme.pillNeutral
    var foreground: Color = SharkordTheme.textPrimary
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))

                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(title)
    }
}

/// square exit button beside the call pills.
struct ExitButton: View {
    /// accessibility label, passed in by the app target so this file stays free of L10n
    /// (the live activity target compiles it too).
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(SharkordTheme.danger)
                .frame(width: 56, height: 56)
                .background(
                    SharkordTheme.dangerDeep,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// custom segmented pill: rounded track with a raised selected segment.
struct SegmentPill: View {
    let items: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let isSelected = index == selection

                Button {
                    selection = index
                } label: {
                    Text(items[index])
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? SharkordTheme.textPrimary : SharkordTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            isSelected
                                ? AnyShapeStyle(SharkordTheme.segmentActive)
                                : AnyShapeStyle(Color.clear),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(SharkordTheme.card, in: Capsule())
    }
}

/// centred empty state: outlined glyph, loud title, grey body.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let body_: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(SharkordTheme.textSecondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(SharkordTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(body_)
                .font(.subheadline)
                .foregroundStyle(SharkordTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
    }
}

/// circular initials avatar with a stable colour, so the same member keeps the same colour
/// across screens.
struct AvatarView: View {
    let name: String
    var diameter: CGFloat = 40
    var isSpeaking = false
    var imageURL: URL? = nil

    private var paletteIndex: Int {
        let sum = name.unicodeScalars.reduce(Int(0)) { $0 + Int($1.value) }
        return sum % avatarPalette.count
    }

    private var initials: String {
        String(name.prefix(1))
    }

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                if isSpeaking {
                    Circle()
                        .strokeBorder(SharkordTheme.success, lineWidth: 2)
                        .padding(-2)
                }
            }
            .accessibilityHidden(true)
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(avatarPalette[paletteIndex], in: Circle())
    }
}
