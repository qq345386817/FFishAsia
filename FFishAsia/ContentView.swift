import SwiftUI

struct ContentView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var selectedCategory: ModelCategory? = nil
    @State private var selectedModel: ModelItem? = nil
    @State private var arModel: ModelItem? = nil
    @State private var statusText = ""
    @State private var isARModelLoaded = false
    @State private var arResetRequestID = 0
    @State private var showDownloads = false
    @State private var showAbout = false
    @State private var searchText = ""
    @State private var visibleToast: DownloadManager.ToastMessage?
    @State private var toastTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.preferred.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .preferred
    }

    init() {
        let snapshot = SnapshotLaunchConfiguration.current
        if let language = snapshot.language {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
        _selectedCategory = State(initialValue: snapshot.category)
        _selectedModel = State(initialValue: snapshot.screen == .detail ? snapshot.model : nil)
        _showDownloads = State(initialValue: snapshot.screen == .downloads)
        _showAbout = State(initialValue: snapshot.screen == .about)
        _searchText = State(initialValue: snapshot.searchText)
    }

    private var filteredModels: [ModelItem] {
        downloadManager.remoteModels.filter { model in
            let matchesCategory = selectedCategory == nil || model.category == selectedCategory
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.matches(keyword: searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        ZStack {
            if let arItem = arModel {
                arView(for: arItem)
                    .zIndex(1)
            } else {
                browseView
            }

            if let toast = visibleToast {
                VStack {
                    Spacer()
                    ToastBanner(message: toast.message, style: toast.style)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: visibleToast?.id)
        .task {
            downloadManager.currentLanguage = appLanguage
            downloadManager.refreshManifest()
        }
        .onChange(of: appLanguageRaw) { _ in
            downloadManager.currentLanguage = appLanguage
        }
        .onReceive(downloadManager.$toast.compactMap { $0 }) { toast in
            showToast(toast)
        }
        .sheet(item: $selectedModel) { model in
            ModelDetailSheet(
                model: model,
                downloadManager: downloadManager,
                language: appLanguage,
                onLaunchAR: {
                    statusText = ""
                    isARModelLoaded = false
                    arModel = model
                    selectedModel = nil
                }
            )
        }
        .sheet(isPresented: $showDownloads) {
            NavigationStack {
                DownloadManagerView(downloadManager: downloadManager, language: appLanguage) { model in
                    showDownloads = false
                    statusText = ""
                    isARModelLoaded = false
                    arModel = model
                }
            }
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack {
                AboutView(language: appLanguage)
            }
        }
        .platformOnboardingCover(isPresented: .constant(!hasSeenOnboarding)) {
            OnboardingView(language: appLanguage) {
                hasSeenOnboarding = true
            }
        }
    }

    private func showToast(_ toast: DownloadManager.ToastMessage) {
        toastTask?.cancel()
        withAnimation {
            visibleToast = toast
        }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    if visibleToast?.id == toast.id {
                        visibleToast = nil
                    }
                }
            }
        }
    }

    private func dismissSearchKeyboard() {
        isSearchFocused = false
    }

    private func emptyStateText() -> (title: String, description: String) {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (L10n.t("empty.search.title", appLanguage), L10n.t("empty.search.description", appLanguage))
        }
        if selectedCategory != nil {
            return (L10n.t("empty.category.title", appLanguage), L10n.t("empty.category.description", appLanguage))
        }
        return (L10n.t("empty.catalog.title", appLanguage), L10n.t("empty.catalog.description", appLanguage))
    }

    private var activeCategoryTitle: String {
        selectedCategory?.label(in: appLanguage) ?? L10n.t("all", appLanguage)
    }

    private var activeFilterSummary: String {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return L10n.t("filter.summary", appLanguage, activeCategoryTitle, filteredModels.count)
        }
        return L10n.t("filter.summary.keyword", appLanguage, activeCategoryTitle, keyword, filteredModels.count)
    }

    private func arView(for model: ModelItem) -> some View {
        ZStack {
            ARViewContainer(
                statusText: $statusText,
                isModelLoaded: $isARModelLoaded,
                modelURL: downloadManager.localURL(for: model),
                hasBuiltInAnimation: model.hasAnimation,
                language: appLanguage,
                resetRequestID: arResetRequestID
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        arModel = nil
                        statusText = ""
                        isARModelLoaded = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.3))
                    }

                    Spacer()

                    Button {
                        statusText = L10n.t("ar.resetRequested", appLanguage)
                        isARModelLoaded = true
                        arResetRequestID += 1
                    } label: {
                        Label(L10n.t("ar.reset", appLanguage), systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Capsule())
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 6) {
                    Text(arOverlayPrimaryText)
                        .font(.caption.weight(.semibold))
                    Text(L10n.t("ar.gestureHint", appLanguage))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private var arOverlayPrimaryText: String {
        let text = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == L10n.t("ar.unsupported", appLanguage) || text == L10n.t("ar.downloadFirst", appLanguage) || text == L10n.t("ar.resetRequested", appLanguage) || text == L10n.t("ar.resetDone", appLanguage) {
            return text
        }
        let failedPrefix = L10n.t("ar.loadFailed", appLanguage, "").replacingOccurrences(of: "%@", with: "")
        let sessionFailedPrefix = L10n.t("ar.sessionFailed", appLanguage, "").replacingOccurrences(of: "%@", with: "")
        if (!failedPrefix.isEmpty && text.hasPrefix(failedPrefix)) || (!sessionFailedPrefix.isEmpty && text.hasPrefix(sessionFailedPrefix)) {
            return text
        }
        // On iOS, ARKit tracking may remain "initializing/limited" even while the model
        // is already visible. Keep the bottom overlay as a stable usage hint.
        return L10n.t("ar.loaded.gesture", appLanguage)
    }

    private var browseView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(activeFilterSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 6)

                if filteredModels.isEmpty {
                    let state = emptyStateText()
                    EmptyStateView(title: state.title, systemImage: "magnifyingglass", description: state.description)
                        .onTapGesture {
                            dismissSearchKeyboard()
                        }
                } else {
                    ScrollView {
                        LazyVGrid(columns: modelGridColumns, alignment: .center, spacing: 12) {
                            ForEach(filteredModels) { model in
                                ModelCard(
                                    model: model,
                                    state: downloadManager.downloadStates[model.id] ?? .notDownloaded,
                                    language: appLanguage,
                                    onRetry: { downloadManager.retry(model) }
                                )
                                    .onTapGesture {
                                        dismissSearchKeyboard()
                                        selectedModel = model
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4).onChanged { _ in
                            dismissSearchKeyboard()
                        }
                    )
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(L10n.t("app.name", appLanguage))
            .platformNavigationBarTitleDisplayModeInline()
            .safeAreaInset(edge: .bottom) {
                bottomFilterBar
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItemGroup(placement: trailingToolbarPlacement) {
                    Button {
                        dismissSearchKeyboard()
                        showDownloads = true
                    } label: {
                        Image(systemName: "tray.full")
                    }

                    Menu {
                        ForEach(AppLanguage.allCases) { language in
                            Button {
                                dismissSearchKeyboard()
                                appLanguageRaw = language.rawValue
                            } label: {
                                if language == appLanguage {
                                    Label(language.displayName, systemImage: "checkmark")
                                } else {
                                    Text(language.displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel(L10n.t("language", appLanguage))

                    Button {
                        dismissSearchKeyboard()
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
    }

    private var modelGridColumns: [GridItem] {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            return [
                GridItem(.adaptive(minimum: 170, maximum: 210), spacing: 14, alignment: .top)
            ]
        }

        return [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top)
        ]
        #else
        [
            GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 14, alignment: .top)
        ]
        #endif
    }

    private var bottomFilterBar: some View {
        VStack(spacing: 10) {
            SearchField(
                text: $searchText,
                prompt: L10n.t("search.prompt", appLanguage),
                clearAccessibilityLabel: L10n.t("clear.search", appLanguage),
                isFocused: $isSearchFocused
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryPill(title: L10n.t("all", appLanguage), systemImage: "globe.asia.australia.fill", isSelected: selectedCategory == nil) {
                        dismissSearchKeyboard()
                        withAnimation(.easeInOut(duration: 0.25)) { selectedCategory = nil }
                    }

                    ForEach(ModelCategory.allCases, id: \.self) { cat in
                        CategoryPill(
                            title: cat.label(in: appLanguage),
                            systemImage: cat.symbolName,
                            isSelected: selectedCategory == cat
                        ) {
                            dismissSearchKeyboard()
                            withAnimation(.easeInOut(duration: 0.25)) { selectedCategory = cat }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

private enum SnapshotScreen: String {
    case catalog
    case detail
    case downloads
    case about
}

private struct SnapshotLaunchConfiguration {
    let screen: SnapshotScreen
    let category: ModelCategory?
    let model: ModelItem?
    let searchText: String
    let language: AppLanguage?

    static var current: SnapshotLaunchConfiguration {
        let arguments = ProcessInfo.processInfo.arguments
        func value(for key: String) -> String? {
            let prefix = "\(key)="
            guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
                return nil
            }
            return String(argument.dropFirst(prefix.count))
        }

        let screen = SnapshotScreen(rawValue: value(for: "FFISH_SNAPSHOT_SCREEN") ?? "catalog") ?? .catalog
        let modelID = value(for: "FFISH_SNAPSHOT_MODEL_ID")
        let model = ModelCatalog.fallbackModels.first { $0.id == modelID } ?? ModelCatalog.fallbackModels.first
        let searchText = value(for: "FFISH_SNAPSHOT_SEARCH") ?? ""
        let language = value(for: "FFISH_SNAPSHOT_APP_LANGUAGE").flatMap(AppLanguage.init(rawValue:))
        let category: ModelCategory?
        switch value(for: "FFISH_SNAPSHOT_CATEGORY") {
        case "plant": category = .plant
        case "animal": category = .animal
        case "special": category = .special
        default: category = nil
        }

        return SnapshotLaunchConfiguration(
            screen: screen,
            category: category,
            model: model,
            searchText: searchText,
            language: language
        )
    }
}

private struct CategoryPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor : Self.unselectedBackground)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private static var unselectedBackground: Color {
        #if os(iOS)
        Color(.tertiarySystemFill)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

private struct SearchField: View {
    @Binding var text: String
    let prompt: String
    let clearAccessibilityLabel: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .font(.subheadline)
                .focused(isFocused)
                .onSubmit {
                    isFocused.wrappedValue = false
                }
                .platformSearchFieldBehavior()

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearAccessibilityLabel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Self.fieldBackground, in: Capsule())
    }

    private static var fieldBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }
}

private struct ModelCard: View {
    let model: ModelItem
    let state: DownloadManager.DownloadState
    let language: AppLanguage
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailView(imageName: model.thumbName, width: nil, height: 96)

            Text(model.localizedDisplayName(for: language))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(minHeight: 36, alignment: .topLeading)

            HStack {
                Text(model.category.label(in: language))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.15))
                    .foregroundStyle(categoryColor)
                    .clipShape(Capsule())
                Spacer()
                DownloadStateBadge(state: state, language: language, onRetry: onRetry)
            }

            Text(model.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: Self.maxCardWidth, alignment: .topLeading)
        .background(Self.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static var cardBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private static var maxCardWidth: CGFloat {
        #if os(iOS)
        .infinity
        #else
        220
        #endif
    }

    private var categoryColor: Color {
        switch model.category {
        case .plant: return .green
        case .animal: return .orange
        case .special: return .purple
        }
    }
}

private struct ModelDetailSheet: View {
    let model: ModelItem
    @ObservedObject var downloadManager: DownloadManager
    let language: AppLanguage
    let onLaunchAR: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ThumbnailView(imageName: model.previewName, width: nil, height: 220)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.localizedDisplayName(for: language))
                            .font(.title.bold())
                        if let secondaryName = model.localizedSecondaryName(for: language), secondaryName != model.localizedDisplayName(for: language) {
                            Text(secondaryName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !model.scientificName.isEmpty {
                            Text(model.scientificName)
                                .font(.subheadline.italic())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        InfoRow(title: L10n.t("detail.downloadStatus", language), value: statusText)
                        InfoRow(title: L10n.t("detail.category", language), value: model.category.detailLabel(in: language))
                        InfoRow(title: L10n.t("detail.faces", language), value: model.formattedFaces)
                        InfoRow(title: L10n.t("detail.vertices", language), value: model.formattedVertices)
                        InfoRow(title: L10n.t("detail.fileSize", language), value: model.formattedSize)
                        InfoRow(title: L10n.t("detail.animation", language), value: model.hasAnimation ? L10n.t("detail.hasAnimation", language) : L10n.t("detail.noAnimation", language))
                    }
                    .padding(.horizontal)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.t("detail.downloadUse", language))
                            .font(.subheadline.bold())

                        downloadArea
                    }
                    .padding(.horizontal)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("detail.taxonomy", language))
                            .font(.subheadline.bold())
                        Text(model.localizedTaxonomicInfo(for: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                    .padding(.horizontal)

                    if let url = model.sketchfabURL {
                        Divider()
                        Link(L10n.t("detail.sketchfab", language), destination: url)
                            .font(.subheadline)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.t("detail.title", language))
            .platformNavigationBarTitleDisplayModeInline()
        }
    }

    private var downloadState: DownloadManager.DownloadState {
        downloadManager.downloadStates[model.id] ?? .notDownloaded
    }

    private var statusText: String {
        switch downloadState {
        case .notDownloaded:
            return L10n.t("status.notDownloaded", language)
        case .downloaded:
            return L10n.t("status.downloaded", language)
        case .downloading(let progress):
            return L10n.t("status.downloading", language, Int(progress * 100))
        case .failed(let message):
            return L10n.t("status.failed", language, message)
        }
    }

    @ViewBuilder
    private var downloadArea: some View {
        switch downloadState {
        case .notDownloaded:
            Button {
                downloadManager.download(model)
            } label: {
                Label(L10n.t("action.downloadModel", language), systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("downloading", language))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("status.failed", language, message))
                    .font(.caption)
                    .foregroundStyle(.red)
                Button {
                    downloadManager.retry(model)
                } label: {
                    Label(L10n.t("action.retryDownload", language), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

        case .downloaded:
            VStack(spacing: 10) {
                Button {
                    onLaunchAR()
                } label: {
                    Label(L10n.t("action.openAR", language), systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    downloadManager.delete(model)
                } label: {
                    Label(L10n.t("action.deleteDownloaded", language), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct DownloadStateBadge: View {
    let state: DownloadManager.DownloadState
    let language: AppLanguage
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .notDownloaded:
            Label(L10n.t("badge.notDownloaded", language), systemImage: "arrow.down.circle")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

        case .downloaded:
            Text(L10n.t("badge.downloaded", language))
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())

        case .downloading(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 50)
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.blue)
            }

        case .failed:
            HStack(spacing: 6) {
                Text(L10n.t("badge.failed", language))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(Capsule())
                Button(L10n.t("action.retry", language)) {
                    onRetry()
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct ToastBanner: View {
    let message: String
    let style: DownloadManager.ToastStyle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: style.iconName)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(style.color.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

private struct OnboardingView: View {
    let language: AppLanguage
    let onFinish: () -> Void
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $selection) {
                OnboardingPage(
                    title: L10n.t("onboarding.1.title", language),
                    subtitle: L10n.t("onboarding.1.subtitle", language),
                    systemImage: "cube.fill"
                )
                .tag(0)

                OnboardingPage(
                    title: L10n.t("onboarding.2.title", language),
                    subtitle: L10n.t("onboarding.2.subtitle", language),
                    systemImage: "arrow.down.circle"
                )
                .tag(1)

                OnboardingPage(
                    title: L10n.t("onboarding.3.title", language),
                    subtitle: L10n.t("onboarding.3.subtitle", language),
                    systemImage: "camera.viewfinder"
                )
                .tag(2)
            }
            .platformOnboardingTabStyle()

            VStack(spacing: 12) {
                Button(selection == 2 ? L10n.t("action.start", language) : L10n.t("action.continue", language)) {
                    if selection == 2 {
                        onFinish()
                    } else {
                        withAnimation { selection += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(L10n.t("action.later", language)) {
                    onFinish()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .platformSystemBackground()
    }
}

private struct OnboardingPage: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()
        }
    }
}

struct ThumbnailView: View {
    let imageName: String
    let width: CGFloat?
    let height: CGFloat

    var body: some View {
        if let width {
            thumbnailContent
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            GeometryReader { proxy in
                thumbnailContent
                    .frame(width: proxy.size.width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(height: height)
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image = PlatformImage(named: imageName) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Self.placeholderColor)
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static var placeholderColor: Color {
        #if os(iOS)
        Color(.systemGray5)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

#if os(iOS)
private typealias PlatformImage = UIImage

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#elseif os(macOS)
private typealias PlatformImage = NSImage

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#endif

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension View {
    @ViewBuilder
    func platformNavigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformOnboardingCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    @ViewBuilder
    func platformSystemBackground() -> some View {
        #if os(iOS)
        self.background(Color(.systemBackground))
        #else
        self.background(Color(nsColor: .windowBackgroundColor))
        #endif
    }

    @ViewBuilder
    func platformSearchFieldBehavior() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformOnboardingTabStyle() -> some View {
        #if os(iOS)
        self.tabViewStyle(.page(indexDisplayMode: .always))
        #else
        self.tabViewStyle(.automatic)
        #endif
    }
}
