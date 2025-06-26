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

struct ContentView: View {
    @StateObject private var viewModel = AuthViewModel()
    @Environment(\.colorScheme) var colorScheme
    
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
                if viewModel.appState == .splash {
                    SplashLoadingBarView()
                } else {
                    LoadingView()
                }
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
            
            if viewModel.showLevelUpPopup {
                LevelUpView(onDismiss: {
                    viewModel.showLevelUpPopup = false
                })
            }

            if viewModel.isRedeemingReward {
                RedeemingView()
            }
        }
        .environmentObject(viewModel)
        .onChange(of: colorScheme) { _ in
            ThemeManager.shared.themeChanged.send()
        }
    }
}

struct Activity: Identifiable {
    let id: String
    let name: String
    let categories: [String]
}

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
                        Button("Finish") {
                            Haptics.shared.impact(.medium)
                            finishActivity()
                        }
                        .font(.headline)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        
                        Button(action: {
                            Haptics.shared.impact(.light)
                            if currentIndex < challenges.count - 1 {
                                currentIndex += 1
                                isSolved = false
                            } else {
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
    
    private func finishActivity() {
        let duration = Date().timeIntervalSince(startTime)
        let stepsCompleted = isSolved ? (currentIndex + 1) : currentIndex
        
        Task {
            await viewModel.updateProgressAndHistory(
                activityId: "numbers-in-ar",
                activityName: "Numbers in AR",
                totalSteps: challenges.count,
                stepsCompleted: stepsCompleted,
                duration: duration,
            )
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
    
    func makeUIView(context: Context) -> ARView {
        print("AR VIEW IS RESETTING: makeUIView has been called.")
        
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
    
    class Coordinator: NSObject {
        weak var arView: ARView?
        var challengeAnchor: AnchorEntity?
        var isSolved: Binding<Bool>?
        private var currentChallenge: NumberChallenge?
        private var previousCountInZone: Int = -1
        private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
        
        func updateChallenge(_ newChallenge: NumberChallenge?) {
            if newChallenge?.question == self.currentChallenge?.question {
                return
            }
            
            self.currentChallenge = newChallenge
            self.previousCountInZone = -1
            
            challengeAnchor?.removeFromParent()
            guard let challenge = newChallenge else { return }

            let anchor = AnchorEntity(plane: .horizontal)
            
            let zoneMesh = MeshResource.generatePlane(width: 0.5, depth: 0.5)
            let zoneMaterial = UnlitMaterial(color: .blue.withAlphaComponent(0.1))
            let zoneEntity = ModelEntity(mesh: zoneMesh, materials: [zoneMaterial])
            zoneEntity.name = "targetZone"
            anchor.addChild(zoneEntity)

            for _ in 0..<challenge.initialCount {
                anchor.addChild(createCube(inZone: true))
            }
            
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
                Haptics.shared.impact(.medium)
                self.previousCountInZone = countInZone
            }
            
            if countInZone == challenge.answer {
                if isSolved?.wrappedValue == false {
                    isSolved?.wrappedValue = true
                    playSuccessAnimation()
                }
            } else {
                isSolved?.wrappedValue = false
            }
        }
        
        func playSuccessAnimation() {
            guard let zone = challengeAnchor?.findEntity(named: "targetZone") as? ModelEntity else { return }
            
            var successMaterial = UnlitMaterial(color: .green)
            successMaterial.blending = .transparent(opacity: 0.5)

            zone.model?.materials = [successMaterial]
        }
    }
}

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

struct ShapesARView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var startTime = Date()
    @Binding var activeActivityId: ActivityID?
    @State private var currentIndex = 0
    
    let shapeData: [ShapeStep] = [
        .init(name: "Cube", color: .systemRed, type: .generated(.generateBox(size: 1.0)),
              targetSize: 0.15),
        
            .init(name: "Sphere", color: .systemBlue, type: .generated(.generateSphere(radius: 1.0)),
                  targetSize: 0.2),
        
            .init(name: "Cylinder", color: .systemGreen, type: .loaded(named: "Cylinder.usdz"),
                  targetSize: 0.002, positionOffset: [0, -0.2, 0]),
        
            .init(name: "Pyramid", color: .systemPurple, type: .loaded(named: "Pyramid.usdz"),
                  targetSize: 0.0025,
                  positionOffset: [0, 0, 0]),
        
            .init(name: "Cone", color: .systemOrange, type: .loaded(named: "Cone.usdz"),
                  targetSize: 0.0025,
                  positionOffset: [0, -0.05, 0]),
        
            .init(name: "Box", color: .systemYellow, type: .generated(.generateBox(size: [0.2, 0.05, 0.12])))
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
                    Button(action: {
                        Haptics.shared.impact(.light)
                        if currentIndex > 0 { currentIndex -= 1 }
                    }) {
                        Image(systemName: "arrow.left")
                    }.modifier(NavButtonModifier())
                    
                    Button("Finish") {
                        Haptics.shared.impact(.medium)
                        let duration = Date().timeIntervalSince(startTime)
                        Task {
                            await viewModel.updateProgressAndHistory(
                                activityId: "shapes-in-ar",
                                activityName: "Shapes in AR",
                                totalSteps: shapeData.count,
                                stepsCompleted: currentIndex + 1,
                                duration: duration,
                            )
                            activeActivityId = nil
                        }
                    }
                    .font(.headline)
                    .padding()
                    .background(.red)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                    
                    Button(action: {
                        Haptics.shared.impact(.light)
                        if currentIndex < shapeData.count - 1 { currentIndex += 1 }
                    }) {
                        Image(systemName: "arrow.right")
                    }.modifier(NavButtonModifier(disabled: currentIndex >= shapeData.count - 1))
                }
                .padding()
            }
        }
    }
}

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
            
            if let size = step.targetSize {
                normalizeAndConfigure(shapeEntity, targetSize: size)
            }
            if let offset = step.positionOffset {
                shapeEntity.position = offset
            }
            
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
                        Task {
                            await viewModel.updateProgressAndHistory(
                                activityId: "alphabets-in-ar",
                                activityName: "Alphabets in AR",
                                totalSteps: alphabetData.count,
                                stepsCompleted: currentIndex + 1,
                                duration: duration,
                            )
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
            if let anchor = self.alphabetAnchor {
                anchor.children.removeAll()
            } else {
                let newAnchor = AnchorEntity(plane: .horizontal)
                arView?.scene.addAnchor(newAnchor)
                self.alphabetAnchor = newAnchor
            }

            guard let anchor = self.alphabetAnchor else { return }
            guard index < models.count else { return }
            
            let step = models[index]
            
            let letterMesh = MeshResource.generateText(step.letter, extrusionDepth: 0.05, font: .systemFont(ofSize: 0.25, weight: .bold))
            let letterMaterial = SimpleMaterial(color: step.color, roughness: 0.3, isMetallic: false)
            let letterEntity = ModelEntity(mesh: letterMesh, materials: [letterMaterial])
            
            do {
                let objectEntity = try await ModelEntity(named: step.modelName)

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

struct SplashScreenView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
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
        .background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
    }
}

