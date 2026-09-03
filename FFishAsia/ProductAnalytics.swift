import Foundation
import OSLog

struct ProductAnalyticsEvent: Equatable, Sendable {
    enum Name: String, Sendable {
        case firstOpen = "first_open"
        case appOpen = "app_open"
        case onboardingComplete = "onboarding_complete"
        case catalogView = "catalog_view"
        case modelDetailOpen = "model_detail_open"
        case modelDownloadStart = "model_download_start"
        case modelDownloadComplete = "model_download_complete"
        case previewStart = "preview_start"
        case arStart = "ar_start"
        case reviewPromptRequested = "review_prompt_requested"
    }

    enum Parameter: String, Sendable {
        case modelID = "model_id"
        case category
        case animated
        case bundled
    }

    let name: Name
    let parameters: [Parameter: String]
    let timestamp: Date
}

@MainActor
final class ProductAnalytics {
    typealias RemoteSink = @MainActor (ProductAnalyticsEvent) -> Void

    static let shared = ProductAnalytics()

    private enum Key {
        static let prefix = "littleNatureProductAnalytics"
        static let didRecordFirstOpen = "\(prefix).didRecordFirstOpen"
        static let previewedModelIDs = "\(prefix).previewedModelIDs"
        static let reviewRequestedVersions = "\(prefix).reviewRequestedVersions"
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let version: () -> String
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.luopeike.FFishAsia",
        category: "ProductAnalytics"
    )
    private var remoteSink: RemoteSink?
    private var previewedThisSession: Set<String> = []

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        version: @escaping () -> String = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        },
        remoteSink: RemoteSink? = nil
    ) {
        self.defaults = defaults
        self.now = now
        self.version = version
        self.remoteSink = remoteSink
    }

    func installRemoteSink(_ sink: RemoteSink?) {
        remoteSink = sink
    }

    func recordAppOpen() {
        if !defaults.bool(forKey: Key.didRecordFirstOpen) {
            defaults.set(true, forKey: Key.didRecordFirstOpen)
            track(.firstOpen)
        }
        track(.appOpen)
    }

    func track(
        _ name: ProductAnalyticsEvent.Name,
        model: ModelItem? = nil,
        bundled: Bool = false
    ) {
        var parameters: [ProductAnalyticsEvent.Parameter: String] = [:]
        if let model {
            parameters = [
                .modelID: model.id,
                .category: model.category.rawValue,
                .animated: model.hasAnimation ? "1" : "0",
                .bundled: bundled ? "1" : "0"
            ]
        }
        let event = ProductAnalyticsEvent(name: name, parameters: parameters, timestamp: now())
        logger.debug("event=\(name.rawValue)")
        remoteSink?(event)
    }

    func recordSuccessfulPreview(model: ModelItem, bundled: Bool) -> Bool {
        guard previewedThisSession.insert(model.id).inserted else { return false }
        track(.previewStart, model: model, bundled: bundled)

        var previewedModelIDs = Set(defaults.array(forKey: Key.previewedModelIDs) as? [String] ?? [])
        previewedModelIDs.insert(model.id)
        defaults.set(Array(previewedModelIDs.sorted().suffix(30)), forKey: Key.previewedModelIDs)

        return previewedModelIDs.count >= 2 && !reviewRequestedVersions.contains(version())
    }

    func markReviewPromptRequested() {
        var versions = reviewRequestedVersions
        versions.insert(version())
        defaults.set(Array(versions).sorted(), forKey: Key.reviewRequestedVersions)
        track(.reviewPromptRequested)
    }

    private var reviewRequestedVersions: Set<String> {
        Set(defaults.array(forKey: Key.reviewRequestedVersions) as? [String] ?? [])
    }
}
