import SwiftUI

#if os(iOS)
import RealityKit
import ARKit
import UIKit

struct ARViewContainer: UIViewRepresentable {
    @Binding var statusText: String
    @Binding var isModelLoaded: Bool
    let modelURL: URL?
    let hasBuiltInAnimation: Bool
    let language: AppLanguage
    let resetRequestID: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView
        context.coordinator.installManualGestures(on: arView)

        guard ARWorldTrackingConfiguration.isSupported else {
            DispatchQueue.main.async {
                self.statusText = L10n.t("ar.unsupported", self.language)
            }
            return arView
        }

        statusText = L10n.t("ar.initializing", language)
        isModelLoaded = false
        context.coordinator.startSession()
        arView.backgroundColor = .white

        return arView
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.cleanup()
        uiView.session.pause()
        uiView.session.delegate = nil
        uiView.scene.anchors.removeAll()
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // UIViewRepresentable is a value type; keep the long-lived coordinator pointed
        // at the latest bindings/state on every SwiftUI update. Without this, the AR
        // model can be visible while the overlay still reads the old “initializing” state.
        context.coordinator.parent = self

        guard let url = modelURL else {
            DispatchQueue.main.async {
                statusText = L10n.t("ar.downloadFirst", language)
            }
            return
        }

        if context.coordinator.consumeResetRequestIfNeeded(resetRequestID, url: url, hasBuiltInAnimation: hasBuiltInAnimation) {
            return
        }

