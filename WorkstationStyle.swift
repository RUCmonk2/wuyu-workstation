import AppKit
import SwiftUI

enum WorkstationAppearance: String, CaseIterable, Identifiable {
    static let preferenceKey = "workstation.appearance"

    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "日间"
        case .dark: "夜间"
        }
    }

    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func saved(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .dark
    }
}

enum WorkstationContrast: String, CaseIterable, Identifiable {
    static let preferenceKey = "workstation.contrast"
    case standard, high

    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: "标准"
        case .high: "高对比"
        }
    }
}

struct ThemeTriplet: Equatable, Sendable {
    let background: UInt32
    let foreground: UInt32
    let accent: UInt32
}

enum WorkstationThemePreset: String, CaseIterable, Identifiable, Sendable {
    static let preferenceKey = "workstation.themePreset"

    case `default` = "default"
    case gruvboxMaterial = "gruvbox_material"
    case catppuccin = "catppuccin"
    case dracula = "dracula"
    case everforest = "everforest"
    case monokai = "monokai"
    case nord = "nord"
    case oneDarkPro = "one_dark_pro"
    case tokyoNight = "tokyo_night"
    case solarized = "solarized"
    case vesper = "vesper"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: "Default"
        case .gruvboxMaterial: "Gruvbox Material"
        case .catppuccin: "Catppuccin"
        case .dracula: "Dracula"
        case .everforest: "Everforest"
        case .monokai: "Monokai"
        case .nord: "Nord"
        case .oneDarkPro: "One Dark Pro"
        case .tokyoNight: "Tokyo Night"
        case .solarized: "Solarized"
        case .vesper: "Vesper"
        }
    }

    func triplet(dark: Bool) -> ThemeTriplet {
        if dark {
            switch self {
            case .default:
                ThemeTriplet(background: 0x13141A, foreground: 0xF0F1F7, accent: 0x8E9BFF)
            case .gruvboxMaterial:
                ThemeTriplet(background: 0x141617, foreground: 0xD4BE98, accent: 0xE78A4E)
            case .catppuccin:
                ThemeTriplet(background: 0x1E1E2E, foreground: 0xCDD6F4, accent: 0xCBA6F7)
            case .dracula:
                ThemeTriplet(background: 0x282A36, foreground: 0xF8F8F2, accent: 0xBD93F9)
            case .everforest:
                ThemeTriplet(background: 0x232A2E, foreground: 0xD3C6AA, accent: 0xA7C080)
            case .monokai:
                ThemeTriplet(background: 0x22231E, foreground: 0xF8F8F2, accent: 0xFD971F)
            case .nord:
                ThemeTriplet(background: 0x242933, foreground: 0xECEFF4, accent: 0x88C0D0)
            case .oneDarkPro:
                ThemeTriplet(background: 0x21252B, foreground: 0xABB2BF, accent: 0x61AFEF)
            case .tokyoNight:
                ThemeTriplet(background: 0x1A1B26, foreground: 0xC0CAF5, accent: 0x7AA2F7)
            case .solarized:
                ThemeTriplet(background: 0x002B36, foreground: 0x93A1A1, accent: 0x268BD2)
            case .vesper:
                ThemeTriplet(background: 0x101010, foreground: 0xF2F2F2, accent: 0xFFC799)
            }
        } else {
            switch self {
            case .default:
                ThemeTriplet(background: 0xF8F8FB, foreground: 0x1E1F2A, accent: 0x5654D1)
            case .gruvboxMaterial:
                ThemeTriplet(background: 0xF9F5D7, foreground: 0x4F3829, accent: 0xC35E0A)
            case .catppuccin:
                ThemeTriplet(background: 0xEFF1F5, foreground: 0x4C4F69, accent: 0x8839EF)
            case .dracula:
                ThemeTriplet(background: 0xF8F8FA, foreground: 0x282A36, accent: 0x7C52D9)
            case .everforest:
                ThemeTriplet(background: 0xFDF6E3, foreground: 0x5C6A72, accent: 0x7F9A00)
            case .monokai:
                ThemeTriplet(background: 0xFAFAFA, foreground: 0x272822, accent: 0xD97706)
            case .nord:
                ThemeTriplet(background: 0xECEFF4, foreground: 0x2E3440, accent: 0x5E81AC)
            case .oneDarkPro:
                ThemeTriplet(background: 0xFAFAFA, foreground: 0x383A42, accent: 0x4078F2)
            case .tokyoNight:
                ThemeTriplet(background: 0xE6E7ED, foreground: 0x343B58, accent: 0x2E7DE9)
            case .solarized:
                ThemeTriplet(background: 0xFDF6E3, foreground: 0x586E75, accent: 0x268BD2)
            case .vesper:
                ThemeTriplet(background: 0xF7F6F4, foreground: 0x171717, accent: 0xC6783A)
            }
        }
    }
}

