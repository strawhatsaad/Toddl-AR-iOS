import SwiftUI
import RealityKit
import Combine
import ARKit

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

// Main View that controls the app's flow
struct ContentView: View {
    @StateObject private var viewModel = AuthViewModel()
    
    var body: some View {
        ZStack {
            Group {
                switch viewModel.appState {
                case .splash:
                    SplashScreenView()
                case .intro:
                    IntroScreenView()
                case .login:
                    LoginView()
                case .signUp:
                    SignUpView()
                case .toddlerProfileSetup:
                    ToddlerProfileSetupView()
                case .mainHub:
                    MainHubView()
                }
            }
            .environmentObject(viewModel)
            .animation(.easeInOut, value: viewModel.appState)
            
            if viewModel.isLoading {
                LoadingView()
            }
            
            if viewModel.showMessage {
                MessageView(
                    title: viewModel.messageTitle,
                    message: viewModel.messageContent,
                    isError: viewModel.messageIsError,
                    onDismiss: {
                        if viewModel.messageTitle == "Success!" {
                            viewModel.appState = .login
                        }
                        viewModel.showMessage = false
                    }
                )
            }
        }
    }
}

// --- NEW --- Numbers in AR Activity
// In Toddl-AR/ContentView.swift

// --- REPLACE the entire NumbersARView struct with this one ---
struct NumbersARView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var startTime = Date()
    
    @Binding var activeActivityId: ActivityID?
    @State private var challenges: [NumberChallenge] = []
    @State private var currentIndex = 0
    @State private var isSolved = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NumbersARViewContainer(challenge: challenges.isEmpty ? nil : challenges[currentIndex], isSolved: $isSolved)
                .edgesIgnoringSafeArea(.all)

            if !challenges.isEmpty {
                VStack {
                    HStack {
                        Text(challenges[currentIndex].question)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(15)
                    .padding(.horizontal)

                    Spacer()

                    HStack(spacing: 20) {
                        // Updated "Finish" button
                        Button("Finish") {
                            finishActivity()
                        }
                        .font(.headline)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(15)

                        // Updated "Next/Done!" button
                        Button(action: {
                            if currentIndex < challenges.count - 1 {
                                currentIndex += 1
                                isSolved = false
                            } else {
                                // On the last step, call finishActivity
                                finishActivity()
                            }
                        }) {
                            HStack {
                                Text(currentIndex < challenges.count - 1 ? "Next" : "Done!")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .font(.headline)
                        .padding()
                        .background(isSolved ? Color.green.opacity(0.9) : Color.gray.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .disabled(!isSolved)
                    }
                    .padding()
                }
            }
        }
        .onAppear(perform: generateChallenges)
    }
    
    func generateChallenges() {
        var newChallenges: [NumberChallenge] = []
        for _ in 0..<5 {
            let isAddition = Bool.random()
            if isAddition {
                let a = Int.random(in: 1...3)
                let b = Int.random(in: 1...2)
                newChallenges.append(NumberChallenge(type: .addition, question: "\(a) + \(b) = ?", initialCount: a, answer: a + b))
            } else {
                let a = Int.random(in: 3...5)
                let b = Int.random(in: 1..<a)
                newChallenges.append(NumberChallenge(type: .subtraction, question: "\(a) - \(b) = ?", initialCount: a, answer: a - b))
            }
        }
        self.challenges = newChallenges
    }
    
    // --- NEW HELPER FUNCTION ---
    private func finishActivity() {
        let duration = Date().timeIntervalSince(startTime)
        
        // We count how many challenges were actually solved
        let stepsCompleted = isSolved ? (currentIndex + 1) : currentIndex
        
        Task {
            await viewModel.updateProgressAndHistory(
                activityId: "numbers-in-ar",
                activityName: "Numbers in AR",
                totalSteps: challenges.count,
                stepsCompleted: stepsCompleted,
                duration: duration
            )
            // Dismiss the view after the update is complete
            activeActivityId = nil
        }
    }
}

struct NumberChallenge {
    enum ChallengeType { case addition, subtraction }
    let type: ChallengeType
    let question: String
    let initialCount: Int
    let answer: Int
}

struct NumbersARViewContainer: UIViewRepresentable {
    var challenge: NumberChallenge?
    @Binding var isSolved: Bool
    //    var key: Int
    
    func makeUIView(context: Context) -> ARView {
        // --- ADD THIS LINE ---
        print("AR VIEW IS RESETTING: makeUIView has been called.")
        // -----------------------
        
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.isSolved = $isSolved
        context.coordinator.updateChallenge(challenge)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // Replace the entire Coordinator class with this updated version
    
    class Coordinator: NSObject {
        weak var arView: ARView?
        var challengeAnchor: AnchorEntity?
        var isSolved: Binding<Bool>?
        private var currentChallenge: NumberChallenge?
        
        // --- NEW PROPERTIES ---
        private var previousCountInZone: Int = -1
        private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
        
        // --- UPDATED: updateChallenge now only sets up the scene once ---
        func updateChallenge(_ newChallenge: NumberChallenge?) {
            // Check if the new challenge is actually different from the current one.
            // This is the key to preventing the reset on completion. If the challenge is the same, we do nothing.
            if newChallenge?.question == self.currentChallenge?.question {
                return
            }
            
            // --- If it's a NEW challenge, we proceed with the reset ---
            
            self.currentChallenge = newChallenge
            self.previousCountInZone = -1 // Reset the haptic counter
            
            challengeAnchor?.removeFromParent()
            guard let challenge = newChallenge else { return }
            
            // Create a new anchor for a fresh scene
            let anchor = AnchorEntity(plane: .horizontal)
            
            let zoneMesh = MeshResource.generatePlane(width: 0.5, depth: 0.5)
            // The material is created fresh and blue every time
            let zoneMaterial = UnlitMaterial(color: .blue.withAlphaComponent(0.1))
            let zoneEntity = ModelEntity(mesh: zoneMesh, materials: [zoneMaterial])
            zoneEntity.name = "targetZone"
            anchor.addChild(zoneEntity)
            
            // Lay out the initial cubes for the new challenge
            for _ in 0..<challenge.initialCount {
                anchor.addChild(createCube(inZone: true))
            }
            
            // Lay out the cubes outside the zone
            for _ in 0..<6 {
                anchor.addChild(createCube(inZone: false))
            }
            
            arView?.scene.addAnchor(anchor)
            self.challengeAnchor = anchor
            recalculateAndCheckSolution()
        }
        
        func createCube(inZone: Bool) -> ModelEntity {
            let cubeMesh = MeshResource.generateBox(size: 0.05, cornerRadius: 0.01)
            let cubeMaterial = SimpleMaterial(color: .systemOrange, roughness: 0.3, isMetallic: false)
            let cube = ModelEntity(mesh: cubeMesh, materials: [cubeMaterial])
            cube.position = randomPosition(inZone: inZone)
            cube.generateCollisionShapes(recursive: true)
            arView?.installGestures([.translation], for: cube).forEach { gesture in
                gesture.addTarget(self, action: #selector(handleDrag))
            }
            return cube
        }
        
        func randomPosition(inZone: Bool) -> SIMD3<Float> {
            let yPos: Float = 0.025
            if inZone {
                return [Float.random(in: -0.2...0.2), yPos, Float.random(in: -0.2...0.2)]
            } else {
                let xPos = Float.random(in: -0.5...0.5)
                let zPos = Float.random(in: 0.3...0.5)
                return [xPos, yPos, zPos]
            }
        }
        
        @objc func handleDrag(_ gesture: EntityTranslationGestureRecognizer) {
            if gesture.state == .ended {
                recalculateAndCheckSolution()
            }
        }
        
        // --- UPDATED: recalculateAndCheckSolution now has haptics ---
        func recalculateAndCheckSolution() {
            guard let anchor = challengeAnchor, let challenge = currentChallenge else { return }
            
            var countInZone = 0
            for entity in anchor.children where entity.name != "targetZone" {
                let position = entity.position(relativeTo: anchor)
                if abs(position.x) <= 0.25 && abs(position.z) <= 0.25 {
                    countInZone += 1
                }
            }
            
            if countInZone != self.previousCountInZone {
                self.hapticGenerator.prepare()
                self.hapticGenerator.impactOccurred()
                self.previousCountInZone = countInZone
            }
            
            if countInZone == challenge.answer {
                // Only trigger "solved" state and animation if the challenge wasn't already marked as solved.
                // This prevents the green zone from getting stuck.
                if isSolved?.wrappedValue == false {
                    isSolved?.wrappedValue = true
                    playSuccessAnimation()
                }
            } else {
                // If the user moves a cube out of the correct solution, mark it as unsolved again.
                isSolved?.wrappedValue = false
            }
        }
        
        func playSuccessAnimation() {
            guard let zone = challengeAnchor?.findEntity(named: "targetZone") as? ModelEntity else { return }
            
            // Create the green success material
            var successMaterial = UnlitMaterial(color: .green)
            successMaterial.blending = .transparent(opacity: 0.5)
            
            // Set the zone's material to green, and that's it!
            zone.model?.materials = [successMaterial]
            
            // The part that changed the color back has been removed.
        }
    }
}

// --- NEW --- Shapes in AR Activity

enum ShapeType {
    case generated(MeshResource)
    case loaded(named: String)
}

struct ShapeStep {
    let name: String
    let color: UIColor
    let type: ShapeType
    var targetSize: Float? = nil
    var positionOffset: SIMD3<Float>? = nil
}

// The main SwiftUI view for the Shapes AR Activity
struct ShapesARView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var startTime = Date()
    @Binding var activeActivityId: ActivityID?
    @State private var currentIndex = 0
    
    // Updated data source with new shapes
    let shapeData: [ShapeStep] = [
        .init(name: "Cube", color: .systemRed, type: .generated(.generateBox(size: 1.0)),
              targetSize: 0.15),
        
            .init(name: "Sphere", color: .systemBlue, type: .generated(.generateSphere(radius: 1.0)),
                  targetSize: 0.2), // A bit larger
        
            .init(name: "Cylinder", color: .systemGreen, type: .loaded(named: "Cylinder.usdz"),
                  targetSize: 0.002, positionOffset: [0, -0.2, 0]),
        
            .init(name: "Pyramid", color: .systemPurple, type: .loaded(named: "Pyramid.usdz"),
                  targetSize: 0.0025,
                  positionOffset: [0, 0, 0]), // Move the pyramid up to sit on the "ground"
        
            .init(name: "Cone", color: .systemOrange, type: .loaded(named: "Cone.usdz"),
                  targetSize: 0.0025,
                  positionOffset: [0, -0.05, 0]), // Move the cone up
        
            .init(name: "Box", color: .systemYellow, type: .generated(.generateBox(size: [0.2, 0.05, 0.12]))) // No targetSize, uses the mesh's defined size
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ShapesARViewContainer(models: shapeData, currentIndex: $currentIndex)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Text(shapeData[currentIndex].name)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(15)
                    .padding(.horizontal)
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: { if currentIndex > 0 { currentIndex -= 1 } }) {
                        Image(systemName: "arrow.left")
                    }.modifier(NavButtonModifier())
                    
                    Button("Finish") {
                        let duration = Date().timeIntervalSince(startTime)
                        // This assumes the user "completes" the activity by finishing.
                        // We pass the total number of steps and how many were viewed.
                        Task {
                            await viewModel.updateProgressAndHistory(
                                activityId: "shapes-in-ar",
                                activityName: "Shapes in AR",
                                totalSteps: shapeData.count,
                                stepsCompleted: currentIndex + 1,
                                duration: duration
                            )
                            // Now dismiss the view
                            activeActivityId = nil
                        }
                    }
                    .font(.headline)
                    .padding()
                    .background(.red)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                    
                    Button(action: { if currentIndex < shapeData.count - 1 { currentIndex += 1 } }) {
                        Image(systemName: "arrow.right")
                    }.modifier(NavButtonModifier(disabled: currentIndex >= shapeData.count - 1))
                }
                .padding()
            }
        }
    }
}

