import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// SwiftUI view that renders the Klaus mascot animation from the `KlausMascot`
/// data asset (an animated GIF shipped in `Assets.xcassets`).
///
/// The GIF is loaded with `ImageIO`, decoded into a frame list with per-frame
/// delays, and played through a `UIImageView` wrapped in a
/// `UIViewRepresentable`. Using `UIImageView.animationImages` rather than
/// SwiftUI's `Image` is what actually animates the sequence — plain `Image`
/// does not play animated GIFs.
///
/// Pixel-art crispness is preserved by forcing nearest-neighbor scaling on
/// the layer (`magnificationFilter = .nearest`) so the chunky pixels stay
/// chunky when the mascot is drawn at bubble/avatar sizes.
struct KlausMascotView: View {
    /// Target side length in points. The mascot has a 336 × 446 frame, so
    /// the view computes a proportional height internally.
    var size: CGFloat
    /// When `true` the animation loops; when `false` only the first frame
    /// is shown (used for static avatars where motion would be distracting).
    var isAnimating: Bool = true

    var body: some View {
        KlausAnimatedImage(targetWidth: size, isAnimating: isAnimating)
            .frame(width: size, height: size * KlausMascotAssets.aspectHeightOverWidth)
            .accessibilityLabel("Klaus, the Wi-Fi Buddy mascot")
    }
}

// MARK: - Asset loader

/// Loads and caches the Klaus animation frames once per process. The GIF
/// ships as an `NSDataAsset` named `KlausMascot` inside `Assets.xcassets`.
enum KlausMascotAssets {
    struct AnimationPayload {
        let frames: [UIImage]
        let duration: TimeInterval
        let pixelSize: CGSize
    }

    /// Nominal aspect ratio (height / width) of a single cleaned frame.
    /// Kept in sync with the bounding box in `generate_klaus_frames.py`.
    static let aspectHeightOverWidth: CGFloat = 446.0 / 336.0

    private static let lock = NSLock()
    private static var cachedPayload: AnimationPayload?

    static func loadAnimation() -> AnimationPayload? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedPayload {
            return cached
        }

        guard let asset = NSDataAsset(name: "KlausMascot") else { return nil }

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
            // Safety fallback: roughly 25 FPS.
            totalDuration = Double(frames.count) * 0.04
        }

        let payload = AnimationPayload(frames: frames, duration: totalDuration, pixelSize: pixelSize)
        cachedPayload = payload
        return payload
    }

    /// Extracts the per-frame delay from GIF metadata with a sane minimum so
    /// aggressive editors that report `0` delays do not make the animation
    /// burn CPU at unbounded speeds.
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
    var targetWidth: CGFloat
    var isAnimating: Bool

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = false
        imageView.layer.magnificationFilter = .nearest
        imageView.layer.minificationFilter = .nearest
        imageView.isAccessibilityElement = false

        configure(imageView)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        configure(uiView)
    }

    private func configure(_ imageView: UIImageView) {
        guard let payload = KlausMascotAssets.loadAnimation() else {
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
        KlausMascotView(size: 160)
        KlausMascotView(size: 64)
        KlausMascotView(size: 32)
    }
    .padding()
    .background(Color(white: 0.1))
}
