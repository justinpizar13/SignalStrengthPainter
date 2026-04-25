"""Generate the WiFi Buddy app icon (1024x1024).

The coloring and geometry here are kept in lockstep with the in-app
``AppLogoView`` SwiftUI view (`SignalStrengthPainter/AppLogoView.swift`). The
in-app logo is the design-of-record, and this icon must render with visually
identical geometry/coloring so the home-screen icon and the in-app branding
read as the same mark.

Design:

- **Wi-Fi glyph** — three concentric arcs (green / yellow / orange) plus a
  red center dot, drawn as round-capped strokes. Classic "signal strength"
  traffic-light palette.
- **Even radial spacing** — stroke width 0.080 of the canvas; each arc is
  inset by stroke + 0.050, giving a consistent 0.050 gap between strokes
  and between the inner arc and the dot. Same cadence as ``AppLogoView``.
- **Vertical centering** — `cy = 0.695` places the glyph bounding box
  (top of outer arc at y=0.250, bottom of dot at y=0.750) dead-center in
  the square canvas.
- **Dark gray background** — full-bleed ``(40, 40, 44)`` squircle. iOS
  applies its own rounded-rect mask at runtime, so the PNG itself is a
  solid square.

No sparkles, no sheen — the in-app ``AppLogoView`` renders the same flat
glyph on a transparent background, and this PNG adds the dark-gray fill
only so the home-screen icon has a proper tile.

Rendered at 4× supersampling and downsampled to 1024×1024 with LANCZOS for
crisp anti-aliased edges. The icon ships as opaque RGB (App Store requires
no alpha channel).
"""

import math

from PIL import Image, ImageDraw, ImageFilter

# --- Canvas setup -----------------------------------------------------------

FINAL_SIZE = 1024
SCALE = 4
SIZE = FINAL_SIZE * SCALE  # 4096

# --- Glyph geometry ---------------------------------------------------------
# Shared with ``AppLogoView`` so the in-app logo and the PNG line up pixel-
# for-pixel (at any scale).

GLYPH_CY_FRAC = 0.695
STROKE_W_FRAC = 0.080
DOT_R_FRAC = 0.055
# Outer bbox radius fractions for outer / middle / inner arcs.
ARC_R_FRACS = [0.445, 0.315, 0.185]

# --- Palette ----------------------------------------------------------------
# Traffic-light Wi-Fi signal palette shared with ``AppLogoView``.
# Colors are 0..255 RGB (SwiftUI 0..1 * 255, rounded).

OUTER_ARC_RGB = (77, 217, 102)    # Color(0.30, 0.85, 0.40)
MIDDLE_ARC_RGB = (250, 209, 56)   # Color(0.98, 0.82, 0.22)
INNER_ARC_RGB = (250, 133, 56)    # Color(0.98, 0.52, 0.22)
DOT_RGB = (250, 82, 82)           # Color(0.98, 0.32, 0.32)

# Dark gray squircle background (full bleed; iOS masks the squircle on
# device). Neutral near-black with a hint of warmth.
BACKGROUND_RGB = (40, 40, 44)


def _draw_arc_stroke(draw: ImageDraw.ImageDraw, size: int, r_outer_frac: float,
                     stroke_w: float, color: tuple, cx: float, cy: float) -> None:
    """Draw a single Wi-Fi arc: a 225°→315° arc stroked with round caps."""
    r_outer = size * r_outer_frac
    bbox = (cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer)
    # PIL arc convention: angles increase clockwise from east. 225° → 315°
    # draws the upper fan shape in screen (y-down) coordinates.
    start_deg = 225
    end_deg = 315
    draw.arc(bbox, start=start_deg, end=end_deg, fill=color,
             width=int(round(stroke_w)))
    # Round caps on each endpoint. PIL arc(width=w) draws inward from the
    # bbox radius, so the stroke centerline is at r_outer - w/2.
    r_center = r_outer - stroke_w / 2
    cap_r = stroke_w / 2
    for ang_deg in (start_deg, end_deg):
        ang = math.radians(ang_deg)
        px_ = cx + r_center * math.cos(ang)
        py_ = cy + r_center * math.sin(ang)
        draw.ellipse(
            (px_ - cap_r, py_ - cap_r, px_ + cap_r, py_ + cap_r),
            fill=color,
        )


def build_glyph_layer(size: int) -> Image.Image:
    """Render the Wi-Fi glyph (arcs + dot) onto a transparent RGBA canvas."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    cx = size / 2
    cy = size * GLYPH_CY_FRAC
    stroke_w = size * STROKE_W_FRAC

    arc_colors = [OUTER_ARC_RGB, MIDDLE_ARC_RGB, INNER_ARC_RGB]
    for r_frac, color in zip(ARC_R_FRACS, arc_colors):
        _draw_arc_stroke(draw, size, r_frac, stroke_w, color, cx, cy)

    dot_r = size * DOT_R_FRAC
    draw.ellipse(
        (cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r),
        fill=DOT_RGB,
    )
    return layer


# --- Compose ----------------------------------------------------------------

def generate_icon(out_path: str) -> None:
    # Dark gray background (full bleed; iOS masks the squircle on device).
    bg = Image.new("RGBA", (SIZE, SIZE), (*BACKGROUND_RGB, 255))

    # Wi-Fi glyph rendered on its own transparent layer and composited.
    # A tiny Gaussian blur on the glyph alpha smooths out aliasing on the
    # curved strokes before downsampling.
    glyph = build_glyph_layer(SIZE)
    alpha = glyph.getchannel("A").filter(
        ImageFilter.GaussianBlur(radius=SCALE * 0.3)
    )
    glyph.putalpha(alpha)
    bg.alpha_composite(glyph)

    # Downsample for final PNG.
    final = bg.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)
    # Icon must be opaque RGB for App Store. Flatten onto the dark-gray bg.
    final_rgb = Image.new("RGB", final.size, BACKGROUND_RGB)
    final_rgb.paste(final, mask=final.getchannel("A"))
    final_rgb.save(out_path, format="PNG", optimize=True)


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "icon_1024x1024.png"
    generate_icon(out)
    print(f"wrote {out}")