// Helper view modifier for navigation buttons
struct NavButtonModifier: ViewModifier {
    var disabled: Bool = false
    func body(content: Content) -> some View {
        content
            .font(.largeTitle)
            .padding()
            .background(.regularMaterial)
            .clipShape(Circle())
            .opacity(disabled ? 0.3 : 1)
            .disabled(disabled)
    }
}


// The container that hosts the ARView for the shapes activity
struct ShapesARViewContainer: UIViewRepresentable {
    let models: [ShapeStep]
    @Binding var currentIndex: Int
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        context.coordinator.models = models
        
        let config = ARWorldTrackingConfiguration()
        arView.session.run(config)
        
        Task {
            await context.coordinator.showShape(at: currentIndex)
        }
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        Task {
            await context.coordinator.showShape(at: currentIndex)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    @MainActor
    class Coordinator: NSObject {
        weak var arView: ARView?
        var shapeAnchor: AnchorEntity?
        var models: [ShapeStep] = []
        
        func showShape(at index: Int) async {
            if let existingAnchor = shapeAnchor {
                arView?.scene.removeAnchor(existingAnchor)
            }
            
            guard index < models.count else { return }
            
            let step = models[index]
            
            let anchor = AnchorEntity(world: [0, -0.1, -0.7])
            let shapeMaterial = SimpleMaterial(color: step.color, roughness: 0.2, isMetallic: false)
            
            let shapeEntity: ModelEntity
            
            switch step.type {
            case .generated(let mesh):
                shapeEntity = ModelEntity(mesh: mesh)
            case .loaded(let filename):
                do {
                    shapeEntity = try await Entity.loadModel(named: filename)
                } catch {
                    print("Error: Could not load model \(filename): \(error)")
                    shapeEntity = ModelEntity(mesh: .generateBox(size: 0.1))
                }
            }
            
            // --- Apply size and position using the familiar pattern ---
            if let size = step.targetSize {
                normalizeAndConfigure(shapeEntity, targetSize: size)
            }
            if let offset = step.positionOffset {
                shapeEntity.position = offset
            }
            // -----------------------------------------------------------
            
            shapeEntity.model?.materials = [shapeMaterial]
            anchor.addChild(shapeEntity)
            arView?.scene.addAnchor(anchor)
            
            self.shapeAnchor = anchor
        }
        func normalizeAndConfigure(_ entity: ModelEntity, targetSize: Float) {
            let bounds = entity.visualBounds(relativeTo: nil)
            let maxDimension = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            if maxDimension > 0 {
                let scaleFactor = targetSize / maxDimension
                entity.setScale(SIMD3<Float>(repeating: scaleFactor), relativeTo: nil)
            }
            
            entity.generateCollisionShapes(recursive: true)
            arView?.installGestures([.all], for: entity)
        }
    }
}

// AR Activity View for Alphabets
struct ARActivityView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var startTime = Date()
    @Binding var activeActivityId: ActivityID?
    @State private var currentIndex = 0
    
