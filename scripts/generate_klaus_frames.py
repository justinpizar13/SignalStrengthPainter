#!/usr/bin/env python3
"""
Extract animated frames from the Klaus mascot GIF, crop to the robot bounding
box, knock out the brownish backdrop so the mascot sits on transparent pixels,
and emit both a full-body animated GIF and a head-cropped portrait GIF for
the SwiftUI KlausMascotView. Source palette (cream body, light-blue face
screen, pink cheeks, red accent square, orange antenna tip, dark outlines)
is preserved as-is — earlier iterations remapped to a two-tone white +
forest-green palette but that lost facial detail.

Outputs:
    SignalStrengthPainter/Assets.xcassets/KlausMascot.dataset/klaus.gif
    SignalStrengthPainter/Assets.xcassets/KlausMascot.dataset/Contents.json
    SignalStrengthPainter/Assets.xcassets/KlausMascotHead.dataset/klaus_head.gif
    SignalStrengthPainter/Assets.xcassets/KlausMascotHead.dataset/Contents.json

Both GIFs are shipped as data assets. At runtime the Swift side decodes them
with ImageIO and plays them with a UIImageView wrapper so nearest-neighbor
pixel-art scaling is preserved.
"""

from __future__ import annotations

import json
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
FULL_DATASET_DIR = ROOT / "SignalStrengthPainter" / "Assets.xcassets" / "KlausMascot.dataset"
HEAD_DATASET_DIR = ROOT / "SignalStrengthPainter" / "Assets.xcassets" / "KlausMascotHead.dataset"
FULL_OUT_GIF = FULL_DATASET_DIR / "klaus.gif"
HEAD_OUT_GIF = HEAD_DATASET_DIR / "klaus_head.gif"

# Tolerance when matching the brown backdrop. The GIF is quantised so a tight
# tolerance would leave dithered halo pixels behind; 18 catches the stragglers.
BG_TOLERANCE = 18
# Extra pixels of padding around the detected robot bounding box.
PADDING = 8

# Head-crop extent, measured from Klaus's top-most non-transparent pixel
# on each frame. The source animation includes a "jump" cycle that shifts
# Klaus's whole body up by ~120 px for a few frames, so cropping from a
# fixed bbox-relative y would cause the face to bounce in and out of the
# portrait frame. Instead we compute each frame's top_y independently and
# take HEAD_HEIGHT_PX pixels downward from there — that keeps the face
# positionally stable in the portrait GIF while preserving the in-place
# eye/mouth animation. HEAD_HEIGHT_PX is tuned to include the antenna,
# the TV-screen face, and the collar/shoulders without cutting into the
# arms, so the portrait reads as a bust in a circular avatar.
HEAD_HEIGHT_PX = 220


def iter_rgba_frames(img: Image.Image):
    """Yield (rgba_frame, duration_ms) tuples from an animated image."""
    for frame in ImageSequence.Iterator(img):
        duration = frame.info.get("duration", 80)
        yield frame.convert("RGBA"), duration


def bbox_over_all_frames(frames) -> tuple[int, int, int, int]:
    """Compute the tight bounding box of non-transparent pixels across every frame.

    The input frames must have already had their backdrop knocked out to
    alpha=0 by ``recolor_frame``. Using alpha rather than RGB tolerance
    gives us the tightest possible bounding box because GIF dither noise
    near the backdrop gets swallowed by the recolor step instead of
    leaking into the bbox as faint non-background pixels.
    """
    min_x, min_y = frames[0].width, frames[0].height
    max_x, max_y = 0, 0

    for frame in frames:
        pixels = frame.load()
        w, h = frame.size
        # Sample every pixel so we do not miss thin features like the antenna.
        for y in range(h):
            for x in range(w):
                _, _, _, a = pixels[x, y]
                if a == 0:
                    continue
                if x < min_x:
                    min_x = x
                if y < min_y:
                    min_y = y
                if x > max_x:
                    max_x = x
                if y > max_y:
                    max_y = y
    return min_x, min_y, max_x, max_y


def recolor_frame(frame: Image.Image, bg_rgb) -> Image.Image:
    """Knock out backdrop pixels, leaving the robot's source palette intact.

    Every pixel close to the sampled brown backdrop becomes fully
    transparent. All other pixels are kept exactly as they appear in
    the source so Klaus renders with his original cream / light-blue /
    pink / red / orange palette.
    """
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


def _top_y_of_opaque_pixels(frame: Image.Image) -> int:
    """Return the y coordinate of the top-most non-transparent pixel in the frame."""
    pixels = frame.load()
    w, h = frame.size
    for y in range(h):
        for x in range(w):
            if pixels[x, y][3] != 0:
                return y
    return 0


