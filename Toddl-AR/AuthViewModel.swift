//
//  AuthViewModel.swift
//  Toddl-AR
//
//  Created by Saad Anjum on 10/06/2025.
//

import SwiftUI
import Firebase
import FirebaseFirestore // Import this for Firestore Codable support
import FirebaseAuth
import Combine

// The AppState enum is now defined here, so it's accessible within the ViewModel.
enum AppState {
    case splash, intro, login, signUp, toddlerProfileSetup, mainHub
}

// A Codable struct to represent our Toddler's profile data
struct ToddlerProfile: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let age: String
    let avatarImageName: String // To store the selected avatar
    
    // --- ADD THESE LINES ---
    var cognitiveSkillsProgress: Double? = 0.0
    var colorPerceptionProgress: Double? = 0.0
    var observationSkillsProgress: Double? = 0.0
}

// --- NEW DATA MODEL FOR HISTORY ---
struct ActivityRecord: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let activityId: String
    let activityName: String
    let dateCompleted: Date
    let durationInSeconds: Int
}

struct AggregatedActivityRecord: Identifiable, Hashable {
    let id: String // Use activityId as the ID
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

// A Codable struct for the User's data
struct AppUser: Identifiable, Codable {
    @DocumentID var id: String?
    let uid: String
    let email: String
    var displayName: String
}


@MainActor
class AuthViewModel: ObservableObject {
    // Published properties to drive UI updates
    @Published var userSession: FirebaseAuth.User?
    @Published var currentUser: AppUser?
    @Published var currentToddlerProfile: ToddlerProfile?
    @Published var appState: AppState = .splash
    
    @Published var activityHistory = [ActivityRecord]()
    
    // Properties for loading states and custom messages
    @Published var isLoading = false
    @Published var showMessage = false
    @Published var messageTitle = ""
    @Published var messageContent = ""
    @Published var messageIsError = false
    
    init() {
        // Check the authentication state when the app starts
        self.userSession = Auth.auth().currentUser
        if self.userSession != nil {
            Task {
                await self.fetchUserData()
            }
        } else {
            self.appState = .splash
        }
    }
    
    // Helper to display messages
    func displayMessage(_ title: String, _ content: String, isError: Bool) {
        self.messageTitle = title
        self.messageContent = content
        self.messageIsError = isError
        self.showMessage = true
    }
    
    // --- AUTHENTICATION METHODS ---
    
    func signIn(withEmail email: String, password: String) async {
        isLoading = true
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            self.userSession = result.user
            await fetchUserData()
        } catch {
            displayMessage("Sign In Failed", error.localizedDescription, isError: true)
            print("DEBUG: Failed to sign in: \(error.localizedDescription)")
        }
        // --- UPDATED --- Explicitly set isLoading to false at the end.
        isLoading = false
    }
    
