#!/usr/bin/env python3
"""
Extract animated frames from the Klaus mascot GIF, crop to the robot bounding
box, knock out the brownish backdrop so the mascot sits on transparent pixels,
and emit the frames plus metadata for the SwiftUI KlausMascotView.

Outputs:
    SignalStrengthPainter/Assets.xcassets/KlausMascot.dataset/klaus.gif
    SignalStrengthPainter/Assets.xcassets/KlausMascot.dataset/Contents.json

The cleaned animated GIF is shipped as a data asset. At runtime the Swift
side decodes it with ImageIO and plays it with a UIImageView wrapper so
pixel-art nearest-neighbor scaling is preserved.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageSequence
except ImportError:
    print("Pillow is required. Install with: pip install Pillow", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
SRC_GIF = Path(
    "/Users/jupizarr/.cursor/projects/Users-jupizarr-SignalStrengthPainter/"
    "assets/polifolli-robot-a8771062-8003-4795-ad9f-dc9619617e0b.png"
)
DATASET_DIR = ROOT / "SignalStrengthPainter" / "Assets.xcassets" / "KlausMascot.dataset"
OUT_GIF = DATASET_DIR / "klaus.gif"

# Tolerance when matching the brown backdrop. The GIF is quantised so a tight
# tolerance would leave dithered halo pixels behind; 18 catches the stragglers.
BG_TOLERANCE = 18
# Extra pixels of padding around the detected robot bounding box.
PADDING = 8


def iter_rgba_frames(img: Image.Image):
    """Yield (rgba_frame, duration_ms) tuples from an animated image."""
    for frame in ImageSequence.Iterator(img):
        duration = frame.info.get("duration", 80)
        yield frame.convert("RGBA"), duration


def bbox_over_all_frames(frames, bg_rgb) -> tuple[int, int, int, int]:
    """Compute the bounding box of non-background pixels across every frame."""
    min_x, min_y = frames[0][0].width, frames[0][0].height
    max_x, max_y = 0, 0

    for frame, _ in frames:
        pixels = frame.load()
        w, h = frame.size
        # Sample every pixel so we do not miss thin features like the antenna.
        for y in range(h):
            for x in range(w):
                r, g, b, _ = pixels[x, y]
                if (
                    abs(r - bg_rgb[0]) > BG_TOLERANCE
                    or abs(g - bg_rgb[1]) > BG_TOLERANCE
                    or abs(b - bg_rgb[2]) > BG_TOLERANCE
                ):
                    if x < min_x:
                        min_x = x
                    if y < min_y:
                        min_y = y
                    if x > max_x:
                        max_x = x
                    if y > max_y:
                        max_y = y
    return min_x, min_y, max_x, max_y


def knock_out_background(frame: Image.Image, bg_rgb) -> Image.Image:
    """Replace pixels close to the backdrop color with transparent pixels."""
    pixels = frame.load()
    w, h = frame.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if (
                abs(r - bg_rgb[0]) <= BG_TOLERANCE
                and abs(g - bg_rgb[1]) <= BG_TOLERANCE
                and abs(b - bg_rgb[2]) <= BG_TOLERANCE
            ):
                pixels[x, y] = (0, 0, 0, 0)
    return frame


def main() -> None:
    if not SRC_GIF.exists():
        print(f"source gif not found: {SRC_GIF}", file=sys.stderr)
        sys.exit(1)

    DATASET_DIR.mkdir(parents=True, exist_ok=True)

    with Image.open(SRC_GIF) as img:
        frames = [(f.copy(), dur) for f, dur in iter_rgba_frames(img)]

    if not frames:
        print("no frames extracted", file=sys.stderr)
        sys.exit(1)

    # Background is sampled from the corner of the first frame.
    bg_pixel = frames[0][0].getpixel((0, 0))
    bg_rgb = bg_pixel[:3]

    min_x, min_y, max_x, max_y = bbox_over_all_frames(frames, bg_rgb)
    min_x = max(0, min_x - PADDING)
    min_y = max(0, min_y - PADDING)
    max_x = min(frames[0][0].width - 1, max_x + PADDING)
    max_y = min(frames[0][0].height - 1, max_y + PADDING)

    bbox = (min_x, min_y, max_x + 1, max_y + 1)
    print(f"bbox across frames: {bbox} -> size {(max_x - min_x + 1, max_y - min_y + 1)}")

    processed = []
    durations = []
    for frame, dur in frames:
        cropped = frame.crop(bbox)
        cleaned = knock_out_background(cropped, bg_rgb)
        processed.append(cleaned)
        durations.append(dur)

    # Pillow wants the master image plus a list of trailing frames.
    head = processed[0]
    tail = processed[1:]

    # GIFs only support 1-bit transparency, but that is fine for this pixel
    # art where every interior color is clearly non-transparent. The cleaner
    # the alpha channel, the less halo you see around the robot.
    head.save(
        OUT_GIF,
        save_all=True,
        append_images=tail,
        loop=0,
        duration=durations,
        disposal=2,
        transparency=0,
        optimize=False,
    )

    contents = {
        "data": [
            {
                "filename": "klaus.gif",
                "idiom": "universal",
                "universal-type-identifier": "com.compuserve.gif",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (DATASET_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    size_kb = OUT_GIF.stat().st_size / 1024
    print(f"wrote {OUT_GIF} ({len(processed)} frames, {size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
