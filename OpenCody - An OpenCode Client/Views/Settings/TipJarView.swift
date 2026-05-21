//
//  TipJarView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI
import StoreKit

/// A Tip Jar view that displays three consumable tip options.
/// Integrates with `TipJarManager` for StoreKit 2 purchase flow.
struct TipJarView: View {

    @State private var tipJarManager = TipJarManager()

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {

                    // MARK: - Header
                    headerSection

                    // MARK: - Tip Options
                    if tipJarManager.isLoading {
                        loadingView
                    } else if tipJarManager.products.isEmpty {
                        emptyView
                    } else {
                        tipCardsSection
                    }

                    // MARK: - Footer
                    footerSection
                }
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Tip Jar")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await tipJarManager.start()
        }
        .alert("Thank You! 💜", isPresented: $tipJarManager.showThankYou) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your support means a lot and helps keep OpenCody going. Thank you!")
        }
        .alert("Oops", isPresented: showErrorBinding) {
            Button("OK", role: .cancel) {
                tipJarManager.errorMessage = nil
            }
        } message: {
            Text(tipJarManager.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Animated heart icon
            ZStack {
                Circle()
                    .fill(Theme.Colors.hotPink.opacity(0.1))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(Theme.Colors.hotPink.opacity(0.05))
                    .frame(width: 100, height: 100)

                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.Colors.hotPink)
            }
            .padding(.bottom, Theme.Spacing.xs)

            Text("Support OpenCody")
                .font(Theme.Fonts.title2)
                .foregroundStyle(Theme.Colors.cloud)

            Text("If you enjoy using OpenCody, consider leaving a tip to support future development.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.silver)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Tip Cards

    private var tipCardsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(tipJarManager.products, id: \.id) { product in
                tipCard(for: product)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func tipCard(for product: Product) -> some View {
        Button {
            Task { await tipJarManager.purchase(product) }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Emoji
                Text(TipJarManager.emoji(for: product.id))
                    .font(.system(size: 32))
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accentColor(for: product.id).opacity(0.1))
                    )

                // Title + description
                VStack(alignment: .leading, spacing: 3) {
                    Text(TipJarManager.tierName(for: product.id))
                        .font(Theme.Fonts.bodyBold)
                        .foregroundStyle(Theme.Colors.cloud)

                    Text(product.description)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                        .lineLimit(2)
                }

                Spacer()

                // Price
                Text(product.displayPrice)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(accentColor(for: product.id))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(accentColor(for: product.id).opacity(0.15))
                    )
                    .overlay(
                        Capsule()
                            .stroke(accentColor(for: product.id).opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.carbon)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.Colors.graphite, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(tipJarManager.isPurchasing)
        .opacity(tipJarManager.isPurchasing ? 0.6 : 1.0)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.cyberBlue)
            Text("Loading products…")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.smoke)

            Text("Could not load products")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.silver)

            Button("Retry") {
                Task { await tipJarManager.loadProducts() }
            }
            .buttonStyle(PrimaryGlassButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("All tips are consumable one-time purchases.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.smoke)

            Text("Thank you for supporting indie development! 💜")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.smoke)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Spacing.xl)
    }

    // MARK: - Helpers

    private func accentColor(for productID: String) -> Color {
        switch productID {
        case "tip_jar":     return Theme.Colors.neonGreen
        case "mid_tip_jar": return Theme.Colors.cyberBlue
        case "big_tip_jar": return Theme.Colors.electricPurple
        default:            return Theme.Colors.cyberBlue
        }
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { tipJarManager.errorMessage != nil },
            set: { if !$0 { tipJarManager.errorMessage = nil } }
        )
    }
}