    func signUp(withEmail email: String, password: String, name: String) async {
        isLoading = true
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            self.userSession = result.user
            
            let newUser = AppUser(uid: result.user.uid, email: email, displayName: name)
            let encodedUser = try Firestore.Encoder().encode(newUser)
            try await Firestore.firestore().collection("users").document(result.user.uid).setData(encodedUser)
            
            self.currentUser = newUser
            displayMessage("Success!", "Your account has been created. Please log in.", isError: false)
            
        } catch {
            displayMessage("Sign Up Failed", error.localizedDescription, isError: true)
            print("DEBUG: Failed to sign up: \(error.localizedDescription)")
        }
        // --- UPDATED --- Explicitly set isLoading to false at the end.
        isLoading = false
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.userSession = nil
            self.currentUser = nil
            self.currentToddlerProfile = nil
            self.appState = .login
        } catch {
            print("DEBUG: Failed to sign out: \(error.localizedDescription)")
        }
    }
    
    // --- FIRESTORE DATA METHODS ---
    
    func fetchUserData() async {
        isLoading = true
        guard let uid = self.userSession?.uid else {
            isLoading = false
            return
        }
        
        do {
            let userDocument = try await Firestore.firestore().collection("users").document(uid).getDocument()
            self.currentUser = try userDocument.data(as: AppUser.self)
            
            let toddlerSnapshot = try await Firestore.firestore().collection("users").document(uid).collection("toddlers").limit(to: 1).getDocuments()
            
            if let toddlerDoc = toddlerSnapshot.documents.first {
                self.currentToddlerProfile = try toddlerDoc.data(as: ToddlerProfile.self)
                self.appState = .mainHub
            } else {
                self.appState = .toddlerProfileSetup
            }
        } catch {
            print("DEBUG: Failed to fetch user data: \(error.localizedDescription)")
            if self.currentUser != nil {
                self.appState = .toddlerProfileSetup
            } else {
                self.appState = .login
            }
        }
        // --- UPDATED --- Explicitly set isLoading to false at the end.
        isLoading = false
    }
    
    func createToddlerProfile(name: String, age: String) async {
        isLoading = true
        guard let uid = self.currentUser?.uid else {
            isLoading = false
            return
        }
        
        let newProfile = ToddlerProfile(name: name, age: age, avatarImageName: "toddler1")
        
        do {
            let encodedProfile = try Firestore.Encoder().encode(newProfile)
            _ = try await Firestore.firestore().collection("users").document(uid).collection("toddlers").addDocument(data: encodedProfile)
            
            self.currentToddlerProfile = newProfile
            self.appState = .mainHub
            
        } catch {
            displayMessage("Profile Creation Failed", error.localizedDescription, isError: true)
            print("DEBUG: Failed to create toddler profile: \(error.localizedDescription)")
        }
        // --- UPDATED --- Explicitly set isLoading to false at the end.
        isLoading = false
    }
    
    // --- ADD THIS ENTIRE NEW FUNCTION ---
    func updateProgressAndHistory(activityId: String, activityName: String, totalSteps: Int, stepsCompleted: Int, duration: TimeInterval) async {
        guard let uid = currentUser?.uid, var profile = self.currentToddlerProfile else { return }
        
        // 1. Calculate Progress Increase
        let progressIncrease = (Double(stepsCompleted) / Double(totalSteps)) * 0.2 // 20% for full completion
        
        // 2. Update Progress based on Activity
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
        default:
            break
        }
        
        // 3. Save the new Activity Record to history
        let newRecord = ActivityRecord(
            activityId: activityId,
            activityName: activityName,
            dateCompleted: Date(),
            durationInSeconds: Int(duration)
        )
        
        // 4. Update Firestore
        do {
            // Update the profile document
            let encodedProfile = try Firestore.Encoder().encode(profile)
            try await Firestore.firestore().collection("users").document(uid).collection("toddlers").document(profile.id!).setData(encodedProfile, merge: true)
            
            // Add a new document to the history sub-collection
            _ = try await Firestore.firestore().collection("users").document(uid).collection("toddlers").document(profile.id!).collection("activityHistory").addDocument(data: Firestore.Encoder().encode(newRecord))
            
            // Update local data
            self.currentToddlerProfile = profile
            if !self.activityHistory.contains(newRecord) {
                self.activityHistory.insert(newRecord, at: 0)
            }
            
        } catch {
            print("Error updating progress: \(error.localizedDescription)")
        }
    }
    func fetchActivityHistory() async {
        guard let uid = currentUser?.uid, let profileId = currentToddlerProfile?.id, activityHistory.isEmpty else { return }
        
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
}

@MainActor
class RecentActivitiesViewModel: ObservableObject {
    @Published var selectedFilter: ActivityFilter = .allTime {
        didSet { processRecords() }
    }
    @Published var aggregatedRecords = [AggregatedActivityRecord]()
    
    @Published var dateFilters: [ActivityFilter] = []
    
    // --- REMOVE 'private' from these two lines ---
        var allRecords: [ActivityRecord] = []
        var cancellables = Set<AnyCancellable>()
        // ---------------------------------------------

    init(historyPublisher: Published<[ActivityRecord]>.Publisher) {
        // This ViewModel will automatically update when the activity history changes
        historyPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] history in
                guard let self = self else { return }
                self.allRecords = history
                self.generateDateFilters()
                self.processRecords()
            }
            .store(in: &cancellables)
    }
    
    func selectFilter(_ filter: ActivityFilter) {
        self.selectedFilter = filter
    }
    
    public func generateDateFilters() {
        var filters: [ActivityFilter] = [.allTime]
        // Get unique dates from the records, limited to the last 7 unique days
        let uniqueDates = Set(allRecords.map { Calendar.current.startOfDay(for: $0.dateCompleted) })
        let recentUniqueDates = Array(uniqueDates).sorted(by: >).prefix(7)
        filters.append(contentsOf: recentUniqueDates.map { .date($0) })
        self.dateFilters = filters
    }
    
    public func processRecords() {
        var recordsToProcess: [ActivityRecord]
        
        // 1. Filter records by date if necessary
        switch selectedFilter {
        case .allTime:
            recordsToProcess = allRecords
        case .date(let date):
            recordsToProcess = allRecords.filter { Calendar.current.isDate($0.dateCompleted, inSameDayAs: date) }
        }
        
        // 2. Aggregate the filtered records
        let dictionary = Dictionary(grouping: recordsToProcess, by: { $0.activityId })
        
        self.aggregatedRecords = dictionary.values.compactMap { recordsInGroup -> AggregatedActivityRecord? in
            guard let firstRecord = recordsInGroup.first else { return nil }
            let totalDuration = recordsInGroup.reduce(0) { $0 + $1.durationInSeconds }
            return AggregatedActivityRecord(id: firstRecord.activityId, name: firstRecord.activityName, totalDuration: totalDuration)
        }
    }
}
