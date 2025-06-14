// Toddl-AR/ARDoodleView.swift

import SwiftUI
import RealityKit
import ARKit

struct ARDoodleView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @Binding var activeActivityId: ActivityID?
    @State private var startTime = Date()
    @State private var clearDoodles = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ARDoodleViewContainer(clearDoodles: $clearDoodles)
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()
                
                HStack {
                    Button("Clear") {
                        Haptics.shared.impact(.medium)
                        clearDoodles.toggle()
                    }
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(15)

                    Button("Finish") {
                        Haptics.shared.impact(.medium)
                        let duration = Date().timeIntervalSince(startTime)
                        Task {
                            await viewModel.updateProgressAndHistory(
                                activityId: "ar-doodling",
                                activityName: "AR Doodling",
                                totalSteps: 1,
                                stepsCompleted: 1,
                                duration: duration
                            )
                            activeActivityId = nil
                        }
                    }
                    .font(.headline)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding()
            }
        }
    }
}

struct ARDoodleViewContainer: UIViewRepresentable {
    @Binding var clearDoodles: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        arView.session.run(config)
        
        context.coordinator.arView = arView
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        arView.addGestureRecognizer(panGesture)
        
        context.coordinator.doodleAnchor = AnchorEntity()
        arView.scene.addAnchor(context.coordinator.doodleAnchor)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if clearDoodles {
            context.coordinator.clearDoodles()
            DispatchQueue.main.async {
                self.clearDoodles = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        weak var arView: ARView?
        var doodleAnchor: AnchorEntity!
        private var lastPanLocation: CGPoint?
        private var strokeColor: UIColor = .random

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let arView = arView else { return }
            let panLocation = gesture.location(in: arView)

            switch gesture.state {
            case .began:
                Haptics.shared.impact(.light)
                lastPanLocation = panLocation
                strokeColor = .random
            case .changed:
                Haptics.shared.selectionChanged()
                if let lastPanLocation = self.lastPanLocation {
                    let points = stride(from: 0, to: 1, by: 0.1).map {
                        let interpolatedPoint = CGPoint(
                            x: lastPanLocation.x * (1 - CGFloat($0)) + panLocation.x * CGFloat($0),
                            y: lastPanLocation.y * (1 - CGFloat($0)) + panLocation.y * CGFloat($0)
                        )
                        return interpolatedPoint
                    }
                    
                    for point in points {
                        placeSphere(at: point)
                    }
                }
                self.lastPanLocation = panLocation
            default:
                lastPanLocation = nil
            }
        }

        private func placeSphere(at screenPosition: CGPoint) {
            guard let arView = arView else { return }
            
            if let raycastResult = arView.ray(through: screenPosition) {
                let position = raycastResult.origin + raycastResult.direction * 0.5
                let sphere = ModelEntity(mesh: .generateSphere(radius: 0.01), materials: [SimpleMaterial(color: strokeColor, isMetallic: false)])
                sphere.position = position
                doodleAnchor.addChild(sphere)
            }
        }
        
        func clearDoodles() {
            doodleAnchor.children.removeAll()
        }
    }
}

extension UIColor {
    static var random: UIColor {
        return UIColor(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1),
            alpha: 1.0
        )
    }
}
