//
//  TipJarManager.swift
//  OpenCody - An OpenCode Client
//

import Foundation
import StoreKit

// MARK: - TipJarManager

/// Manages StoreKit 2 consumable in-app purchases for the Tip Jar feature.
///
/// Loads three tip products from the App Store, handles purchase flow,
/// and listens for unfinished transactions on launch.
///
/// Runs on `MainActor` — safe for SwiftUI observation.
@Observable
final class TipJarManager {

    // MARK: - Product Identifiers

    /// The three consumable tip product IDs registered in App Store Connect.
    static let productIDs: Set<String> = [
        "tip_jar",
        "mid_tip_jar",
        "big_tip_jar",
    ]

    /// Preferred display order: small → mid → big.
    private static let sortOrder: [String] = [
        "tip_jar",
        "mid_tip_jar",
        "big_tip_jar",
    ]

    // MARK: - State

    /// The loaded StoreKit products, sorted small → mid → big.
    private(set) var products: [Product] = []

    /// Whether a purchase is currently in progress.
    private(set) var isPurchasing = false

    /// Whether products are currently loading.
    private(set) var isLoading = false

    /// Set after a successful purchase to trigger a thank-you alert.
    var showThankYou = false

    /// Non-nil when an error should be displayed to the user.
    var errorMessage: String?

    // MARK: - Private

    /// Task handle for the transaction listener so it can be cancelled.
    @ObservationIgnored
    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Call once on view appear to load products and start listening for transactions.
    func start() async {
        startTransactionListener()
        await loadProducts()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products

    /// Fetches the tip products from the App Store.
    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            // Sort by our preferred order
            products = storeProducts.sorted { a, b in
                let indexA = Self.sortOrder.firstIndex(of: a.id) ?? Int.max
                let indexB = Self.sortOrder.firstIndex(of: b.id) ?? Int.max
                return indexA < indexB
            }
        } catch {
            errorMessage = "Could not load products. Please try again later."
        }
    }

    // MARK: - Purchase

    /// Initiates a purchase for the given product.
    ///
    /// - Parameter product: The `Product` to purchase.
    func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                // Consumables must be finished immediately.
                await transaction.finish()
                showThankYou = true

            case .userCancelled:
                break

            case .pending:
                errorMessage = "Purchase is pending approval."

            @unknown default:
                break
            }
        } catch StoreKitError.userCancelled {
            // User cancelled — no error needed
        } catch {
            errorMessage = "Purchase failed. Please try again."
        }
    }

    // MARK: - Transaction Listener

    /// Listens for unfinished transactions (e.g. interrupted purchases).
    private func startTransactionListener() {
        transactionListenerTask = Task.detached {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                case .unverified:
                    break
                }
            }
        }
    }

    // MARK: - Verification

    /// Unwraps a verified transaction or throws if verification failed.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}

// MARK: - Convenience

extension TipJarManager {

    /// Human-readable emoji for each tip tier.
    static func emoji(for productID: String) -> String {
        switch productID {
        case "tip_jar":     return "☕"
        case "mid_tip_jar": return "🧁"
        case "big_tip_jar": return "🎉"
        default:            return "💜"
        }
    }

    /// Human-readable tier name.
    static func tierName(for productID: String) -> String {
        switch productID {
        case "tip_jar":     return "Small Tip"
        case "mid_tip_jar": return "Medium Tip"
        case "big_tip_jar": return "Big Tip"
        default:            return "Tip"
        }
    }
}
