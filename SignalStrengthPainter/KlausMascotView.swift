import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// SwiftUI view that renders the Klaus mascot animation from one of the
/// `KlausMascot*` data assets (transparent animated GIFs shipped in
/// `Assets.xcassets`).
///
/// Two variants exist, selected via `DisplayMode`:
/// - `.full` loads `KlausMascot` — the full-body (head-to-feet) animated
///   GIF, including Klaus's idle + jump animation. Used in the assistant
///   sheet header where there's room for him to bounce.
/// - `.portrait` loads `KlausMascotHead` — a face-aligned head crop where
///   each frame has been offset so Klaus's face stays in the same spot
///   across the animation (no body bounce). Used in small circular
///   avatars so the user always sees his face in the circle.
///
/// The GIF is loaded with `ImageIO`, decoded into a frame list with
/// per-frame delays, and played through a `UIImageView` wrapped in a
/// `UIViewRepresentable`. Using `UIImageView.animationImages` rather than
/// SwiftUI's `Image` is what actually animates the sequence — plain
/// `Image` does not play animated GIFs.
///
/// Pixel-art crispness is preserved by forcing nearest-neighbor scaling
/// on the layer (`magnificationFilter = .nearest`) so the chunky pixels
/// stay chunky at avatar sizes.
struct KlausMascotView: View {
    /// How the mascot is cropped and rendered.
    enum DisplayMode {
        /// Full-body animated mascot. Aspect-fits into a `size × size`
        /// square; the natural tall aspect ratio means the width will
        /// be smaller than `size`.
        case full
        /// Face-aligned head/shoulders crop. Aspect-fills into a
        /// `size × size` square, so the face fills a circular avatar
        /// cleanly with minimal transparent space.
        case portrait
    }

    /// Target bounding-box side length in points. For `.full`, this is
    /// the max extent (height) of the mascot's tall aspect ratio. For
    /// `.portrait`, this is the side of the square container — the
    /// head crop is scaled to fill it so the face sits centered in
    /// a circular mask.
    var size: CGFloat

    /// Crop + scaling mode. Defaults to `.full` to preserve existing
    /// call sites that show the whole mascot.
    var mode: DisplayMode = .full

    /// When `true` the animation loops; when `false` only the first
    /// frame is shown (used for static previews where motion would
    /// be distracting).
    var isAnimating: Bool = true

    /// When `true` the RGB channels of every animation frame are
    /// inverted at render time via `colorInvert()`. Alpha is preserved,
    /// so transparent pixels stay transparent — only the mascot's body
    /// colors flip.
    ///
    /// Defaults to `false` now that the asset itself is baked in the
    /// final white + forest-green palette. Previously the source GIF
    /// used the artist's original cream/blue/red palette and this flag
    /// was used to push it toward a darker silhouette at runtime; that
    /// inversion produced muddy orange/brown tones which is the opposite
    /// of the branded two-tone look Klaus now ships with.
    var invertColors: Bool = false

    var body: some View {
        KlausAnimatedImage(mode: mode, isAnimating: isAnimating)
            .frame(width: size, height: size)
            .modifier(KlausColorModifier(invertColors: invertColors))
            .accessibilityLabel("Klaus, the Wi-Fi Buddy mascot")
    }
}

/// Applies the optional color-inversion treatment to the mascot. Split
/// into its own `ViewModifier` (rather than an inline `if invertColors`
/// branch) so the same `UIImageView`-backed representable instance is
/// reused across renders — the modifier only wraps the rendered output,
/// it doesn't swap the underlying view identity, which would throw away
/// the animation state.
private struct KlausColorModifier: ViewModifier {
    var invertColors: Bool

    func body(content: Content) -> some View {
        if invertColors {
            content.colorInvert()
        } else {
            content
        }
    }
}

// MARK: - Asset loader

/// Loads and caches the Klaus animation frames once per process per
/// variant. The GIFs ship as `NSDataAsset`s inside `Assets.xcassets`.
enum KlausMascotAssets {
    struct AnimationPayload {
        let frames: [UIImage]
        let duration: TimeInterval
        let pixelSize: CGSize
    }

    /// Data-asset name for the requested display mode.
    static func assetName(for mode: KlausMascotView.DisplayMode) -> String {
        switch mode {
        case .full: return "KlausMascot"
        case .portrait: return "KlausMascotHead"
        }
    }

    private static let lock = NSLock()
    private static var cachedPayloads: [String: AnimationPayload] = [:]