    let alphabetData = [
        AlphabetStep(letter: "A", word: "Apple", modelName: "Apple.usdz", color: .systemRed, targetSize: 0.002, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "B", word: "Ball", modelName: "Ball.usdz", color: .systemBlue, targetSize: 0.2, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "C", word: "Cat", modelName: "Cat.usdz", color: .systemOrange, targetSize: 0.0075, positionOffset: [0, 0, 0]),
        AlphabetStep(letter: "D", word: "Dog", modelName: "Dog.usdz", color: .systemGreen, targetSize: 0.0095, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "E", word: "Elephant", modelName: "Elephant.usdz", color: .systemBlue, targetSize: 0.0085, positionOffset: [0, -0.25, 0]),
        AlphabetStep(letter: "F", word: "Fish", modelName: "Fish.usdz", color: .systemOrange, targetSize: 0.0075, positionOffset: [0.1, 0.02, 0]),
        AlphabetStep(letter: "G", word: "Guitar", modelName: "Guitar.usdz", color: .systemPurple, targetSize: 0.0075, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "H", word: "Horse", modelName: "Horse.usdz", color: .systemPink, targetSize: 0.0075, positionOffset: [0.2, 0, 0]),
        AlphabetStep(letter: "I", word: "Igloo", modelName: "Igloo.usdz", color: .systemIndigo, targetSize: 0.0075, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "J", word: "Jam", modelName: "Jam.usdz", color: .systemRed, targetSize: 0.0035, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "K", word: "Kite", modelName: "Kite.usdz", color: .systemBlue, targetSize: 0.0075, positionOffset: [0, 0.02, 0]),
        AlphabetStep(letter: "L", word: "Lion", modelName: "Lion.usdz", color: .systemOrange, targetSize: 0.0095, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "M", word: "Mouse", modelName: "Mouse.usdz", color: .systemGreen, targetSize: 0.0045, positionOffset: [0, 0, 0]),
        AlphabetStep(letter: "N", word: "Nest", modelName: "Nest.usdz", color: .systemYellow, targetSize: 0.0035, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "O", word: "Octopus", modelName: "Octopus.usdz", color: .systemTeal, targetSize: 0.000075, positionOffset: [0.35, 0, 0]),
        AlphabetStep(letter: "P", word: "Plane", modelName: "Plane.usdz", color: .systemPurple, targetSize: 0.0075, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "Q", word: "Quack", modelName: "Quack.usdz", color: .systemPink, targetSize: 0.0045, positionOffset: [0.1, -0.1, 0]),
        AlphabetStep(letter: "R", word: "Rabbit", modelName: "Rabbit.usdz", color: .systemIndigo, targetSize: 0.0040, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "S", word: "Slide", modelName: "Slide.usdz", color: .systemRed, targetSize: 0.0075, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "T", word: "Tree", modelName: "Tree.usdz", color: .systemBlue, targetSize: 0.0095, positionOffset: [0.15, 0, 0]),
        AlphabetStep(letter: "U", word: "Umbrella", modelName: "Umbrella.usdz", color: .systemOrange, targetSize: 0.0075, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "V", word: "Violin", modelName: "Violin.usdz", color: .systemGreen, targetSize: 0.0075, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "W", word: "Wolf", modelName: "Wolf.usdz", color: .systemYellow, targetSize: 0.0099, positionOffset: [0.15, 0, -0.65]),
        AlphabetStep(letter: "X", word: "Xylophone", modelName: "Xylophone.usdz", color: .systemTeal, targetSize: 0.0065, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "Y", word: "Yacht", modelName: "Yacht.usdz", color: .systemPurple, targetSize: 0.0095, positionOffset: [0.1, 0, 0]),
        AlphabetStep(letter: "Z", word: "Zebra", modelName: "Zebra.usdz", color: .systemPink, targetSize: 0.0075, positionOffset: [0.1, 0, 0])
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(currentIndex: $currentIndex, models: alphabetData)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Text(alphabetData[currentIndex].letter)
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                    Text("is for")
                        .font(.title2)
                    Text(alphabetData[currentIndex].word)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Spacer()
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(15)
                .padding(.horizontal)
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: { if currentIndex > 0 { currentIndex -= 1 } }) {
                        Image(systemName: "arrow.left")
                    }
                    .font(.largeTitle)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .opacity(currentIndex > 0 ? 1 : 0.3)
                    .disabled(currentIndex <= 0)
                    
