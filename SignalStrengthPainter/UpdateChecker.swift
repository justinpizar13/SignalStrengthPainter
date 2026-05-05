import Foundation
import SwiftUI
import UIKit

/// Polls Apple's iTunes Lookup endpoint on app launch to detect when a
/// newer App Store build is available, and surfaces a small "What's
/// new" banner above the tab content so users can update without
/// hunting for the App Store page themselves.
///
/// Design notes:
/// - HTTPS only (`https://itunes.apple.com/lookup`); the request body
///   is the public bundle identifier, never PII or device state.
/// - The "Update" CTA opens a hardcoded App Store URL — the lookup
///   response includes a `trackViewUrl` we deliberately don't use, so
///   a poisoned response can't redirect users off-platform.
/// - Result is cached for 24h to avoid hammering Apple's endpoint, and
///   the last-seen newer version is persisted so the banner can render
///   instantly on subsequent launches before the live check completes.
/// - Dismissal is per-version (`updateBanner.dismissedVersion`) so a
///   user who taps "Not now" on 1.2 still sees the banner when 1.3
///   ships, but isn't nagged on every launch in between.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var availableVersion: String?
    @Published private(set) var releaseNotes: String?

    private let bundleID: String
    private let appStoreURL = URL(string: "https://apps.apple.com/app/wifi-buddy/id6763663209")!
    private let session: URLSession

    /// Once a day is plenty — App Store Connect approvals are not
    /// minute-fast and a noisier cadence would just hit Apple's lookup
    /// endpoint without changing the user-facing outcome.
    private let checkInterval: TimeInterval = 24 * 60 * 60

    private enum DefaultsKey {
        static let lastCheck = "updateBanner.lastCheckTimestamp"
        static let dismissed = "updateBanner.dismissedVersion"
        static let cachedVersion = "updateBanner.cachedVersion"
        static let cachedNotes = "updateBanner.cachedReleaseNotes"
    }

    init(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.wifibuddy.app",
        session: URLSession = .shared
    ) {
        self.bundleID = bundleID
        self.session = session
        // Hydrate from the last-seen result so the banner appears
        // instantly on launch for users who saw it previously — the
        // live check refreshes or clears it a moment later.
        let defaults = UserDefaults.standard
        if let cached = defaults.string(forKey: DefaultsKey.cachedVersion),
           !cached.isEmpty,
           Self.isVersion(cached, newerThan: currentVersion) {
            availableVersion = cached
            releaseNotes = defaults.string(forKey: DefaultsKey.cachedNotes)
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// `true` when an update was found and the user has not already
    /// dismissed it for that exact version. Drives banner visibility.
    var shouldShowUpdateBanner: Bool {
        guard let v = availableVersion else { return false }
        let dismissed = UserDefaults.standard.string(forKey: DefaultsKey.dismissed) ?? ""
        return v != dismissed
    }

    /// Banner-friendly first paragraph of release notes, trimmed and
    /// capped so a long "What's New" block doesn't blow out the
    /// safe-area inset.
    var releaseNotesSnippet: String? {
        guard let notes = releaseNotes else { return nil }
        let firstLine = notes
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? notes
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let limit = 160
        if trimmed.count > limit {
            let cutoff = trimmed.index(trimmed.startIndex, offsetBy: limit)
            return String(trimmed[..<cutoff]).trimmingCharacters(in: .whitespaces) + "…"
        }
        return trimmed
    }

    /// Hits the iTunes Lookup endpoint and updates state if a newer
    /// App Store version is available. Silent on failure — a flaky
    /// network shouldn't surface an error banner nobody asked for.
    func checkForUpdate(force: Bool = false) async {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: DefaultsKey.lastCheck)
        if !force && (now - last) < checkInterval && availableVersion != nil {
            return
        }

        guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return }
        components.queryItems = [URLQueryItem(name: "bundleId", value: bundleID)]
        guard let url = components.url, url.scheme == "https" else { return }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let parsed = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let entry = parsed.results.first else { return }

            defaults.set(now, forKey: DefaultsKey.lastCheck)

            let trimmedNotes = entry.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isVersion(entry.version, newerThan: currentVersion) {
                availableVersion = entry.version
                releaseNotes = trimmedNotes
                defaults.set(entry.version, forKey: DefaultsKey.cachedVersion)
                defaults.set(trimmedNotes ?? "", forKey: DefaultsKey.cachedNotes)
            } else {
                availableVersion = nil
                releaseNotes = nil
                defaults.removeObject(forKey: DefaultsKey.cachedVersion)
                defaults.removeObject(forKey: DefaultsKey.cachedNotes)
            }
        } catch {
            // Network flakes are intentionally swallowed; the banner is
            // a "nice-to-have" prompt, not a critical alert.
        }
    }

    /// Suppresses the banner for the currently advertised version.
    /// Called from the banner's "Not now" affordance.
    func dismissUpdate() {
        if let v = availableVersion {
            UserDefaults.standard.set(v, forKey: DefaultsKey.dismissed)
        }
        availableVersion = nil
        releaseNotes = nil
    }

    /// Opens the canonical App Store page so the user can tap Update.
    func openAppStore() {
        UIApplication.shared.open(appStoreURL)
    }

    /// Pure dotted-decimal comparison (e.g. "1.10" > "1.9", "1.1" ==
    /// "1.1.0"). Returns `false` for any non-numeric component so an
    /// unparseable string from a poisoned response can't trick us into
    /// nagging the user with a bogus prompt.
    static func isVersion(_ candidate: String, newerThan baseline: String) -> Bool {
        let candParts = candidate.split(separator: ".").map { Int($0) }
        let baseParts = baseline.split(separator: ".").map { Int($0) }
        if candParts.contains(nil) || baseParts.contains(nil) { return false }
        let cand = candParts.compactMap { $0 }
        let base = baseParts.compactMap { $0 }
        let length = max(cand.count, base.count)
        for i in 0..<length {
            let c = i < cand.count ? cand[i] : 0
            let b = i < base.count ? base[i] : 0
            if c > b { return true }
            if c < b { return false }
        }
        return false
    }

    private struct LookupResponse: Decodable {
        let resultCount: Int
        let results: [Entry]
        struct Entry: Decodable {
            let version: String
            let releaseNotes: String?
        }
    }
}
