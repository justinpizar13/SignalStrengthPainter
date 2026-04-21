import SwiftUI

/// Renders a `SurveyInsightsReport` as a stack of themed cards.
///
/// Layout:
///   1. Grade header (big letter + headline + summary)
///   2. Quick-stat grid (4 tiles: coverage %, dead zones, samples, distance)
///   3. Coverage mix bar (stacked green / amber / red ratio with legend)
///   4. Latency range strip (min / median / p95 / max)
///   5. Insight cards (ranked list from the engine)
///
/// Designed to slot into the finished-survey layout in `ContentView` and pick
/// up `@Environment(\.theme)` so it matches the rest of the app's card design.
struct SurveyInsightsView: View {
    @Environment(\.theme) private var theme
    let report: SurveyInsightsReport

    var body: some View {
        VStack(spacing: 14) {
            gradeHeader
            statsGrid
            coverageMix
            latencyRange
            insightCards
        }
    }

    // MARK: - Grade header

    private var gradeHeader: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(report.grade.color.opacity(0.18))
                    Circle()
                        .stroke(report.grade.color.opacity(0.55), lineWidth: 1.5)
                    Text(report.grade.rawValue)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(report.grade.color)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("SURVEY INSIGHTS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                            .tracking(0.6)
                    }
                    Text(report.grade.headline)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Score: \(Int(report.gradeScore.rounded())) / 100")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer(minLength: 0)
            }

            Text(report.grade.summary)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(report.grade.color.opacity(0.35), lineWidth: 1.2)
                )
        )
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        let excellentPct = Int((report.excellentPercentage * 100).rounded())
        let deadZoneCount = report.deadZones.count
        let distance = formatDistance(report.distanceWalkedMeters)
        let samples = "\(report.samplesWithLatency)"

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            statTile(
                icon: "checkmark.seal.fill",
                tint: Color(red: 0.25, green: 0.86, blue: 0.43),
                value: "\(excellentPct)%",
                label: "Excellent coverage"
            )
            statTile(
                icon: "exclamationmark.triangle.fill",
                tint: deadZoneCount == 0
                    ? Color(red: 0.25, green: 0.86, blue: 0.43)
                    : Color(red: 0.98, green: 0.55, blue: 0.22),
                value: "\(deadZoneCount)",
                label: deadZoneCount == 1 ? "Dead zone" : "Dead zones"
            )
            statTile(
                icon: "figure.walk",
                tint: .blue,
                value: distance,
                label: "Walked"
            )
            statTile(
                icon: "mappin.and.ellipse",
                tint: .blue,
                value: samples,
                label: "Samples"
            )
        }
    }

    private func statTile(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Coverage mix bar

    private var coverageMix: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Coverage mix")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(report.samplesWithLatency) samples")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            GeometryReader { geo in
                let total = max(geo.size.width, 1)
                let excellentW = CGFloat(report.excellentPercentage) * total
                let fairW = CGFloat(report.fairPercentage) * total
                let poorW = CGFloat(report.poorPercentage) * total
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(red: 0.25, green: 0.86, blue: 0.43))
                        .frame(width: excellentW)
                    Rectangle()
                        .fill(Color(red: 0.98, green: 0.78, blue: 0.28))
                        .frame(width: fairW)
                    Rectangle()
                        .fill(Color(red: 0.98, green: 0.39, blue: 0.34))
                        .frame(width: poorW)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)

            HStack(spacing: 14) {
                legendDot(
                    color: Color(red: 0.25, green: 0.86, blue: 0.43),
                    label: "Excellent",
                    pct: report.excellentPercentage
                )
                legendDot(
                    color: Color(red: 0.98, green: 0.78, blue: 0.28),
                    label: "Fair",
                    pct: report.fairPercentage
                )
                legendDot(
                    color: Color(red: 0.98, green: 0.39, blue: 0.34),
                    label: "Poor",
                    pct: report.poorPercentage
                )
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    private func legendDot(color: Color, label: String, pct: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Text("\(Int((pct * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.tertiaryText)
        }
    }

    // MARK: - Latency range

    private var latencyRange: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Latency range")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("jitter ±\(Int(report.jitterMs.rounded())) ms")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            HStack(spacing: 10) {
                latencyTile(label: "Best", ms: report.minLatencyMs, tint: Color(red: 0.25, green: 0.86, blue: 0.43))
                latencyTile(label: "Median", ms: report.medianLatencyMs, tint: .blue)
                latencyTile(label: "Worst 5%", ms: report.p95LatencyMs, tint: Color(red: 0.98, green: 0.55, blue: 0.22))
                latencyTile(label: "Worst", ms: report.maxLatencyMs, tint: Color(red: 0.98, green: 0.39, blue: 0.34))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    private func latencyTile(label: String, ms: Double, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(ms.rounded()))")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("ms")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Insight cards

    private var insightCards: some View {
        VStack(spacing: 10) {
            ForEach(report.insights) { insight in
                insightCard(insight)
            }
        }
    }

    private func insightCard(_ insight: SurveyInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(severityTint(insight.severity).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: insight.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(severityTint(insight.severity))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(insight.body)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(severityTint(insight.severity).opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func severityTint(_ severity: SurveyInsight.Severity) -> Color {
        switch severity {
        case .positive: return Color(red: 0.25, green: 0.86, blue: 0.43)
        case .neutral: return .blue
        case .warning: return Color(red: 0.98, green: 0.78, blue: 0.28)
        case .critical: return Color(red: 0.98, green: 0.39, blue: 0.34)
        }
    }

    // MARK: - Helpers

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1 {
            return String(format: "%.1f m", meters)
        }
        if meters < 10 {
            return String(format: "%.1f m", meters)
        }
        return "\(Int(meters.rounded())) m"
    }
}

/// Placeholder shown when the survey was too short to draw conclusions.
struct SurveyInsightsPlaceholder: View {
    @Environment(\.theme) private var theme
    let sampleCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Insights need a longer walk")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
            }
            Text(sampleCount == 0
                 ? "No latency samples were captured. Start a new survey and walk the space for at least 20–30 seconds so we can read the signal at multiple spots."
                 : "Only \(sampleCount) latency sample\(sampleCount == 1 ? "" : "s") were captured — that's not enough to spot dead zones or compare rooms. Try a longer walk, pausing briefly in each area you care about.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }
}