                    Button("Finish") {
                        let duration = Date().timeIntervalSince(startTime)
                        // This assumes the user "completes" the activity by finishing.
                        // We pass the total number of steps and how many were viewed.
                        Task {
                            await viewModel.updateProgressAndHistory(
                                activityId: "alphabets-in-ar",
                                activityName: "Alphabets in AR",
                                totalSteps: alphabetData.count,
                                stepsCompleted: currentIndex + 1,
                                duration: duration
                            )
                            // Now dismiss the view
                            activeActivityId = nil
                        }
                    }
                    .font(.headline)
                    .padding()
                    .background(.red)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                    
                    Button(action: { if currentIndex < alphabetData.count - 1 { currentIndex += 1 } }) {
                        Image(systemName: "arrow.right")
                    }
                    .font(.largeTitle)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .opacity(currentIndex < alphabetData.count - 1 ? 1 : 0.3)
                    .disabled(currentIndex >= alphabetData.count - 1)
                }
                .padding()
            }
        }
    }
}

// Data model for each step in the alphabet activity
struct AlphabetStep {
    let letter: String
    let word: String
    let modelName: String
    let color: UIColor
    let targetSize: Float?
    let positionOffset: SIMD3<Float>?
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var currentIndex: Int
    let models: [AlphabetStep]
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        context.coordinator.models = models
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        Task {
            await context.coordinator.showAlphabet(at: currentIndex)
        }
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        Task {
            await context.coordinator.showAlphabet(at: currentIndex)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        weak var arView: ARView?
        var alphabetAnchor: AnchorEntity?
        var models: [AlphabetStep] = []
        
        @MainActor
        func showAlphabet(at index: Int) async {
            // If we have a persistent anchor, remove all the old models from it.
            if let anchor = self.alphabetAnchor {
                anchor.children.removeAll()
            } else {
                // If this is the first run, create our persistent anchor and add it to the scene.
                let newAnchor = AnchorEntity(plane: .horizontal)
                arView?.scene.addAnchor(newAnchor)
                self.alphabetAnchor = newAnchor
            }
            
            // We can now be sure we have a clean anchor to work with.
            guard let anchor = self.alphabetAnchor else { return }
            guard index < models.count else { return }
            
            let step = models[index]
            
            let letterMesh = MeshResource.generateText(step.letter, extrusionDepth: 0.05, font: .systemFont(ofSize: 0.25, weight: .bold))
            let letterMaterial = SimpleMaterial(color: step.color, roughness: 0.3, isMetallic: false)
            let letterEntity = ModelEntity(mesh: letterMesh, materials: [letterMaterial])
            
            do {
                let objectEntity = try await ModelEntity(named: step.modelName)
                
                // This helper function will now add the new models to our persistent anchor
                configureAndPlaceModels(letter: letterEntity, object: objectEntity, on: anchor, step: step)
                
            } catch {
                print("Error loading model \(step.modelName): \(error)")
                let fallbackEntity = ModelEntity(mesh: .generateBox(size: 0.1), materials: [SimpleMaterial(color: .orange, isMetallic: false)])
                anchor.addChild(fallbackEntity)
            }
        }
        
        @MainActor
        func configureAndPlaceModels(letter: ModelEntity, object: ModelEntity, on anchor: AnchorEntity, step: AlphabetStep) {
            let objectSize = step.targetSize ?? 0.15
            
            normalizeAndConfigure(object, targetSize: objectSize)
            normalizeAndConfigure(letter, targetSize: 0.2)
            
            let letterBounds = letter.visualBounds(relativeTo: nil)
            let objectBounds = object.visualBounds(relativeTo: nil)
            
            let gap: Float = 0.1
            let letterWidth = letterBounds.extents.x
            let objectWidth = objectBounds.extents.x
            
            letter.position.x = -gap/2 - letterWidth/2
            object.position.x = gap/2 + objectWidth/2
            
            letter.position.y = -letterBounds.min.y
            object.position.y = -objectBounds.min.y
            
            if let offset = step.positionOffset {
                object.position += offset
            }
            
            anchor.addChild(letter)
            anchor.addChild(object)
        }
        
        func normalizeAndConfigure(_ entity: ModelEntity, targetSize: Float) {
            let bounds = entity.visualBounds(relativeTo: nil)
            let maxDimension = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            if maxDimension > 0 {
                let scaleFactor = targetSize / maxDimension
                entity.setScale(SIMD3<Float>(repeating: scaleFactor), relativeTo: nil)
            }
            
            entity.generateCollisionShapes(recursive: true)
            arView?.installGestures([.all], for: entity)
            
            if let firstAnimation = entity.availableAnimations.first {
                entity.playAnimation(firstAnimation.repeat())
            }
        }
    }
}


