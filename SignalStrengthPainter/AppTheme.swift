import SwiftUI

// MARK: - Appearance Preference

enum AppearanceMode: Int {
    case system = 0
    case light = 1
    case dark = 2

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Theme

struct AppTheme {
    let background: Color
    let cardFill: Color
    let cardStroke: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let quaternaryText: Color
    let canvasBackground: Color
    let canvasStroke: Color
    let divider: Color
    let buttonText: Color
    let subtle: Color

    static func resolved(for colorScheme: ColorScheme) -> AppTheme {
        colorScheme == .dark ? .dark : .light
    }

    static let dark = AppTheme(
        background: Color(red: 0.06, green: 0.06, blue: 0.08),
        cardFill: Color.white.opacity(0.04),
        cardStroke: Color.white.opacity(0.06),
        primaryText: .white,
        secondaryText: Color.white.opacity(0.6),
        tertiaryText: Color.white.opacity(0.45),
        quaternaryText: Color.white.opacity(0.25),
        canvasBackground: Color(red: 0.12, green: 0.12, blue: 0.14),
        canvasStroke: Color.white.opacity(0.18),
        divider: Color.white.opacity(0.06),
        buttonText: .white,
        subtle: Color.white.opacity(0.08)
    )

    static let light = AppTheme(
        background: Color(red: 0.95, green: 0.95, blue: 0.97),
        cardFill: Color.white,
        cardStroke: Color.black.opacity(0.08),
        primaryText: Color(red: 0.1, green: 0.1, blue: 0.12),
        secondaryText: Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.6),
        tertiaryText: Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.45),
        quaternaryText: Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.25),
        canvasBackground: Color(red: 0.92, green: 0.92, blue: 0.93),
        canvasStroke: Color.black.opacity(0.12),
        divider: Color.black.opacity(0.08),
        buttonText: .white,
        subtle: Color.black.opacity(0.05)
    )
}

// MARK: - Environment Key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .dark
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Theme-Providing View Modifier

struct ThemedRootModifier: ViewModifier {
    @AppStorage("appearanceMode") private var appearanceModeRaw: Int = AppearanceMode.system.rawValue
    @Environment(\.colorScheme) private var systemScheme

    private var mode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var effectiveScheme: ColorScheme {
        mode.colorScheme ?? systemScheme
    }

    func body(content: Content) -> some View {
        content
            .environment(\.theme, AppTheme.resolved(for: effectiveScheme))
            .preferredColorScheme(mode.colorScheme)
    }
}

extension View {
    func withAppTheme() -> some View {
        modifier(ThemedRootModifier())
    }
}
