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
}
