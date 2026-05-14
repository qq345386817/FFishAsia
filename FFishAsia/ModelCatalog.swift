import Foundation

enum ModelCategory: String, CaseIterable, Codable {
    case plant
    case animal
    case special

    func label(in language: AppLanguage) -> String {
        switch self {
        case .plant: return L10n.t("plant", language)
        case .animal: return L10n.t("animal", language)
        case .special: return L10n.t("special", language)
        }
    }

    func detailLabel(in language: AppLanguage) -> String {
        switch self {
        case .plant: return L10n.t("detail.category.plant", language)
        case .animal: return L10n.t("detail.category.animal", language)
        case .special: return L10n.t("detail.category.special", language)
        }
    }

    var symbolName: String {
        switch self {
        case .plant: return "leaf.fill"
        case .animal: return "pawprint.fill"
        case .special: return "sparkles"
        }
    }
}

struct ModelItem: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let englishName: String
    let localizedNameZhHans: String
    let localizedNameJa: String
    let localizedNameEn: String
    let scientificName: String
    let filename: String
    let taxonomicInfo: String
    let localizedTaxonomicInfoZhHans: String
    let localizedTaxonomicInfoJa: String
    let localizedTaxonomicInfoEn: String
    let fileSizeMB: Double
    let faceCount: Int
    let vertexCount: Int
    let sketchfabUID: String
    let hasAnimation: Bool
    let category: ModelCategory
    let downloadURL: URL?
    let thumbName: String
    let previewName: String

    var sketchfabURL: URL? {
        if !sketchfabUID.isEmpty {
            return URL(string: "https://sketchfab.com/3d-models/\(sketchfabUID)")
        }
        return downloadURL
    }

    var formattedSize: String {
        String(format: "%.1f MB", fileSizeMB)
    }

    var formattedFaces: String {
        NumberFormatter.localizedString(from: NSNumber(value: faceCount), number: .decimal)
    }

    var formattedVertices: String {
        NumberFormatter.localizedString(from: NSNumber(value: vertexCount), number: .decimal)
    }

    func localizedDisplayName(for language: AppLanguage) -> String {
        ModelNameLocalization.name(for: self, language: language)
    }

    func localizedSecondaryName(for language: AppLanguage) -> String? {
        ModelNameLocalization.secondaryName(for: self, language: language)
    }

    func localizedName(for language: AppLanguage) -> String? {
        switch language {
        case .zhHans:
            return localizedNameZhHans.ifNotEmpty
        case .ja:
            return localizedNameJa.ifNotEmpty
        case .en:
            return localizedNameEn.ifNotEmpty
        }
    }

    func localizedTaxonomicInfo(for language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return localizedTaxonomicInfoZhHans.ifNotEmpty ?? taxonomicInfo
        case .ja:
            return localizedTaxonomicInfoJa.ifNotEmpty ?? taxonomicInfo
        case .en:
            return localizedTaxonomicInfoEn.ifNotEmpty ?? taxonomicInfo
        }
    }

    func matches(keyword: String) -> Bool {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let normalizedQuery = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return ModelNameLocalization.searchableNames(for: self)
            .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
            .contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    init(
        id: String,
        displayName: String,
        englishName: String,
        localizedNameZhHans: String = "",
        localizedNameJa: String = "",
        localizedNameEn: String = "",
        scientificName: String,
        filename: String,
        taxonomicInfo: String,
        localizedTaxonomicInfoZhHans: String = "",
        localizedTaxonomicInfoJa: String = "",
        localizedTaxonomicInfoEn: String = "",
        fileSizeMB: Double,
        faceCount: Int,
        vertexCount: Int,
        sketchfabUID: String,
        hasAnimation: Bool,
        category: ModelCategory,
        downloadURL: URL?
    ) {
        self.id = id
        self.displayName = displayName
        self.englishName = englishName
        self.localizedNameZhHans = localizedNameZhHans
        self.localizedNameJa = localizedNameJa
        self.localizedNameEn = localizedNameEn
        self.scientificName = scientificName
        self.filename = filename
        self.taxonomicInfo = taxonomicInfo
        self.localizedTaxonomicInfoZhHans = localizedTaxonomicInfoZhHans
        self.localizedTaxonomicInfoJa = localizedTaxonomicInfoJa
        self.localizedTaxonomicInfoEn = localizedTaxonomicInfoEn
        self.fileSizeMB = fileSizeMB
        self.faceCount = faceCount
        self.vertexCount = vertexCount
        self.sketchfabUID = sketchfabUID
        self.hasAnimation = hasAnimation
        self.category = category
        self.downloadURL = downloadURL

        let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        self.thumbName = "\(baseName)_thumb.jpeg"
        self.previewName = "\(baseName)_preview.jpeg"
    }
}

private struct RemoteManifest: Decodable {
    let models: [RemoteManifestModel]
}

private struct RemoteManifestModel: Decodable {
    let id: String
    let filename: String
    let download_url: URL?
    let file_size_mb: Double?
    let category: String?
    let name_ja: String?
    let name_en: String?
    let name_zh_hans: String?
    let scientific_name: String?
    let taxonomic_info: String?
    let taxonomic_info_zh_hans: String?
    let taxonomic_info_ja: String?
    let taxonomic_info_en: String?
    let sketchfab_url: URL?
    let face_count: Int?
    let vertex_count: Int?
    let has_animation: Bool?
    let animations: Int?
}

struct ModelCatalog {
    static let manifestURL = URL(string: "https://pub-0154a542ca38442c855387e2736c8f19.r2.dev/manifest.json")!
    static let modelsBaseURL = URL(string: "https://pub-0154a542ca38442c855387e2736c8f19.r2.dev/models/")!
    static let fallbackModels: [ModelItem] = loadBundledManifestModels()

