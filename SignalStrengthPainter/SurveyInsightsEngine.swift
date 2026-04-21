import CoreGraphics
import Foundation
import SwiftUI

/// A single high-signal observation for the user, derived from a completed survey.
///
/// The engine emits a small ranked list of these so the UI can render them as
/// cards with icons, bodies, and severity tints. The goal is "tell me the one
/// thing I actually need to know," not raw statistics.
struct SurveyInsight: Identifiable {
    enum Severity {
        case positive   // green
        case neutral    // blue / themed
        case warning    // amber
        case critical   // red
    }

    let id = UUID()
    let icon: String
    let title: String
    let body: String
    let severity: Severity
}

/// A dead zone is a contiguous region (cluster) of poor-quality samples.
/// Centroid is in the same map-point coordinate space as `TrailPoint.position`.
struct DeadZone: Identifiable {
    let id = UUID()
    let centroid: CGPoint
    let sampleCount: Int
    let averageLatencyMs: Double
    let worstLatencyMs: Double
    /// Approximate radius in map points (max distance from centroid to a member).
    let radiusPoints: CGFloat
}

/// Overall summary of the walk. Used for the big "grade card" at the top of
/// the review screen.
enum SurveyGrade: String {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case f = "F"

    var headline: String {
        switch self {
        case .a: return "Excellent coverage"
        case .b: return "Solid coverage with minor weak spots"
        case .c: return "Mixed coverage — room to improve"
        case .d: return "Weak coverage across this space"
        case .f: return "Very poor coverage — action needed"
        }
    }

    var summary: String {
        switch self {
        case .a:
            return "Most of the space you walked has low-latency, responsive Wi-Fi — strong enough for gaming, 4K streaming, and video calls."
        case .b:
            return "The bulk of this space is healthy, but a few spots dip into higher latency. Small placement tweaks can lift you to an A."
        case .c:
            return "Parts of this space work well for browsing, but you'll feel the drops during calls, gaming, or streaming. A repositioning or mesh hop would help."
        case .d:
            return "A large portion of this space is struggling. Your router is likely too far, blocked, or overloaded for this area."
        case .f:
            return "Almost nothing in this space is usable as-is. You likely need a mesh node, range extender, or to move the router closer."
        }
    }

    var color: Color {
        switch self {
        case .a: return Color(red: 0.25, green: 0.86, blue: 0.43)
        case .b: return Color(red: 0.40, green: 0.80, blue: 0.55)
        case .c: return Color(red: 0.98, green: 0.78, blue: 0.28)
        case .d: return Color(red: 0.98, green: 0.55, blue: 0.22)
        case .f: return Color(red: 0.98, green: 0.39, blue: 0.34)
        }
    }
}

/// The full report handed to `SurveyInsightsView` for rendering.
///
/// Every numeric field here has been sanity-checked for empty/short walks by
/// `SurveyInsightsEngine.generate(...)`. If a report is returned, it's safe to
/// render; if the walk was too short to draw real conclusions, `generate`
/// returns `nil` and the UI shows a "walk more" placeholder instead.
struct SurveyInsightsReport {
    let grade: SurveyGrade
    let gradeScore: Double              // 0...100
    let totalSamples: Int
    let samplesWithLatency: Int
    let distanceWalkedMeters: Double
    let durationSeconds: Double

    let excellentPercentage: Double     // 0...1
    let fairPercentage: Double          // 0...1
    let poorPercentage: Double          // 0...1

    let medianLatencyMs: Double
    let p95LatencyMs: Double
    let meanLatencyMs: Double
    let minLatencyMs: Double
    let maxLatencyMs: Double
    let jitterMs: Double                // mean absolute consecutive delta

    let deadZones: [DeadZone]
    let bestSpot: CGPoint?
    let worstSpot: CGPoint?

    /// `+1` = latency strictly worsens the further you walk from the starting spot.
    /// `-1` = latency strictly improves. `~0` = no relationship.
    let routerProximityCorrelation: Double

    /// Ordered highest-value first. UI should render top N as cards.
    let insights: [SurveyInsight]
}

enum SurveyInsightsEngine {

    /// Minimum samples with latency data before we're willing to draw conclusions.
    /// Below this the walk is too short to say anything meaningful and `generate`
    /// returns `nil`, so the UI can show an "keep walking" placeholder instead of
    /// lying about coverage based on 3 pings.
    static let minimumSamplesForReport = 8