struct LoginView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
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
                    
                    PrimaryButton(title: "Log in") {
                        hideKeyboard()
                        Task { await viewModel.signIn(withEmail: email, password: password) }
                    }
                    .padding(.top, 20)
                    
                    HStack {
                        Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                        Text("OR").foregroundColor(.secondary)
                        Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                    }
                    
                    GoogleSignInButton {
                        Task {
                            await viewModel.signInWithGoogle()
                        }
                    }
                    
                    HStack {
                        Text("Don't have an account?")
                            .foregroundColor(.secondary)
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

struct SignUpView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
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
                        Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                        Text("OR").foregroundColor(.secondary)
                        Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                    }
                    
                    GoogleSignInButton {
                        Task {
                            await viewModel.signInWithGoogle()
                        }
                    }
                    
                    
                    HStack {
                        Text("Already have an account?")
                            .foregroundColor(.secondary)
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

struct ToddlerProfileSetupView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var toddlerName = ""
    @State private var toddlerAge = ""
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
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

struct MainHubView: View {
    @State private var selectedTab: Tab = .activity
    @Namespace private var animation
    
    @State private var activeActivityId: ActivityID? = nil
    
    enum Tab {
        case activity, profile, settings
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            TabView(selection: $selectedTab.animation(.easeInOut)) {
                ActivitiesView(activeActivityId: $activeActivityId).tag(Tab.activity)
                ToddlerProfileView().tag(Tab.profile)
                SettingsView().tag(Tab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            HStack {
                TabBarButton(iconName: "gamecontroller.fill", tab: .activity, selectedTab: $selectedTab, animation: animation)
                TabBarButton(iconName: "person.fill", tab: .profile, selectedTab: $selectedTab, animation: animation)
                TabBarButton(iconName: "gearshape.fill", tab: .settings, selectedTab: $selectedTab, animation: animation)
            }
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .background(.regularMaterial)
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
            } else if activity.id == "ar-doodling" {
                ARDoodleView(activeActivityId: $activeActivityId)
            }
        }
    }
}

struct ActivityID: Identifiable {
    let id: String
}

struct ActivityCardView: View {
    let activityId: String
    let activityName: String
    var duration: Int? = nil
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                activityImageView
                Spacer()
            }
            .frame(height: 120)
            .clipped()
            .cornerRadius(15)
            
            Text(activityName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            if let duration = duration {
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                    Text(formatDuration(duration))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
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
        Image(activityId)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

struct ActivitiesView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @Binding var activeActivityId: ActivityID?
    
    @ObservedObject private var screenTimeManager = ScreenTimeManager.shared
    
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    @Namespace private var categoryAnimation
    
    let categories = ["All", "Cognitive", "Color", "Observation", "Creative"]
    
    let allActivities: [Activity] = [
        .init(id: "alphabets-in-ar", name: "Alphabets in AR", categories: ["Cognitive", "Color", "Observation"]),
        .init(id: "numbers-in-ar", name: "Numbers in AR", categories: ["Cognitive", "Observation"]),
        .init(id: "shapes-in-ar", name: "Shapes in AR", categories: ["Color", "Observation"]),
        .init(id: "ar-doodling", name: "AR Doodling", categories: ["Creative"])
    ]
    
    private var filteredActivities: [Activity] {
        var activitiesToShow = allActivities
        
        if selectedCategory != "All" {
            activitiesToShow = allActivities.filter { $0.categories.contains(selectedCategory) }
        }
        
        if !searchText.isEmpty {
            activitiesToShow = activitiesToShow.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        return activitiesToShow
    }
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        
        NavigationView {
            ZStack{
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Hello,\n\(viewModel.currentUser?.displayName ?? "User")")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .padding(.top, 20)
                        
                        CustomTextField(placeholder: "Search activity...", text: $searchText, iconName: "magnifyingglass")
                        
                        Text("Category")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(categories, id: \.self) { category in
                                    CategoryButton(title: category, isSelected: selectedCategory == category, animation: categoryAnimation) {
                                        hapticGenerator.impactOccurred()
                                        withAnimation(.spring()) {
                                            selectedCategory = category
                                        }
                                    }
                                }
                            }
                        }
                        
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredActivities) { activity in
                                Button(action: {
                                    self.activeActivityId = ActivityID(id: activity.id)
                                }) {
                                    ActivityCardView(activityId: activity.id, activityName: activity.name)
                                }
                            }
                        }
                        
                    }
                    .padding()
                }
                .background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
                if screenTimeManager.isLocked {
                    TimeLockedView()
                }
            }
            .navigationBarHidden(true)
            .onTapGesture {
                hideKeyboard()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var isShowingChangePassword = false
    
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
                    Button("Change Password") {
                        isShowingChangePassword = true
                    }
                    .foregroundColor(.primary)
                }
                
                Section(header: Text("Toddler Profiles")) {
                    Button("Add another toddler profile") {
                        viewModel.appState = .toddlerProfileSetup
                    }
                    .foregroundColor(.primary)
                }
                
                Section(header: Text("Health")) {
                    NavigationLink("Screen Time Settings") {
                        ScreenTimeSettingsView()
                    }
                }
                
                Section(header: Text("Notifications")) {
                    Toggle(isOn: .constant(true)) {
                        Text("Enable Notifications")
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            await viewModel.signOut()
                        }
                    }) {
                        Text("Sign Out")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $isShowingChangePassword) {
                ChangePasswordView()
            }
        }
    }
}


