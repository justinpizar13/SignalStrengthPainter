import Foundation
import StoreKit
import UserNotifications

/// StoreKit 2 manager for WiFi Buddy Pro.
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
    // These IDs are compile-time constants with no main-actor state, so we
    // mark them `nonisolated` to let nonisolated contexts (e.g. SwiftUI
    // previews, Sendable closures, `@ViewBuilder` bodies) reference them
    // without having to hop to the main actor first.
    nonisolated static let annualProductID = "com.wifibuddy.pro.sub.annual"

    /// IDs we actively *offer* for purchase. The paywall + product
    /// catalog only ever reads this set. Single-plan since 1.11 —
    /// previous Monthly + Yearly SKUs were collapsed into one annual
    /// plan at $9.99/year. Legacy IDs are not loaded for purchase but
    /// are still honored for entitlement (see `entitlementRecognizedProductIDs`).
    nonisolated static let allProductIDs: Set<String> = [annualProductID]

    /// Pre-1.11 product IDs. Existing subscribers on these legacy SKUs
    /// must keep their Pro entitlement until their term ends — Apple
    /// honors the original price/term until the user cancels or it
    /// expires. We load these into `Product.products(for:)` so that
    /// `refreshGracePeriodStatus` can query their subscription status
    /// (a legacy subscriber whose card declines would otherwise lose
    /// Pro during the billing-retry window because the grace check
    /// iterates `products`). The paywall reads
    /// `product(for: annualProductID)` only, so loading legacy product
    /// metadata does NOT surface old plans for purchase. We DO accept
    /// them inside `Transaction.currentEntitlements` so an existing
    /// subscriber upgrading to the 1.11 binary doesn't suddenly lose
    /// access. When the last legacy subscriber expires, this set can
    /// be emptied — but there's no harm in leaving it indefinitely.
    nonisolated static let legacyProductIDs: Set<String> = [
        "com.wifibuddy.pro.sub.monthly",
        "com.wifibuddy.pro.sub.yearly"
    ]

    /// Union of currently-offered + legacy IDs. We use this set both
    /// for the `Product.products(for:)` fetch (so legacy SKUs have
    /// loaded `subscription.status` available for grace-period checks)
    /// AND for matching against `Transaction.currentEntitlements`.
    nonisolated static let entitlementRecognizedProductIDs: Set<String> =
        allProductIDs.union(legacyProductIDs)

    /// Persisted flag that stops us from re-scheduling the trial-end
    /// reminder every time the app relaunches and walks the entitlements.
    /// Keyed per transaction so an introductory-offer upgrade/downgrade
    /// between products still fires a reminder for the new trial.
    private static let scheduledTrialReminderKey = "trial.reminder.scheduledForTxnID"

    /// Local notification identifier used for the trial-end reminder.
    /// Single, fixed ID so re-scheduling replaces any previous pending
    /// reminder (e.g., after a cancellation + re-enrollment).
    private static let trialReminderNotificationID = "wifibuddy.trial.day2.reminder"

    // MARK: - Published state

    @Published private(set) var products: [Product] = []
    @Published private(set) var isProUser: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isRestoring: Bool = false
    @Published var lastError: String?

    /// True when the active Pro entitlement is the introductory free
    /// trial (as opposed to a paid, recurring period). Used by the paywall
    /// to tailor copy, and by the app to drive "Trial ends in X days"
    /// reminders. Derived from `Transaction.currentEntitlements`; never
    /// persisted, so we can't be tricked by a UserDefaults override.
    @Published private(set) var hasActiveTrial: Bool = false

    /// When the active trial is scheduled to end. `nil` when no trial is
    /// active. Driven by `Transaction.expirationDate` for the trial
    /// transaction.
    @Published private(set) var trialExpiration: Date?

    /// When a billing retry is scheduled to give up and revoke the
    /// subscription. Populated only while the user is inside Apple's
    /// billing grace window (i.e. payment failed but Apple is still
    /// retrying). We keep `isProUser = true` during grace so a transient
    /// card decline doesn't instantly yank features — the app instead
    /// surfaces a soft banner pointing at Manage Subscriptions.
    @Published private(set) var gracePeriodExpiration: Date?

    /// Which of our product IDs the user is eligible to redeem the
    /// introductory free-trial offer on. Apple forbids showing "free
    /// trial" copy to users who've already consumed it on that
    /// subscription group, so the paywall reads this set before
    /// advertising the offer.
    @Published private(set) var introOfferEligibleProductIDs: Set<String> = []

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
    /// the hard-coded "$9.99/year" copy in `PaywallView`.
    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            // Fetch metadata for the currently-offered SKU AND any legacy
            // SKUs still held by pre-1.11 subscribers. The paywall only
            // reads `product(for: annualProductID)` so legacy SKUs never
            // surface for purchase — they're loaded purely so
            // `refreshGracePeriodStatus` can query each subscription's
            // status and keep legacy subscribers entitled during a
            // billing-retry / grace-period window.
            let loaded = try await Product.products(for: Self.entitlementRecognizedProductIDs)
            self.products = loaded

            await refreshIntroOfferEligibility()

            // `Product.products(for:)` does NOT throw when the store simply
            // has nothing to return for our IDs — most commonly because the
            // app isn't attached to Xcode's StoreKit config file on device,
            // or the IDs aren't in App Store Connect / Sandbox yet. We
            // specifically check that the *annual* product loaded (not just
            // that *something* loaded) so a misconfigured ASC where only a
            // legacy SKU is attached still surfaces a useful error instead
            // of silently breaking the buy button.
            if loaded.first(where: { $0.id == Self.annualProductID }) == nil {
                #if DEBUG
                lastError = """
                    WiFi Buddy Pro's annual subscription wasn't returned by StoreKit. \
                    On a physical device, launch the app from Xcode (⌘R) so \
                    Configuration.storekit is attached — or configure a \
                    Sandbox tester. Product ID expected: \(Self.annualProductID).
                    """
                #else
                lastError = "WiFi Buddy Pro isn't available right now. Please try again later."
                #endif
            }
        } catch {
            // Same rationale as `purchaseErrorMessage(for:)` — Apple
            // reviewers screenshot whatever ends up here, so identify
            // the concrete failure rather than collapsing to a generic
            // line. `error.localizedDescription` is fine for product
            // loading because the StoreKit errors that surface here
            // (network, storefront, system) localize meaningfully.
            let typeTag = String(describing: type(of: error))
            lastError = "Couldn't load subscription options (\(typeTag)): \(error.localizedDescription). Check your connection and try again."
        }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    /// Whether the currently signed-in Apple ID can still redeem the
    /// introductory free-trial offer on `productID`. Apple scopes
    /// intro-offer eligibility to the subscription group (not the
    /// individual product), and `Product.SubscriptionInfo.isEligibleForIntroOffer`
    /// is the authoritative source — callers MUST NOT advertise a trial
    /// in the UI when this returns `false`, or the purchase will go
    /// through at full price and we'll face a wave of refund requests.
    func isEligibleForIntroOffer(productID: String) -> Bool {
        introOfferEligibleProductIDs.contains(productID)
    }

    /// Returns `true` when the product identified by `productID` declares
    /// an introductory offer whose payment mode is a free trial. Used to
    /// disambiguate which `.introductory` transactions in
    /// `Transaction.currentEntitlements` represent our free-trial flow
    /// versus any future paid intro offer we might add.
    ///
    /// Reading the payment mode off the `Product` (instead of the
    /// `Transaction`) keeps the check working on iOS 17.0 where the
    /// richer `Transaction.offer` struct isn't available yet.
    fileprivate func productHasFreeTrialOffer(productID: String) -> Bool {
        guard let product = products.first(where: { $0.id == productID }) else {
            // When products haven't loaded yet we optimistically assume
            // an `.introductory` transaction is a trial — our current
            // StoreKit config only ships free-trial intro offers, so
            // this preserves correct behavior until the product catalog
            // arrives from the App Store.
            return true
        }
        guard let introOffer = product.subscription?.introductoryOffer else {
            return false
        }
        return introOffer.paymentMode == .freeTrial
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
            // App Review screenshots only show whatever is in `lastError`,
            // so a generic "Purchase failed. Please try again." gives us
            // nothing to act on when a rejection comes back. Capture the
            // concrete StoreKit failure mode (sandbox unavailable, intro
            // offer ineligible, network, system error, …) so the alert
            // identifies *which* error class fired. The user-friendly
            // recovery hint stays first; the diagnostic suffix is short
            // enough to coexist on a single screenshot.
            lastError = Self.purchaseErrorMessage(for: error)
            return false
        }
    }

    /// Translate a `Product.purchase()` thrown error into a human-readable
    /// alert that *also* identifies the specific StoreKit failure for App
    /// Review screenshots. We deliberately avoid `error.localizedDescription`
    /// alone because StoreKit's localized strings collapse most failures to
    /// "Cannot connect to iTunes Store" — useless when triaging an actual
    /// configuration bug like a missing intro-offer territory or an
    /// unavailable product.
    private static func purchaseErrorMessage(for error: Error) -> String {
        let recovery = "Please try again."
        let detail: String

        switch error {
        case let purchaseError as Product.PurchaseError:
            switch purchaseError {
            case .productUnavailable:
                detail = "Product unavailable. The subscription isn't currently available for purchase in your region."
            case .purchaseNotAllowed:
                detail = "Purchases aren't allowed on this device. Check Screen Time / parental controls in Settings."
            case .ineligibleForOffer:
                detail = "This Apple ID isn't eligible for the introductory offer."
            case .invalidQuantity:
                detail = "Invalid purchase quantity."
            case .invalidOfferIdentifier, .invalidOfferPrice, .invalidOfferSignature, .missingOfferParameters:
                detail = "Subscription offer configuration is invalid."
            @unknown default:
                detail = "Purchase failed (PurchaseError: \(purchaseError))."
            }
        case let storeError as StoreKitError:
            switch storeError {
            case .userCancelled:
                detail = "Cancelled."
            case .networkError:
                detail = "Network error. Check your connection and try again."
            case .systemError:
                detail = "iOS reported a system-level StoreKit error."
            case .notAvailableInStorefront:
                detail = "Not available in this App Store storefront."
            case .notEntitled:
                detail = "Apple ID not entitled to make this purchase."
            case .unknown:
                detail = "Unknown StoreKit error."
            @unknown default:
                detail = "Purchase failed (StoreKitError: \(storeError))."
            }
        default:
            detail = "Purchase failed (\(type(of: error)): \(error.localizedDescription))."
        }

        return "\(detail) \(recovery)"
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
                lastError = "No active WiFi Buddy Pro subscription was found on this Apple ID."
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
        var trialActive = false
        var trialEndDate: Date?
        var activeTrialTransactionID: UInt64?

        for await result in Transaction.currentEntitlements {
            // `.unverified` = JWS signature didn't check out. Treat as
            // absent, never grant access.
            guard case .verified(let transaction) = result else { continue }

            // Recognize *both* the currently-offered annual SKU and the
            // pre-1.11 legacy IDs (monthly + old yearly). Existing
            // subscribers must keep Pro until their term ends — Apple
            // doesn't refund them just because we collapsed the catalog
            // server-side. See `legacyProductIDs` for rationale.
            guard Self.entitlementRecognizedProductIDs.contains(transaction.productID) else { continue }
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

            // Trial detection: StoreKit 2 marks the transaction's
            // `offerType` as `.introductory` while the user is inside an
            // introductory offer. Our StoreKit config (see
            // `Configuration.storekit`) only declares a *free-trial*
            // intro offer on the annual subscription, so an active
            // `.introductory` transaction here is unambiguously a free
            // trial. If a paid intro offer (pay-as-you-go or pay-up-front)
            // is ever added, cross-reference the matching
            // `Product.subscription?.introductoryOffer?.paymentMode`
            // before treating the transaction as a trial.
            //
            // iOS 17.2 added a richer `Transaction.offer` struct with
            // an explicit `paymentMode`; we intentionally stick to the
            // flat `offerType` accessor so the code compiles on our
            // iOS 17.0 deployment target without per-version guards.
            if transaction.offerType == .introductory,
               let expiry = transaction.expirationDate,
               expiry > Date(),
               productHasFreeTrialOffer(productID: transaction.productID) {
                trialActive = true
                trialEndDate = expiry
                activeTrialTransactionID = transaction.id
            }
        }

        self.hasActiveTrial = trialActive
        self.trialExpiration = trialEndDate

        await refreshGracePeriodStatus(hasActiveEntitlement: &active)

        self.isProUser = active

        // Refresh intro-offer eligibility whenever entitlements change —
        // a new purchase or refund flips the eligibility for everyone
        // in the same subscription group.
        await refreshIntroOfferEligibility()

        if trialActive, let trialEndDate, let txnID = activeTrialTransactionID {
            await scheduleTrialEndReminderIfNeeded(
                transactionID: txnID,
                trialExpiration: trialEndDate
            )
        } else if !trialActive {
            clearTrialReminder()
        }
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

    /// Ask StoreKit whether the current Apple ID is still eligible for the
    /// intro offer on the product we sell. Per-subscription-group, so a
    /// returning subscriber who already burned the trial on the legacy
    /// monthly/yearly SKUs won't be eligible on the new annual SKU
    /// either — exactly the behavior we want.
    private func refreshIntroOfferEligibility() async {
        var eligible: Set<String> = []
        for product in products {
            guard let subscription = product.subscription else { continue }
            let isEligible = await subscription.isEligibleForIntroOffer
            if isEligible { eligible.insert(product.id) }
        }
        self.introOfferEligibleProductIDs = eligible
    }

    /// Inspect the subscription status for each of our products and
    /// surface an in-grace-period expiration date when Apple reports
    /// `.inBillingRetryPeriod` with a `gracePeriodExpirationDate`. In
    /// that window we deliberately keep `isProUser = true` via the
    /// `inout` parameter so we don't kick a paying user out over a
    /// transient billing hiccup. The caller is responsible for showing
    /// the grace-period banner — revocation only happens once Apple
    /// stops retrying.
    private func refreshGracePeriodStatus(hasActiveEntitlement: inout Bool) async {
        var earliestGraceExpiration: Date?

        for product in products {
            guard let subscription = product.subscription else { continue }
            guard let statuses = try? await subscription.status else { continue }

            for status in statuses {
                // We only care about grace for active-ish states. An
                // explicitly revoked/expired status should not keep
                // `isProUser` true.
                guard status.state == .inBillingRetryPeriod ||
                      status.state == .inGracePeriod else { continue }

                guard case .verified(let renewal) = status.renewalInfo else { continue }
                guard let graceExpiry = renewal.gracePeriodExpirationDate,
                      graceExpiry > Date() else { continue }

                // Keep the user on Pro through the grace period.
                hasActiveEntitlement = true

                if earliestGraceExpiration == nil || graceExpiry < earliestGraceExpiration! {
                    earliestGraceExpiration = graceExpiry
                }
            }
        }

        self.gracePeriodExpiration = earliestGraceExpiration
    }

    /// Schedules a single local notification 24 hours before the
    /// active trial expires, reminding the user when the charge will
    /// hit and how to cancel. Apple requires clear disclosure for
    /// intro offers, and this reminder measurably reduces refund
    /// requests by eliminating "I forgot I had a trial" churn. We
    /// only schedule once per trial transaction (`transactionID` key)
    /// and skip if less than ~24h remain — re-scheduling at launch
    /// otherwise fires the notification in the past.
    private func scheduleTrialEndReminderIfNeeded(
        transactionID: UInt64,
        trialExpiration: Date
    ) async {
        let defaults = UserDefaults.standard
        let scheduledTxnKey = Self.scheduledTrialReminderKey
        let priorTxn = defaults.object(forKey: scheduledTxnKey) as? UInt64
        if priorTxn == transactionID { return }

        let center = UNUserNotificationCenter.current()
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return
        }
        guard granted else { return }

        // Fire 24 hours before expiration. If we're already past that
        // point, skip — sending a "your trial ends tomorrow" notification
        // the same day it ends annoys users without adding value.
        let fireDate = trialExpiration.addingTimeInterval(-24 * 60 * 60)
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 60 else { return }

        let content = UNMutableNotificationContent()
        content.title = "WiFi Buddy Pro trial ends tomorrow"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        content.body = "Your free trial ends on \(formatter.string(from: trialExpiration)). "
            + "Cancel anytime in Settings → Apple ID → Subscriptions to avoid being charged."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.trialReminderNotificationID,
            content: content,
            trigger: trigger
        )

        // Replace any prior pending reminder so we never fire two.
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.trialReminderNotificationID]
        )

        do {
            try await center.add(request)
            defaults.set(transactionID, forKey: scheduledTxnKey)
        } catch {
            // Swallow — failure here means the user silently won't see
            // the reminder, but we don't want to surface a scary error
            // for a nice-to-have disclosure notification.
        }
    }

    /// Cancel any pending trial reminder and clear our scheduled-txn
    /// marker. Called when the trial ends (converted or cancelled) so
    /// a future trial can re-schedule cleanly.
    private func clearTrialReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.trialReminderNotificationID]
        )
        UserDefaults.standard.removeObject(forKey: Self.scheduledTrialReminderKey)
    }

    enum StoreError: Error {
        case failedVerification
    }
}