    /// Produce the insights report for a finished survey, or `nil` if the walk
    /// was too short to analyse.
    ///
    /// - Parameters:
    ///   - trail: Ordered trail points, oldest first.
    ///   - pointsPerMeter: Map-units-per-meter constant used by the view model,
    ///     so the engine can convert path lengths and cluster thresholds into
    ///     real-world meters.
    static func generate(trail: [TrailPoint], pointsPerMeter: Double) -> SurveyInsightsReport? {
        let rated = trail.filter { $0.latencyMs != nil }
        guard rated.count >= minimumSamplesForReport else { return nil }

        let latencies = rated.compactMap { $0.latencyMs }
        let sortedLatencies = latencies.sorted()

        let excellentCount = rated.filter { $0.quality == .excellent }.count
        let fairCount = rated.filter { $0.quality == .fair }.count
        let poorCount = rated.filter { $0.quality == .poor }.count
        let total = Double(rated.count)
        let excellentPct = Double(excellentCount) / total
        let fairPct = Double(fairCount) / total
        let poorPct = Double(poorCount) / total

        let median = percentile(sortedLatencies, p: 0.5)
        let p95 = percentile(sortedLatencies, p: 0.95)
        let mean = latencies.reduce(0, +) / total
        let minLatency = sortedLatencies.first ?? 0
        let maxLatency = sortedLatencies.last ?? 0

        // Jitter = mean absolute difference between consecutive samples (in time order).
        // Uses the original order, not the sorted one, because temporal jitter is the signal.
        let jitter = meanAbsoluteDelta(latencies)

        let distance = walkedDistancePoints(trail) / CGFloat(pointsPerMeter)
        let duration: Double
        if let first = trail.first?.timestamp, let last = trail.last?.timestamp {
            duration = max(0, last.timeIntervalSince(first))
        } else {
            duration = 0
        }

        let deadZones = clusterDeadZones(
            rated.filter { $0.quality == .poor },
            thresholdPoints: CGFloat(pointsPerMeter * 1.8)
        )

        let bestSpot = rated.min(by: { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) })?.position
        let worstSpot = rated.max(by: { ($0.latencyMs ?? -.infinity) < ($1.latencyMs ?? -.infinity) })?.position

        let proximityCorrelation = routerProximityCorrelation(rated: rated)

        let (grade, score) = computeGrade(
            excellentPct: excellentPct,
            poorPct: poorPct,
            median: median,
            p95: p95
        )

        let insights = buildInsights(
            grade: grade,
            excellentPct: excellentPct,
            fairPct: fairPct,
            poorPct: poorPct,
            median: median,
            p95: p95,
            mean: mean,
            jitter: jitter,
            deadZones: deadZones,
            proximityCorrelation: proximityCorrelation,
            distanceMeters: distance,
            sampleCount: rated.count
        )