struct RGBColor: Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255.0
        g = Double((hex >> 8) & 0xFF) / 255.0
        b = Double(hex & 0xFF) / 255.0
    }

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    init?(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let val = UInt32(cleaned, radix: 16) else { return nil }
        self.init(hex: val)
    }

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.r = Double(converted.redComponent)
        self.g = Double(converted.greenComponent)
        self.b = Double(converted.blueComponent)
    }

    var hexString: String {
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    var color: Color {
        Color(red: r, green: g, blue: b)
    }

    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    func blended(with other: RGBColor, amount: Double) -> RGBColor {
        let t = min(max(amount, 0), 1)
        return RGBColor(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t
        )
    }
}

@MainActor
final class WorkstationThemeStore: ObservableObject {
    static let customBgKey = "workstation.custom.backgroundHex"
    static let customFgKey = "workstation.custom.foregroundHex"
    static let customAccentKey = "workstation.custom.accentHex"

    @Published var appearance: WorkstationAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: WorkstationAppearance.preferenceKey)
            NSApplication.shared.appearance = appearance.nativeAppearance
        }
    }

    @Published var preset: WorkstationThemePreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: WorkstationThemePreset.preferenceKey)
        }
    }

    @Published var contrast: WorkstationContrast {
        didSet {
            UserDefaults.standard.set(contrast.rawValue, forKey: WorkstationContrast.preferenceKey)
        }
    }

    @Published var fontPercent: Int {
        didSet {
            let norm = WorkstationTextSize.normalized(fontPercent)
            if fontPercent != norm {
                fontPercent = norm
                return
            }
            UserDefaults.standard.set(norm, forKey: WorkstationTextSize.preferenceKey)
        }
    }

    @Published var customBackgroundHex: String {
        didSet { UserDefaults.standard.set(customBackgroundHex, forKey: Self.customBgKey) }
    }

    @Published var customForegroundHex: String {
        didSet { UserDefaults.standard.set(customForegroundHex, forKey: Self.customFgKey) }
    }

    @Published var customAccentHex: String {
        didSet { UserDefaults.standard.set(customAccentHex, forKey: Self.customAccentKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.appearance = WorkstationAppearance.saved(in: defaults)
        let savedPreset = defaults.string(forKey: WorkstationThemePreset.preferenceKey)
            .flatMap(WorkstationThemePreset.init(rawValue:)) ?? .gruvboxMaterial
        self.preset = savedPreset
        self.contrast = defaults.string(forKey: WorkstationContrast.preferenceKey)
            .flatMap(WorkstationContrast.init(rawValue:)) ?? .standard
        let savedFont = defaults.object(forKey: WorkstationTextSize.preferenceKey) as? Int ?? WorkstationTextSize.standard
        self.fontPercent = WorkstationTextSize.normalized(savedFont)
        self.customBackgroundHex = defaults.string(forKey: Self.customBgKey) ?? ""
        self.customForegroundHex = defaults.string(forKey: Self.customFgKey) ?? ""
        self.customAccentHex = defaults.string(forKey: Self.customAccentKey) ?? ""
    }

    var hasCustomOverrides: Bool {
        !customBackgroundHex.isEmpty || !customForegroundHex.isEmpty || !customAccentHex.isEmpty
    }

    func selectPreset(_ newPreset: WorkstationThemePreset) {
        preset = newPreset
        clearCustomOverrides()
    }

    func clearCustomOverrides() {
        customBackgroundHex = ""
        customForegroundHex = ""
        customAccentHex = ""
    }

    func effectiveRGB(for scheme: ColorScheme) -> (bg: RGBColor, fg: RGBColor, accent: RGBColor, isDark: Bool) {
        let isDark: Bool = switch appearance {
        case .dark: true
        case .light: false
        case .system: scheme == .dark
        }
        let base = preset.triplet(dark: isDark)
        let bg = RGBColor(hexString: customBackgroundHex) ?? RGBColor(hex: base.background)
        let fg = RGBColor(hexString: customForegroundHex) ?? RGBColor(hex: base.foreground)
        let accent = RGBColor(hexString: customAccentHex) ?? RGBColor(hex: base.accent)
        return (bg, fg, accent, isDark)
    }

    func palette(for scheme: ColorScheme) -> WorkstationPalette {
        let resolved = effectiveRGB(for: scheme)
        return WorkstationPalette(
            bg: resolved.bg,
            fg: resolved.fg,
            accent: resolved.accent,
            dark: resolved.isDark,
            highContrast: contrast == .high
        )
    }
}

enum WorkstationTextSize {
    static let preferenceKey = "workstation.fontPercent"
    static let standard = 100
    static let range = 85...135
    static let step = 5

    static func normalized(_ percent: Int) -> Int {
        let clamped = min(max(percent, range.lowerBound), range.upperBound)
        return ((clamped + step / 2) / step) * step
    }

    static func scale(for percent: Int) -> CGFloat {
        CGFloat(normalized(percent)) / 100
    }
}

private struct WorkstationTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var workstationTextScale: CGFloat {
        get { self[WorkstationTextScaleKey.self] }
        set { self[WorkstationTextScaleKey.self] = newValue }
    }
}