// The Splash Screen View
struct SplashScreenView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Image("figure.wave")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 180, height: 180)
                    .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                
                Text("Toddl-AR")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5)) {
                    self.scale = 1.0
                    self.opacity = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if viewModel.userSession == nil {
                        viewModel.appState = .intro
                    }
                }
            }
        }
    }
}

// View for the swipeable intro screens
struct IntroScreenView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    
    var body: some View {
        VStack {
            TabView {
                IntroPage(imageName: "illustration-1", title: "Learn anytime and anywhere", description: "Toddl-AR is the perfect place for your children to learn something new.")
                IntroPage(imageName: "illustration-4", title: "Find the perfect plan for your little nugget!", description: "Toddl-AR provides plans that align with your child's best interests.")
                IntroPage(imageName: "illustration-5", title: "Improve their skills is the Number One Priority", description: "Fun and exciting activities to bring out the best in your child.")
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            
            PrimaryButton(title: "Let's Start") {
                viewModel.appState = .login
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .background(Color.white.edgesIgnoringSafeArea(.all))
    }
}

// The Login Screen
struct LoginView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(spacing: 20) {
                    Image("illustration-2")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 280)
                        .cornerRadius(20)
                        .padding(.top, 40)
                    
                    Text("Log in")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    CustomTextField(placeholder: "Email", text: $email, iconName: "envelope.fill")
                    CustomSecureField(placeholder: "Password", text: $password)
                    
                    HStack {
                        Spacer()
                        Button("Forgot Password?") {}
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                    
                    PrimaryButton(title: "Log in") {
                        hideKeyboard()
                        Task { await viewModel.signIn(withEmail: email, password: password) }
                    }
                    .padding(.top, 20)
                    
                    HStack {
                        Text("Don't have an account?")
                            .foregroundColor(.gray)
                        Button("Sign up") {
                            viewModel.appState = .signUp
                        }
                        .foregroundColor(.orange)
                        .fontWeight(.bold)
                    }
                    .font(.system(size: 16, design: .rounded))
                    .padding(.top, 20)
                    Spacer()
                }
                .padding(30)
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
}

// The Sign Up Screen
struct SignUpView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(spacing: 20) {
                    Image("illustration-3")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 220)
                        .cornerRadius(20)
                        .padding(.top, 40)
                    
                    Text("Sign up")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .padding(.bottom, 10)
                    
                    CustomTextField(placeholder: "Name", text: $name, iconName: "person.fill")
                    CustomTextField(placeholder: "Email", text: $email, iconName: "envelope.fill")
                    CustomSecureField(placeholder: "Password", text: $password)
                    
                    PrimaryButton(title: "Sign up") {
                        hideKeyboard()
                        Task { await viewModel.signUp(withEmail: email, password: password, name: name) }
                    }
                    .padding(.top, 30)
                    
                    HStack {
                        Text("Already have an account?")
                            .foregroundColor(.gray)
                        Button("Log in") {
                            viewModel.appState = .login
                        }
                        .foregroundColor(.orange)
                        .fontWeight(.bold)
                    }
                    .font(.system(size: 16, design: .rounded))
                    .padding(.top, 20)
                    Spacer()
                }
                .padding(30)
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
}

