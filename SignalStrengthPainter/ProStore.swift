import Foundation
import StoreKit

/// StoreKit 2 manager for Wi-Fi Buddy Pro.
///
/// Entitlement source of truth is `Transaction.currentEntitlements` — we never
/// persist a `isProUser` flag in `UserDefaults`. A user who jailbreaks their
/// device can flip a plain `@AppStorage("isProUser")` to `true`, but they
/// cannot forge a StoreKit 2 `VerificationResult.verified` entry because that
/// chain is JWS-signed by Apple and validated on-device. If the user refunds
/// the subscription, `revocationDate` is populated and `isProUser` drops to
/// `false` on the next entitlement refresh.
@MainActor
final class ProStore: ObservableObject {

    // MARK: - Product IDs

    /// Product IDs must match exactly what is configured in App Store Connect
    /// (or the local `.storekit` configuration file used during development).
    /// Keep the list narrow — any unknown ID silently drops out of the
    /// entitlement check below, which means a mistyped ID here manifests as
    /// "the user paid but the app still shows the paywall".
    static let monthlyProductID = "com.wifibuddy.pro.monthly"
    static let yearlyProductID = "com.wifibuddy.pro.yearly"
    static let allProductIDs: Set<String> = [monthlyProductID, yearlyProductID]

    // MARK: - Published state

    @Published private(set) var products: [Product] = []
    @Published private(set) var isProUser: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isRestoring: Bool = false
    @Published var lastError: String?

    // MARK: - Lifecycle

    private var transactionListener: Task<Void, Never>?

    init() {
        // Transactions can arrive outside of a direct purchase flow — e.g.
        // parental approval finally coming through (`.pending` → approved),
        // a family-sharing transfer, or a refund. We need to finish those
        // transactions and re-derive `isProUser` even when the paywall is
        // not on screen, so the listener lives for the lifetime of the app.
        transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }

        Task { await refresh() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public API

    /// Reload product metadata and re-derive the Pro entitlement.
    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
    }

    /// Fetch `Product` objects from the App Store so we can show localized
    /// pricing on the paywall. Failure here is non-fatal — we fall back to
    /// the hard-coded "$2.99 / $9.99" copy in `PaywallView`.
    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            // Show Monthly first, Yearly second, regardless of what the
            // store returns — the paywall layout assumes that order.
            self.products = loaded.sorted { lhs, _ in
                lhs.id == Self.monthlyProductID
            }
        } catch {
            lastError = "Couldn't load subscription options. Check your connection and try again."
        }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    /// Start a purchase flow for `product`. Returns `true` if the user now
    /// has an active Pro entitlement as a result.
    func purchase(_ product: Product) async -> Bool {
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isProUser

            case .userCancelled:
                return false

            case .pending:
                // Ask-to-Buy / SCA — we don't have the entitlement yet,
                // but `Transaction.updates` will deliver it later.
                lastError = "Purchase is pending approval. You'll get Pro access once it's approved."
                return false

            @unknown default:
                return false
            }
        } catch StoreError.failedVerification {
            lastError = "We couldn't verify that purchase with the App Store."
            return false
        } catch {
            lastError = "Purchase failed. Please try again."
            return false
        }
    }

    /// Implements the "Restore Purchase" button.
    ///
    /// `AppStore.sync()` forces a refresh of the user's transaction history
    /// from the App Store (the user is prompted to sign in if needed). After
    /// the sync, `Transaction.currentEntitlements` will reflect any active
    /// subscription tied to the signed-in Apple ID, including one purchased
    /// on a different device. We then re-derive `isProUser` from that
    /// authoritative source.
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isProUser {
                lastError = "No active Wi-Fi Buddy Pro subscription was found on this Apple ID."
            }
        } catch {
            lastError = "Couldn't restore purchases. Please try again."
        }
    }

    /// Walk `Transaction.currentEntitlements` and set `isProUser` based on
    /// whether any verified, non-revoked, non-expired transaction matches
    /// one of our product IDs. This is the *only* place `isProUser` is set
    /// to `true` — callers cannot force it.
    func refreshEntitlements() async {
        var active = false

        for await result in Transaction.currentEntitlements {
            // `.unverified` = JWS signature didn't check out. Treat as
            // absent, never grant access.
            guard case .verified(let transaction) = result else { continue }

            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            // `isUpgraded` is set on the old transaction when the user moves
            // up a tier inside the same subscription group — skip it to
            // avoid double-counting. The new transaction will be present in
            // the same enumeration.
            guard transaction.isUpgraded == false else { continue }

            if let expiry = transaction.expirationDate {
                if expiry > Date() { active = true }
            } else {
                // Non-subscription (consumable/non-consumable) — treat any
                // verified purchase as active Pro.
                active = true
            }
        }

        self.isProUser = active
    }

    // MARK: - Internals

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
