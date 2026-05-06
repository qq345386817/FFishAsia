import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case ja = "ja"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        case .en: return "English"
        }
    }

    var localeIdentifier: String { rawValue }

    static var preferred: AppLanguage {
        let preferredIdentifiers = Locale.preferredLanguages.map { $0.lowercased() }
        if preferredIdentifiers.contains(where: { $0.hasPrefix("zh-hans") || $0.hasPrefix("zh-cn") || $0 == "zh" }) {
            return .zhHans
        }
        if preferredIdentifiers.contains(where: { $0.hasPrefix("ja") }) {
            return .ja
        }
        return .en
    }
}

enum L10n {
    static func t(_ key: String, _ language: AppLanguage, _ arguments: CVarArg...) -> String {
        let format = localizedFormat(for: key, language: language)
        return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    private static func localizedFormat(for key: String, language: AppLanguage) -> String {
        if let value = localizedString(for: key, language: language) {
            return value
        }
        if language != .en, let value = localizedString(for: key, language: .en) {
            return value
        }
        return key
    }

    private static func localizedString(for key: String, language: AppLanguage) -> String? {
        let bundle = localizedBundles[language] ?? Bundle.main
        let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        return value == key ? nil : value
    }

    private static let localizedBundles: [AppLanguage: Bundle] = {
        Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { language in
            let bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
                .flatMap(Bundle.init(path:)) ?? Bundle.main
            return (language, bundle)
        })
    }()
}

enum ModelNameLocalization {
    static func name(for model: ModelItem, language: AppLanguage) -> String {
        model.localizedName(for: language) ?? fallbackName(for: model, language: language)
    }

    static func secondaryName(for model: ModelItem, language: AppLanguage) -> String? {
        switch language {
        case .zhHans:
            return model.localizedName(for: .en) ?? model.englishName.ifNotEmpty ?? model.displayName
        case .ja:
            return model.localizedName(for: .en) ?? model.englishName.ifNotEmpty
        case .en:
            return model.localizedName(for: .ja) ?? (model.displayName.isEmpty ? nil : model.displayName)
        }
    }

    static func searchableNames(for model: ModelItem) -> [String] {
        var names = [model.displayName, model.englishName, model.scientificName, model.taxonomicInfo]
        for language in AppLanguage.allCases {
            if let name = model.localizedName(for: language) {
                names.append(name)
            }
        }
        return names
    }

    private static func fallbackName(for model: ModelItem, language: AppLanguage) -> String {
        switch language {
        case .zhHans, .en:
            return model.englishName.ifNotEmpty ?? model.displayName
        case .ja:
            return model.displayName
        }
    }
}

private extension String {
    var ifNotEmpty: String? {
        isEmpty ? nil : self
    }
}
