//
//  AuthViewModel.swift
//  Toddl-AR
//
//  Created by Saad Anjum on 10/06/2025.
//

import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - App State and Data Models
enum AppState {
    case splash, intro, login, signUp, toddlerProfileSetup, mainHub
}

struct ToddlerProfile: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let age: String
    let avatarImageName: String
    
    // Properties are now non-optional for easier use in the app
    var cognitiveSkillsProgress: Double
    var colorPerceptionProgress: Double
    var observationSkillsProgress: Double
    var level: Int
    var redeemedRewardIDs: [String]

    // CodingKeys help Codable match properties to Firestore fields
    enum CodingKeys: String, CodingKey {
        case id, name, age, avatarImageName, cognitiveSkillsProgress, colorPerceptionProgress, observationSkillsProgress, level, redeemedRewardIDs
    }
    
    // A custom decoder that provides default values if a field is missing from Firestore
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // These fields are required and should always exist
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        age = try container.decode(String.self, forKey: .age)
        avatarImageName = try container.decode(String.self, forKey: .avatarImageName)

        // For new fields, we use decodeIfPresent. If the key is missing, we provide a default value.
        // This is the key to fixing the persistence bug.
        cognitiveSkillsProgress = try container.decodeIfPresent(Double.self, forKey: .cognitiveSkillsProgress) ?? 0.0
        colorPerceptionProgress = try container.decodeIfPresent(Double.self, forKey: .colorPerceptionProgress) ?? 0.0
        observationSkillsProgress = try container.decodeIfPresent(Double.self, forKey: .observationSkillsProgress) ?? 0.0
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 0
        redeemedRewardIDs = try container.decodeIfPresent([String].self, forKey: .redeemedRewardIDs) ?? []
    }
    
    // A custom encoder to match our decoder
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
    }
    
    // A default initializer for creating brand new profiles
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
    let id: String // The ID is now a permanent, non-optional constant
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


// MARK: - AuthViewModel
@MainActor
class AuthViewModel: ObservableObject {
    // MARK: Published Properties
    @Published var userSession: FirebaseAuth.User?
    @Published var currentUser: AppUser?
    @Published var currentToddlerProfile: ToddlerProfile?
    @Published var appState: AppState = .splash
    
    @Published var activityHistory = [ActivityRecord]()
    @Published var showLevelUpPopup = false
    @Published var isRedeemingReward = false
    
    @Published var isLoading = false
    @Published var showMessage = false
    @Published var messageTitle = ""
    @Published var messageContent = ""
    @Published var messageIsError = false
    
    let allRewards: [Reward] = [
        .init(id: "playtime", title: "30 Mins of Extra Playtime", description: "Your little explorer has earned some extra fun! Enjoy a bonus 30 minutes of free play as a reward for all their hard work.", imageName: "play.circle"),
        .init(id: "dessert", title: "A Dessert of Choice", description: "Time for a sweet treat! Your sunshine has earned their favorite dessert. A yummy reward for a brilliant mind!", imageName: "gift.circle"),
        .init(id: "storytime", title: "Extra Story Time", description: "One more story, please! Cuddle up and enjoy an extra 10 minutes of magical story time together.", imageName: "book.circle"),
        .init(id: "park", title: "A Visit to the Park", description: "Let's go outside! It's time for an adventure at the park to celebrate a job well done.", imageName: "figure.walk.circle"),
        .init(id: "toy", title: "A Toy of Choice", description: "A special prize for a special learner! Your little nugget gets to choose a new toy on your next shopping trip.", imageName: "star.circle")
    ]
    
    // MARK: - Init
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
    
    // MARK: - Public Methods
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

    func signOut() {
        do {
            try Auth.auth().signOut()
            self.userSession = nil
            self.currentUser = nil
            self.currentToddlerProfile = nil
            self.activityHistory = []
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
            
            let toddlerSnapshot = try await Firestore.firestore().collection("users").document(uid).collection("toddlers").limit(to: 1).getDocuments()
            
            if let toddlerDoc = toddlerSnapshot.documents.first {
                self.currentToddlerProfile = try toddlerDoc.data(as: ToddlerProfile.self)
                
                // --- THIS IS THE KEY FIX ---
                // Fetch activity history right after loading the profile.
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
            
            self.currentToddlerProfile = newProfile
            self.appState = .mainHub
        } catch {
            displayMessage("Profile Creation Failed", error.localizedDescription, isError: true)
        }
    }
    
    func updateProgressAndHistory(activityId: String, activityName: String, totalSteps: Int, stepsCompleted: Int, duration: TimeInterval) async {
        guard let uid = currentUser?.uid, var profile = self.currentToddlerProfile, let profileId = profile.id else { return }
        
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
            
            self.currentToddlerProfile = profile
            if !self.activityHistory.contains(newRecord) {
                self.activityHistory.insert(newRecord, at: 0)
            }
        } catch {
            print("Error updating progress: \(error.localizedDescription)")
        }
    }
    
    // --- REPLACE the entire redeemReward function with this version ---
    func redeemReward(_ reward: Reward) async {
        guard let uid = currentUser?.uid, var profile = self.currentToddlerProfile, let profileId = profile.id else { return }
        
        self.isRedeemingReward = true
        defer { self.isRedeemingReward = false }
        
        // Add the redeemed reward's ID to our local copy of the profile
        profile.redeemedRewardIDs.append(reward.id)
        
        do {
            // This is the new, more direct approach.
            // We are manually telling Firestore to update only the 'redeemedRewardIDs' field.
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("toddlers").document(profileId)
                .updateData(["redeemedRewardIDs": profile.redeemedRewardIDs])
            
            // Update the local @Published property to match what we just saved
            self.currentToddlerProfile = profile
            
        } catch {
            print("Error redeeming reward: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    private func fetchActivityHistory() async {
        guard let uid = currentUser?.uid, let profileId = currentToddlerProfile?.id else { return }
        
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
            // 1. Level up!
            profile.level = profile.level + 1
            
            // 2. Reset progress bars
            profile.cognitiveSkillsProgress = 0.0
            profile.colorPerceptionProgress = 0.0
            profile.observationSkillsProgress = 0.0
            
            // 3. Trigger the celebration popup
            self.showLevelUpPopup = true
            
            // --- UPDATED REWARD RESET LOGIC ---
            // Now, the rewards will only reset if the new level is even AND all rewards were redeemed.
            if profile.level % 2 == 0 && profile.redeemedRewardIDs.count == allRewards.count {
                profile.redeemedRewardIDs = []
            }
        }
    }
}


// These two helper classes are for the Recent Activities screen.
// They can remain here or be moved to the ContentView file.
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
