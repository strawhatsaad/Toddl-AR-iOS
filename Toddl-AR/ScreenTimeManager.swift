// ScreenTimeManager.swift

import Foundation
import Combine

// NOTE: For a real app, you MUST use the Keychain to securely store the passcode.
fileprivate func savePasscodeToKeychain(_ passcode: String) {
    UserDefaults.standard.set(passcode, forKey: "screenTimePasscode")
}

fileprivate func getPasscodeFromKeychain() -> String? {
    UserDefaults.standard.string(forKey: "screenTimePasscode")
}

@MainActor
class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    
    private static let dailyLimitKey = "dailyLimitInMinutes"
    private static let dailyUsageKey = "dailyScreenTimeUsage"
    private static let extensionKey = "dailyExtensionGranted"
    
    @Published var dailyLimitInMinutes: Int
    @Published private(set) var timeSpentToday: TimeInterval
    @Published private(set) var isLocked: Bool = false
    
    private var hasGrantedExtensionToday: Bool

    private init() {
        let savedLimit = UserDefaults.standard.integer(forKey: Self.dailyLimitKey)
        let initialLimit = savedLimit == 0 ? 60 : savedLimit
        
        let (usage, hasExtension) = Self.loadTodaysUsage()

        self.dailyLimitInMinutes = initialLimit
        self.timeSpentToday = usage
        self.hasGrantedExtensionToday = hasExtension
        
        checkLockStatus()
    }
    
    func setDailyLimit(_ minutes: Int) {
        dailyLimitInMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.dailyLimitKey)
        checkLockStatus()
    }
    
    func addSession(duration: TimeInterval) {
        timeSpentToday += duration
        Self.saveTodaysUsage(usage: timeSpentToday, hasExtension: hasGrantedExtensionToday)
        checkLockStatus()
    }

    func grantExtension() {
        hasGrantedExtensionToday = true
        Self.saveTodaysUsage(usage: timeSpentToday, hasExtension: true)
        checkLockStatus()
    }

    func checkPasscode(_ passcode: String) -> Bool {
        return getPasscodeFromKeychain() == passcode
    }

    func setPasscode(_ passcode: String) {
        savePasscodeToKeychain(passcode)
    }

    var isPasscodeSet: Bool {
        return getPasscodeFromKeychain() != nil
    }

    private func checkLockStatus() {
        let limitInSeconds = TimeInterval(dailyLimitInMinutes * 60)
        var effectiveLimit = limitInSeconds

        if hasGrantedExtensionToday {
            effectiveLimit += 15 * 60
        }
        
        isLocked = timeSpentToday >= effectiveLimit
    }
    
    private static var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func loadTodaysUsage() -> (usage: TimeInterval, hasExtension: Bool) {
        guard let usageData = UserDefaults.standard.dictionary(forKey: dailyUsageKey) as? [String: TimeInterval],
              let usage = usageData[todayDateString] else {
            return (0, false)
        }
        
        let extensionData = UserDefaults.standard.dictionary(forKey: extensionKey) as? [String: Bool]
        let hasExtension = extensionData?[todayDateString] ?? false
        
        return (usage, hasExtension)
    }
    
    private static func saveTodaysUsage(usage: TimeInterval, hasExtension: Bool) {
        let newUsageData = [todayDateString: usage]
        let newExtensionData = [todayDateString: hasExtension]
        
        UserDefaults.standard.set(newUsageData, forKey: dailyUsageKey)
        UserDefaults.standard.set(newExtensionData, forKey: extensionKey)
    }
}
