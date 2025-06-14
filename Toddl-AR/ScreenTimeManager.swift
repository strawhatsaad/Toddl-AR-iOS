// ScreenTimeManager.swift

import Foundation
import Combine

@MainActor
class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    
    // --- Published properties for the UI to observe ---
    @Published var dailyLimitInMinutes: Int = 60
    @Published private(set) var timeSpentToday: TimeInterval = 0
    @Published private(set) var isLocked: Bool = false
    @Published var isPasscodeSet: Bool = false
    
    // --- Internal state properties ---
    private var passcode: String?
    private var hasGrantedExtensionToday: Bool = false
    
    private init() {}
    
    // --- Helper to get today's date as a string ---
    private static var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Configures the manager with the loaded profile. Resets daily usage if it's a new day.
    func configure(with profile: ToddlerProfile) {
        self.dailyLimitInMinutes = profile.dailyLimitInMinutes
        self.passcode = profile.screenTimePasscode
        self.isPasscodeSet = profile.screenTimePasscode != nil

        // Check if the last usage was today. If not, reset the daily timer.
        if profile.lastUsageDate == Self.todayDateString {
            self.timeSpentToday = profile.timeSpentToday
            self.hasGrantedExtensionToday = profile.hasGrantedExtensionToday
        } else {
            self.timeSpentToday = 0
            self.hasGrantedExtensionToday = false
        }
        
        checkLockStatus()
    }

    /// Resets the manager to its default state on logout.
    func reset() {
        self.dailyLimitInMinutes = 60
        self.timeSpentToday = 0
        self.isLocked = false
        self.passcode = nil
        self.isPasscodeSet = false
        self.hasGrantedExtensionToday = false
    }
    
    /// Returns the latest screen time data to be saved to the database.
    func getCurrentDataForSave() -> (passcode: String?, limit: Int, usage: TimeInterval, hasExtension: Bool, date: String) {
        return (self.passcode, self.dailyLimitInMinutes, self.timeSpentToday, self.hasGrantedExtensionToday, Self.todayDateString)
    }

    // MARK: - In-Memory State Modifiers

    func setDailyLimit(_ minutes: Int) {
        dailyLimitInMinutes = minutes
        checkLockStatus()
    }
    
    func addSession(duration: TimeInterval) {
        timeSpentToday += duration
        checkLockStatus()
    }

    func grantExtension() {
        hasGrantedExtensionToday = true
        checkLockStatus()
    }

    func checkPasscode(_ passcode: String) -> Bool {
        return self.passcode == passcode
    }

    func setPasscode(_ passcode: String) {
        self.passcode = passcode
        self.isPasscodeSet = true
    }

    /// Checks if the time spent has exceeded the allowed limit.
    private func checkLockStatus() {
        let limitInSeconds = TimeInterval(dailyLimitInMinutes * 60)
        var effectiveLimit = limitInSeconds

        if hasGrantedExtensionToday {
            effectiveLimit += 15 * 60 // 15 minute extension
        }
        
        isLocked = timeSpentToday >= effectiveLimit
    }
}