// Toddler Profile Setup Screen
struct ToddlerProfileSetupView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var toddlerName = ""
    @State private var toddlerAge = ""
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(spacing: 25) {
                    Text("Setup Toddler's Profile")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.top, 50)
                    
                    Image("toddler1")
                        .resizable()
                        .frame(width: 190, height: 190, alignment: .top)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.orange, lineWidth: 4))
                        .shadow(radius: 10)
                        .padding(.bottom, 20)
                    
                    CustomTextField(placeholder: "Toddler's Name", text: $toddlerName, iconName: "face.smiling.fill")
                    CustomTextField(placeholder: "Age", text: $toddlerAge, iconName: "gift.fill")
                        .keyboardType(.numberPad)
                    
                    PrimaryButton(title: "Create Profile") {
                        hideKeyboard()
                        guard !toddlerName.isEmpty, !toddlerAge.isEmpty else {
                            viewModel.displayMessage("Error", "Please fill in all fields.", isError: true)
                            return
                        }
                        Task { await viewModel.createToddlerProfile(name: toddlerName, age: toddlerAge) }
                    }
                    .padding(.top, 30)
                    
                    Spacer()
                }
                .padding(30)
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
}

// Main Hub View with Bottom Tab Bar
struct MainHubView: View {
    @State private var selectedTab: Tab = .activity
    @Namespace private var animation
    
    @State private var activeActivityId: ActivityID? = nil
    
    enum Tab {
        case activity, profile, settings
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(UIColor.systemGray6).edgesIgnoringSafeArea(.all)
            
            TabView(selection: $selectedTab.animation(.easeInOut)) {
                ActivitiesView(activeActivityId: $activeActivityId).tag(Tab.activity)
                ToddlerProfileView().tag(Tab.profile)
                SettingsView().tag(Tab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Custom Tab Bar
            HStack {
                TabBarButton(iconName: "gamecontroller.fill", tab: .activity, selectedTab: $selectedTab, animation: animation)
                TabBarButton(iconName: "person.fill", tab: .profile, selectedTab: $selectedTab, animation: animation)
                TabBarButton(iconName: "gearshape.fill", tab: .settings, selectedTab: $selectedTab, animation: animation)
            }
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            .padding(.horizontal)
        }
        .edgesIgnoringSafeArea(.bottom)
        .fullScreenCover(item: $activeActivityId) { activity in
            if activity.id == "alphabets-in-ar" {
                ARActivityView(activeActivityId: $activeActivityId)
            } else if activity.id == "numbers-in-ar" {
                NumbersARView(activeActivityId: $activeActivityId)
            } else if activity.id == "shapes-in-ar" {
                ShapesARView(activeActivityId: $activeActivityId)
            }
        }
    }
}

// Allows using a String? for the .fullScreenCover item
struct ActivityID: Identifiable {
    let id: String
}

// --- NEW --- Reusable view for the activity cards on the main hub

// Replace the entire ActivityCardView struct with this corrected version.

struct ActivityCardView: View {
    let activityId: String
    let activityName: String
    var duration: Int? = nil
    
