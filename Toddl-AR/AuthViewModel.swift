import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth
import Combine
import GoogleSignIn
import FirebaseAI

enum AppState {
    case splash, intro, login, signUp, toddlerProfileSetup, mainHub
}

struct ToddlerProfile: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var name: String
    var age: String
    let avatarImageName: String
    
    var cognitiveSkillsProgress: Double
    var colorPerceptionProgress: Double
    var observationSkillsProgress: Double
    var level: Int
    var redeemedRewardIDs: [String]

    var screenTimePasscode: String?
    var dailyLimitInMinutes: Int
    var timeSpentToday: TimeInterval
    var hasGrantedExtensionToday: Bool
    var lastUsageDate: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, age, avatarImageName, cognitiveSkillsProgress, colorPerceptionProgress, observationSkillsProgress, level, redeemedRewardIDs
        case screenTimePasscode, dailyLimitInMinutes, timeSpentToday, hasGrantedExtensionToday, lastUsageDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        age = try container.decode(String.self, forKey: .age)
        avatarImageName = try container.decode(String.self, forKey: .avatarImageName)
        
        cognitiveSkillsProgress = try container.decodeIfPresent(Double.self, forKey: .cognitiveSkillsProgress) ?? 0.0
        colorPerceptionProgress = try container.decodeIfPresent(Double.self, forKey: .colorPerceptionProgress) ?? 0.0
        observationSkillsProgress = try container.decodeIfPresent(Double.self, forKey: .observationSkillsProgress) ?? 0.0
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 0
        redeemedRewardIDs = try container.decodeIfPresent([String].self, forKey: .redeemedRewardIDs) ?? []

        screenTimePasscode = try container.decodeIfPresent(String.self, forKey: .screenTimePasscode)
        dailyLimitInMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyLimitInMinutes) ?? 60
        timeSpentToday = try container.decodeIfPresent(TimeInterval.self, forKey: .timeSpentToday) ?? 0.0
        hasGrantedExtensionToday = try container.decodeIfPresent(Bool.self, forKey: .hasGrantedExtensionToday) ?? false
        lastUsageDate = try container.decodeIfPresent(String.self, forKey: .lastUsageDate) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(age, forKey: .age)
        try container.encode(avatarImageName, forKey: .avatarImageName)
        
        try container.encode(cognitiveSkillsProgress, forKey: .cognitiveSkillsProgress)
        try container.encode(colorPerceptionProgress, forKey: .colorPerceptionProgress)
        try container.encode(observationSkillsProgress, forKey: .observationSkillsProgress)
        try container.encode(level, forKey: .level)
        try container.encode(redeemedRewardIDs, forKey: .redeemedRewardIDs)

        try container.encodeIfPresent(screenTimePasscode, forKey: .screenTimePasscode)
        try container.encode(dailyLimitInMinutes, forKey: .dailyLimitInMinutes)
        try container.encode(timeSpentToday, forKey: .timeSpentToday)
        try container.encode(hasGrantedExtensionToday, forKey: .hasGrantedExtensionToday)
        try container.encode(lastUsageDate, forKey: .lastUsageDate)
    }

    init(id: String? = nil, name: String, age: String, avatarImageName: String) {
        self.id = id
        self.name = name
        self.age = age
        self.avatarImageName = avatarImageName
        
        self.cognitiveSkillsProgress = 0.0
        self.colorPerceptionProgress = 0.0
        self.observationSkillsProgress = 0.0
        self.level = 0
        self.redeemedRewardIDs = []

        self.screenTimePasscode = nil
        self.dailyLimitInMinutes = 60
        self.timeSpentToday = 0
        self.hasGrantedExtensionToday = false
        self.lastUsageDate = ""
    }
}

struct ActivityRecord: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let activityId: String
    let activityName: String
    let dateCompleted: Date
    let durationInSeconds: Int
}

struct Reward: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let imageName: String
}

struct AppUser: Identifiable, Codable {
    @DocumentID var id: String?
    let uid: String
    let email: String
    var displayName: String
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var userSession: FirebaseAuth.User?
    @Published var currentUser: AppUser?
    @Published var toddlerProfiles: [ToddlerProfile] = []
    @Published var selectedToddlerProfile: ToddlerProfile?
    @Published var appState: AppState = .splash
    
    @Published var activityHistory = [ActivityRecord]()
    @Published var showLevelUpPopup = false
    @Published var isRedeemingReward = false
    
    @Published var isLoading = false
    @Published var showMessage = false
    @Published var messageTitle = ""
    @Published var messageContent = ""
    @Published var messageIsError = false
    