    static func decodeManifest(from data: Data) throws -> [ModelItem] {
        let manifest = try JSONDecoder().decode(RemoteManifest.self, from: data)
        return manifest.models.map { raw in
            let rawName = raw.name_ja ?? raw.name_en ?? raw.filename
            let displayName = nonEmpty(raw.name_ja) ?? parseDisplayName(from: rawName)
            let englishName = nonEmpty(raw.name_en) ?? parseEnglishName(from: rawName)
            let downloadURL = raw.download_url ?? modelsBaseURL.appendingPathComponent(raw.filename)
            let hasAnimation = raw.has_animation ?? ((raw.animations ?? 0) > 0)
            let taxonomy = cleanTaxonomicInfo(raw.taxonomic_info_ja ?? raw.taxonomic_info ?? raw.scientific_name ?? "")
            return ModelItem(
                id: raw.id,
                displayName: displayName,
                englishName: englishName,
                localizedNameZhHans: raw.name_zh_hans ?? "",
                localizedNameJa: raw.name_ja ?? displayName,
                localizedNameEn: raw.name_en ?? englishName,
                scientificName: raw.scientific_name ?? "",
                filename: raw.filename,
                taxonomicInfo: taxonomy,
                localizedTaxonomicInfoZhHans: cleanTaxonomicInfo(raw.taxonomic_info_zh_hans ?? raw.taxonomic_info ?? raw.scientific_name ?? ""),
                localizedTaxonomicInfoJa: cleanTaxonomicInfo(raw.taxonomic_info_ja ?? raw.taxonomic_info ?? raw.scientific_name ?? ""),
                localizedTaxonomicInfoEn: cleanTaxonomicInfo(raw.taxonomic_info_en ?? raw.taxonomic_info ?? raw.scientific_name ?? ""),
                fileSizeMB: raw.file_size_mb ?? 0,
                faceCount: raw.face_count ?? 0,
                vertexCount: raw.vertex_count ?? 0,
                sketchfabUID: raw.sketchfab_url?.lastPathComponent ?? raw.id,
                hasAnimation: hasAnimation,
                category: hasAnimation ? .special : parseCategory(from: raw.category),
                downloadURL: downloadURL
            )
        }
    }

    private static func loadBundledManifestModels() -> [ModelItem] {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let models = try? decodeManifest(from: data)
        else {
            print("⚠️ 无法加载 manifest.json")
            return []
        }

        return models
    }

    private static func parseDisplayName(from name: String) -> String {
        var cleaned = name
        if cleaned.hasPrefix("CC0 ") || cleaned.hasPrefix("CC0,") {
            cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        cleaned = cleaned.components(separatedBy: .symbols).joined()
        if let commaIndex = cleaned.firstIndex(of: ",") {
            return String(cleaned[..<commaIndex]).trimmingCharacters(in: .whitespaces)
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    private static func parseEnglishName(from name: String) -> String {
        if let commaIndex = name.firstIndex(of: ",") {
            return String(name[name.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
        }

        let cleaned = name
            .replacingOccurrences(of: "CC0", with: "")
            .components(separatedBy: .symbols)
            .joined(separator: " ")
        let pattern = #"[A-Za-z][A-Za-z0-9 .'-]*(?:[A-Za-z0-9])"#
        if let range = cleaned.range(of: pattern, options: .regularExpression) {
            return String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func parseScientificName(from description: String) -> String {
        let lines = description.components(separatedBy: .newlines)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            if lowercased.contains("license") || lowercased.contains("better model") || lowercased.contains("http") {
                continue
            }
            let pattern = #"\b([A-Z][a-z]+ [a-z]+(?: [a-z]+)?)\b"#
            if let range = trimmed.range(of: pattern, options: .regularExpression) {
                return String(trimmed[range])
            }
        }
        return ""
    }

    private static func cleanTaxonomicInfo(_ description: String) -> String {
        description
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "**", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lowercased = line.lowercased()
                if lowercased.hasPrefix("license:") { return false }
                if lowercased.hasPrefix("better model:") { return false }
                if lowercased.contains("http://") || lowercased.contains("https://") { return false }
                return true
            }
            .joined(separator: "\n")
    }

    private static func parseCategory(from source: String?) -> ModelCategory {
        let value = (source ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let animalKeywords = [
            "animal", "animalia", "amphibia", "mammalia", "aves", "reptilia", "actinopterygii",
            "arthropoda", "insecta", "mollusca", "cephalopoda", "fish", "frog", "octopus", "hornet",
            "crab", "shrimp", "butterfly", "bird", "蛙", "鱼", "魚", "鸟", "鳥", "蜂", "虫", "蟹", "虾", "蝦", "章鱼", "章魚", "タコ", "カエル", "ハチ"
        ]
        if animalKeywords.contains(where: value.contains) {
            return .animal
        }

        let plantKeywords = [
            "plant", "plantae", "magnoliophyta", "angiospermae", "flower", "tree", "leaf", "lotus",
            "rose", "cherry", "azalea", "hibiscus", "lily", "apricot", "wisteria",
            "花", "树", "樹", "植物", "葉", "莲", "蓮", "樱", "櫻", "梅", "藤", "百合", "桜", "サクラ", "ハス", "ツツジ", "ユリ", "フジ"
        ]
        if plantKeywords.contains(where: value.contains) {
            return .plant
        }

        return .special
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

private extension String {
    var ifNotEmpty: String? {
        isEmpty ? nil : self
    }
}