    var body: some View {
        VStack {
            // The helper property now contains the necessary modifiers inside it
            activityImageView
                .frame(height: 120) // These modifiers work on any view
                .clipped()
                .cornerRadius(15)
            
            Text(activityName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            // --- ADD THIS BLOCK TO DISPLAY THE DURATION ---
                       if let duration = duration {
                           Spacer(minLength: 4)
                           HStack(spacing: 4) {
                               Image(systemName: "clock.fill")
                               Text(formatDuration(duration))
                           }
                           .font(.caption)
                           .foregroundColor(.secondary)
                       }
                       // ---------------------------------------------
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
    }
    
    private func formatDuration(_ totalSeconds: Int) -> String {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            if minutes > 0 {
                return "\(minutes) min \(seconds) sec"
            } else {
                return "\(seconds) sec"
            }
        }
    
    @ViewBuilder
    private var activityImageView: some View {
        // The conditional logic is now self-contained
        if activityId == "shapes-in-ar" {
            ZStack {
                Color(UIColor.systemGray5)
                Image(systemName: "square.on.circle")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
            }
        } else {
            // .resizable() and .aspectRatio() are now applied only to the Image
            Image(activityId)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
}

// Activities View (Home Screen)
struct ActivitiesView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @Binding var activeActivityId: ActivityID?
    
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @Namespace private var categoryAnimation
    let categories = ["All", "Colors", "Alphabet", "Animals"]
    
    let activities = [
        ("alphabets-in-ar", "Alphabets in AR"),
        ("numbers-in-ar", "Numbers in AR"),
        ("shapes-in-ar", "Shapes in AR")
    ]
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Hello,\n\(viewModel.currentUser?.displayName ?? "User")")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .padding(.top, 20)
                    
                    HStack {
                        CustomTextField(placeholder: "Search activity...", text: $searchText, iconName: "magnifyingglass")
                    }
                    
                    Text("Category")
                        .font(.headline)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(categories, id: \.self) { category in
                                CategoryButton(title: category, isSelected: selectedCategory == category, animation: categoryAnimation) {
                                    withAnimation(.spring()) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                    }
                    
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(activities, id: \.0) { activityId, activityName in
                            // We now use our new, reusable card view
                            Button(action: {
                                self.activeActivityId = ActivityID(id: activityId)
                            }) {
                                ActivityCardView(activityId: activityId, activityName: activityName)
                            }
                        }
                    }
                    
                }
                .padding()
            }
            .navigationBarHidden(true)
            .onTapGesture {
                hideKeyboard()
            }
        }
    }
}

// Settings Screen
struct SettingsView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account Information")) {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                        Text("Name")
                        Spacer()
                        Text(viewModel.currentUser?.displayName ?? "")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Email")
                        Spacer()
                        Text(viewModel.currentUser?.email ?? "")
                            .foregroundColor(.gray)
                    }
                }
                
                Section(header: Text("Security")) {
                    Button(action: {}) {
                        Text("Change Password")
                    }
                    .foregroundColor(.primary)
                }
                
                Section(header: Text("Notifications")) {
                    Toggle(isOn: .constant(true)) {
                        Text("Enable Notifications")
                    }
                }
                
                Section {
                    Button(action: {
                        viewModel.signOut()
                    }) {
                        Text("Sign Out")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}


// Toddler Profile View
struct ToddlerProfileView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    
    var body: some View {
        // Embed in NavigationView to enable NavigationLinks
        NavigationView {
            VStack(spacing: 25) {
                Image(viewModel.currentToddlerProfile?.avatarImageName ?? "toddler1")
                    .resizable()
                    .frame(width: 190, height: 190, alignment: .top)
                    .clipShape(Circle())
                    .padding(.top, 20) // Reduced top padding
                
                Text(viewModel.currentToddlerProfile?.name ?? "Toddler")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                
                VStack(spacing: 15) {
                    // Changed Buttons to NavigationLinks
                    NavigationLink(destination: RecentActivitiesView()) {
                        ProfileOptionButton(title: "Activities")
                    }
                    
                    NavigationLink(destination: ProgressScreenView()) {
                        ProfileOptionButton(title: "Progress")
                    }
                    
                    // This button can remain as is, or you can build a Rewards screen for it later
                    Button(action: {}) {
                        ProfileOptionButton(title: "Rewards")
                    }
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .padding(.horizontal, 30)
            .navigationBarHidden(true) // Hides the default nav bar title area
        }
    }
}

// --- NEW/UPDATED Reusable UI Components ---

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2)
                Text("Please Wait...")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(Color.black.opacity(0.5))
            .cornerRadius(20)
        }
        .transition(.opacity)
    }
}

struct MessageView: View {
    let title: String
    let message: String
    let isError: Bool
    let onDismiss: () -> Void
    