    var isPasswordUser: Bool {
        guard let providerId = userSession?.providerData.first?.providerID else { return false }
        return providerId == "password"
    }
    
    let allRewards: [Reward] = [
        .init(id: "playtime", title: "30 Mins of Extra Playtime", description: "Your little explorer has earned some extra fun! Enjoy a bonus 30 minutes of free play as a reward for all their hard work.", imageName: "play.circle"),
        .init(id: "dessert", title: "A Dessert of Choice", description: "Time for a sweet treat! Your sunshine has earned their favorite dessert. A yummy reward for a brilliant mind!", imageName: "gift.circle"),
        .init(id: "storytime", title: "Extra Story Time", description: "One more story, please! Cuddle up and enjoy an extra 10 minutes of magical story time together.", imageName: "book.circle"),
        .init(id: "park", title: "A Visit to the Park", description: "Let's go outside! It's time for an adventure at the park to celebrate a job well done.", imageName: "figure.walk.circle"),
        .init(id: "toy", title: "A Toy of Choice", description: "A special prize for a special learner! Your little nugget gets to choose a new toy on your next shopping trip.", imageName: "star.circle")
    ]

    init() {
        self.userSession = Auth.auth().currentUser
        if self.userSession != nil {
            Task {
                await self.fetchUserData()
            }
        } else {
            self.appState = .splash
        }
    }

    func displayMessage(_ title: String, _ content: String, isError: Bool) {
        messageTitle = title
        messageContent = content
        messageIsError = isError
        showMessage = true
    }
    
