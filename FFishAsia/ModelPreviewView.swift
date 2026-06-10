import SwiftUI

#if os(iOS)
import RealityKit
import UIKit

struct ModelPreviewView: View {
    let model: ModelItem
    let modelURL: URL?
    let language: AppLanguage

    @State private var statusText = ""
    @State private var isModelLoaded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ModelPreviewContainer(
                statusText: $statusText,
                isModelLoaded: $isModelLoaded,
                modelURL: modelURL,
                hasBuiltInAnimation: model.hasAnimation,
                language: language
            )
            .ignoresSafeArea()

            VStack(spacing: 6) {
                Text(statusText.isEmpty ? L10n.t("ar.loadingModel", language) : statusText)
                    .font(.subheadline.weight(.semibold))
                if isModelLoaded {
                    Text(L10n.t("preview.hint", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .navigationTitle(model.localizedDisplayName(for: language))
        .platformNavigationBarTitleDisplayModeInline()
    }
}

private struct ModelPreviewContainer: UIViewRepresentable {
    @Binding var statusText: String
    @Binding var isModelLoaded: Bool
    let modelURL: URL?
    let hasBuiltInAnimation: Bool
    let language: AppLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.systemBackground)
        arView.renderOptions.insert(.disableAREnvironmentLighting)
        context.coordinator.arView = arView
        context.coordinator.installGestures(on: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.parent = self
        guard let modelURL else {
            DispatchQueue.main.async {
                statusText = L10n.t("ar.downloadFirst", language)
                isModelLoaded = false
            }
            return
        }
        context.coordinator.loadModel(url: modelURL, hasBuiltInAnimation: hasBuiltInAnimation)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.cleanup()
        uiView.scene.anchors.removeAll()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ModelPreviewContainer
        weak var arView: ARView?
        private var currentModel: Entity?
        private var lastLoadedURL: URL?
        private var lastPanTranslation: CGPoint = .zero
        private var lastPinchScale: CGFloat = 1
        private let previewDepthOffset: Float = 3.0

        init(_ parent: ModelPreviewContainer) {
            self.parent = parent
        }

        func installGestures(on arView: ARView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            arView.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            arView.addGestureRecognizer(pinch)
        }

        func cleanup() {
            currentModel = nil
            lastLoadedURL = nil
            updateParent(isModelLoaded: false)
        }

        func loadModel(url: URL, hasBuiltInAnimation: Bool) {
            guard let arView, lastLoadedURL != url else { return }
            lastLoadedURL = url
            updateParent(statusText: L10n.t("ar.loadingModel", parent.language), isModelLoaded: false)
            arView.scene.anchors.removeAll()

            do {
                let modelEntity = try ModelEntity.load(contentsOf: url)
                hideSketchfabHelperCubes(in: modelEntity)
                makeMaterialsDoubleSided(in: modelEntity)

                let fittedModel = Entity()
                fittedModel.addChild(modelEntity)
                fit(fittedModel, sourceBounds: modelEntity.visualBounds(relativeTo: nil))
                fittedModel.generateCollisionShapes(recursive: true)

                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(fittedModel)
                anchor.addChild(makeCamera(for: fittedModel))
                anchor.addChild(makeLight())
                arView.scene.addAnchor(anchor)

                currentModel = fittedModel
                for animation in modelEntity.availableAnimations {
                    modelEntity.playAnimation(animation.repeat(), transitionDuration: 0.3)
                }
                updateParent(statusText: L10n.t("ar.loaded.gesture", parent.language), isModelLoaded: true)
            } catch {
                lastLoadedURL = nil
                updateParent(statusText: L10n.t("ar.loadFailed", parent.language, error.localizedDescription), isModelLoaded: false)
            }
        }

        private func updateParent(statusText: String? = nil, isModelLoaded: Bool? = nil) {
            DispatchQueue.main.async {
                if let statusText {
                    self.parent.statusText = statusText
                }
                if let isModelLoaded {
                    self.parent.isModelLoaded = isModelLoaded
                }
            }
        }

        private func fit(_ modelEntity: Entity, sourceBounds bounds: BoundingBox) {
            let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            let targetMaxSize: Float = 0.32
            let scale = maxExtent > 0 ? min(max(targetMaxSize / maxExtent, 0.00005), 5.0) : targetMaxSize
            modelEntity.scale = SIMD3<Float>(repeating: scale)
            modelEntity.position = SIMD3<Float>(
                -bounds.center.x * scale,
                -bounds.center.y * scale,
                -bounds.center.z * scale - previewDepthOffset
            )
        }

        private func makeCamera(for modelEntity: Entity) -> PerspectiveCamera {
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 35
            camera.camera.near = 0.001
            camera.camera.far = 100
            let bounds = modelEntity.visualBounds(relativeTo: nil)
            let verticalFOV = Float(camera.camera.fieldOfViewInDegrees) * .pi / 180
            let aspect = arView.map { Float(max($0.bounds.width, 1) / max($0.bounds.height, 1)) } ?? 1
            let horizontalFOV = 2 * atan(tan(verticalFOV / 2) * aspect)
            let verticalDistance = (bounds.extents.y * 0.5) / tan(verticalFOV / 2)
            let horizontalDistance = (bounds.extents.x * 0.5) / tan(horizontalFOV / 2)
            let depthPadding = bounds.extents.z * 0.5
            let distance = max(max(verticalDistance, horizontalDistance) + depthPadding, 1.0) * 1.35
            let focus = SIMD3<Float>(0, 0, -previewDepthOffset)
            camera.position = SIMD3<Float>(0, 0, focus.z + distance)
            camera.look(at: focus, from: camera.position, relativeTo: nil)
            return camera
        }

        private func makeLight() -> DirectionalLight {
            let light = DirectionalLight()
            light.light.intensity = 2600
            light.light.color = .white
            light.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0)) *
                simd_quatf(angle: .pi / 5, axis: SIMD3<Float>(0, 1, 0))
            return light
        }

        private func hideSketchfabHelperCubes(in entity: Entity, parentName: String = "") {
            let lowercasedParentName = parentName.lowercased()
            for child in entity.children {
                let lowercasedName = child.name.lowercased()
                let isHelperCube = lowercasedName.hasPrefix("cube_")
                let isHelperCubeMesh = lowercasedName == "object_0" && lowercasedParentName.hasPrefix("cube_")
                if isHelperCube || isHelperCubeMesh {
                    child.isEnabled = false
                } else {
                    hideSketchfabHelperCubes(in: child, parentName: child.name)
                }
            }
        }

        private func makeMaterialsDoubleSided(in entity: Entity) {
            if var modelComponent = entity.components[ModelComponent.self] {
                modelComponent.materials = modelComponent.materials.map { material in
                    if var pbr = material as? PhysicallyBasedMaterial {
                        pbr.faceCulling = .none
                        return pbr
                    }
                    if #available(iOS 18.0, *) {
                        if var simple = material as? SimpleMaterial {
                            simple.faceCulling = .none
                            return simple
                        }
                        if var unlit = material as? UnlitMaterial {
                            unlit.faceCulling = .none
                            return unlit
                        }
                    }
                    return material
                }
                entity.components.set(modelComponent)
            }

            for child in entity.children {
                makeMaterialsDoubleSided(in: child)
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let model = currentModel else { return }
            let translation = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .began:
                lastPanTranslation = translation
            case .changed:
                let delta = Float(translation.x - lastPanTranslation.x) * 0.01
                model.orientation = simd_quatf(angle: delta, axis: SIMD3<Float>(0, 1, 0)) * model.orientation
                lastPanTranslation = translation
            default:
                lastPanTranslation = .zero
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let model = currentModel else { return }
            switch recognizer.state {
            case .began:
                lastPinchScale = recognizer.scale
            case .changed:
                let factor = Float(recognizer.scale / max(lastPinchScale, 0.001))
                let next = min(max(model.scale.x * factor, 0.00005), 8.0)
                model.scale = SIMD3<Float>(repeating: next)
                lastPinchScale = recognizer.scale
            default:
                lastPinchScale = 1
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#elseif os(macOS)
import AppKit
import SceneKit

struct ModelPreviewView: View {
    let model: ModelItem
    let modelURL: URL?
    let language: AppLanguage

    @State private var statusText = ""
    @State private var isModelLoaded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ModelPreviewContainer(statusText: $statusText, isModelLoaded: $isModelLoaded, modelURL: modelURL, language: language)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                Text(statusText.isEmpty ? L10n.t("ar.loadingModel", language) : statusText)
                    .font(.subheadline.weight(.semibold))
                if isModelLoaded {
                    Text(L10n.t("preview.hint", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(20)
        }
        .navigationTitle(model.localizedDisplayName(for: language))
    }
}

private struct ModelPreviewContainer: NSViewRepresentable {
    @Binding var statusText: String
    @Binding var isModelLoaded: Bool
    let modelURL: URL?
    let language: AppLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SCNView {
        let sceneView = SCNView(frame: .zero)
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = .windowBackgroundColor
        sceneView.rendersContinuously = true
        context.coordinator.sceneView = sceneView
        return sceneView
    }

    func updateNSView(_ sceneView: SCNView, context: Context) {
        context.coordinator.parent = self
        guard let modelURL else {
            DispatchQueue.main.async {
                statusText = L10n.t("ar.downloadFirst", language)
                isModelLoaded = false
            }
            return
        }
        context.coordinator.loadModel(url: modelURL)
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: Coordinator) {
        nsView.scene = nil
    }

    final class Coordinator {
        var parent: ModelPreviewContainer
        weak var sceneView: SCNView?
        private var lastLoadedURL: URL?

        init(_ parent: ModelPreviewContainer) {
            self.parent = parent
        }

        func loadModel(url: URL) {
            guard let sceneView, lastLoadedURL != url else { return }
            lastLoadedURL = url
            updateParent(statusText: L10n.t("ar.loadingModel", parent.language), isModelLoaded: false)

            do {
                let sourceScene = try SCNScene(url: url, options: [.checkConsistency: true])
                let scene = SCNScene()
                installCameraAndLights(in: scene)
                let modelRoot = SCNNode()
                sourceScene.rootNode.childNodes.forEach { node in
                    node.removeFromParentNode()
                    modelRoot.addChildNode(node)
                }
                hideSketchfabHelperCubes(in: modelRoot)
                makeMaterialsDoubleSided(in: modelRoot)
                fitModel(modelRoot)
                scene.rootNode.addChildNode(modelRoot)
                sceneView.scene = scene
                updateParent(statusText: L10n.t("ar.loaded.gesture", parent.language), isModelLoaded: true)
            } catch {
                lastLoadedURL = nil
                updateParent(statusText: L10n.t("ar.loadFailed", parent.language, error.localizedDescription), isModelLoaded: false)
            }
        }

        private func updateParent(statusText: String? = nil, isModelLoaded: Bool? = nil) {
            DispatchQueue.main.async {
                if let statusText {
                    self.parent.statusText = statusText
                }
                if let isModelLoaded {
                    self.parent.isModelLoaded = isModelLoaded
                }
            }
        }

        private func installCameraAndLights(in scene: SCNScene) {
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.fieldOfView = 35
            cameraNode.position = SCNVector3(0, 0, 4)
            scene.rootNode.addChildNode(cameraNode)

            let keyLight = SCNNode()
            keyLight.light = SCNLight()
            keyLight.light?.type = .directional
            keyLight.light?.intensity = 900
            keyLight.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
            scene.rootNode.addChildNode(keyLight)

            let fillLight = SCNNode()
            fillLight.light = SCNLight()
            fillLight.light?.type = .ambient
            fillLight.light?.intensity = 350
            scene.rootNode.addChildNode(fillLight)
        }

        private func fitModel(_ node: SCNNode) {
            let bounds = node.boundingBox
            let center = SCNVector3((bounds.min.x + bounds.max.x) / 2, (bounds.min.y + bounds.max.y) / 2, (bounds.min.z + bounds.max.z) / 2)
            let extent = SCNVector3(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z)
            let maxExtent = Swift.max(extent.x, Swift.max(extent.y, extent.z))
            guard maxExtent > 0 else { return }
            let scale = 1.8 / maxExtent
            node.position = SCNVector3(-center.x * scale, -center.y * scale, -center.z * scale)
            node.scale = SCNVector3(scale, scale, scale)
        }

        private func hideSketchfabHelperCubes(in node: SCNNode, parentName: String = "") {
            let parentLower = parentName.lowercased()
            for child in node.childNodes {
                let lower = child.name?.lowercased() ?? ""
                let isHelperCube = lower.hasPrefix("cube_")
                let isHelperCubeMesh = lower == "object_0" && parentLower.hasPrefix("cube_")
                if isHelperCube || isHelperCubeMesh {
                    child.isHidden = true
                } else {
                    hideSketchfabHelperCubes(in: child, parentName: child.name ?? "")
                }
            }
        }

        private func makeMaterialsDoubleSided(in node: SCNNode) {
            node.geometry?.materials.forEach { $0.isDoubleSided = true }
            node.childNodes.forEach(makeMaterialsDoubleSided)
        }
    }
}
#endif
