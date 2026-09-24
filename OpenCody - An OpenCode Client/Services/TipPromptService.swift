//
//  TipPromptService.swift
//  OpenCody - An OpenCode Client
//

import Foundation
import StoreKit

// MARK: - TipPromptService

/// Encapsulates the trigger logic for the occasional "Support the Developer" prompt.
///
/// Tracks last-prompt date and whether the user has ever tipped (via StoreKit
/// transaction history); launch counters and the quiet period shared with the rating
/// prompt come from `PromptEngagement`. All thresholds are exposed as constants at the
/// top for easy tuning / A-B testing.
@Observable
final class TipPromptService {

    // MARK: - Tunable Thresholds

    /// Minimum number of app launches before the prompt can appear.
    static let minimumLaunchCount = 10

    /// Minimum number of days since first launch before the prompt can appear.
    static let minimumDaysSinceFirstLaunch = 7

    /// Minimum number of days between prompt presentations.
    static let cooldownDays = 90

    // MARK: - UserDefaults Keys

    private enum Key {
        static let lastPromptDate     = "tipPrompt_lastPromptDate"
        static let hasTippedCached    = "tipPrompt_hasTippedCached"
    }

    // MARK: - Singleton

    static let shared = TipPromptService()

    // MARK: - Observable State

    /// Whether the tip prompt alert should be presented.
    var showPrompt = false

    // MARK: - Private State

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private var hasTippedCached: Bool

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasTippedCached = defaults.bool(forKey: Key.hasTippedCached)
    }

    // MARK: - Prompt Eligibility

    /// Whether all conditions are met to show the prompt.
    ///
    /// Conditions:
    /// 1. User has never tipped (verified against StoreKit history).
    /// 2. At least `minimumLaunchCount` launches recorded.
    /// 3. At least `minimumDaysSinceFirstLaunch` days since first launch.
    /// 4. At least `cooldownDays` since the prompt was last shown (or never shown).
    /// 5. No other prompt was shown inside the shared quiet period.
    var shouldShowPrompt: Bool {
        // Never prompt users who have already tipped.
        if hasTippedCached { return false }

        // Launch count threshold.
        guard PromptEngagement.launchCount(defaults: defaults) >= Self.minimumLaunchCount else {
            return false
        }

        // Days-since-first-launch threshold.
        guard let daysSinceFirst = PromptEngagement.daysSinceFirstLaunch(defaults: defaults),
              daysSinceFirst >= Self.minimumDaysSinceFirstLaunch else {
            return false
        }

        // Cooldown since last prompt.
        let lastPromptTimestamp = defaults.double(forKey: Key.lastPromptDate)
        if lastPromptTimestamp > 0 {
            let lastPrompt = Date(timeIntervalSince1970: lastPromptTimestamp)
            let daysSincePrompt = Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? 0
            guard daysSincePrompt >= Self.cooldownDays else { return false }
        }

        return PromptEngagement.isQuietPeriodOver(defaults: defaults)
    }

    // MARK: - Prompt Lifecycle

    /// Record that the prompt was just shown. Resets the 90-day cooldown.
    func recordPromptShown() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastPromptDate)
        PromptEngagement.recordPromptShown(defaults: defaults)
    }

    // MARK: - StoreKit History Check

    /// Verify against StoreKit transaction history whether the user has ever purchased
    /// a tip product. This survives reinstalls because Apple maintains the transaction
    /// ledger server-side for the Apple ID.
    ///
    /// Call once on app launch (or lazily before the first eligibility check).
    func refreshHasTippedFromStoreKit() async {
        // Already confirmed — skip the iteration.
        if hasTippedCached { return }

        let tipIDs = TipJarManager.productIDs

        for await result in Transaction.all {
            switch result {
            case .verified(let transaction):
                if tipIDs.contains(transaction.productID) {
                    markHasTipped()
                    return
                }
            case .unverified:
                // Can't trust unverified transactions — skip.
                break
            }
        }
    }

    /// Explicitly mark the user as having tipped (e.g. after a successful purchase).
    func markHasTipped() {
        hasTippedCached = true
        defaults.set(true, forKey: Key.hasTippedCached)
    }
}