    func signIn(withEmail email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            self.userSession = result.user
            await fetchUserData()
        } catch {
            displayMessage("Sign In Failed", error.localizedDescription, isError: true)
        }
    }
    
    func signUp(withEmail email: String, password: String, name: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            self.userSession = result.user
            
            let newUser = AppUser(uid: result.user.uid, email: email, displayName: name)
            try await Firestore.firestore().collection("users").document(result.user.uid).setData(from: newUser)
            
            self.currentUser = newUser
            displayMessage("Success!", "Your account has been created. Please log in.", isError: false)
        } catch {
            displayMessage("Sign Up Failed", error.localizedDescription, isError: true)
        }
    }
    
    func signOut() async {
        await saveScreenTimeData()
        
        do {
            try Auth.auth().signOut()
            self.userSession = nil
            self.currentUser = nil
            self.toddlerProfiles = []
            self.selectedToddlerProfile = nil
            self.activityHistory = []
            
            ScreenTimeManager.shared.reset()
            
            self.appState = .login
        } catch {
            print("DEBUG: Failed to sign out: \(error.localizedDescription)")
        }
    }
    
    func fetchUserData() async {
        isLoading = true
        defer { isLoading = false }
        guard let uid = self.userSession?.uid else { return }
        
        do {
            let userDocument = try await Firestore.firestore().collection("users").document(uid).getDocument()
            self.currentUser = try userDocument.data(as: AppUser.self)
            
            let toddlerSnapshot = try await Firestore.firestore().collection("users").document(uid).collection("toddlers").getDocuments()
            self.toddlerProfiles = toddlerSnapshot.documents.compactMap { try? $0.data(as: ToddlerProfile.self) }

            if !self.toddlerProfiles.isEmpty {
                self.selectedToddlerProfile = self.toddlerProfiles.first
                
                if let profile = self.selectedToddlerProfile {
                    ScreenTimeManager.shared.configure(with: profile)
                }
                
                await fetchActivityHistory()
                
                self.appState = .mainHub
            } else {
                self.appState = .toddlerProfileSetup
            }
        } catch {
            print("DEBUG: Failed to fetch user data: \(error.localizedDescription)")
            self.appState = self.currentUser != nil ? .toddlerProfileSetup : .login
        }
    }
    
    func createToddlerProfile(name: String, age: String) async {
        isLoading = true
        defer { isLoading = false }
        guard let uid = self.currentUser?.uid else { return }
        
        var newProfile = ToddlerProfile(name: name, age: age, avatarImageName: "toddler1")
        
        do {
            let newDocRef = Firestore.firestore().collection("users").document(uid).collection("toddlers").document()
            newProfile.id = newDocRef.documentID
            try await newDocRef.setData(from: newProfile)
            
            self.toddlerProfiles.append(newProfile)
            self.selectedToddlerProfile = newProfile
            self.appState = .mainHub
        } catch {
            displayMessage("Profile Creation Failed", error.localizedDescription, isError: true)
        }
    }

    func switchToddlerProfile(to profile: ToddlerProfile?) {
        guard let profile = profile else { return }
        self.selectedToddlerProfile = profile
        Task {
            await fetchActivityHistory()
        }
    }
    
    func updateProgressAndHistory(activityId: String, activityName: String, totalSteps: Int, stepsCompleted: Int, duration: TimeInterval) async {
        guard let uid = currentUser?.uid, var profile = self.selectedToddlerProfile, let profileId = profile.id else { return }
        
        ScreenTimeManager.shared.addSession(duration: duration)
        
        let (_, _, timeSpent, hasExtension, date) = ScreenTimeManager.shared.getCurrentDataForSave()
        profile.timeSpentToday = timeSpent
        profile.hasGrantedExtensionToday = hasExtension
        profile.lastUsageDate = date
        
        let progressIncrease = (Double(stepsCompleted) / Double(totalSteps)) * 0.2
        
        switch activityId {
        case "alphabets-in-ar":
            profile.cognitiveSkillsProgress = min(1.0, (profile.cognitiveSkillsProgress ?? 0) + progressIncrease)
            profile.colorPerceptionProgress = min(1.0, (profile.colorPerceptionProgress ?? 0) + progressIncrease)
            profile.observationSkillsProgress = min(1.0, (profile.observationSkillsProgress ?? 0) + progressIncrease)
        case "numbers-in-ar":
            profile.cognitiveSkillsProgress = min(1.0, (profile.cognitiveSkillsProgress ?? 0) + progressIncrease)
            profile.observationSkillsProgress = min(1.0, (profile.observationSkillsProgress ?? 0) + progressIncrease)
        case "shapes-in-ar":
            profile.colorPerceptionProgress = min(1.0, (profile.colorPerceptionProgress ?? 0) + progressIncrease)
            profile.observationSkillsProgress = min(1.0, (profile.observationSkillsProgress ?? 0) + progressIncrease)
        default: break
        }
        
        let newRecord = ActivityRecord(activityId: activityId, activityName: activityName, dateCompleted: Date(), durationInSeconds: Int(duration))
        
        checkForLevelUp(profile: &profile)
        
        do {
            try await Firestore.firestore().collection("users").document(uid).collection("toddlers").document(profileId).setData(from: profile, merge: true)
            try await Firestore.firestore().collection("users").document(uid).collection("toddlers").document(profileId).collection("activityHistory").addDocument(from: newRecord)
            
            self.selectedToddlerProfile = profile
            if !self.activityHistory.contains(newRecord) {
                self.activityHistory.insert(newRecord, at: 0)
            }
        } catch {
            print("Error updating progress: \(error.localizedDescription)")
        }
    }
    
    func redeemReward(_ reward: Reward) async {
        guard let uid = currentUser?.uid, var profile = self.selectedToddlerProfile, let profileId = profile.id else { return }
        
        self.isRedeemingReward = true
        defer { self.isRedeemingReward = false }
        
        profile.redeemedRewardIDs.append(reward.id)
        
        if profile.redeemedRewardIDs.count == allRewards.count {
            profile.redeemedRewardIDs = []
        }
        
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("toddlers").document(profileId)
                .updateData(["redeemedRewardIDs": profile.redeemedRewardIDs])
            
            self.selectedToddlerProfile = profile
            
        } catch {
            print("Error redeeming reward: \(error.localizedDescription)")
        }
    }
    
    private func fetchActivityHistory() async {
        guard let uid = currentUser?.uid, let profileId = selectedToddlerProfile?.id else {
            self.activityHistory = []
            return
        }
        
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("toddlers").document(profileId)
                .collection("activityHistory")
                .order(by: "dateCompleted", descending: true)
                .limit(to: 20)
                .getDocuments()
            
            self.activityHistory = snapshot.documents.compactMap { try? $0.data(as: ActivityRecord.self) }
        } catch {
            print("Error fetching activity history: \(error.localizedDescription)")
        }
    }
    
    private func checkForLevelUp(profile: inout ToddlerProfile) {
        let allProgressFull = profile.cognitiveSkillsProgress >= 1.0 &&
        profile.colorPerceptionProgress >= 1.0 &&
        profile.observationSkillsProgress >= 1.0
        
        if allProgressFull {
            profile.level = profile.level + 1
            
            profile.cognitiveSkillsProgress = 0.0
            profile.colorPerceptionProgress = 0.0
            profile.observationSkillsProgress = 0.0
            
            self.showLevelUpPopup = true
        }
    }
    
    func signInWithGoogle() async {
        isLoading = true
        
        guard let topVC = UIApplication.shared.keyWindow?.rootViewController else {
            displayMessage("Error", "Could not find a view to present from.", isError: true)
            isLoading = false
            return
        }
        
        do {
            let gidSignInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: topVC)
            
            guard let idToken = gidSignInResult.user.idToken?.tokenString else {
                throw URLError(.badServerResponse, userInfo: ["message": "Could not fetch Google ID Token."])
            }
            let accessToken = gidSignInResult.user.accessToken.tokenString
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            let result = try await Auth.auth().signIn(with: credential)
            let user = result.user
            
            let userDocRef = Firestore.firestore().collection("users").document(user.uid)
            let document = try await userDocRef.getDocument()
            
            if !document.exists {
                print("DEBUG: New user signing in with Google. Creating user document...")
                let newUser = AppUser(uid: user.uid, email: user.email ?? "", displayName: user.displayName ?? "User")
                try await userDocRef.setData(from: newUser)
            }
            
            self.userSession = user
            await fetchUserData()
            
        } catch {
            displayMessage("Google Sign-In Failed", error.localizedDescription, isError: true)
            print("DEBUG: Google Sign-In failed with error: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    func updateToddlerProfile(name: String, age: String) async {
        isLoading = true
        defer { isLoading = false }
        
        guard let uid = currentUser?.uid, var profile = self.selectedToddlerProfile, let profileId = profile.id else { return }
        
        profile.name = name
        profile.age = age
        
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("toddlers").document(profileId)
                .setData(from: profile, merge: true)
            
            if let index = self.toddlerProfiles.firstIndex(where: { $0.id == profileId }) {
                self.toddlerProfiles[index] = profile
                self.selectedToddlerProfile = profile
            }
        } catch {
            displayMessage("Profile Update Failed", error.localizedDescription, isError: true)
        }
    }
    
    func changePassword(currentPassword: String?, newPassword: String) async {
        isLoading = true
        defer { isLoading = false }
        
        guard let user = self.userSession else {
            displayMessage("Error", "You must be logged in to change your password.", isError: true)
            return
        }
        
        do {
            if isPasswordUser {
                guard let email = user.email, let currentPassword = currentPassword, !currentPassword.isEmpty else {
                    displayMessage("Error", "Your current password is required.", isError: true)
                    return
                }
                let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
                try await user.reauthenticate(with: credential)
            }
            
            try await user.updatePassword(to: newPassword)
            displayMessage("Success!", "Your password has been changed successfully.", isError: false)
            
        } catch {
            displayMessage("Error", "The operation failed. Please check your current password and try again.", isError: true)
            print("DEBUG: Password change failed: \(error.localizedDescription)")
        }
    }
    
    func saveScreenTimeData() async {
        guard var profile = self.selectedToddlerProfile else { return }
        
        let (passcode, limit, usage, hasExtension, date) = ScreenTimeManager.shared.getCurrentDataForSave()
        
        profile.screenTimePasscode = passcode
        profile.dailyLimitInMinutes = limit
        profile.timeSpentToday = usage
        profile.hasGrantedExtensionToday = hasExtension
        profile.lastUsageDate = date
        
        self.selectedToddlerProfile = profile
        await saveToddlerProfile(profile)
    }
    
    private func saveToddlerProfile(_ profile: ToddlerProfile) async {
        guard let uid = currentUser?.uid, let profileId = profile.id else { return }
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("toddlers").document(profileId)
                .setData(from: profile, merge: true)
            print("DEBUG: Toddler profile saved successfully.")
        } catch {
            displayMessage("Error", "Could not save profile settings.", isError: true)
            print("DEBUG: Could not save profile: \(error.localizedDescription)")
        }
    }
    
    func setScreenTimePasscode(passcode: String) async {
            ScreenTimeManager.shared.setPasscode(passcode)
            
            guard var profile = self.selectedToddlerProfile else { return }
            profile.screenTimePasscode = passcode
            await saveToddlerProfile(profile)
        }
        
        func setScreenTimeLimit(minutes: Int) async {
            ScreenTimeManager.shared.setDailyLimit(minutes)

            guard var profile = self.selectedToddlerProfile else { return }
            profile.dailyLimitInMinutes = minutes
            await saveToddlerProfile(profile)
        }

        func grantScreenTimeExtension() async {
            ScreenTimeManager.shared.grantExtension()

            guard var profile = self.selectedToddlerProfile else { return }
            let (_, _, _, hasExtension, date) = ScreenTimeManager.shared.getCurrentDataForSave()
            profile.hasGrantedExtensionToday = hasExtension
            profile.lastUsageDate = date
            await saveToddlerProfile(profile)
        }
    
    func deleteToddlerProfile(profile: ToddlerProfile) async {
            guard let uid = currentUser?.uid, let profileId = profile.id else { return }
            
            isLoading = true
            defer { isLoading = false }
            
            do {
                try await Firestore.firestore().collection("users").document(uid).collection("toddlers").document(profileId).delete()

                if let index = self.toddlerProfiles.firstIndex(where: { $0.id == profileId }) {
                    self.toddlerProfiles.remove(at: index)
                }

                if self.toddlerProfiles.isEmpty {
                    self.selectedToddlerProfile = nil
                    self.appState = .toddlerProfileSetup
                } else {
                    self.selectedToddlerProfile = self.toddlerProfiles.first
                    await fetchActivityHistory()
                }
                
            } catch {
                displayMessage("Profile Deletion Failed", error.localizedDescription, isError: true)
            }
        }

    func generateAIReport() async -> AIReport? {
        guard let profile = selectedToddlerProfile else { return nil }

        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(modelName: "gemini-2.5-flash")

        let parentName = self.currentUser?.displayName ?? "there"

        let topActivities = Dictionary(grouping: activityHistory, by: { $0.activityName })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        let prompt = """
          Act as a warm, encouraging, and insightful early childhood educator.
          Your task is to generate a short, positive, and easy-to-read progress report for a parent about their toddler's activity in the Toddl-AR app.

          Here is the data for the parent and toddler:
          - Parent's Name: \(parentName)
          - Toddler's Name: \(profile.name)
          - Cognitive Skills Progress: \(Int(profile.cognitiveSkillsProgress * 100))%
          - Color Perception Progress: \(Int(profile.colorPerceptionProgress * 100))%
          - Observation Skills Progress: \(Int(profile.observationSkillsProgress * 100))%
          - Their favorite activities recently have been: \(topActivities.joined(separator: ", ")).

          Based on this data, please write a 5-6 sentence report.
          - Start with a positive greeting addressed to the parent by their name (e.g., "Hi \(parentName),").
          - Mention their toddler's progress in a specific area.
          - Mention the area for improvement.
          - Highlight their interest in their favorite activities.
          - Conclude with an encouraging remark for the parent.
          - Do not use technical jargon. Keep the language simple and heartwarming.
        """

        do {
            let response = try await model.generateContent(prompt)
            
            let skills = [
                ("Cognitive", profile.cognitiveSkillsProgress),
                ("Color", profile.colorPerceptionProgress),
                ("Observation", profile.observationSkillsProgress)
            ]
            let weakestSkill = skills.min(by: { $0.1 < $1.1 })
            let allActivities: [Activity] = [
                .init(id: "alphabets-in-ar", name: "Alphabets in AR", categories: ["Cognitive", "Color", "Observation"]),
                .init(id: "numbers-in-ar", name: "Numbers in AR", categories: ["Cognitive", "Observation"]),
                .init(id: "shapes-in-ar", name: "Shapes in AR", categories: ["Color", "Observation"]),
                .init(id: "ar-doodling", name: "AR Doodling", categories: ["Creative"])
            ]
            
            var suggestions: [Activity] = []
            if let weakest = weakestSkill, weakest.1 < 0.8 {
                suggestions = allActivities.filter { $0.categories.contains(weakest.0) }.shuffled().prefix(2).map { $0 }
            }
            
            return AIReport(
                assessment: response.text ?? "Could not generate report text.",
                suggestions: suggestions,
                topActivities: allActivities.filter { topActivities.contains($0.name) }
            )

        } catch {
            print("Error generating content: \(error.localizedDescription)")
            return AIReport(
                assessment: "There was an issue generating the report. Please check your connection and try again.",
                suggestions: [],
                topActivities: []
            )
        }
    }
}

struct AggregatedActivityRecord: Identifiable, Hashable {
    let id: String
    let name: String
    var totalDuration: Int
}

enum ActivityFilter: Hashable, Identifiable {
    case allTime
    case date(Date)
    
    var id: String {
        switch self {
        case .allTime: return "allTime"
        case .date(let date): return date.ISO8601Format()
        }
    }
}

struct AIReport {
    let assessment: String
    let suggestions: [Activity]
    let topActivities: [Activity]
}

extension UIApplication {
    var keyWindow: UIWindow? {
        return self.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene })
            .flatMap({ $0 as? UIWindowScene })?.windows
            .first(where: \.isKeyWindow)
    }
}
