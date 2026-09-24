//
//  ReviewPromptService.swift
//  OpenCody - An OpenCode Client
//

import Foundation

// MARK: - ReviewPromptService

/// Trigger logic for the occasional "please rate the app" prompt.
///
/// Mirrors `TipPromptService`, but fires earlier in a user's lifetime: rating costs
/// nothing, so it's the first thing we ask for — the tip prompt follows much later.
/// Shared launch counters and the cross-prompt quiet period live in
/// `PromptEngagement`, so the two asks can never land on the same visit.
@Observable
final class ReviewPromptService {

    // MARK: - Tunable Thresholds

    /// Minimum number of app launches before the prompt can appear.
    static let minimumLaunchCount = 5

    /// Minimum number of days since first launch before the prompt can appear.
    static let minimumDaysSinceFirstLaunch = 3

    /// Minimum number of days between prompt presentations.
    ///
    /// The system rating sheet is throttled by iOS to three per year anyway; this only
    /// governs how often we're willing to ask at all.
    static let cooldownDays = 120

    // MARK: - UserDefaults Keys

    private enum Key {
        static let lastPromptDate = "reviewPrompt_lastPromptDate"
        static let hasRated       = "reviewPrompt_hasRated"
    }

    // MARK: - Singleton

    static let shared = ReviewPromptService()

    // MARK: - Observable State

    /// Whether the rating prompt alert should be presented.
    var showPrompt = false

    // MARK: - Private State

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private var hasRated: Bool

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasRated = defaults.bool(forKey: Key.hasRated)
    }

    // MARK: - Prompt Eligibility

    /// Whether all conditions are met to show the prompt.
    ///
    /// Conditions:
    /// 1. The user hasn't already taken us up on it.
    /// 2. At least `minimumLaunchCount` launches recorded.
    /// 3. At least `minimumDaysSinceFirstLaunch` days since first launch.
    /// 4. At least `cooldownDays` since this prompt was last shown (or never shown).
    /// 5. No other prompt was shown inside the shared quiet period.
    var shouldShowPrompt: Bool {
        // Never nag someone who already went to the App Store for us.
        if hasRated { return false }

        guard PromptEngagement.launchCount(defaults: defaults) >= Self.minimumLaunchCount else {
            return false
        }

        guard let daysSinceFirst = PromptEngagement.daysSinceFirstLaunch(defaults: defaults),
              daysSinceFirst >= Self.minimumDaysSinceFirstLaunch else {
            return false
        }

        let lastPromptTimestamp = defaults.double(forKey: Key.lastPromptDate)
        if lastPromptTimestamp > 0 {
            let lastPrompt = Date(timeIntervalSince1970: lastPromptTimestamp)
            let daysSincePrompt = Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? 0
            guard daysSincePrompt >= Self.cooldownDays else { return false }
        }

        return PromptEngagement.isQuietPeriodOver(defaults: defaults)
    }

    // MARK: - Prompt Lifecycle

    /// Record that the prompt was just shown. Resets both cooldowns.
    func recordPromptShown() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastPromptDate)
        PromptEngagement.recordPromptShown(defaults: defaults)
    }

    /// Record that the user accepted the ask, so we never bring it up again.
    ///
    /// Whether they actually left a review is invisible to the app — iOS reports nothing
    /// back from the rating sheet — so accepting is treated as done.
    func markHasRated() {
        hasRated = true
        defaults.set(true, forKey: Key.hasRated)
    }
}
