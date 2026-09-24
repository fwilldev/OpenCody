//
//  PromptEngagement.swift
//  OpenCody - An OpenCode Client
//

import Foundation

// MARK: - PromptEngagement

/// Shared usage counters and throttling for the app's occasional asks — the tip prompt
/// (`TipPromptService`) and the rating prompt (`ReviewPromptService`).
///
/// Both prompts are driven by the same two questions ("has this person used the app
/// enough?" and "have we asked recently?"), so the bookkeeping lives here instead of
/// being duplicated — which also guarantees the two never appear back to back.
enum PromptEngagement {

    // MARK: - Tunables

    /// Minimum number of days between *any* two prompts, regardless of which one.
    static let minimumDaysBetweenPrompts = 21

    // MARK: - UserDefaults Keys

    private enum Key {
        /// Launch counters keep their historical `tipPrompt_` prefix so existing
        /// installs don't lose the usage history they've already accumulated.
        static let launchCount     = "tipPrompt_launchCount"
        static let firstLaunchDate = "tipPrompt_firstLaunchDate"
        static let lastPromptDate  = "prompt_lastShownDate"
    }

    // MARK: - Launch Tracking

    /// Call once per app launch (from the root view's `.task`).
    static func recordLaunch(defaults: UserDefaults = .standard) {
        // First launch date — write once, never overwrite.
        if defaults.object(forKey: Key.firstLaunchDate) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.firstLaunchDate)
        }
        defaults.set(defaults.integer(forKey: Key.launchCount) + 1, forKey: Key.launchCount)
    }

    static func launchCount(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: Key.launchCount)
    }

    /// Days since the app was first launched, or `nil` when that was never recorded.
    static func daysSinceFirstLaunch(defaults: UserDefaults = .standard) -> Int? {
        let timestamp = defaults.double(forKey: Key.firstLaunchDate)
        guard timestamp > 0 else { return nil }
        let firstLaunch = Date(timeIntervalSince1970: timestamp)
        return Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
    }

    // MARK: - Cross-Prompt Throttle

    /// Whether enough time has passed since the last prompt of any kind.
    static func isQuietPeriodOver(defaults: UserDefaults = .standard) -> Bool {
        let timestamp = defaults.double(forKey: Key.lastPromptDate)
        guard timestamp > 0 else { return true }
        let last = Date(timeIntervalSince1970: timestamp)
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return days >= minimumDaysBetweenPrompts
    }

    /// Record that some prompt was just shown, starting the shared quiet period.
    static func recordPromptShown(defaults: UserDefaults = .standard) {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastPromptDate)
    }
}