struct ToddlerProfileView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var isShowingUpdateSheet = false
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.toddlerProfiles.count > 1 {
                    Picker("Select Profile", selection: Binding(get: {
                        viewModel.selectedToddlerProfile
                    }, set: { newProfile in
                        Haptics.shared.selectionChanged()
                        viewModel.switchToddlerProfile(to: newProfile)
                    })) {
                        ForEach(viewModel.toddlerProfiles) { profile in
                            Text(profile.name).tag(profile as ToddlerProfile?)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                }
                
                if let profile = viewModel.selectedToddlerProfile {
                    VStack(spacing: 25) {
                        Image(profile.avatarImageName)
                            .resizable()
                            .frame(width: 190, height: 190, alignment: .top)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.orange, lineWidth: 4))
                            .shadow(radius: 10)
                            .padding(.bottom)
                        
                        Text(profile.name)
                            .font(.title.bold())
                        
                        VStack(spacing: 15) {
                            NavigationLink(destination: RecentActivitiesView()) {
                                ProfileOptionButton(title: "Activities")
                            }
                            NavigationLink(destination: ProgressScreenView()) {
                                ProfileOptionButton(title: "Progress")
                            }
                            NavigationLink(destination: RewardsScreenView()) {
                                ProfileOptionButton(title: "Rewards")
                            }
                            NavigationLink(destination: AIProgressReportView()) {
                                ProfileOptionButton(title: "AI Progress Report")
                            }
                            Button {
                                isShowingUpdateSheet = true
                            } label: {
                                ProfileOptionButton(title: "Edit Profile")
                            }
                        }
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 30)
                    
                    Spacer()
                } else {
                    VStack {
                        Text("No Toddler Profile Found")
                            .font(.headline)
                        Button("Create a Profile") {
                            viewModel.appState = .toddlerProfileSetup
                        }
                        .padding()
                    }
                }
            }
            .background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
            .navigationTitle("Toddler Profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingUpdateSheet) {
                if let profile = viewModel.selectedToddlerProfile {
                    UpdateToddlerProfileView(profile: profile)
                }
            }
        }
    }
}

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
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .scaleEffect(isShowing ? 1 : 0.5)
            .opacity(isShowing ? 1 : 0)
            .onAppear {
                Haptics.shared.notification(isError ? .error : .success)
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
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        Button(action: {
            if selectedTab != tab {
                hapticGenerator.impactOccurred()
                selectedTab = tab
            }
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
                .background(isSelected ? Color.orange : Color(UIColor.systemGray4))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
    }
}

struct ProfileOptionButton: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
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
        Button(action: {
            Haptics.shared.impact(.medium)
            action()
        }) {
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
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct ProgressScreenView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var redrawTrigger = false
    
    var body: some View {
        ZStack{
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    if let profile = viewModel.selectedToddlerProfile {
                        
                        Text(profile.name)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        
                        Image(profile.avatarImageName)
                            .resizable()
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.orange, lineWidth: 3))
                            .shadow(radius: 7)
                            .padding(.bottom)
                        
                        Text("Current Level: \(profile.level)")
                            .font(.title2.weight(.semibold))
                            .padding(.bottom)
                        
                        ProgressRow(
                            title: "Cognitive Skills",
                            progress: profile.cognitiveSkillsProgress,
                            color: .blue
                        )
                        ProgressRow(
                            title: "Color Perception",
                            progress: profile.colorPerceptionProgress,
                            color: .purple
                        )
                        ProgressRow(
                            title: "Observation Skills",
                            progress: profile.observationSkillsProgress,
                            color: .orange
                        )
                    } else {
                        Text("No profile data available.")
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Toddler's Progress")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ThemeManager.shared.themeChanged) {
            self.redrawTrigger.toggle()
        }
        .id(redrawTrigger)
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

struct RecentActivitiesView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var selectedFilter: ActivityFilter = .allTime
    @State private var redrawTrigger = false
    
    @Environment(\.colorScheme) var colorScheme
    
    private var dateFilters: [ActivityFilter] {
        var uniqueDates: [Date] = []
        for record in viewModel.activityHistory {
            let date = Calendar.current.startOfDay(for: record.dateCompleted)
            if !uniqueDates.contains(date) {
                uniqueDates.append(date)
            }
        }
        
        let sortedDates = uniqueDates.sorted(by: >)
        
        var filters: [ActivityFilter] = [.allTime]
        filters.append(contentsOf: sortedDates.prefix(7).map { .date($0) })
        
        return filters
    }

    private var aggregatedRecords: [AggregatedActivityRecord] {
        let recordsToProcess: [ActivityRecord]
        
        switch selectedFilter {
        case .allTime:
            recordsToProcess = viewModel.activityHistory
        case .date(let date):
            recordsToProcess = viewModel.activityHistory.filter { Calendar.current.isDate($0.dateCompleted, inSameDayAs: date) }
        }
        
        let dictionary = Dictionary(grouping: recordsToProcess, by: { $0.activityId })
        
        return dictionary.values.compactMap { recordsInGroup -> AggregatedActivityRecord? in
            guard let firstRecord = recordsInGroup.first else { return nil }
            let totalDuration = recordsInGroup.reduce(0) { $0 + $1.durationInSeconds }
            return AggregatedActivityRecord(id: firstRecord.activityId, name: firstRecord.activityName, totalDuration: totalDuration)
        }.sorted(by: { $0.name < $1.name })
    }
    
    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    
    var body: some View {
        ZStack{
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(dateFilters) { filter in
                            FilterButton(filter: filter, isSelected: selectedFilter == filter) {
                                self.selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(UIColor.systemGray6))
                
                ScrollView {
                    if aggregatedRecords.isEmpty {
                        ContentUnavailableView(
                            "No Activities Recorded",
                            systemImage: "clock.badge.xmark",
                            description: Text("Complete some activities to see your history here.")
                        )
                        .padding(.top, 50)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(aggregatedRecords) { record in
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
        }
        .navigationTitle("Recent Activities")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ThemeManager.shared.themeChanged) {
            self.redrawTrigger.toggle()
        }
        .id(redrawTrigger)
    }
}

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

struct RewardsScreenView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var redrawTrigger = false
    
    @State private var selectedRewardForConfirmation: Reward?
    
    let columns = [GridItem(.flexible())]
    
    var body: some View {
        ZStack{
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    if let profile = viewModel.selectedToddlerProfile {
                        ForEach(Array(viewModel.allRewards.enumerated()), id: \.element) { index, reward in
                            RewardCardView(
                                reward: reward,

                                isUnlocked: (profile.level % viewModel.allRewards.count) > index,
                                
                                isRedeemed: profile.redeemedRewardIDs.contains(reward.id),
                                onRedeem: {
                                    self.selectedRewardForConfirmation = reward
                                }
                            )
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
        }
        .navigationTitle("Rewards")
        .sheet(item: $selectedRewardForConfirmation) { reward in
            RedemptionSuccessView(reward: reward)
                .environmentObject(viewModel)
                .presentationDetents([.height(400)])
        }
        .onReceive(ThemeManager.shared.themeChanged) {
            self.redrawTrigger.toggle()
        }
        .id(redrawTrigger)
    }
}

struct RewardCardView: View {
    let reward: Reward
    let isUnlocked: Bool
    let isRedeemed: Bool
    let onRedeem: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: reward.imageName)
                .font(.system(size: 70))
                .foregroundColor(.orange)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
            
            VStack(spacing: 8) {
                Text(reward.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text(reward.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            
            Spacer(minLength: 0)
            
            if isRedeemed {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Redeemed!")
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                .font(.title2)
                .padding(.bottom)
            } else {
                Button(action: onRedeem) {
                    Text("Redeem Reward")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!isUnlocked)
                .padding([.horizontal, .bottom])
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            ZStack {
                if !isUnlocked {
                    Color.black.opacity(0.6).clipShape(RoundedRectangle(cornerRadius: 20))
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
            }
        )
    }
}

struct LevelUpView: View {
    let onDismiss: () -> Void
    @State private var isShowing = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Text("🎉")
                    .font(.system(size: 80))
                
                Text("Level Up!")
                    .font(.largeTitle).bold()
                    .foregroundColor(.orange)
                
                Text("Hooray! Your little one is reaching new heights. Every milestone is a testament to their growing mind and your wonderful guidance. Keep up the amazing work!")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Continue") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.top)
            }
            .padding(30)
            .background(.regularMaterial)
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(40)
            .scaleEffect(isShowing ? 1 : 0.5)
            .opacity(isShowing ? 1 : 0)
            .onAppear {
                Haptics.shared.notification(.success)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isShowing = true
                }
            }
        }
        .transition(.opacity)
    }
}

struct RedemptionSuccessView: View {
    let reward: Reward
    @EnvironmentObject var viewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 25) {
            Text("🎁")
                .font(.system(size: 80))
            
            Text("Yay! Reward Unlocked!")
                .font(.largeTitle).bold()
                .foregroundColor(.orange)
            
            Text("You've redeemed the **\(reward.title)** reward! Enjoy this special treat as a celebration of all the amazing learning and growth.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Awesome!") {
                Task {
                    await viewModel.redeemReward(reward)
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.top)
        }
        .padding(30)
    }
}

struct RedeemingView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Text("🎁")
                    .font(.system(size: 60))
                Text("Unlocking Reward...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            .transition(.opacity)
        }
    }
}

