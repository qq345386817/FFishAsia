import Foundation

#if os(iOS)
import Combine
import RealityKit

enum RealityKitModelLoader {
    typealias LoadingOperation = @MainActor (URL) -> AnyPublisher<ModelEntity, Error>

    @MainActor
    static func loadModel(
        contentsOf url: URL,
        using operation: LoadingOperation = { url in
            ModelEntity.loadModelAsync(contentsOf: url).eraseToAnyPublisher()
        }
    ) -> AnyPublisher<ModelEntity, Error> {
        operation(url)
    }
}
#endif
