//
//  ThemeManager.swift
//  Toddl-AR
//
//  Created by Saad Anjum on 12/06/2025.
//

// ThemeManager.swift

import Combine
import SwiftUI

// This simple class will send a notification when the theme changes.
class ThemeManager {
    static let shared = ThemeManager()
    let themeChanged = PassthroughSubject<Void, Never>()
}