struct TimeLockedView: View {
    @ObservedObject private var screenTimeManager = ScreenTimeManager.shared
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var isShowingPasscodeEntry = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Text("⌛")
                    .font(.system(size: 80))
                Text("Whoops, slow down!")
                    .font(.largeTitle).bold()
                    .foregroundColor(.white)
                Text("It's time for a little break. Great job learning today!")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button("15 more minutes, please?") {
                    isShowingPasscodeEntry = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.top)
            }
            .padding(30)
        }
        .sheet(isPresented: $isShowingPasscodeEntry) {
            PasscodeEntryView(
                prompt: "Enter passcode to get 15 more minutes.",
                onSuccess: {
                    Task {
                        await viewModel.grantScreenTimeExtension()
                        isShowingPasscodeEntry = false
                    }
                }
            )
        }
    }
}

struct PasscodeEntryView: View {
    let prompt: String
    let onSuccess: () -> Void

    @ObservedObject private var screenTimeManager = ScreenTimeManager.shared
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var passcode: String = ""
    @State private var isCreatingPasscode = false
    @State private var firstPasscode: String = ""
    @State private var wrongPasscode = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(promptText)
                .font(.headline)
                .padding()

            SecureField("4-digit passcode", text: $passcode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .multilineTextAlignment(.center)

            if wrongPasscode {
                Text("Incorrect passcode. Try again.").foregroundColor(.red)
            }

            Button(buttonText) {
                handleButtonTap()
            }
            .buttonStyle(.borderedProminent)

        }
        .onAppear {
            if !screenTimeManager.isPasscodeSet {
                isCreatingPasscode = true
            }
        }
    }

    private var promptText: String {
        if isCreatingPasscode && firstPasscode.isEmpty {
            return "Create a new 4-digit passcode."
        } else if isCreatingPasscode {
            return "Confirm your new passcode."
        } else {
            return prompt
        }
    }

    private var buttonText: String {
        isCreatingPasscode ? "Set Passcode" : "Unlock"
    }

    private func handleButtonTap() {
        if isCreatingPasscode {
            if firstPasscode.isEmpty {
                firstPasscode = passcode
                passcode = ""
            } else {
                if firstPasscode == passcode {
                    Task {
                        await viewModel.setScreenTimePasscode(passcode: passcode)
                        onSuccess()
                    }
                } else {
                    wrongPasscode = true
                    passcode = ""
                    firstPasscode = ""
                }
            }
        } else {
            if screenTimeManager.checkPasscode(passcode) {
                onSuccess()
            } else {
                wrongPasscode = true
                passcode = ""
            }
        }
    }
}