    @State private var isShowing = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Prevent dismissal by tapping background
                }
            
            VStack(spacing: 20) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(isError ? .red : .green)
                
                VStack(alignment: .center, spacing: 5) {
                    Text(title)
                        .font(.title2).bold()
                    Text(message)
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                
                PrimaryButton(title: isError ? "Try Again" : "Continue") {
                    withAnimation {
                        isShowing = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }
            }
            .padding()
            .frame(width: 300)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 20)
            .scaleEffect(isShowing ? 1 : 0.5)
            .opacity(isShowing ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    isShowing = true
                }
            }
        }
        .transition(.opacity)
    }
}


struct TabBarButton: View {
    let iconName: String
    let tab: MainHubView.Tab
    @Binding var selectedTab: MainHubView.Tab
    let animation: Namespace.ID
    
    var body: some View {
        Button(action: {
            selectedTab = tab
        }) {
            VStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(selectedTab == tab ? .orange : .gray.opacity(0.6))
                
                if selectedTab == tab {
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: 30, height: 4)
                        .matchedGeometryEffect(id: "underline", in: animation)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 30, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}


struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let animation: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(Color.orange)
                                .matchedGeometryEffect(id: "category_background", in: animation)
                        }
                    }
                )
                .foregroundColor(isSelected ? .white : .black)
        }
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
    }
}

// --- Other Reusable Components (Unchanged) ---
struct ProfileOptionButton: View {
    let title: String
    // Remove the action from here
    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white)
            .cornerRadius(15)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
    }
}

struct CustomTextField: View {
    var placeholder: String
    @Binding var text: String
    var iconName: String
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .font(.system(size: 16, design: .rounded))
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
}

struct CustomSecureField: View {
    var placeholder: String
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundColor(.gray)
            SecureField(placeholder, text: $text)
                .font(.system(size: 16, design: .rounded))
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
}

struct PrimaryButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .cornerRadius(15)
                .shadow(color: .orange.opacity(0.3), radius: 10, y: 5)
        }
    }
}

struct IntroPage: View {
    let imageName: String
    let title: String
    let description: String
    var body: some View {
        VStack(spacing: 30) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
            
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            
            Text(description)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

// In ContentView.swift

// --- NEW SCREEN 1: Toddler's Progress ---
struct ProgressScreenView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let profile = viewModel.currentToddlerProfile {
                    ProgressRow(
                        title: "Cognitive Skills",
                        progress: profile.cognitiveSkillsProgress ?? 0,
                        color: .blue
                    )
                    ProgressRow(
                        title: "Color Perception",
                        progress: profile.colorPerceptionProgress ?? 0,
                        color: .purple
                    )
                    ProgressRow(
                        title: "Observation Skills",
                        progress: profile.observationSkillsProgress ?? 0,
                        color: .orange
                    )
                } else {
                    Text("No profile data available.")
                }
            }
            .padding()
        }
        .navigationTitle("Toddler's Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProgressRow: View {
    let title: String
    let progress: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .shadow(color: color.opacity(0.3), radius: 5, y: 3)
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(15)
    }
}


// --- NEW SCREEN 2: Recent Activities ---
// --- REPLACE the entire RecentActivitiesView struct ---

struct RecentActivitiesView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    // The view now has its own StateObject for its logic
    @StateObject private var viewModel: RecentActivitiesViewModel

    init() {
        // We must initialize the StateObject in the init, passing it the publisher from the parent
        _viewModel = StateObject(wrappedValue: RecentActivitiesViewModel(historyPublisher: AuthViewModel().$activityHistory))
    }

    // A two-column grid for the activity cards
    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            // Horizontal scrolling filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.dateFilters) { filter in
                        FilterButton(filter: filter, isSelected: viewModel.selectedFilter == filter) {
                            viewModel.selectFilter(filter)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .background(Color(UIColor.systemBackground))
            .shadow(radius: 1)

            // Grid of activity cards
            ScrollView {
                if viewModel.aggregatedRecords.isEmpty {
                    Text("No activities recorded for this day.")
                        .foregroundColor(.secondary)
                        .padding(.top, 50)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.aggregatedRecords) { record in
                            ActivityCardView(
                                activityId: record.id,
                                activityName: record.name,
                                duration: record.totalDuration
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Recent Activities")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Link the view model to the auth view model's publisher upon appearing
            // This ensures the ViewModel gets created with the correct data source.
            viewModel.link(to: authViewModel)
        }
    }
}

// A new subview for the filter buttons
struct FilterButton: View {
    let filter: ActivityFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(filterText)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.orange : Color(UIColor.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
    
    private var filterText: String {
        switch filter {
        case .allTime:
            return "All Time"
        case .date(let date):
            if Calendar.current.isDateInToday(date) { return "Today" }
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

extension RecentActivitiesViewModel {
    func link(to authViewModel: AuthViewModel) {
        // This re-establishes the subscription with the actual instance of the AuthViewModel
        authViewModel.$activityHistory
            .receive(on: RunLoop.main)
            .sink { [weak self] history in
                guard let self = self else { return }
                self.allRecords = history
                self.generateDateFilters()
                self.processRecords()
            }
            .store(in: &cancellables)
    }
}

#Preview {
    ContentView()
}
