import CoreGraphics
import Foundation
import SwiftUI

enum LatencyQuality: String {
    case excellent
    case fair
    case poor

    var color: Color {
        switch self {
        case .excellent:
            return Color(red: 0.25, green: 0.86, blue: 0.43)
        case .fair:
            return Color(red: 0.98, green: 0.78, blue: 0.28)
        case .poor:
            return Color(red: 0.98, green: 0.39, blue: 0.34)
        }
    }

    var description: String {
        switch self {
        case .excellent:
            return "Excellent for Gaming/Video"
        case .fair:
            return "Web Browsing Only"
        case .poor:
            return "Dead Zone"
        }
    }
}

struct TrailPoint: Identifiable {
    let id = UUID()
    let position: CGPoint
    let latencyMs: Double?
    let timestamp: Date

    init(position: CGPoint, latencyMs: Double?, timestamp: Date = Date()) {
        self.position = position
        self.latencyMs = latencyMs
        self.timestamp = timestamp
    }

    var normalizedSignal: Double {
        guard let latencyMs else { return 0 }
        if latencyMs <= 35 { return 1.0 }
        if latencyMs >= 220 { return 0.0 }
        return 1.0 - ((latencyMs - 35) / (220 - 35))
    }

    var quality: LatencyQuality {
        guard let latencyMs else {
            return .poor
        }
        if latencyMs < 50 {
            return .excellent
        } else if latencyMs <= 150 {
            return .fair
        }
        return .poor
    }

    var heatColor: Color {
        let value = normalizedSignal

        if value < 0.5 {
            let fraction = value / 0.5
            return Color(
                red: 1.0,
                green: 0.35 + (0.45 * fraction),
                blue: 0.28 + (0.12 * fraction)
            )
        }

        let fraction = (value - 0.5) / 0.5
        return Color(
            red: 1.0 - (0.75 * fraction),
            green: 0.8 + (0.12 * fraction),
            blue: 0.4 - (0.1 * fraction)
        )
    }
}