struct ScreenTimeSettingsView: View {
    @ObservedObject private var screenTimeManager = ScreenTimeManager.shared
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var isUnlocked = false
    @State private var isShowingPasscodeView = false

    var timeOptions: [Int] {
        var options = Array(stride(from: 15, through: 120, by: 15))
        options.append(2)
        return options.sorted()
    }

    var body: some View {
        Form {
            if isUnlocked {
                Section(header: Text("Daily Screen Time Limit")) {
                    Picker("Time Limit", selection: $screenTimeManager.dailyLimitInMinutes) {
                        ForEach(timeOptions, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .onChange(of: screenTimeManager.dailyLimitInMinutes) { newLimit in
                        Task {
                            await viewModel.setScreenTimeLimit(minutes: newLimit)
                        }
                    }
                }
            } else {
                Text("Enter passcode to manage screen time settings.")
            }
        }
        .navigationTitle("Screen Time")
        .onAppear {
            if !isUnlocked {
                isShowingPasscodeView = true
            }
        }
        .sheet(isPresented: $isShowingPasscodeView) {
            PasscodeEntryView(prompt: "Enter passcode to manage settings.") {
                isUnlocked = true
                isShowingPasscodeView = false
            }
        }
    }
}

struct GoogleSignInButton: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image("google-logo")
                    .resizable()
                    .frame(width: 20, height: 20)
                
                Text("Sign in with Google")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(15)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
        }
    }
}

