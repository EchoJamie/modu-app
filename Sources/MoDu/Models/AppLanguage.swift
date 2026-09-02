import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    nonisolated static let storageKey = "appLanguage.v1"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: L10n.string(.languageSystem)
        case .english: L10n.string(.languageEnglish)
        case .simplifiedChinese: L10n.string(.languageSimplifiedChinese)
        }
    }

    var resolvedLocalization: String {
        switch self {
        case .system:
            Bundle.preferredLocalizations(
                from: L10n.supportedLanguages,
                forPreferences: Locale.preferredLanguages
            ).first ?? "en"
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        }
    }

    static func restored(from defaults: UserDefaults = .standard) -> AppLanguage {
        guard
            let rawValue = defaults.string(forKey: storageKey),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return .system
        }
        return language
    }
}
