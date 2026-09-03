import Foundation
import OSLog

actor ProductAnalyticsUploader {
    static let shared = ProductAnalyticsUploader()

    private static let endpoint = URL(string: "https://littlenature-api.luopeike.com/v1/events")!
    private static let installationIDKey = "littleNatureProductAnalytics.installationID"
    private static let queueKey = "littleNatureProductAnalytics.uploadQueue"
    private static let maximumQueueSize = 300
    private static let batchSize = 20
    private static let maximumEventAge: TimeInterval = 30 * 24 * 60 * 60

    private struct QueuedEvent: Codable, Sendable {
        let id: UUID
        let name: String
        let occurredAt: Date
        let properties: [String: String]

        init(_ event: ProductAnalyticsEvent) {
            id = UUID()
            name = event.name.rawValue
            occurredAt = event.timestamp
            properties = Dictionary(uniqueKeysWithValues: event.parameters.map { ($0.key.rawValue, $0.value) })
        }
    }

    private struct UploadContext: Encodable {
        let appVersion: String
        let buildNumber: String
        let platform: String
        let osVersion: String
        let locale: String
    }

    private struct UploadBatch: Encodable {
        let schemaVersion = 1
        let appID = "little-nature"
        let installationID: String
        let sessionID: String
        let context: UploadContext
        let events: [QueuedEvent]
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let endpoint: URL
    private let installationID: UUID
    private let sessionID = UUID()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.luopeike.FFishAsia",
        category: "ProductAnalyticsUpload"
    )
    private var queue: [QueuedEvent]
    private var scheduledFlush: Task<Void, Never>?
    private var isUploading = false
    private var consecutiveFailures = 0

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        endpoint: URL = ProductAnalyticsUploader.endpoint
    ) {
        self.defaults = defaults
        self.session = session
        self.endpoint = endpoint
        if let storedID = defaults.string(forKey: Self.installationIDKey),
           let parsedID = UUID(uuidString: storedID) {
            installationID = parsedID
        } else {
            let newID = UUID()
            installationID = newID
            defaults.set(newID.uuidString.lowercased(), forKey: Self.installationIDKey)
        }
        if let data = defaults.data(forKey: Self.queueKey),
           let storedQueue = try? Self.storageDecoder.decode([QueuedEvent].self, from: data) {
            let cutoff = Date().addingTimeInterval(-Self.maximumEventAge)
            queue = Array(storedQueue.filter { $0.occurredAt >= cutoff }.suffix(Self.maximumQueueSize))
        } else {
            queue = []
        }
    }

    @MainActor
    static func install() {
#if DEBUG
        return
#else
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("FFISH_SNAPSHOT_") }) else { return }
        guard ProcessInfo.processInfo.environment["FFISH_DISABLE_ANALYTICS"] != "1" else { return }
        ProductAnalytics.shared.installRemoteSink { event in
            Task { await ProductAnalyticsUploader.shared.enqueue(event) }
        }
        Task { await ProductAnalyticsUploader.shared.flush() }
#endif
    }

    func enqueue(_ event: ProductAnalyticsEvent) {
        queue.append(QueuedEvent(event))
        if queue.count > Self.maximumQueueSize {
            queue.removeFirst(queue.count - Self.maximumQueueSize)
        }
        persistQueue()
        scheduleFlush(after: queue.count >= Self.batchSize ? 0 : 5)
    }

    func flush() async {
#if DEBUG
        guard endpoint != Self.endpoint else { return }
#endif
        scheduledFlush?.cancel()
        scheduledFlush = nil
        let cutoff = Date().addingTimeInterval(-Self.maximumEventAge)
        queue.removeAll { $0.occurredAt < cutoff }
        persistQueue()
        guard !isUploading, !queue.isEmpty else { return }

        isUploading = true
        defer { isUploading = false }
        let events = Array(queue.prefix(Self.batchSize))
        do {
            let response = try await upload(events)
            switch response.statusCode {
            case 200..<300:
                remove(events)
                consecutiveFailures = 0
                if !queue.isEmpty { scheduleFlush(after: 0.25) }
            case 400..<500 where response.statusCode != 408 && response.statusCode != 429:
                logger.error("Discarding rejected analytics batch: HTTP \(response.statusCode)")
                remove(events)
            default:
                scheduleRetry()
            }
        } catch {
            logger.debug("Analytics upload deferred: \(error.localizedDescription)")
            scheduleRetry()
        }
    }

    private func upload(_ events: [QueuedEvent]) async throws -> HTTPURLResponse {
        let payload = UploadBatch(
            installationID: installationID.uuidString.lowercased(),
            sessionID: sessionID.uuidString.lowercased(),
            context: UploadContext(
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                platform: Self.platform,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
            ),
            events: events
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try Self.uploadEncoder.encode(payload)
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return response
    }

    private func remove(_ uploaded: [QueuedEvent]) {
        let ids = Set(uploaded.map(\.id))
        queue.removeAll { ids.contains($0.id) }
        persistQueue()
    }

    private func scheduleRetry() {
        consecutiveFailures = min(consecutiveFailures + 1, 8)
        scheduleFlush(after: min(pow(2, Double(consecutiveFailures)) * 5, 900))
    }

    private func scheduleFlush(after delay: TimeInterval) {
        guard scheduledFlush == nil else { return }
        scheduledFlush = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func persistQueue() {
        guard !queue.isEmpty else {
            defaults.removeObject(forKey: Self.queueKey)
            return
        }
        if let data = try? Self.storageEncoder.encode(queue) {
            defaults.set(data, forKey: Self.queueKey)
        }
    }

    private static var platform: String {
#if os(macOS)
        "macos"
#else
        "ios"
#endif
    }

    private static let storageEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let storageDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    private static let uploadEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
