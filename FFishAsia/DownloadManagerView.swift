import SwiftUI

struct DownloadManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var downloadManager: DownloadManager
    let language: AppLanguage
    let onOpenModel: (ModelItem) -> Void
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(summaryText)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }

                    if !downloadedModels.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllConfirmation = true
                        } label: {
                            Label(L10n.t("downloads.clear", language), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }

            if !downloadingModels.isEmpty {
                Section(L10n.t("downloads.downloading.section", language)) {
                    ForEach(downloadingModels) { model in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(model.localizedDisplayName(for: language))
                                    .font(.headline)
                                Spacer()
                                Text(downloadManager.formattedFileSize(for: model))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if case let .downloading(progress) = downloadManager.downloadStates[model.id] {
                                HStack(spacing: 8) {
                                    ProgressView(value: progress)
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section(L10n.t("downloads.downloaded.section", language)) {
                if downloadedModels.isEmpty {
                    EmptyDownloadStateView(
                        title: L10n.t("downloads.empty.title", language),
                        description: L10n.t("downloads.empty.description", language)
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(downloadedModels) { model in
                    HStack(spacing: 12) {
                        Button {
                            onOpenModel(model)
                        } label: {
                            HStack(spacing: 12) {
                                ThumbnailView(imageName: model.thumbName, width: 60, height: 60, remoteURL: model.thumbnailURL)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.localizedDisplayName(for: language))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(downloadManager.formattedFileSize(for: model))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            downloadManager.delete(model)
                        } label: {
                            Image(systemName: "trash")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.t("action.deleteDownloaded", language))
                        .help(L10n.t("action.deleteDownloaded", language))
                    }
                }
            }
        }
        .navigationTitle(L10n.t("downloads.title", language))
        .platformNavigationBarTitleDisplayModeInline()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(L10n.t("action.close", language))
                    .help(L10n.t("action.close", language))
            }
        }
        .downloadManagerWindowFrame()
        .onAppear {
            downloadManager.refreshCacheStats()
        }
        .alert(L10n.t("downloads.confirm.title", language), isPresented: $showDeleteAllConfirmation) {
            Button(L10n.t("downloads.confirm.delete", language), role: .destructive) {
                downloadManager.deleteAll()
            }
            Button(L10n.t("downloads.confirm.cancel", language), role: .cancel) {}
        } message: {
            Text(L10n.t("downloads.confirm.message", language))
        }
    }

    private var downloadedModels: [ModelItem] {
        downloadManager.downloadedModels()
    }

    private var downloadingModels: [ModelItem] {
        downloadManager.downloadingModels()
    }

    private var summaryText: String {
        if downloadedModels.isEmpty {
            return L10n.t("downloads.summary.empty", language)
        }
        return L10n.t("downloads.summary", language, downloadedModels.count, downloadManager.totalCacheSizeMB)
    }
}

private extension View {
    @ViewBuilder
    func downloadManagerWindowFrame() -> some View {
        #if os(macOS)
        self.frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 620)
        #else
        self
        #endif
    }
}

private struct EmptyDownloadStateView: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
