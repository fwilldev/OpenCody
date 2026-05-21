//
//  TipPromptService.swift
//  OpenCody - An OpenCode Client
//

import Foundation
import StoreKit

// MARK: - TipPromptService

/// Encapsulates the trigger logic for the occasional "Support the Developer" prompt.
///
/// Tracks launch count, first-launch date, last-prompt date, and whether the user
/// has ever tipped (via StoreKit transaction history). All thresholds are exposed as
/// constants at the top for easy tuning / A-B testing.
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
        static let launchCount        = "tipPrompt_launchCount"
        static let firstLaunchDate    = "tipPrompt_firstLaunchDate"
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

    // MARK: - Launch Tracking

    /// Call once per app launch (in the root view's `.task`).
    func recordAppLaunch() {
        // First launch date — write once, never overwrite.
        if defaults.object(forKey: Key.firstLaunchDate) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.firstLaunchDate)
        }

        let count = defaults.integer(forKey: Key.launchCount)
        defaults.set(count + 1, forKey: Key.launchCount)
    }

    // MARK: - Prompt Eligibility

    /// Whether all conditions are met to show the prompt.
    ///
    /// Conditions:
    /// 1. User has never tipped (verified against StoreKit history).
    /// 2. At least `minimumLaunchCount` launches recorded.
    /// 3. At least `minimumDaysSinceFirstLaunch` days since first launch.
    /// 4. At least `cooldownDays` since the prompt was last shown (or never shown).
    var shouldShowPrompt: Bool {
        // Never prompt users who have already tipped.
        if hasTippedCached { return false }

        // Launch count threshold.
        let launches = defaults.integer(forKey: Key.launchCount)
        guard launches >= Self.minimumLaunchCount else { return false }

        // Days-since-first-launch threshold.
        let firstLaunchTimestamp = defaults.double(forKey: Key.firstLaunchDate)
        guard firstLaunchTimestamp > 0 else { return false }
        let firstLaunch = Date(timeIntervalSince1970: firstLaunchTimestamp)
        let daysSinceFirst = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        guard daysSinceFirst >= Self.minimumDaysSinceFirstLaunch else { return false }

        // Cooldown since last prompt.
        let lastPromptTimestamp = defaults.double(forKey: Key.lastPromptDate)
        if lastPromptTimestamp > 0 {
            let lastPrompt = Date(timeIntervalSince1970: lastPromptTimestamp)
            let daysSincePrompt = Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? 0
            guard daysSincePrompt >= Self.cooldownDays else { return false }
        }

        return true
    }

    // MARK: - Prompt Lifecycle

    /// Record that the prompt was just shown. Resets the 90-day cooldown.
    func recordPromptShown() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastPromptDate)
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