extension View {
    func workstationFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(WorkstationFont(size: size, weight: weight))
    }
}

private struct WorkstationFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    @Environment(\.workstationTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight))
    }
}

struct ClientGlyph: View {
    let client: Client?
    let size: CGFloat

    var body: some View {
        Group {
            switch client {
            case .codex:
                outline(Self.cloudTerminal)
            case .antigravity:
                outline(Self.arch)
            case .gemini:
                outline(Self.sparkle)
            case .claude:
                outline(Self.sunburst)
            case nil:
                Image(systemName: "tray.full")
                    .font(.system(size: size * 0.88, weight: .medium))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func outline(_ path: Path) -> some View {
        let scale = size / 16
        return path
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .stroke(style: StrokeStyle(lineWidth: 1.35 * scale, lineCap: .round, lineJoin: .round))
    }

    private static let cloudTerminal = Path { path in
        path.move(to: CGPoint(x: 4.4, y: 12.9))
        path.addCurve(to: CGPoint(x: 1.7, y: 10.2), control1: CGPoint(x: 2.9, y: 12.9), control2: CGPoint(x: 1.7, y: 11.7))
        path.addCurve(to: CGPoint(x: 3.6, y: 7.6), control1: CGPoint(x: 1.7, y: 9), control2: CGPoint(x: 2.5, y: 7.9))
        path.addCurve(to: CGPoint(x: 7.5, y: 3.4), control1: CGPoint(x: 3.7, y: 5.2), control2: CGPoint(x: 5.4, y: 3.4))
        path.addCurve(to: CGPoint(x: 11.2, y: 5.7), control1: CGPoint(x: 9.2, y: 3.4), control2: CGPoint(x: 10.5, y: 4.4))
        path.addCurve(to: CGPoint(x: 14.3, y: 9), control1: CGPoint(x: 12.9, y: 5.6), control2: CGPoint(x: 14.3, y: 7.1))
        path.addCurve(to: CGPoint(x: 10.9, y: 12.9), control1: CGPoint(x: 14.3, y: 11.1), control2: CGPoint(x: 12.8, y: 12.9))
        path.closeSubpath()

        path.move(to: CGPoint(x: 5.2, y: 7.6))
        path.addLine(to: CGPoint(x: 6.9, y: 9))
        path.addLine(to: CGPoint(x: 5.2, y: 10.4))
        path.move(to: CGPoint(x: 8.5, y: 10.4))
        path.addLine(to: CGPoint(x: 10.7, y: 10.4))
    }

    private static let arch = Path { path in
        path.move(to: CGPoint(x: 2.0, y: 13.0))
        path.addCurve(to: CGPoint(x: 8.0, y: 3.0), control1: CGPoint(x: 4.8, y: 10.8), control2: CGPoint(x: 5.4, y: 3.0))
        path.addCurve(to: CGPoint(x: 14.0, y: 13.0), control1: CGPoint(x: 10.6, y: 3.0), control2: CGPoint(x: 11.2, y: 10.8))
    }

    private static let sparkle = Path { path in
        path.move(to: CGPoint(x: 8, y: 1.6))
        path.addQuadCurve(to: CGPoint(x: 14.4, y: 8), control: CGPoint(x: 9.2, y: 6.8))
        path.addQuadCurve(to: CGPoint(x: 8, y: 14.4), control: CGPoint(x: 9.2, y: 9.2))
        path.addQuadCurve(to: CGPoint(x: 1.6, y: 8), control: CGPoint(x: 6.8, y: 9.2))
        path.addQuadCurve(to: CGPoint(x: 8, y: 1.6), control: CGPoint(x: 6.8, y: 6.8))
        path.closeSubpath()
    }

    private static let sunburst = Path { path in
        let cx = 8.0
        let cy = 8.0
        for i in 0..<8 {
            let angle = Double(i) * (.pi / 4.0)
            let x1 = cx + cos(angle) * 2.1
            let y1 = cy + sin(angle) * 2.1
            let x2 = cx + cos(angle) * 6.0
            let y2 = cy + sin(angle) * 6.0
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
        }
    }
}

struct WorkstationPalette: Sendable {
    private let bg: RGBColor
    private let fg: RGBColor
    private let acc: RGBColor
    private let dark: Bool
    private let highContrast: Bool

    init(bg: RGBColor, fg: RGBColor, accent: RGBColor, dark: Bool, highContrast: Bool = false) {
        self.bg = bg
        self.fg = fg
        self.acc = accent
        self.dark = dark
        self.highContrast = highContrast
    }

    private var liftTarget: RGBColor { dark ? RGBColor(hex: 0xFFFFFF) : RGBColor(hex: 0x000000) }
    private var white: RGBColor { RGBColor(hex: 0xFFFFFF) }
    private var black: RGBColor { RGBColor(hex: 0x111214) }

    var canvas: Color { bg.color }
    var sidebar: Color {
        dark ? bg.blended(with: liftTarget, amount: highContrast ? 0.045 : 0.032).color
             : bg.blended(with: fg, amount: 0.042).color
    }
    var surface: Color {
        dark ? bg.blended(with: liftTarget, amount: highContrast ? 0.085 : 0.062).color
             : bg.blended(with: white, amount: 0.72).color
    }
    var codeSurface: Color {
        dark ? bg.blended(with: black, amount: 0.34).color
             : bg.blended(with: fg, amount: 0.055).color
    }
    var field: Color {
        dark ? bg.blended(with: liftTarget, amount: 0.038).color
             : bg.blended(with: white, amount: 0.55).color
    }
    var line: Color {
        let amt = highContrast ? (dark ? 0.22 : 0.22) : (dark ? 0.13 : 0.13)
        return bg.blended(with: fg, amount: amt).color
    }
    var selected: Color {
        bg.blended(with: acc, amount: dark ? 0.24 : 0.17).color
    }
    var hover: Color {
        bg.blended(with: fg, amount: dark ? 0.095 : 0.075).color
    }
    var ink: Color {
        highContrast ? fg.blended(with: dark ? white : black, amount: 0.22).color : fg.color
    }
    var muted: Color {
        fg.blended(with: bg, amount: highContrast ? 0.20 : 0.30).color
    }
    var quiet: Color {
        fg.blended(with: bg, amount: highContrast ? 0.36 : 0.46).color
    }
    var accent: Color { acc.color }
    var accentText: Color {
        acc.relativeLuminance > 0.36 ? Color(red: 0.08, green: 0.09, blue: 0.10) : Color.white
    }
    var accentWash: Color {
        bg.blended(with: acc, amount: dark ? 0.20 : 0.14).color
    }
    var success: Color { tone(0x1E8750, 0x7EC699) }
    var successWash: Color { bg.blended(with: RGBColor(hex: dark ? 0x7EC699 : 0x1E8750), amount: dark ? 0.18 : 0.13).color }
    var warning: Color { tone(0xC26A1A, 0xE7A45B) }
    var warningWash: Color { bg.blended(with: RGBColor(hex: dark ? 0xE7A45B : 0xC26A1A), amount: dark ? 0.20 : 0.14).color }
    var danger: Color { tone(0xB82E4C, 0xEA7A89) }

    func clientColor(_ client: Client?) -> Color {
        switch client {
        case .codex: tone(0x4F5AE6, 0x8BA0FF)
        case .antigravity: tone(0x7647D4, 0xC29CFF)
        case .gemini: tone(0x1E7AE6, 0x6DB8FF)
        case .claude: tone(0xD65D3B, 0xEF8D6B)
        case nil: accent
        }
    }

    func clientWash(_ client: Client?) -> Color {
        switch client {
        case .codex: bg.blended(with: RGBColor(hex: dark ? 0x8BA0FF : 0x4F5AE6), amount: dark ? 0.20 : 0.13).color
        case .antigravity: bg.blended(with: RGBColor(hex: dark ? 0xC29CFF : 0x7647D4), amount: dark ? 0.20 : 0.13).color
        case .gemini: bg.blended(with: RGBColor(hex: dark ? 0x6DB8FF : 0x1E7AE6), amount: dark ? 0.20 : 0.13).color
        case .claude: bg.blended(with: RGBColor(hex: dark ? 0xEF8D6B : 0xD65D3B), amount: dark ? 0.20 : 0.13).color
        case nil: accentWash
        }
    }

    func statusColor(_ status: PacketStatus) -> Color {
        switch status {
        case .open: accent
        case .inProgress: warning
        case .replied: tone(0x1E7AE6, 0x6DB8FF)
        case .done: success
        case .archived: quiet
        }
    }

    private func tone(_ light: UInt32, _ darkHex: UInt32) -> Color {
        RGBColor(hex: self.dark ? darkHex : light).color
    }
}

private struct WorkstationPaletteKey: EnvironmentKey {
    static let defaultValue = WorkstationPalette(
        bg: RGBColor(hex: 0x141617),
        fg: RGBColor(hex: 0xD4BE98),
        accent: RGBColor(hex: 0xE78A4E),
        dark: true
    )
}

extension EnvironmentValues {
    var workstationPalette: WorkstationPalette {
        get { self[WorkstationPaletteKey.self] }
        set { self[WorkstationPaletteKey.self] = newValue }
    }
}

struct VisualEffectGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct WorkstationButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, quiet, subtleDanger }

    let role: Role
    let compact: Bool

    init(_ role: Role = .secondary, compact: Bool = false) {
        self.role = role
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        Appearance(configuration: configuration, role: role, compact: compact)
    }

    private struct Appearance: View {
        let configuration: Configuration
        let role: Role
        let compact: Bool

        @Environment(\.workstationPalette) private var palette
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        private var fill: Color {
            switch role {
            case .primary: palette.accent.opacity(hovered ? 0.88 : 1)
            case .secondary: hovered ? palette.hover : palette.surface
            case .quiet: hovered ? palette.hover : .clear
            case .subtleDanger: hovered ? palette.danger.opacity(0.16) : .clear
            }
        }

        private var foreground: Color {
            switch role {
            case .primary: palette.accentText
            case .subtleDanger: palette.danger
            case .secondary, .quiet: palette.ink
            }
        }

        var body: some View {
            configuration.label
                .workstationFont(compact ? 11.5 : 12, weight: .medium)
                .foregroundStyle(foreground)
                .padding(.horizontal, compact ? 9 : 11)
                .frame(minHeight: compact ? 27 : 31)
                .background(fill, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(role == .secondary ? palette.line : .clear)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.42)
                .onHover { hovered = $0 }
        }
    }
}