def _crop_head_aligned(frame: Image.Image, head_height: int) -> Image.Image:
    """Crop the frame to a head-height-sized portrait aligned to the robot's
    current top y.

    Using each frame's own top-most opaque pixel as the crop origin means
    Klaus's face stays in roughly the same place within the portrait across
    resting and jumping frames, rather than bouncing in and out of view.
    """
    w, h = frame.size
    top_y = _top_y_of_opaque_pixels(frame)
    bottom_y = top_y + head_height
    if bottom_y > h:
        top_y = max(0, h - head_height)
        bottom_y = top_y + head_height
    return frame.crop((0, top_y, w, bottom_y))


def save_animated_gif(frames, durations, out_path: Path) -> None:
    """Save a list of RGBA frames as a looping, transparency-preserving GIF."""
    head = frames[0]
    tail = frames[1:]
    # GIFs only support 1-bit transparency, but that is fine for this pixel
    # art where every interior color is clearly non-transparent.
    head.save(
        out_path,
        save_all=True,
        append_images=tail,
        loop=0,
        duration=durations,
        disposal=2,
        transparency=0,
        optimize=False,
    )


def write_dataset_manifest(dataset_dir: Path, filename: str) -> None:
    """Write the Contents.json manifest so Xcode treats the GIF as a data asset."""
    contents = {
        "data": [
            {
                "filename": filename,
                "idiom": "universal",
                "universal-type-identifier": "com.compuserve.gif",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (dataset_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> None:
    if not SRC_GIF.exists():
        print(f"source gif not found: {SRC_GIF}", file=sys.stderr)
        sys.exit(1)

    FULL_DATASET_DIR.mkdir(parents=True, exist_ok=True)
    HEAD_DATASET_DIR.mkdir(parents=True, exist_ok=True)

    with Image.open(SRC_GIF) as img:
        source_frames = [(f.copy(), dur) for f, dur in iter_rgba_frames(img)]

    if not source_frames:
        print("no frames extracted", file=sys.stderr)
        sys.exit(1)

    # Background is sampled from the corner of the first frame.
    bg_pixel = source_frames[0][0].getpixel((0, 0))
    bg_rgb = bg_pixel[:3]

    # First pass: knock out the backdrop. Doing this first lets the bbox
    # scan below key on alpha=0 and ignore GIF dither noise that would
    # otherwise inflate the bounding box.
    recolored_frames: list[Image.Image] = []
    durations: list[int] = []
    for frame, dur in source_frames:
        recolored_frames.append(recolor_frame(frame, bg_rgb))
        durations.append(dur)

    min_x, min_y, max_x, max_y = bbox_over_all_frames(recolored_frames)
    frame_w, frame_h = recolored_frames[0].size
    min_x = max(0, min_x - PADDING)
    min_y = max(0, min_y - PADDING)
    max_x = min(frame_w - 1, max_x + PADDING)
    max_y = min(frame_h - 1, max_y + PADDING)

    bbox = (min_x, min_y, max_x + 1, max_y + 1)
    bbox_w = max_x - min_x + 1
    bbox_h = max_y - min_y + 1
    print(f"bbox across frames: {bbox} -> size {(bbox_w, bbox_h)}")

    head_height = min(HEAD_HEIGHT_PX, bbox_h)
    print(f"head crop: per-frame aligned -> size ({bbox_w}, {head_height})")

    full_frames: list[Image.Image] = []
    head_frames: list[Image.Image] = []
    for frame in recolored_frames:
        cropped = frame.crop(bbox)
        full_frames.append(cropped)
        head_frames.append(_crop_head_aligned(cropped, head_height))

    save_animated_gif(full_frames, durations, FULL_OUT_GIF)
    save_animated_gif(head_frames, durations, HEAD_OUT_GIF)
    write_dataset_manifest(FULL_DATASET_DIR, FULL_OUT_GIF.name)
    write_dataset_manifest(HEAD_DATASET_DIR, HEAD_OUT_GIF.name)

    full_kb = FULL_OUT_GIF.stat().st_size / 1024
    head_kb = HEAD_OUT_GIF.stat().st_size / 1024
    print(f"wrote {FULL_OUT_GIF} ({len(full_frames)} frames, {full_kb:.1f} KB)")
    print(f"wrote {HEAD_OUT_GIF} ({len(head_frames)} frames, {head_kb:.1f} KB)")


if __name__ == "__main__":
    main()
