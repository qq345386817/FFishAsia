import Foundation
import SwiftUI

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(message: String)
    }

    enum ToastStyle {
        case success
        case info
        case error

        var iconName: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .info: return "arrow.down.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .info: return .accentColor
            case .error: return .red
            }
        }
    }

    struct ToastMessage: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: ToastStyle
    }

    @Published var remoteModels: [ModelItem] = ModelCatalog.fallbackModels
    @Published var downloadStates: [String: DownloadState] = [:]
    @Published var totalCacheSizeMB: Double = 0
    @Published var toast: ToastMessage?
    var currentLanguage: AppLanguage = .preferred

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private var activeDownloads: [Int: ModelItem] = [:]
    private var activeTaskByModelID: [String: Int] = [:]
    private let fileManager = FileManager.default

    private override init() {
        super.init()
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        syncDownloadStates()
        refreshCacheStats()
    }

    private var modelsDirectory: URL {
        Self.modelsDirectoryURL
    }

    private var snapshotDownloadedModelIDs: Set<String> {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("FFISH_SNAPSHOT_SEEDED_DOWNLOADS=true") else {
            return []
        }

        if let value = arguments.first(where: { $0.hasPrefix("FFISH_SNAPSHOT_DOWNLOADED_MODEL_IDS=") })?
            .split(separator: "=", maxSplits: 1)
            .last {
            return Set(value.split(separator: ",").map(String.init))
        }

        return Set(remoteModels.prefix(3).map(\.id))
    }

    private nonisolated static var modelsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FFishAsia", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    func refreshManifest() {
        let url = ModelCatalog.manifestURL
        let task = session.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    print("⚠️ manifest 下载失败: \(error.localizedDescription)")
                    self.remoteModels = ModelCatalog.fallbackModels
                    self.syncDownloadStates()
                    return
                }

                guard let data else {
                    self.remoteModels = ModelCatalog.fallbackModels
                    self.syncDownloadStates()
                    return
                }

                do {
                    self.remoteModels = try ModelCatalog.decodeManifest(from: data)
                } catch {
                    print("⚠️ manifest 解析失败: \(error.localizedDescription)")
                    self.remoteModels = ModelCatalog.fallbackModels
                }
                self.syncDownloadStates()
                self.refreshCacheStats()
            }
        }
        task.resume()
    }

    func localURL(for model: ModelItem) -> URL? {
        let url = modelsDirectory.appendingPathComponent(model.filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(_ model: ModelItem) -> Bool {
        localURL(for: model) != nil || snapshotDownloadedModelIDs.contains(model.id)
    }

    func download(_ model: ModelItem) {
        guard !isDownloaded(model) else {
            downloadStates[model.id] = .downloaded
            presentToast(L10n.t("toast.alreadyLocal", currentLanguage, model.localizedDisplayName(for: currentLanguage)), style: .info)
            return
        }
        guard activeTaskByModelID[model.id] == nil else {
            return
        }
        if case .downloading = downloadStates[model.id] {
            return
        }

        guard let remoteURL = model.downloadURL else {
            downloadStates[model.id] = .failed(message: L10n.t("toast.invalidURL", currentLanguage))
            presentToast(L10n.t("toast.downloadFailed", currentLanguage, model.localizedDisplayName(for: currentLanguage)), style: .error)
            return
        }

        let task = session.downloadTask(with: remoteURL)
        task.taskDescription = model.filename
        activeDownloads[task.taskIdentifier] = model
        activeTaskByModelID[model.id] = task.taskIdentifier
        downloadStates[model.id] = .downloading(progress: 0)
        presentToast(L10n.t("toast.startDownload", currentLanguage, model.localizedDisplayName(for: currentLanguage)), style: .info)
        task.resume()
    }

    func retry(_ model: ModelItem) {
        if case .failed = downloadStates[model.id] {
            downloadStates[model.id] = .notDownloaded
        }
        download(model)
    }

    func delete(_ model: ModelItem) {
        let url = modelsDirectory.appendingPathComponent(model.filename)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        downloadStates[model.id] = .notDownloaded
        refreshCacheStats()
        presentToast(L10n.t("toast.deleted", currentLanguage, model.localizedDisplayName(for: currentLanguage)), style: .success)
    }

    func deleteAll() {
        let models = downloadedModels()
        for model in models {
            let url = modelsDirectory.appendingPathComponent(model.filename)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            downloadStates[model.id] = .notDownloaded
        }
        refreshCacheStats()
        if models.isEmpty {
            presentToast(L10n.t("toast.noDownloadsToDelete", currentLanguage), style: .info)
        } else {
            presentToast(L10n.t("toast.deletedAll", currentLanguage), style: .success)
        }
    }

    func refreshCacheStats() {
        let downloadedModels = remoteModels.filter(isDownloaded)
        let injectedModelIDs = snapshotDownloadedModelIDs
        let totalBytes = downloadedModels.reduce(Int64(0)) { partial, model in
            if injectedModelIDs.contains(model.id) {
                return partial + Int64(model.fileSizeMB * 1_048_576)
            }
            let url = modelsDirectory.appendingPathComponent(model.filename)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return partial + Int64(values?.fileSize ?? 0)
        }
        totalCacheSizeMB = Double(totalBytes) / 1_048_576
        syncDownloadStates()
    }

    func fileSizeMB(for model: ModelItem) -> Double {
        guard let url = localURL(for: model),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return model.fileSizeMB
        }
        return Double(fileSize) / 1_048_576
    }

    func downloadedModels() -> [ModelItem] {
        remoteModels.filter(isDownloaded)
    }

    func downloadingModels() -> [ModelItem] {
        remoteModels.filter { model in
            if case .downloading = downloadStates[model.id] {
                return true
            }
            return false
        }
    }

    func formattedFileSize(for model: ModelItem) -> String {
        String(format: "%.1f MB", fileSizeMB(for: model))
    }

    private func syncDownloadStates() {
        for model in remoteModels {
            if case .downloading = downloadStates[model.id] {
                continue
            }
            if isDownloaded(model) {
                downloadStates[model.id] = .downloaded
            } else if case .failed = downloadStates[model.id] {
                continue
            } else {
                downloadStates[model.id] = .notDownloaded
            }
        }
    }

    private func presentToast(_ message: String, style: ToastStyle) {
        toast = ToastMessage(message: message, style: style)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [weak self] in
            guard let self, let model = self.activeDownloads[downloadTask.taskIdentifier] else { return }
            self.downloadStates[model.id] = .downloading(progress: progress)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskID = downloadTask.taskIdentifier
        let filename = downloadTask.taskDescription ?? UUID().uuidString
        let destination = Self.modelsDirectoryURL.appendingPathComponent(filename)
        let moveResult: Result<Void, Error>

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(at: Self.modelsDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destination)
            moveResult = .success(())
        } catch {
            moveResult = .failure(error)
        }

        Task { @MainActor [weak self] in
            guard let self, let model = self.activeDownloads[taskID] else { return }
            switch moveResult {
            case .success:
                self.downloadStates[model.id] = .downloaded
                self.presentToast(L10n.t("toast.downloadComplete", self.currentLanguage, model.localizedDisplayName(for: self.currentLanguage)), style: .success)
            case .failure(let error):
                self.downloadStates[model.id] = .failed(message: self.errorMessage(from: error))
                self.presentToast(L10n.t("toast.downloadFailed", self.currentLanguage, model.localizedDisplayName(for: self.currentLanguage)), style: .error)
            }
            self.removeActiveTask(for: taskID)
            self.refreshCacheStats()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            guard let self, let model = self.activeDownloads[task.taskIdentifier] else { return }
            self.downloadStates[model.id] = .failed(message: self.errorMessage(from: error))
            self.presentToast(L10n.t("toast.downloadFailed", self.currentLanguage, model.localizedDisplayName(for: self.currentLanguage)), style: .error)
            self.removeActiveTask(for: task.taskIdentifier)
        }
    }
}

private extension DownloadManager {
    func removeActiveTask(for taskID: Int) {
        guard let model = activeDownloads[taskID] else { return }
        activeDownloads.removeValue(forKey: taskID)
        activeTaskByModelID.removeValue(forKey: model.id)
    }

    func errorMessage(from error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return L10n.t("error.noInternet", currentLanguage)
            case .timedOut:
                return L10n.t("error.timeout", currentLanguage)
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
                return L10n.t("error.server", currentLanguage)
            case .cancelled:
                return L10n.t("error.cancelled", currentLanguage)
            default:
                return L10n.t("error.download", currentLanguage, urlError.localizedDescription)
            }
        }
        return L10n.t("error.download", currentLanguage, error.localizedDescription)
    }
}
