import SwiftUI

/// User-selectable floor-plan backdrop drawn under the survey heatmap.
///
/// The survey canvas supports three sample plans plus a blank option. The
/// intent is to give the user a shape roughly matching their space so the
/// heat blobs land on recognizable rooms instead of an abstract grid.
///
/// Rooms are described in **normalized** coordinates (each room's `normalizedRect`
/// lives in `[0, 1]²`) so the same template renders correctly at any canvas size.
/// `SignalCanvasView` scales the rects into the actual draw rect at render time.
enum FloorPlanTemplate: String, CaseIterable, Identifiable, Codable {
    case blank
    case apartmentMain
    case upstairs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .apartmentMain: return "Apartment"
        case .upstairs: return "Upstairs"
        }
    }

    /// Short human-facing description shown in the picker subtitle.
    var summary: String {
        switch self {
        case .blank:
            return "Plain canvas — no walls drawn."
        case .apartmentMain:
            return "Living room, kitchen, dining, bedrooms, bath."
        case .upstairs:
            return "Master, 2 bedrooms, 2 baths, hallway."
        }
    }

    /// SF Symbol rendered in the picker chip.
    var iconName: String {
        switch self {
        case .blank: return "square.dashed"
        case .apartmentMain: return "sofa.fill"
        case .upstairs: return "bed.double.fill"
        }
    }

    /// Room list for this template. Empty for `.blank`.
    var rooms: [FloorPlanRoom] {
        switch self {
        case .blank:
            return []

        case .apartmentMain:
            // Layout (roughly 1–2 bedroom apartment main floor):
            //
            // ┌──────────────────┬────────────┐
            // │                  │  Kitchen   │
            // │   Living Room    ├────────────┤
            // │                  │  Dining    │
            // ├──────────┬───────┴───┬────────┤
            // │Bedroom 1 │ Bedroom 2 │  Bath  │
            // └──────────┴───────────┴────────┘
            return [
                FloorPlanRoom(
                    name: "Living Room",
                    normalizedRect: CGRect(x: 0.02, y: 0.04, width: 0.56, height: 0.52),
                    tint: .living
                ),
                FloorPlanRoom(
                    name: "Kitchen",
                    normalizedRect: CGRect(x: 0.60, y: 0.04, width: 0.38, height: 0.26),
                    tint: .kitchen
                ),
                FloorPlanRoom(
                    name: "Dining",
                    normalizedRect: CGRect(x: 0.60, y: 0.32, width: 0.38, height: 0.24),
                    tint: .dining
                ),
                FloorPlanRoom(
                    name: "Bedroom 1",
                    normalizedRect: CGRect(x: 0.02, y: 0.60, width: 0.30, height: 0.36),
                    tint: .bedroom
                ),
                FloorPlanRoom(
                    name: "Bedroom 2",
                    normalizedRect: CGRect(x: 0.34, y: 0.60, width: 0.38, height: 0.36),
                    tint: .bedroom
                ),
                FloorPlanRoom(
                    name: "Bath",
                    normalizedRect: CGRect(x: 0.74, y: 0.60, width: 0.24, height: 0.36),
                    tint: .bath
                ),
            ]

        case .upstairs:
            // Layout (upstairs of a house):
            //
            // ┌───────────────┬─────────┬──────────────┐
            // │               │         │              │
            // │    Master     │ Bath 1  │   Bedroom 2  │
            // │    Bedroom    │         │              │
            // ├───────────────┴─────────┴──────────────┤
            // │                Hallway                  │
            // ├───────────────┬─────────┬──────────────┤
            // │   Linen       │         │              │
            // │   Closet      │ Bath 2  │   Bedroom 3  │
            // └───────────────┴─────────┴──────────────┘
            return [
                FloorPlanRoom(
                    name: "Master",
                    normalizedRect: CGRect(x: 0.02, y: 0.04, width: 0.42, height: 0.40),
                    tint: .bedroom
                ),
                FloorPlanRoom(
                    name: "Bath 1",
                    normalizedRect: CGRect(x: 0.46, y: 0.04, width: 0.18, height: 0.40),
                    tint: .bath
                ),
                FloorPlanRoom(
                    name: "Bedroom 2",
                    normalizedRect: CGRect(x: 0.66, y: 0.04, width: 0.32, height: 0.40),
                    tint: .bedroom
                ),
                FloorPlanRoom(
                    name: "Hallway",
                    normalizedRect: CGRect(x: 0.02, y: 0.46, width: 0.96, height: 0.10),
                    tint: .hallway
                ),
                FloorPlanRoom(
                    name: "Closet",
                    normalizedRect: CGRect(x: 0.02, y: 0.58, width: 0.42, height: 0.38),
                    tint: .storage
                ),
                FloorPlanRoom(
                    name: "Bath 2",
                    normalizedRect: CGRect(x: 0.46, y: 0.58, width: 0.18, height: 0.38),
                    tint: .bath
                ),
                FloorPlanRoom(
                    name: "Bedroom 3",
                    normalizedRect: CGRect(x: 0.66, y: 0.58, width: 0.32, height: 0.38),
                    tint: .bedroom
                ),
            ]
        }
    }
}

struct FloorPlanRoom {
    let name: String
    let normalizedRect: CGRect
    let tint: FloorPlanRoomTint
}

enum FloorPlanRoomTint {
    case living
    case bedroom
    case kitchen
    case bath
    case dining
    case hallway
    case storage

    /// Earthy room-fill color matching the existing canvas palette. Each tint
    /// is a muted solid so heat-map overlays stay readable on top.
    var color: Color {
        switch self {
        case .living:  return Color(red: 0.56, green: 0.42, blue: 0.25)
        case .bedroom: return Color(red: 0.38, green: 0.41, blue: 0.33)
        case .kitchen: return Color(red: 0.47, green: 0.43, blue: 0.35)
        case .bath:    return Color(red: 0.36, green: 0.46, blue: 0.55)
        case .dining:  return Color(red: 0.42, green: 0.39, blue: 0.28)
        case .hallway: return Color(red: 0.34, green: 0.33, blue: 0.31)
        case .storage: return Color(red: 0.38, green: 0.36, blue: 0.30)
        }
    }
}