    static func loadAnimation(for mode: KlausMascotView.DisplayMode) -> AnimationPayload? {
        let name = assetName(for: mode)

        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedPayloads[name] {
            return cached
        }

        guard let asset = NSDataAsset(name: name) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true
        ]
        guard let source = CGImageSourceCreateWithData(asset.data as CFData, options as CFDictionary) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        var totalDuration: TimeInterval = 0
        var pixelSize = CGSize.zero

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            frames.append(uiImage)
            if pixelSize == .zero {
                pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
            }

            let frameDuration = Self.frameDelay(at: index, source: source)
            totalDuration += frameDuration
        }

        guard !frames.isEmpty else { return nil }

        if totalDuration <= 0 {
            totalDuration = Double(frames.count) * 0.04
        }

        let payload = AnimationPayload(frames: frames, duration: totalDuration, pixelSize: pixelSize)
        cachedPayloads[name] = payload
        return payload
    }

    /// Extracts the per-frame delay from GIF metadata with a sane
    /// minimum so aggressive editors that report `0` delays do not
    /// make the animation burn CPU at unbounded speeds.
    private static func frameDelay(at index: Int, source: CGImageSource) -> TimeInterval {
        let defaults: TimeInterval = 0.08
        let minimum: TimeInterval = 0.02

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return defaults
        }
        guard let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return defaults
        }

        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval
        let delay = unclamped ?? clamped ?? defaults

        return max(delay, minimum)
    }
}

// MARK: - UIKit bridge

private struct KlausAnimatedImage: UIViewRepresentable {
    var mode: KlausMascotView.DisplayMode
    var isAnimating: Bool

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode(for: mode)
        imageView.backgroundColor = .clear
        // Hard-clip to the SwiftUI frame. Without this a UIImageView will
        // render its image at the image's native point size if `sizeThatFits`
        // isn't respected, causing the mascot to overflow the container
        // (seen previously as a giant Klaus in the assistant sheet header).
        imageView.clipsToBounds = true
        imageView.layer.magnificationFilter = .nearest
        imageView.layer.minificationFilter = .nearest
        imageView.isAccessibilityElement = false

        // SwiftUI uses the wrapped UIImageView's intrinsic content size
        // (the GIF's native pixel size, e.g. 336×446 pt) when nothing else
        // constrains it. Dropping the hugging + compression priorities to
        // the lowest legal level lets the `.frame(width:height:)` modifier
        // win unconditionally.
        imageView.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow - 1, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow - 1, for: .vertical)

        configure(imageView)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.contentMode = contentMode(for: mode)
        configure(uiView)
    }

    /// Tell SwiftUI the view can accept whatever size the parent proposes.
    /// Without this override SwiftUI consults the underlying `UIImageView`'s
    /// intrinsic content size (the image's native pixel dimensions, which
    /// are hundreds of points tall for this 336×446 GIF) and the mascot
    /// blows past the intended bubble/avatar bounds.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        let width = proposal.width ?? 44
        let height = proposal.height ?? 44
        return CGSize(width: width, height: height)
    }

    private func contentMode(for mode: KlausMascotView.DisplayMode) -> UIView.ContentMode {
        switch mode {
        case .full:
            // Fit so the mascot's tall aspect ratio is preserved inside
            // the bounding box without being stretched or cropped.
            return .scaleAspectFit
        case .portrait:
            // Fill so the head crop covers the full square avatar; any
            // minor overhang on the wider axis is clipped away by the
            // circle mask the caller typically applies.
            return .scaleAspectFill
        }
    }

    private func configure(_ imageView: UIImageView) {
        guard let payload = KlausMascotAssets.loadAnimation(for: mode) else {
            imageView.image = nil
            return
        }

        if isAnimating {
            if imageView.animationImages == nil || imageView.animationImages?.count != payload.frames.count {
                imageView.animationImages = payload.frames
                imageView.animationDuration = payload.duration
                imageView.animationRepeatCount = 0
            }
            imageView.image = payload.frames.first
            if !imageView.isAnimating {
                imageView.startAnimating()
            }
        } else {
            if imageView.isAnimating {
                imageView.stopAnimating()
            }
            imageView.animationImages = nil
            imageView.image = payload.frames.first
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        KlausMascotView(size: 160, mode: .full)
        KlausMascotView(size: 64, mode: .full)
        KlausMascotView(size: 46, mode: .portrait)
            .clipShape(Circle())
        KlausMascotView(size: 34, mode: .portrait)
            .clipShape(Circle())
    }
    .padding()
    .background(Color(white: 0.1))
}
