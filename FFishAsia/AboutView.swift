import SwiftUI

struct AboutView: View {
    let language: AppLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 8) {
                    Text("🌱 " + L10n.t("app.name", language))
                        .font(.largeTitle.bold())
                    Text(L10n.t("about.subtitle", language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t("about.download.title", language), systemImage: "arrow.down.circle")
                        .font(.headline)
                    Text(L10n.t("about.download.body", language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t("about.license.title", language), systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    Text(L10n.t("about.source.body", language))
                    Text(L10n.t("about.license.body", language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Link(L10n.t("about.cc0.link", language), destination: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t("about.thanks.title", language), systemImage: "heart.fill")
                        .font(.headline)
                    Text(L10n.t("about.thanks.body", language))
                    Text(L10n.t("about.research.body", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t("about.sketchfab.title", language), systemImage: "cube")
                        .font(.headline)
                    Text(L10n.t("about.sketchfab.body", language))
                    Link(L10n.t("about.sketchfab.link", language), destination: URL(string: "https://sketchfab.com/ffishAsia-and-floraZia")!)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("about.version.title", language))
                        .font(.headline)
                    Text(L10n.t("app.name", language) + " v2.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(platformSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .navigationTitle(L10n.t("about.title", language))
        .platformNavigationBarTitleDisplayModeInline()
    }

    private var platformSummary: String {
        #if os(macOS)
        "macOS 13+ · SwiftUI · SceneKit"
        #else
        "iOS 17+ · SwiftUI · RealityKit · ARKit"
        #endif
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AboutView(language: .zhHans)
        }
    }
}
