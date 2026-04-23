import SwiftUI

/// In-app viewer for the bundled legal documents (`PrivacyPolicy.md`
/// and `TermsOfUse.md`). Rendered via `AttributedString`'s built-in
/// Markdown parser so we don't need a third-party Markdown renderer
/// — Apple's stdlib path handles headings, emphasis, links, and list
/// items well enough for straightforward legal prose.
///
/// Apple's guideline 3.1.2 requires a paywall that sells an
/// auto-renewing subscription to link to both a Privacy Policy and a
/// EULA/Terms of Use. We satisfy that requirement by bundling both
/// documents inside the app and presenting them via this view, which
/// means the links work even on a device with no internet connection
/// and there's no external host to keep alive over the life of the
/// app.
///
/// Presented as a sheet via `.sheet(item: $legalDoc)` from the
/// paywall's disclosure block; also reachable from future Settings
/// entries.
struct LegalDocumentView: View {
    enum Kind: String, Identifiable, CaseIterable {
        case privacyPolicy
        case termsOfUse

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .privacyPolicy: return "Privacy Policy"
            case .termsOfUse: return "Terms of Use"
            }
        }

        /// Resource filename (without extension) in the app bundle.
        var resourceName: String {
            switch self {
            case .privacyPolicy: return "PrivacyPolicy"
            case .termsOfUse: return "TermsOfUse"
            }
        }
    }

    let kind: Kind

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: true) {
                if let attributed = loadAttributed() {
                    Text(attributed)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.primaryText)
                        .tint(.blue)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                } else {
                    fallbackMessage
                }
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(kind.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(theme.cardFill)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    /// Load the Markdown source from the main bundle and parse it
    /// into an `AttributedString`. Returns `nil` only if the bundle
    /// is missing the resource — which would be a build-time wiring
    /// bug, surfaced via `fallbackMessage` rather than a silent
    /// empty sheet.
    private func loadAttributed() -> AttributedString? {
        guard
            let url = Bundle.main.url(
                forResource: kind.resourceName,
                withExtension: "md"
            ),
            let data = try? Data(contentsOf: url),
            let raw = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        // `.inlineOnlyPreservingWhitespace` keeps paragraph breaks so
        // the rendered doc reads like a document, not a single run-on
        // paragraph. Headings rendered inline as bold; sufficient for
        // the short legal pages we ship.
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: raw, options: options))
    }

    private var fallbackMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 28))
                .foregroundStyle(theme.tertiaryText)
            Text("Document unavailable")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text("Please contact support@wifibuddy.app for the latest version.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    LegalDocumentView(kind: .privacyPolicy)
        .withAppTheme()
}