        return SurveyInsightsReport(
            grade: grade,
            gradeScore: score,
            totalSamples: trail.count,
            samplesWithLatency: rated.count,
            distanceWalkedMeters: distance,
            durationSeconds: duration,
            excellentPercentage: excellentPct,
            fairPercentage: fairPct,
            poorPercentage: poorPct,
            medianLatencyMs: median,
            p95LatencyMs: p95,
            meanLatencyMs: mean,
            minLatencyMs: minLatency,
            maxLatencyMs: maxLatency,
            jitterMs: jitter,
            deadZones: deadZones,
            bestSpot: bestSpot,
            worstSpot: worstSpot,
            routerProximityCorrelation: proximityCorrelation,
            insights: insights
        )
    }

    // MARK: - Stats primitives

    private static func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clampedP = max(0, min(1, p))
        let idx = Int((clampedP * Double(sorted.count - 1)).rounded())
        return sorted[idx]
    }

    private static func meanAbsoluteDelta(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<values.count {
            total += abs(values[i] - values[i - 1])
        }
        return total / Double(values.count - 1)
    }

    private static func walkedDistancePoints(_ trail: [TrailPoint]) -> CGFloat {
        guard trail.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<trail.count {
            let dx = trail[i].position.x - trail[i - 1].position.x
            let dy = trail[i].position.y - trail[i - 1].position.y
            total += hypot(dx, dy)
        }
        return total
    }

    // MARK: - Grade

    /// Blend coverage mix and absolute latency into a 0-100 score then bucket.
    /// 60% of the weight is the mix of quality buckets (favoring excellent,
    /// penalizing poor); 40% is absolute median latency. p95 is used as a
    /// secondary penalty so a walk with a single 500 ms spike still loses points.
    private static func computeGrade(
        excellentPct: Double,
        poorPct: Double,
        median: Double,
        p95: Double
    ) -> (SurveyGrade, Double) {
        let coverageScore = 100.0 * (excellentPct - 0.5 * poorPct).clamped(to: 0...1)

        let latencyScore: Double
        if median <= 30 { latencyScore = 100 }
        else if median >= 200 { latencyScore = 0 }
        else { latencyScore = 100 * (1 - (median - 30) / 170) }

        let p95Penalty = p95 > 200 ? 10.0 : 0.0

        let rawScore = (coverageScore * 0.6 + latencyScore * 0.4) - p95Penalty
        let score = max(0, min(100, rawScore))

        let grade: SurveyGrade
        switch score {
        case 85...: grade = .a
        case 70..<85: grade = .b
        case 55..<70: grade = .c
        case 40..<55: grade = .d
        default: grade = .f
        }
        return (grade, score)
    }

    // MARK: - Dead zone clustering

    /// Single-link spatial clustering: two poor points merge into the same zone
    /// if any pair across the two groups is within `thresholdPoints` of each other.
    /// Good enough for the handful of points in a walk without needing full DBSCAN.
    private static func clusterDeadZones(
        _ poorPoints: [TrailPoint],
        thresholdPoints: CGFloat
    ) -> [DeadZone] {
        guard !poorPoints.isEmpty else { return [] }

        var clusters: [[TrailPoint]] = []
        for point in poorPoints {
            var mergedIntoCluster = false
            for idx in clusters.indices {
                if clusters[idx].contains(where: { distance($0.position, point.position) <= thresholdPoints }) {
                    clusters[idx].append(point)
                    mergedIntoCluster = true
                    break
                }
            }
            if !mergedIntoCluster {
                clusters.append([point])
            }
        }

        // Second pass to merge clusters that became reachable through newly added points.
        var changed = true
        while changed {
            changed = false
            outer: for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    if clustersAreNearby(clusters[i], clusters[j], threshold: thresholdPoints) {
                        clusters[i].append(contentsOf: clusters[j])
                        clusters.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }

        return clusters
            .filter { $0.count >= 2 }   // ignore single isolated blips
            .map { members -> DeadZone in
                let cx = members.map { $0.position.x }.reduce(0, +) / CGFloat(members.count)
                let cy = members.map { $0.position.y }.reduce(0, +) / CGFloat(members.count)
                let centroid = CGPoint(x: cx, y: cy)
                let latencies = members.compactMap { $0.latencyMs }
                let avg = latencies.reduce(0, +) / Double(max(latencies.count, 1))
                let worst = latencies.max() ?? 0
                let radius = members.map { distance($0.position, centroid) }.max() ?? 0
                return DeadZone(
                    centroid: centroid,
                    sampleCount: members.count,
                    averageLatencyMs: avg,
                    worstLatencyMs: worst,
                    radiusPoints: radius
                )
            }
            .sorted { $0.sampleCount > $1.sampleCount }
    }

    private static func clustersAreNearby(
        _ a: [TrailPoint],
        _ b: [TrailPoint],
        threshold: CGFloat
    ) -> Bool {
        for pointA in a {
            for pointB in b where distance(pointA.position, pointB.position) <= threshold {
                return true
            }
        }
        return false
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Router proximity hint

    /// Pearson correlation between distance-from-start and latency.
    /// Used as a heuristic to guess router direction:
    /// - strongly positive  → signal worsens with distance → router near start
    /// - strongly negative  → signal improves with distance → walking toward router
    /// - near zero          → signal is uniform, router direction inconclusive
    private static func routerProximityCorrelation(rated: [TrailPoint]) -> Double {
        guard let start = rated.first?.position, rated.count >= 4 else { return 0 }
        let distances = rated.map { Double(distance($0.position, start)) }
        let latencies = rated.compactMap { $0.latencyMs }
        guard distances.count == latencies.count else { return 0 }

        let meanX = distances.reduce(0, +) / Double(distances.count)
        let meanY = latencies.reduce(0, +) / Double(latencies.count)
        var covariance = 0.0
        var varX = 0.0
        var varY = 0.0
        for i in 0..<distances.count {
            let dx = distances[i] - meanX
            let dy = latencies[i] - meanY
            covariance += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        guard varX > 0, varY > 0 else { return 0 }
        let r = covariance / sqrt(varX * varY)
        return max(-1, min(1, r))
    }

    // MARK: - Insight synthesis

    private static func buildInsights(
        grade: SurveyGrade,
        excellentPct: Double,
        fairPct: Double,
        poorPct: Double,
        median: Double,
        p95: Double,
        mean: Double,
        jitter: Double,
        deadZones: [DeadZone],
        proximityCorrelation: Double,
        distanceMeters: Double,
        sampleCount: Int
    ) -> [SurveyInsight] {
        var insights: [SurveyInsight] = []

        // 1) Coverage / grade summary is always first.
        insights.append(coverageInsight(
            grade: grade,
            excellentPct: excellentPct,
            fairPct: fairPct,
            poorPct: poorPct
        ))

        // 2) Dead zones: the single most actionable finding for a Wi-Fi survey.
        if !deadZones.isEmpty {
            insights.append(deadZonesInsight(deadZones))
        }

        // 3) Latency picture — mean / p95 tells the user how the network
        //    actually *feels*, not just the best-case.
        insights.append(latencyProfileInsight(median: median, p95: p95, mean: mean))

        // 4) Stability: high jitter hurts calls / games even when the mean is OK.
        if let stability = stabilityInsight(jitter: jitter, median: median) {
            insights.append(stability)
        }

        // 5) Router-direction hint: compelling when the correlation is strong.
        if let hint = routerDirectionInsight(correlation: proximityCorrelation, distanceMeters: distanceMeters) {
            insights.append(hint)
        }

        // 6) Closing recommendation — always present, tailored to grade +
        //    whether dead zones exist.
        insights.append(recommendationInsight(
            grade: grade,
            deadZonesCount: deadZones.count,
            poorPct: poorPct,
            jitter: jitter,
            median: median
        ))

        return insights
    }

    private static func coverageInsight(
        grade: SurveyGrade,
        excellentPct: Double,
        fairPct: Double,
        poorPct: Double
    ) -> SurveyInsight {
        let pctExcellent = Int((excellentPct * 100).rounded())
        let pctFair = Int((fairPct * 100).rounded())
        let pctPoor = Int((poorPct * 100).rounded())

        let severity: SurveyInsight.Severity
        switch grade {
        case .a, .b: severity = .positive
        case .c: severity = .neutral
        case .d: severity = .warning
        case .f: severity = .critical
        }

        let body: String
        if excellentPct >= 0.85 {
            body = "\(pctExcellent)% of the area you walked is great for streaming, calls, and gaming. Only \(pctPoor)% dipped into weak territory."
        } else if poorPct >= 0.4 {
            body = "\(pctPoor)% of your walked area is struggling, \(pctFair)% is borderline, and only \(pctExcellent)% is reliably fast."
        } else {
            body = "\(pctExcellent)% is great, \(pctFair)% is okay for browsing, and \(pctPoor)% is weak. The mix is typical of a single-router home with some coverage gaps."
        }

        return SurveyInsight(
            icon: "chart.pie.fill",
            title: "Coverage breakdown",
            body: body,
            severity: severity
        )
    }

    private static func deadZonesInsight(_ zones: [DeadZone]) -> SurveyInsight {
        let worst = zones[0]
        let count = zones.count

        if count == 1 {
            let body = "Found 1 dead zone with \(worst.sampleCount) weak samples, averaging \(Int(worst.averageLatencyMs)) ms (peaked at \(Int(worst.worstLatencyMs)) ms). Check the map — that spot is likely behind a wall, appliance, or simply too far from your router."
            return SurveyInsight(
                icon: "exclamationmark.triangle.fill",
                title: "1 dead zone detected",
                body: body,
                severity: .warning
            )
        }

        let body = "Found \(count) dead zones across your walk. The biggest has \(worst.sampleCount) weak samples averaging \(Int(worst.averageLatencyMs)) ms. Multiple dead zones usually mean a single router can't reach the whole space — a mesh node or repositioning could close the gaps."
        return SurveyInsight(
            icon: "exclamationmark.triangle.fill",
            title: "\(count) dead zones detected",
            body: body,
            severity: .critical
        )
    }

    private static func latencyProfileInsight(median: Double, p95: Double, mean: Double) -> SurveyInsight {
        let medianInt = Int(median.rounded())
        let p95Int = Int(p95.rounded())
        let meanInt = Int(mean.rounded())

        // p95 flags worst-case pain even when the median looks fine.
        if p95 > 200 && median <= 80 {
            return SurveyInsight(
                icon: "waveform.path.ecg",
                title: "Occasional spikes hurt the experience",
                body: "Your typical response is a healthy \(medianInt) ms (avg \(meanInt) ms), but the worst 5% of spots hit \(p95Int)+ ms. Those spikes are what cause dropped video calls, game lag, and stuttering — usually concentrated in one or two rooms.",
                severity: .warning
            )
        }

        if median <= 50 {
            return SurveyInsight(
                icon: "waveform.path.ecg",
                title: "Latency is responsive overall",
                body: "Median latency is \(medianInt) ms and the average is \(meanInt) ms — well inside the range where video calls, gaming, and 4K streaming feel snappy. Worst 5% was \(p95Int) ms.",
                severity: .positive
            )
        }

        if median <= 150 {
            return SurveyInsight(
                icon: "waveform.path.ecg",
                title: "Latency is usable but sluggish",
                body: "Median latency is \(medianInt) ms (avg \(meanInt) ms, worst 5% \(p95Int) ms). That's fine for browsing and buffered video, but calls and gaming will feel delayed. Moving closer to the router usually fixes this.",
                severity: .warning
            )
        }

        return SurveyInsight(
            icon: "waveform.path.ecg",
            title: "Latency is high across the walk",
            body: "Median latency is \(medianInt) ms (avg \(meanInt) ms, worst 5% \(p95Int) ms). Page loads will feel slow and real-time apps will stutter. This usually points to distance from the router, interference, or a congested network.",
            severity: .critical
        )
    }

    private static func stabilityInsight(jitter: Double, median: Double) -> SurveyInsight? {
        // Only surface jitter when it's actually large relative to the median,
        // so we don't scold the user over a 3 ms wobble on a 25 ms baseline.
        guard jitter >= 20, median > 0, jitter / max(median, 1) >= 0.5 else { return nil }

        let jitterInt = Int(jitter.rounded())
        if jitter / max(median, 1) >= 1.0 {
            return SurveyInsight(
                icon: "bolt.horizontal.circle",
                title: "Connection is unstable",
                body: "Latency jumps by \(jitterInt) ms between nearby spots — almost as big as the median itself. That kind of variability usually means interference (microwaves, Bluetooth, a neighbor's router on the same channel) or an overloaded 2.4 GHz band.",
                severity: .critical
            )
        }

        return SurveyInsight(
            icon: "bolt.horizontal.circle",
            title: "Connection wobbles as you move",
            body: "Latency shifts by about \(jitterInt) ms between samples. A little jitter is normal, but this much means small movements change your signal noticeably — likely a channel or obstacle issue rather than pure distance.",
            severity: .warning
        )
    }

    private static func routerDirectionInsight(correlation r: Double, distanceMeters: Double) -> SurveyInsight? {
        guard distanceMeters >= 3.0 else { return nil } // too short to infer direction
        guard abs(r) >= 0.35 else { return nil }        // too weak a signal to claim

        if r >= 0.35 {
            let percent = Int((r * 100).rounded())
            return SurveyInsight(
                icon: "location.north.line.fill",
                title: "Router is likely near your starting spot",
                body: "Signal got weaker the further you walked (\(percent)% correlation between distance and latency). If your router isn't near where you started, that's a strong hint the first spots are getting line-of-sight and the far spots are blocked by walls or floors.",
                severity: .neutral
            )
        }

        let percent = Int((-r * 100).rounded())
        return SurveyInsight(
            icon: "location.north.line.fill",
            title: "You walked toward a stronger signal",
            body: "Latency actually improved as you walked (\(percent)% correlation). If your router is near where you finished, that matches — the starting spots were the furthest from it.",
            severity: .neutral
        )
    }

    private static func recommendationInsight(
        grade: SurveyGrade,
        deadZonesCount: Int,
        poorPct: Double,
        jitter: Double,
        median: Double
    ) -> SurveyInsight {
        var actions: [String] = []

        if deadZonesCount >= 2 || poorPct >= 0.3 {
            actions.append("Consider a mesh system or a second access point so the far rooms get a direct signal instead of relying on walls.")
        } else if deadZonesCount == 1 {
            actions.append("Try moving your router a few feet toward the dead zone, or raise it up — most routers cover a dome, not a sphere.")
        }

        if jitter / max(median, 1) >= 0.5 && jitter >= 20 {
            actions.append("Log into your router and switch to a less-crowded 5 GHz channel. The Devices tab can show you who's online while you test.")
        }

        if median > 150 {
            actions.append("If you're on 2.4 GHz, switch this device to the 5 GHz network — it's almost always faster when you're within a few rooms of the router.")
        }

        if deadZonesCount == 0 && poorPct < 0.1 && grade == .a {
            actions.append("Coverage is already great here. Run another survey in rooms you didn't walk today to confirm the whole house is this healthy.")
        }

        if actions.isEmpty {
            actions.append("Walk the rooms you care most about (bedroom, office, living room) to confirm coverage where it matters most.")
        }

        let joined = actions.map { "• \($0)" }.joined(separator: "\n")
        return SurveyInsight(
            icon: "lightbulb.fill",
            title: "What to do next",
            body: joined,
            severity: .neutral
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
