import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var locale: Locale {
        resolvedLanguage.explicitLocale
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.string("Follow System")
        case .english:
            return L10n.string("English")
        case .simplifiedChinese:
            return L10n.string("Simplified Chinese")
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue) ?? .system
    }

    static var systemResolvedLanguage: AppLanguage {
        guard let preferredLanguage = Locale.preferredLanguages.first?.lowercased() else {
            return .english
        }

        return preferredLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    private var resolvedLanguage: AppLanguage {
        switch self {
        case .system:
            return Self.systemResolvedLanguage
        case .english, .simplifiedChinese:
            return self
        }
    }

    private var explicitLocale: Locale {
        switch self {
        case .system, .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }
}

enum L10n {
    static func string(_ key: String) -> String {
        localizedString(for: key, language: .current)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: localizedString(for: key, language: .current),
            locale: AppLanguage.current.locale,
            arguments: arguments
        )
    }

    private static func localizedString(for key: String, language: AppLanguage) -> String {
        let resolvedLanguage = language == .system ? AppLanguage.systemResolvedLanguage : language

        guard
            let path = Bundle.main.path(forResource: resolvedLanguage.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        }

        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