        context.coordinator.loadModel(url: url, hasBuiltInAnimation: hasBuiltInAnimation)
    }

    class Coordinator: NSObject, ARSessionDelegate, UIGestureRecognizerDelegate {
        var parent: ARViewContainer
        weak var arView: ARView?
        private var currentAnchor: AnchorEntity?
        private var currentModel: Entity?
        private var lastLoadedURL: URL?
        private var animationTimer: Timer?
        private var floatPhase: Float = 0
        private var rotatingEntity: Entity?
        private var isModelLoaded = false
        private var isLoading = false
        private var lastPanTranslation: CGPoint = .zero
        private var lastPinchScale: CGFloat = 1
        private var lastRotation: CGFloat = 0
        private var lastHandledResetRequestID = 0
        private var initialModelScale = SIMD3<Float>(repeating: 1)
        private var initialModelPosition = SIMD3<Float>(repeating: 0)

        init(_ parent: ARViewContainer) {
            self.parent = parent
            self.lastHandledResetRequestID = parent.resetRequestID
        }

        func startSession() {
            guard let arView, ARWorldTrackingConfiguration.isSupported else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        func installManualGestures(on arView: ARView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            arView.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            arView.addGestureRecognizer(pinch)

            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotation.delegate = self
            arView.addGestureRecognizer(rotation)
        }

        func cleanup() {
            animationTimer?.invalidate()
            animationTimer = nil
            rotatingEntity = nil
            currentModel = nil
            currentAnchor = nil
            lastLoadedURL = nil
            isModelLoaded = false
            isLoading = false
            parent.isModelLoaded = false
        }

        func loadModel(url: URL, hasBuiltInAnimation: Bool) {
            guard let arView, !isLoading, lastLoadedURL != url else { return }
            isLoading = true
            isModelLoaded = false
            lastLoadedURL = url
            parent.statusText = L10n.t("ar.loadingModel", parent.language)
            parent.isModelLoaded = false

            if let oldAnchor = currentAnchor {
                arView.scene.removeAnchor(oldAnchor)
            }
            animationTimer?.invalidate()

            // Use an immediate world anchor instead of waiting for plane detection.
            // This avoids staying on “initializing AR” when ARKit is slow to find a plane,
            // and it makes repeated open/close of the same model deterministic.
            let anchor = AnchorEntity(world: simd_float4x4(translation: initialAnchorPosition(in: arView)))
            currentAnchor = anchor

            do {
                let modelEntity = try ModelEntity.load(contentsOf: url)
                hideSketchfabHelperCubes(in: modelEntity)
                makeMaterialsDoubleSided(in: modelEntity)

                let bounds = modelEntity.visualBounds(relativeTo: nil)
                let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
                // Keep the first AR view comfortably inside the camera frame.
                // Some Sketchfab USDZ files use very large source units, so the lower
                // scale bound must be tiny instead of clamped to 0.02.
                let targetMaxSize: Float = 0.035
                let fittedScale = maxExtent > 0 ? min(max(targetMaxSize / maxExtent, 0.00005), 2.0) : 0.035

                let memoryKey = transformMemoryKey(for: url)
                initialModelScale = SIMD3<Float>(repeating: fittedScale)
                initialModelPosition = -bounds.center * fittedScale
                modelEntity.scale = initialModelScale
                modelEntity.position = initialModelPosition
                modelEntity.generateCollisionShapes(recursive: true)
                currentModel = modelEntity

                anchor.addChild(modelEntity)
                restoreTransform(memoryKey: memoryKey, anchor: anchor, model: modelEntity)
                arView.scene.addAnchor(anchor)

                isLoading = false
                isModelLoaded = true
                parent.isModelLoaded = true
                let animations = modelEntity.availableAnimations
                if hasBuiltInAnimation || !animations.isEmpty {
                    for animation in animations {
                        modelEntity.playAnimation(animation.repeat(), transitionDuration: 0.3)
                    }
                    parent.statusText = L10n.t("ar.loaded.gesture", parent.language)
                } else {
                    parent.statusText = L10n.t("ar.loaded.gesture", parent.language)
                }
            } catch {
                isLoading = false
                isModelLoaded = false
                parent.isModelLoaded = false
                lastLoadedURL = nil
                parent.statusText = L10n.t("ar.loadFailed", parent.language, error.localizedDescription)
            }
        }


        private func hideSketchfabHelperCubes(in entity: Entity, parentName: String = "") {
            let lowercasedParentName = parentName.lowercased()
            for child in entity.children {
                let lowercasedName = child.name.lowercased()
                // Many Sketchfab USDZ files include a visible helper cube named
                // Cube_0/Cube_2, sometimes with a child mesh named Object_0. Hide the
                // whole cube subtree, but do not hide every Object_0 globally: several
                // real biological meshes, including the lily model, use Object_0.
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

        private func transformMemoryKey(for url: URL) -> String {
            "ar.transform.\(url.lastPathComponent)"
        }

        func consumeResetRequestIfNeeded(_ resetRequestID: Int, url: URL, hasBuiltInAnimation: Bool) -> Bool {
            guard resetRequestID != lastHandledResetRequestID else { return false }
            lastHandledResetRequestID = resetRequestID
            resetModelToInitialState(url: url, hasBuiltInAnimation: hasBuiltInAnimation)
            return true
        }

        private func resetModelToInitialState(url: URL, hasBuiltInAnimation: Bool) {
            clearSavedTransform(for: url)
            lastPanTranslation = .zero
            lastPinchScale = 1
            lastRotation = 0

            if let arView, let anchor = currentAnchor, let model = currentModel, lastLoadedURL == url {
                // Make reset visibly useful even if the user has physically moved the phone:
                // put the existing model back in front of the current camera, and restore
                // the exact initial scale/center/orientation without waiting for a reload.
                anchor.position = initialAnchorPosition(in: arView)
                anchor.orientation = simd_quatf()
                model.scale = initialModelScale
                model.position = initialModelPosition
                model.orientation = simd_quatf()
                parent.statusText = L10n.t("ar.resetDone", parent.language)
                parent.isModelLoaded = true
                isModelLoaded = true
                return
            }

            lastLoadedURL = nil
            currentModel = nil

            if let oldAnchor = currentAnchor {
                arView?.scene.removeAnchor(oldAnchor)
            }
            currentAnchor = nil
            animationTimer?.invalidate()
            animationTimer = nil
            rotatingEntity = nil

            parent.statusText = L10n.t("ar.resetDone", parent.language)
            parent.isModelLoaded = false
            isModelLoaded = false
            isLoading = false
            loadModel(url: url, hasBuiltInAnimation: hasBuiltInAnimation)
        }

        private func initialAnchorPosition(in arView: ARView) -> SIMD3<Float> {
            guard let frame = arView.session.currentFrame else {
                return SIMD3<Float>(0, 0, -1.8)
            }

            let transform = frame.camera.transform
            let cameraPosition = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            return cameraPosition + simd_normalize(forward) * 1.8
        }

        private func clearSavedTransform(for url: URL) {
            let memoryKey = transformMemoryKey(for: url)
            let defaults = UserDefaults.standard
            [
                "exists",
                "scale",
                "anchor.x",
                "anchor.y",
                "anchor.z",
                "orientation.ix",
                "orientation.iy",
                "orientation.iz",
                "orientation.r"
            ].forEach { suffix in
                defaults.removeObject(forKey: "\(memoryKey).\(suffix)")
            }
        }

        private func restoreTransform(memoryKey: String, anchor: AnchorEntity, model: Entity) {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "\(memoryKey).exists") else { return }

            let savedScale = defaults.float(forKey: "\(memoryKey).scale")
            if savedScale > 0 {
                model.scale = SIMD3<Float>(repeating: min(max(savedScale, 0.00005), 5.0))
            }

            anchor.position = SIMD3<Float>(
                defaults.float(forKey: "\(memoryKey).anchor.x"),
                defaults.float(forKey: "\(memoryKey).anchor.y"),
                defaults.float(forKey: "\(memoryKey).anchor.z")
            )

            let ix = defaults.float(forKey: "\(memoryKey).orientation.ix")
            let iy = defaults.float(forKey: "\(memoryKey).orientation.iy")
            let iz = defaults.float(forKey: "\(memoryKey).orientation.iz")
            let r = defaults.float(forKey: "\(memoryKey).orientation.r")
            if r != 0 || ix != 0 || iy != 0 || iz != 0 {
                model.orientation = simd_quatf(ix: ix, iy: iy, iz: iz, r: r)
            }
        }

        private func saveCurrentTransform() {
            guard let url = lastLoadedURL, let anchor = currentAnchor, let model = currentModel else { return }
            let memoryKey = transformMemoryKey(for: url)
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "\(memoryKey).exists")
            defaults.set(model.scale.x, forKey: "\(memoryKey).scale")
            defaults.set(anchor.position.x, forKey: "\(memoryKey).anchor.x")
            defaults.set(anchor.position.y, forKey: "\(memoryKey).anchor.y")
            defaults.set(anchor.position.z, forKey: "\(memoryKey).anchor.z")
            defaults.set(model.orientation.vector.x, forKey: "\(memoryKey).orientation.ix")
            defaults.set(model.orientation.vector.y, forKey: "\(memoryKey).orientation.iy")
            defaults.set(model.orientation.vector.z, forKey: "\(memoryKey).orientation.iz")
            defaults.set(model.orientation.vector.w, forKey: "\(memoryKey).orientation.r")
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let anchor = currentAnchor else { return }
            let translation = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .began:
                lastPanTranslation = translation
            case .changed:
                let dx = Float(translation.x - lastPanTranslation.x) * 0.0015
                let dy = Float(translation.y - lastPanTranslation.y) * -0.0015
                anchor.position += SIMD3<Float>(dx, dy, 0)
                lastPanTranslation = translation
            default:
                saveCurrentTransform()
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
                let next = min(max(model.scale.x * factor, 0.00005), 5.0)
                model.scale = SIMD3<Float>(repeating: next)
                lastPinchScale = recognizer.scale
            default:
                saveCurrentTransform()
                lastPinchScale = 1
            }
        }

        @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            guard let model = currentModel else { return }
            switch recognizer.state {
            case .began:
                lastRotation = recognizer.rotation
            case .changed:
                let delta = Float(recognizer.rotation - lastRotation)
                model.orientation = simd_quatf(angle: -delta, axis: SIMD3<Float>(0, 1, 0)) * model.orientation
                lastRotation = recognizer.rotation
            default:
                saveCurrentTransform()
                lastRotation = 0
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .notAvailable:
                guard !isModelLoaded && !isLoading && lastLoadedURL == nil else { return }
                DispatchQueue.main.async { self.parent.statusText = L10n.t("ar.cameraUnavailable", self.parent.language) }
            case .limited(let reason):
                // Do not let ARKit tracking-state callbacks overwrite model-loading or
                // loaded UI text. Tracking may remain “initializing/limited” briefly even
                // after the model is already visible.
                guard !isModelLoaded && !isLoading && lastLoadedURL == nil else { return }
                let msg: String
                switch reason {
                case .initializing: msg = L10n.t("ar.initializing", parent.language)
                case .relocalizing: msg = L10n.t("ar.relocalizing", parent.language)
                case .excessiveMotion: msg = L10n.t("ar.excessiveMotion", parent.language)
                case .insufficientFeatures: msg = L10n.t("ar.insufficientFeatures", parent.language)
                @unknown default: msg = L10n.t("ar.trackingLimited", parent.language)
                }
                DispatchQueue.main.async { self.parent.statusText = msg }
            case .normal:
                if !isModelLoaded && !isLoading {
                    DispatchQueue.main.async { self.parent.statusText = L10n.t("ar.ready", self.parent.language) }
                }
            @unknown default:
                break
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async {
                self.parent.statusText = L10n.t("ar.sessionFailed", self.parent.language, error.localizedDescription)
            }
        }

        private func addStaticAnimations(to entity: Entity) {
            let originalY = entity.position.y
            rotatingEntity = entity
            floatPhase = 0

            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self, let entity = self.rotatingEntity else { return }
                self.floatPhase += 0.05
                let yOffset = sin(self.floatPhase) * 0.03
                entity.position = SIMD3<Float>(entity.position.x, originalY + yOffset, entity.position.z)
                let angle = self.floatPhase * 0.1
                entity.transform.rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }
}

private extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    }
}
#elseif os(macOS)
import AppKit
import SceneKit

struct ARViewContainer: NSViewRepresentable {
    @Binding var statusText: String
    @Binding var isModelLoaded: Bool
    let modelURL: URL?
    let hasBuiltInAnimation: Bool
    let language: AppLanguage
    let resetRequestID: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SCNView {
        let sceneView = SCNView(frame: .zero)
        sceneView.scene = context.coordinator.emptyScene()
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = .windowBackgroundColor
        sceneView.rendersContinuously = true
        context.coordinator.sceneView = sceneView
        statusText = L10n.t("ar.initializing", language)
        return sceneView
    }

    func updateNSView(_ sceneView: SCNView, context: Context) {
        context.coordinator.parent = self

        guard let url = modelURL else {
            DispatchQueue.main.async {
                statusText = L10n.t("ar.downloadFirst", language)
                isModelLoaded = false
            }
            return
        }

        if context.coordinator.consumeResetRequestIfNeeded(resetRequestID, url: url) {
            return
        }

        context.coordinator.loadModel(url: url)
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: Coordinator) {
        coordinator.cleanup()
        nsView.scene = nil
    }

    final class Coordinator: NSObject {
        var parent: ARViewContainer
        weak var sceneView: SCNView?
        private var lastLoadedURL: URL?
        private var lastHandledResetRequestID = 0

