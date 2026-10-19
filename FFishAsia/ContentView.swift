import StoreKit
import SwiftUI

struct ContentView: View {
    @Environment(\.requestReview) private var requestReview
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var selectedCategory: ModelCategory? = nil
    @State private var catalogFilter: CatalogFilter = .all
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedModel: ModelItem? = nil
    @State private var previewModel: ModelItem? = nil
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
    private let snapshot: SnapshotLaunchConfiguration

    private var appLanguage: AppLanguage {
        AppLanguage.normalized(from: appLanguageRaw) ?? .preferred
    }

    init() {
        let snapshot = SnapshotLaunchConfiguration.current
        self.snapshot = snapshot
        if let language = snapshot.language {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
        _selectedCategory = State(initialValue: snapshot.category)
        _selectedModel = State(initialValue: snapshot.screen == .detail ? snapshot.model : nil)
        _previewModel = State(initialValue: nil)
        _arModel = State(initialValue: snapshot.screen == .ar ? snapshot.model : nil)
        _showDownloads = State(initialValue: snapshot.screen == .downloads)
        _showAbout = State(initialValue: snapshot.screen == .about)
        _searchText = State(initialValue: snapshot.searchText)
    }

    private var filteredModels: [ModelItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = downloadManager.remoteModels.filter { model in
            let matchesCategory = selectedCategory == nil || model.category == selectedCategory
            let matchesSearch = keyword.isEmpty || model.matches(keyword: keyword)
            let isAvailableOffline = downloadManager.downloadStates[model.id] == .downloaded
            return matchesCategory && matchesSearch && catalogFilter.includes(model, isAvailableOffline: isAvailableOffline)
        }
        guard selectedCategory == nil, keyword.isEmpty else {
            return models
        }
        return ModelCatalog.merchandised(models)
    }

    var body: some View {
        ZStack {
            if snapshot.screen == .preview, let model = snapshot.model {
                NavigationStack {
                    ModelPreviewView(
                        model: model,
                        modelURL: downloadManager.localURL(for: model),
                        language: appLanguage,
                        onModelLoaded: {}
                    )
                }
            } else if let arItem = arModel {
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
            ProductAnalytics.shared.track(.catalogView)
            downloadManager.refreshManifest()
        }
        .task(id: appLanguageRaw) {
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
                onPreview: {
                    previewModel = model
                    selectedModel = nil
                },
                onLaunchAR: {
                    statusText = ""
                    isARModelLoaded = false
                    arModel = model
                    selectedModel = nil
                }
            )
        }
        .sheet(item: $previewModel) { model in
            NavigationStack {
                ModelPreviewView(
                    model: model,
                    modelURL: downloadManager.localURL(for: model),
                    language: appLanguage,
                    onModelLoaded: { recordSuccessfulPreview(of: model) }
                )
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 640)
                #endif
            }
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
                ProductAnalytics.shared.track(.onboardingComplete)
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

    private func recordSuccessfulPreview(of model: ModelItem) {
        guard ProductAnalytics.shared.recordSuccessfulPreview(
            model: model,
            bundled: downloadManager.isBundled(model)
        ) else { return }
        ProductAnalytics.shared.markReviewPromptRequested()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            requestReview()
        }
    }

    private func emptyStateText() -> (title: String, description: String) {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (L10n.t("empty.search.title", appLanguage), L10n.t("empty.search.description", appLanguage))
        }
        if selectedCategory != nil {
            return (L10n.t("empty.category.title", appLanguage), L10n.t("empty.category.description", appLanguage))
        }
        if catalogFilter != .all {
            return (L10n.t(catalogFilter.localizationKey, appLanguage), L10n.t("empty.catalogFilter.description", appLanguage))
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
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(activeFilterSummary)
                            .fixedSize()
                        Spacer()
                        catalogFilterMenu
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(activeFilterSummary)
                            .fixedSize(horizontal: false, vertical: true)
                        catalogFilterMenu
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 6)

                if filteredModels.isEmpty {
                    let state = emptyStateText()
                    EmptyStateView(title: state.title, systemImage: "magnifyingglass", description: state.description)
                        .onTapGesture {
                            dismissSearchKeyboard()
                        }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: modelGridColumns, alignment: .center, spacing: 12) {
                                ForEach(filteredModels) { model in
                                    ModelCard(
                                        model: model,
                                        state: downloadManager.downloadStates[model.id] ?? .notDownloaded,
                                        isBundled: downloadManager.isBundled(model),
                                        language: appLanguage,
                                        onOpen: {
                                            dismissSearchKeyboard()
                                            ProductAnalytics.shared.track(
                                                .modelDetailOpen,
                                                model: model,
                                                bundled: downloadManager.isBundled(model)
                                            )
                                            selectedModel = model
                                        }
                                    )
                                    .id(model.id)
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
                        .task(id: filteredModels.map(\.id)) {
                            await performSnapshotCatalogAutoScroll(using: proxy)
                        }
                    }
                }
            }
            .platformCatalogBackground()
            .onChange(of: catalogFilter) { _ in dismissSearchKeyboard() }
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
                    .accessibilityLabel(L10n.t("downloads.title", appLanguage))
                    .help(L10n.t("downloads.title", appLanguage))

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
                    .accessibilityLabel(L10n.t("about.title", appLanguage))
                    .help(L10n.t("about.title", appLanguage))
                }
            }
        }
    }

    private var catalogFilterMenu: some View {
        Menu {
            Picker(L10n.t("catalog.filter.title", appLanguage), selection: $catalogFilter) {
                ForEach(CatalogFilter.allCases) { filter in
                    Label(L10n.t(filter.localizationKey, appLanguage), systemImage: filter.symbolName)
                        .tag(filter)
                }
            }
        } label: {
            Label(L10n.t(catalogFilter.localizationKey, appLanguage), systemImage: "line.3.horizontal.decrease")
                .font(.footnote.weight(.medium))
                .fixedSize()
                .padding(.vertical, 12)
        }
        .accessibilityIdentifier("catalog.filter")
        .help(L10n.t("catalog.filter.title", appLanguage))
    }

    private var modelGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), alignment: .top)]
        }
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
        return [
            GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 14, alignment: .top)
        ]
        #endif
    }

    private func performSnapshotCatalogAutoScroll(using proxy: ScrollViewProxy) async {
        guard snapshot.autoScrollCatalog, snapshot.screen == .catalog, filteredModels.count > 12 else { return }

        let firstID = filteredModels[0].id
        await MainActor.run {
            proxy.scrollTo(firstID, anchor: .top)
        }

        if snapshot.autoScrollStyle == "slow" {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            let targetIndex = min(filteredModels.count - 1, max(0, filteredModels.count * 2 / 5))
            let targetID = filteredModels[targetIndex].id
            await MainActor.run {
                withAnimation(.easeInOut(duration: 8.8)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
            return
        }

        try? await Task.sleep(nanoseconds: 3_500_000_000)
        guard !Task.isCancelled else { return }

        let midpointIndex = min(filteredModels.count - 1, max(0, filteredModels.count / 3))
        let midpointID = filteredModels[midpointIndex].id
        await MainActor.run {
            withAnimation(.easeInOut(duration: 4.2)) {
                proxy.scrollTo(midpointID, anchor: .center)
            }
        }

        try? await Task.sleep(nanoseconds: 4_600_000_000)
        guard !Task.isCancelled else { return }

        let finalIndex = min(filteredModels.count - 1, max(0, filteredModels.count * 2 / 3))
        let finalID = filteredModels[finalIndex].id
        await MainActor.run {
            withAnimation(.easeInOut(duration: 3.4)) {
                proxy.scrollTo(finalID, anchor: .center)
            }
        }
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
    case preview
    case ar
    case downloads
    case about
}

private struct SnapshotLaunchConfiguration {
    let screen: SnapshotScreen
    let category: ModelCategory?
    let model: ModelItem?
    let searchText: String
    let language: AppLanguage?
    let autoScrollCatalog: Bool
    let autoScrollStyle: String?

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
        let language = value(for: "FFISH_SNAPSHOT_APP_LANGUAGE").flatMap(AppLanguage.normalized(from:))
        let autoScrollCatalog = value(for: "FFISH_SNAPSHOT_AUTOSCROLL") == "1"
        let autoScrollStyle = value(for: "FFISH_SNAPSHOT_AUTOSCROLL_STYLE")
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
            language: language,
            autoScrollCatalog: autoScrollCatalog,
            autoScrollStyle: autoScrollStyle
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
            .frame(minHeight: 44)
            .background(isSelected ? Color.accentColor : Self.unselectedBackground)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(clearAccessibilityLabel)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
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
    let isBundled: Bool
    let language: AppLanguage
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var titleHeight = 40

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(imageName: model.thumbName, width: nil, height: 96, remoteURL: model.thumbnailURL)
                    .overlay(alignment: .topLeading) {
                        if model.hasAnimation {
                            Label(L10n.t("catalog.filter.animated", language), systemImage: "play.circle.fill")
                                .font(.caption2.weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .padding(6)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                                .padding(6)
                        }
                    }

                Text(model.localizedDisplayName(for: language))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .frame(minHeight: titleHeight, alignment: .topLeading)

                HStack {
                    Text(model.category.label(in: language))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.15))
                        .foregroundStyle(categoryColor)
                        .clipShape(Capsule())
                    Spacer()
                    DownloadStateBadge(state: state, isBundled: isBundled, language: language)
                }
            }
            .padding(8)
            .frame(maxWidth: Self.maxCardWidth, alignment: .topLeading)
            .background(Self.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("model.\(model.id)")
        .accessibilityElement(children: .combine)
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
    @Environment(\.dismiss) private var dismiss
    let model: ModelItem
    @ObservedObject var downloadManager: DownloadManager
    let language: AppLanguage
    let onPreview: () -> Void
    let onLaunchAR: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ThumbnailView(imageName: model.previewName, width: nil, height: 220, remoteURL: model.previewURL)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.localizedDisplayName(for: language))
                            .font(.title2.bold())
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
                        VStack(alignment: .leading, spacing: 6) {
                            Label(model.category.detailLabel(in: language), systemImage: model.category.symbolName)
                            if model.hasAnimation {
                                Label(L10n.t("catalog.filter.animated", language), systemImage: "play.circle.fill")
                            }
                            if downloadManager.isBundled(model) {
                                Label(L10n.t("status.included", language), systemImage: "checkmark.circle.fill")
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal)

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.t("detail.taxonomy", language), systemImage: "leaf.fill")
                            .font(.headline)
                        Text(model.localizedTaxonomicInfo(for: language))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal)

                    Divider()

                    DisclosureGroup(L10n.t("detail.modelInformation", language)) {
                        VStack(alignment: .leading, spacing: 10) {
                            InfoRow(title: L10n.t("detail.downloadStatus", language), value: statusText)
                            InfoRow(title: L10n.t("detail.fileSize", language), value: model.formattedSize)
                            InfoRow(title: L10n.t("detail.faces", language), value: model.formattedFaces)
                            InfoRow(title: L10n.t("detail.vertices", language), value: model.formattedVertices)
                            if let url = model.sketchfabURL {
                                Link(L10n.t("detail.sketchfab", language), destination: url)
                                    .font(.subheadline)
                            }
                            if downloadState == .downloaded && !downloadManager.isBundled(model) {
                                Button(role: .destructive) {
                                    downloadManager.delete(model)
                                } label: {
                                    Label(L10n.t("action.deleteDownloaded", language), systemImage: "trash")
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(statusText)
                        Spacer(minLength: 8)
                        Text(model.formattedSize)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    downloadArea
                        .controlSize(.large)
                }
                .frame(maxWidth: 648)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .navigationTitle(L10n.t("detail.title", language))
            .platformNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L10n.t("action.close", language))
                        .help(L10n.t("action.close", language))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    private var downloadState: DownloadManager.DownloadState {
        downloadManager.downloadStates[model.id] ?? .notDownloaded
    }

    private var statusText: String {
        switch downloadState {
        case .notDownloaded:
            return L10n.t("status.notDownloaded", language)
        case .downloaded:
            return downloadManager.isBundled(model)
                ? L10n.t("status.included", language)
                : L10n.t("status.downloaded", language)
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
                    onPreview()
                } label: {
                    Label(L10n.t("action.preview3D", language), systemImage: "cube.transparent")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                #if os(iOS)
                Button {
                    ProductAnalytics.shared.track(
                        .arStart,
                        model: model,
                        bundled: downloadManager.isBundled(model)
                    )
                    onLaunchAR()
                } label: {
                    Label(L10n.t("action.openAR", language), systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                #endif
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
    let isBundled: Bool
    let language: AppLanguage

    var body: some View {
        switch state {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.t("badge.notDownloaded", language))

        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
                .accessibilityLabel(L10n.t(isBundled ? "badge.included" : "badge.downloaded", language))

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

    var body: some View {
        VStack(spacing: 24) {
            OnboardingPage(
                title: L10n.t("onboarding.1.title", language),
                subtitle: L10n.t("onboarding.1.subtitle", language),
                systemImage: "cube.transparent.fill"
            )

            VStack(spacing: 12) {
                Button(L10n.t("action.start", language)) {
                    onFinish()
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
    var remoteURL: URL? = nil

    var body: some View {
        if let width {
            thumbnailContent
                .frame(width: width, height: height)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            GeometryReader { proxy in
                thumbnailContent
                    .frame(width: proxy.size.width, height: height)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: height)
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image = PlatformImage(named: imageName) {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .clipped()
        } else if let remoteURL {
            AsyncImage(url: remoteURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().clipped()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Self.placeholderColor)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
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
    func platformCatalogBackground() -> some View {
        #if os(iOS)
        self.background(Color(.systemGroupedBackground))
        #else
        self.background(Color(nsColor: .windowBackgroundColor))
        #endif
    }

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