struct SplashLoadingBarView: View {
    @State private var progress: Double = 0.0
    
    @State private var timer: Timer?
    
    var body: some View {
        VStack {
            Spacer()
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                .padding(.horizontal, 80)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .shadow(color: .orange.opacity(0.3), radius: 5)
            
            Text("Loading Profile...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(.bottom, 60)
        .transition(.opacity.animation(.easeInOut))
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
                if self.progress < 0.95 {
                    self.progress += 0.01
                } else {
                    self.timer?.invalidate()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

struct UpdateToddlerProfileView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var toddlerName: String
    @State private var toddlerAge: String
    
    @State private var isShowingDeleteConfirmation = false
    
    init(profile: ToddlerProfile) {
        _toddlerName = State(initialValue: profile.name)
        _toddlerAge = State(initialValue: profile.age)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Toddler's Details")) {
                    TextField("Name", text: $toddlerName)
                    TextField("Age", text: $toddlerAge)
                        .keyboardType(.numberPad)
                }
                
                Section {
                    Button("Delete Profile", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Update Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.updateToddlerProfile(name: toddlerName, age: toddlerAge)
                            dismiss()
                        }
                    }
                    .disabled(toddlerName.isEmpty)
                }
            }
            .alert("Are you sure you want to delete this profile?", isPresented: $isShowingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        if let profile = viewModel.selectedToddlerProfile {
                            await viewModel.deleteToddlerProfile(profile: profile)
                        }
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    
    private var isPasswordValid: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }
    
    var body: some View {
        NavigationView {
            Form {
                if viewModel.isPasswordUser {
                    Section(header: Text("Current Password"), footer: Text("Required to confirm your identity.")) {
                        SecureField("Enter your current password", text: $currentPassword)
                    }
                }
                
                Section(header: Text("New Password"), footer: Text(viewModel.isPasswordUser ? "" : "Since you signed in with Google, you can add a password to your account for email-based login.")) {
                    SecureField("Enter new password", text: $newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)
                }
                
                if !newPassword.isEmpty && newPassword != confirmPassword {
                    Text("Passwords do not match.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.leading)
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.changePassword(
                                currentPassword: currentPassword,
                                newPassword: newPassword
                            )
                            if !viewModel.showMessage || !viewModel.messageIsError {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isPasswordValid)
                }
            }
        }
    }
}

struct AIProgressReportView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var report: AIReport?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("Analyzing Toddler's Progress...")
                        .padding(.top, 50)
                } else if let report = report {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text("AI's Assessment")
                                .font(.title2.bold())
                        }
                        Text(report.assessment)
                            .font(.body)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(15)

                    if !report.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .font(.title2)
                                    .foregroundColor(.yellow)
                                Text("Try These Next!")
                                    .font(.title2.bold())
                            }
                            
                            ForEach(report.suggestions) { activity in
                                ActivityCardView(activityId: activity.id, activityName: activity.name)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(15)
                    }

                    if !report.topActivities.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                             HStack {
                                Image(systemName: "star.fill")
                                    .font(.title2)
                                    .foregroundColor(.yellow)
                                Text("Top Activities")
                                    .font(.title2.bold())
                            }
                            Text("\(viewModel.selectedToddlerProfile?.name ?? "Your toddler")'s favorite activities are:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ForEach(report.topActivities.indices, id: \.self) { index in
                                Text("\(index + 1). \(report.topActivities[index].name)")
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(15)
                    }

                } else {
                    ContentUnavailableView(
                        "Report Not Available",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Could not generate the AI report at this time. Please check your internet connection and try again.")
                    )
                    .padding(.top, 50)
                }
                
                Spacer(minLength: 100)
            }
            .padding()
        }
        .navigationTitle("AI Progress Report")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            self.report = await viewModel.generateAIReport()
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
