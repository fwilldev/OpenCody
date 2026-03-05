//
//  NotificationSettings.swift
//  OpenCody - An OpenCode Client
//

import Foundation

// MARK: - NotificationSettings

/// UserDefaults-backed notification preferences.
///
/// Each toggle controls whether a specific notification category produces
/// an OS notification. All toggles default to `true` (opt-out model).
///
/// Runs on `MainActor` (project default) — safe for SwiftUI observation.
@Observable
final class NotificationSettings {

    static let shared = NotificationSettings()

    // MARK: - Keys

    private enum Keys {
        static let turnComplete = "notification.turnComplete"
        static let errors = "notification.errors"
        static let permissions = "notification.permissions"
        static let questions = "notification.questions"
    }

    // MARK: - Toggles

    /// Notify when a session finishes generating (session.idle).
    var turnCompleteEnabled: Bool {
        didSet { UserDefaults.standard.set(turnCompleteEnabled, forKey: Keys.turnComplete) }
    }

    /// Notify on session errors.
    var errorsEnabled: Bool {
        didSet { UserDefaults.standard.set(errorsEnabled, forKey: Keys.errors) }
    }

    /// Notify when a tool is waiting for permission approval.
    var permissionsEnabled: Bool {
        didSet { UserDefaults.standard.set(permissionsEnabled, forKey: Keys.permissions) }
    }

    /// Notify when the agent asks a question.
    var questionsEnabled: Bool {
        didSet { UserDefaults.standard.set(questionsEnabled, forKey: Keys.questions) }
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        // Register defaults so first launch has all toggles enabled
        defaults.register(defaults: [
            Keys.turnComplete: true,
            Keys.errors: true,
            Keys.permissions: true,
            Keys.questions: true,
        ])

        turnCompleteEnabled = defaults.bool(forKey: Keys.turnComplete)
        errorsEnabled = defaults.bool(forKey: Keys.errors)
        permissionsEnabled = defaults.bool(forKey: Keys.permissions)
        questionsEnabled = defaults.bool(forKey: Keys.questions)
    }
}