        init(_ parent: ARViewContainer) {
            self.parent = parent
            self.lastHandledResetRequestID = parent.resetRequestID
        }

        func emptyScene() -> SCNScene {
            let scene = SCNScene()
            installCameraAndLights(in: scene)
            return scene
        }

        func cleanup() {
            lastLoadedURL = nil
            parent.isModelLoaded = false
        }

        func consumeResetRequestIfNeeded(_ resetRequestID: Int, url: URL) -> Bool {
            guard resetRequestID != lastHandledResetRequestID else { return false }
            lastHandledResetRequestID = resetRequestID
            lastLoadedURL = nil
            loadModel(url: url)
            parent.statusText = L10n.t("ar.resetDone", parent.language)
            return true
        }

        func loadModel(url: URL) {
            guard let sceneView, lastLoadedURL != url else { return }
            lastLoadedURL = url
            parent.statusText = L10n.t("ar.loadingModel", parent.language)
            parent.isModelLoaded = false

            do {
                let sourceScene = try SCNScene(url: url, options: [.checkConsistency: true])
                let scene = emptyScene()
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

                parent.isModelLoaded = true
                parent.statusText = L10n.t("ar.loaded.gesture", parent.language)
            } catch {
                lastLoadedURL = nil
                parent.isModelLoaded = false
                parent.statusText = L10n.t("ar.loadFailed", parent.language, error.localizedDescription)
            }
        }

        private func installCameraAndLights(in scene: SCNScene) {
            let cameraNode = SCNNode()
            cameraNode.name = "PreviewCamera"
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
            let min = bounds.min
            let max = bounds.max
            let center = SCNVector3(
                (min.x + max.x) / 2,
                (min.y + max.y) / 2,
                (min.z + max.z) / 2
            )
            let extent = SCNVector3(max.x - min.x, max.y - min.y, max.z - min.z)
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
