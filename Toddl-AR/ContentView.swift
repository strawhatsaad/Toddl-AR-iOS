import SwiftUI
import RealityKit
import Combine
import ARKit

// --- NEW --- Helper to allow dismissing the keyboard
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
            // The main view determined by the app's state
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
            
            // --- Overlays for Loading and Messages ---
            
            // Loading View Overlay
            if viewModel.isLoading {
                LoadingView()
            }
            
            // Custom Message View Overlay
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

// AR Activity View
struct ARActivityView: View {
    @Binding var activeActivityId: String?
    @State private var currentIndex = 0
    
    // --- UPDATED with your new data ---
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
                    
                    Button("Finish") { activeActivityId = nil }
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
        
        context.coordinator.showAlphabet(at: currentIndex)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.showAlphabet(at: currentIndex)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        weak var arView: ARView?
        var alphabetAnchor: AnchorEntity?
        var models: [AlphabetStep] = []
        var modelLoadCancellable: AnyCancellable?

        func showAlphabet(at index: Int) {
            if let existingAnchor = alphabetAnchor {
                arView?.scene.removeAnchor(existingAnchor)
            }
            
            guard index < models.count else { return }
            
            let step = models[index]
            
            let anchor = AnchorEntity(plane: .horizontal)
            
            let letterMesh = MeshResource.generateText(step.letter, extrusionDepth: 0.05, font: .systemFont(ofSize: 0.25, weight: .bold))
            let letterMaterial = SimpleMaterial(color: step.color, roughness: 0.3, isMetallic: false)
            let letterEntity = ModelEntity(mesh: letterMesh, materials: [letterMaterial])

            modelLoadCancellable = ModelEntity.loadModelAsync(named: step.modelName)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Error loading model \(step.modelName): \(error)")
                    }
                }, receiveValue: { [weak self] objectEntity in
                    self?.configureAndPlaceModels(letter: letterEntity, object: objectEntity, on: anchor, step: step)
                })
        }
        
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
            
            arView?.scene.addAnchor(anchor)
            self.alphabetAnchor = anchor
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
    
    @State private var activeActivityId: String? = nil
    
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
        .fullScreenCover(item: $activeActivityId) { id in
            ARActivityView(activeActivityId: $activeActivityId)
        }
    }
}

// Allows using a String? for the .fullScreenCover item
extension String: Identifiable {
    public var id: String { self }
}

// Activities View (Home Screen)
struct ActivitiesView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @Binding var activeActivityId: String?

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @Namespace private var categoryAnimation
    let categories = ["All", "Colors", "Alphabet", "Animals"]
    
    let activities = [
        ("alphabets-in-ar", "Alphabets in AR"),
        ("animals-in-ar", "Animals in AR"),
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
                            Button(action: {
                                self.activeActivityId = activityId
                            }) {
                                VStack {
                                    Image(activityId)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 120)
                                        .clipped()
                                        .cornerRadius(15)
                                    Text(activityName)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.primary)
                                }
                                .padding()
                                .background(Color.white)
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
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
        VStack(spacing: 25) {
            Image(viewModel.currentToddlerProfile?.avatarImageName ?? "toddler1")
                .resizable()
                .frame(width: 190, height: 190, alignment: .top)
                .clipShape(Circle())
                .padding(.top, 60)
            
            Text(viewModel.currentToddlerProfile?.name ?? "Toddler")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            VStack(spacing: 15) {
                ProfileOptionButton(title: "Activities", action: {})
                ProfileOptionButton(title: "Progress", action: {})
                ProfileOptionButton(title: "Rewards", action: {})
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding(.horizontal, 30)
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
    let action: () -> Void
    var body: some View {
        Button(action: action) {
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

#Preview {
    ContentView()
}
