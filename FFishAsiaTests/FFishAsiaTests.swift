import XCTest

#if os(iOS)
import Combine
import RealityKit
#endif

#if os(macOS)
@testable import Little_Nature
#else
@testable import FFishAsia
#endif

final class FFishAsiaTests: XCTestCase {
    func testManifestDecodingBuildsFallbackDownloadURL() throws {
        let model = try XCTUnwrap(ModelCatalog.decodeManifest(from: manifestData()).first)

        XCTAssertEqual(model.id, "test-model")
        XCTAssertEqual(model.downloadURL, ModelCatalog.modelsBaseURL.appendingPathComponent("test.usdz"))
        XCTAssertEqual(model.localizedDisplayName(for: .zhHans), "测试花")
    }

    func testAnimatedModelUsesSpecialCategory() throws {
        let model = try XCTUnwrap(ModelCatalog.decodeManifest(from: manifestData()).first)

        XCTAssertTrue(model.hasAnimation)
        XCTAssertEqual(model.category, .special)
    }

    func testSearchMatchesLocalizedNamesIgnoringCaseAndDiacritics() throws {
        let model = try XCTUnwrap(ModelCatalog.decodeManifest(from: manifestData()).first)

        XCTAssertTrue(model.matches(keyword: "creme blossom"))
        XCTAssertTrue(model.matches(keyword: "测试花"))
        XCTAssertFalse(model.matches(keyword: "freshwater crab"))
    }

    func testMerchandisedCatalogStartsWithIncludedAnimatedModel() throws {
        let models = ModelCatalog.merchandised(ModelCatalog.fallbackModels)

        XCTAssertEqual(models.first?.id, ModelCatalog.starterModelID)
        XCTAssertEqual(models.first?.hasAnimation, true)
        XCTAssertEqual(Set(models.map(\.id)), Set(ModelCatalog.fallbackModels.map(\.id)))
    }

    @MainActor
    func testDownloadManagerExcludesIncludedModelFromDownloads() {
        let downloadManager = DownloadManager.shared
        XCTAssertFalse(downloadManager.downloadedModels().contains(where: downloadManager.isBundled))
    }

    #if os(iOS)
    func testRealityKitModelLoadingHopsToMainThread() async {
        let operationStarted = expectation(description: "Model loading operation started")

        await Task.detached {
            let publisher = await RealityKitModelLoader.loadModel(
                contentsOf: URL(fileURLWithPath: "/tmp/test.usdz"),
                using: { _ in
                    XCTAssertTrue(Thread.isMainThread)
                    operationStarted.fulfill()
                    return Empty<ModelEntity, Error>(completeImmediately: true)
                        .eraseToAnyPublisher()
                }
            )
            let cancellable = publisher.sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            withExtendedLifetime(cancellable) {}
        }.value

        await fulfillment(of: [operationStarted], timeout: 1)
    }
    #endif

    @MainActor
    func testReviewEligibilityRequiresTwoDifferentSuccessfulPreviews() throws {
        let suiteName = "ProductAnalyticsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = ProductAnalytics(defaults: defaults, version: { "1.2.2" })
        let models = ModelCatalog.merchandised(ModelCatalog.fallbackModels)
        let first = try XCTUnwrap(models.first)
        let second = try XCTUnwrap(models.dropFirst().first)

        XCTAssertFalse(analytics.recordSuccessfulPreview(model: first, bundled: true))
        XCTAssertFalse(analytics.recordSuccessfulPreview(model: first, bundled: true))
        XCTAssertTrue(analytics.recordSuccessfulPreview(model: second, bundled: false))
        analytics.markReviewPromptRequested()
        XCTAssertFalse(analytics.recordSuccessfulPreview(model: try XCTUnwrap(models.dropFirst(2).first), bundled: false))
    }

    func testManifestUsesExplicitImageURLsAndDerivesLegacyFallbacks() throws {
        let legacy = try XCTUnwrap(ModelCatalog.decodeManifest(from: manifestData()).first)
        XCTAssertEqual(legacy.thumbnailURL?.lastPathComponent, "test_thumb.jpeg")
        XCTAssertEqual(legacy.previewURL?.lastPathComponent, "test_preview.jpeg")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData()) as? [String: Any])
        var models = try XCTUnwrap(manifest["models"] as? [[String: Any]])
        models[0]["thumbnail_url"] = "https://example.com/images/thumbnail-version.jpeg"
        models[0]["preview_url"] = "https://example.com/images/preview-version.jpeg"
        manifest["models"] = models
        let explicit = try XCTUnwrap(ModelCatalog.decodeManifest(from: JSONSerialization.data(withJSONObject: manifest)).first)
        XCTAssertEqual(explicit.thumbnailURL?.absoluteString, "https://example.com/images/thumbnail-version.jpeg")
        XCTAssertEqual(explicit.previewURL?.absoluteString, "https://example.com/images/preview-version.jpeg")
    }

    func testBundledCatalogHasUniqueModelsAndCompleteTranslations() throws {
        let models = ModelCatalog.fallbackModels
        XCTAssertFalse(models.isEmpty)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertEqual(Set(models.map(\.filename)).count, models.count)
        for model in models {
            for language in AppLanguage.allCases {
                XCTAssertFalse(model.localizedName(for: language)?.isEmpty ?? true, "\(model.filename): \(language)")
                XCTAssertFalse(model.localizedTaxonomicInfo(for: language).isEmpty, model.filename)
            }
            XCTAssertEqual(model.downloadURL?.pathExtension, "usdz")
            XCTAssertGreaterThan(model.fileSizeMB, 0)
        }
    }

    func testNewAnimatedCatfishKeepsItsAnimationAndLocalizedSearchNames() throws {
        let model = try XCTUnwrap(ModelCatalog.fallbackModels.first { $0.id == "51e0cc7840c54790bfd674d70dfb6bab" })
        XCTAssertTrue(model.hasAnimation)
        XCTAssertEqual(model.category, .special)
        for name in ["有明溪鲶", "アリアケギバチ", "Ariake Stream Catfish", "Tachysurus aurantiacus"] {
            XCTAssertTrue(model.matches(keyword: name))
        }
    }

    private func manifestData() -> Data {
        Data(
            """
            {
              "models": [
                {
                  "id": "test-model",
                  "filename": "test.usdz",
                  "file_size_mb": 1.5,
                  "category": "plant",
                  "name_ja": "テストの花",
                  "name_en": "Crème Blossom",
                  "name_zh_hans": "测试花",
                  "name_zh_hant": "測試花",
                  "scientific_name": "Flora exemplaris",
                  "has_animation": true
                }
              ]
            }
            """.utf8
        )
    }

}
