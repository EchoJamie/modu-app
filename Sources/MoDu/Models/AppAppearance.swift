import SwiftUI

/// 主题的明暗模式。名称保留为 `AppAppearance`，以兼容已有偏好键和值。
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: L10n.string(.appearanceSystem)
        case .light: L10n.string(.appearanceLight)
        case .dark: L10n.string(.appearanceDark)
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resolvesDark(systemColorScheme: ColorScheme) -> Bool {
        switch self {
        case .system: systemColorScheme == .dark
        case .light: false
        case .dark: true
        }
    }
}
