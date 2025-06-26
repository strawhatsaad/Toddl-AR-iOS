import Foundation
import Combine

@MainActor
class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    @Published var dailyLimitInMinutes: Int = 60
    @Published private(set) var timeSpentToday: TimeInterval = 0
    @Published private(set) var isLocked: Bool = false
    @Published var isPasscodeSet: Bool = false

    private var passcode: String?
    private var hasGrantedExtensionToday: Bool = false
    
    private init() {}

    private static var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func configure(with profile: ToddlerProfile) {
        self.dailyLimitInMinutes = profile.dailyLimitInMinutes
        self.passcode = profile.screenTimePasscode
        self.isPasscodeSet = profile.screenTimePasscode != nil

        if profile.lastUsageDate == Self.todayDateString {
            self.timeSpentToday = profile.timeSpentToday
            self.hasGrantedExtensionToday = profile.hasGrantedExtensionToday
        } else {
            self.timeSpentToday = 0
            self.hasGrantedExtensionToday = false
        }
        
        checkLockStatus()
    }

    func reset() {
        self.dailyLimitInMinutes = 60
        self.timeSpentToday = 0
        self.isLocked = false
        self.passcode = nil
        self.isPasscodeSet = false
        self.hasGrantedExtensionToday = false
    }

    func getCurrentDataForSave() -> (passcode: String?, limit: Int, usage: TimeInterval, hasExtension: Bool, date: String) {
        return (self.passcode, self.dailyLimitInMinutes, self.timeSpentToday, self.hasGrantedExtensionToday, Self.todayDateString)
    }

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
    
    private func checkLockStatus() {
        let limitInSeconds = TimeInterval(dailyLimitInMinutes * 60)
        var effectiveLimit = limitInSeconds

        if hasGrantedExtensionToday {
            effectiveLimit += 15 * 60
        }
        
        isLocked = timeSpentToday >= effectiveLimit
    }
}
