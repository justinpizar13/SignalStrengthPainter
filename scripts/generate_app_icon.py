"""Generate the Wi-Fi Buddy app icon (1024x1024).

The coloring here is kept in lockstep with the in-app ``AppLogoView`` SwiftUI
view (`SignalStrengthPainter/AppLogoView.swift`). The in-app logo is the
design-of-record, and this icon must render with visually identical coloring
so the home-screen icon and the in-app branding read as the same mark.

Key properties mirrored from ``AppLogoView``:

- **Diagonal iridescent gradient**, 6 stops running top-left → bottom-right.
  Palette matches ``IridescentPalette.earthy`` — the unified earthy palette
  used in both light and dark mode in-app: burgundy → slate → warm brown →
  forest green → plum → slate. Darker, muted tones so the rainbow reads
  without the candy-pastel look of the earlier "Apple glass" palette.
- **Light cream background.** Earlier icon iterations used a pure black
  background with bright pastel arcs; the earthy palette's darker tones
  would disappear on black, so the icon now uses a light cream squircle
  that matches the background color the in-app logo renders over.
- **No vertical "3D depth" shading.** Earlier iterations of this script
  brightened the top of the glyph and darkened the bottom to emulate a lit
  form; the in-app logo intentionally omits that so the rainbow reads
  evenly. Removing it here makes the PNG and the SwiftUI view match.
- **Diagonal glass sheen** clipped to the glyph, peaking at gradient
  location ≈ 0.39 (``u + v ≈ 0.78``). The SwiftUI view draws the same
  band at the same location, using a soft warm off-white at 0.40 alpha.
- **Sparkle positions** match ``AppLogoView.drawSparkles`` (y fractions
  0.185 / 0.295 / 0.095) and are tinted with the same gradient, RGB-dimmed
  by 0.9 — again matching the SwiftUI dim path.

Rendered at 4× supersampling and downsampled to 1024×1024 with LANCZOS for
crisp anti-aliased edges. The icon ships as opaque RGB (App Store requires
no alpha channel); the iOS runtime applies its own squircle mask.
"""

from PIL import Image, ImageDraw, ImageFilter

# --- Canvas setup -----------------------------------------------------------

FINAL_SIZE = 1024
SCALE = 4
SIZE = FINAL_SIZE * SCALE  # 4096

# --- Glyph geometry ---------------------------------------------------------
# Shared with ``AppLogoView`` so the in-app logo and the PNG line up pixel-
# for-pixel (at any scale).

GLYPH_CY_FRAC = 0.635
OUTER_R_FRAC = 0.425
MID_R_FRAC = 0.302
INNER_R_FRAC = 0.180
STROKE_W_FRAC = 0.096
DOT_R_FRAC = 0.064


def lerp(a, b, t):
    return a + (b - a) * t


# --- Iridescent material ----------------------------------------------------
# Six-stop diagonal gradient that mirrors ``IridescentPalette.earthy`` in
# ``AppLogoView.swift`` — the single shared palette used in both light and
# dark mode. Stop locations match SwiftUI's Gradient(stops:) array exactly
# so the color distribution is identical.
#
# SwiftUI colors are 0..1 RGB; converted to 0..255 here (rounded).

GRADIENT_STOPS = [
    # (location 0..1, (r, g, b) 0..255)
    (0.00, (122,  56,  87)),   # pink (burgundy)  Color(0.48, 0.22, 0.34)
    (0.20, ( 69,  64,  71)),   # silverWarm       Color(0.27, 0.25, 0.28)
    (0.40, (115,  82,  51)),   # peach (warm brown) Color(0.45, 0.32, 0.20)
    (0.60, ( 51,  92,  77)),   # mint (forest)    Color(0.20, 0.36, 0.30)
    (0.80, ( 71,  59, 117)),   # lavender (plum)  Color(0.28, 0.23, 0.46)
    (1.00, ( 64,  66,  71)),   # silverCool       Color(0.25, 0.26, 0.28)
]

# --- Background -------------------------------------------------------------
# Light cream squircle background so the earthy glyph reads with contrast.
# Matches the off-white seen when the in-app logo renders over the light
# theme's `cardFill` (near-white). iOS applies its squircle mask on device.

BACKGROUND_RGB = (242, 241, 246)


def sample_gradient(t: float) -> tuple:
    """Interpolate the 6-stop gradient at parameter ``t`` in [0, 1]."""
    if t <= GRADIENT_STOPS[0][0]:
        return GRADIENT_STOPS[0][1]
    if t >= GRADIENT_STOPS[-1][0]:
        return GRADIENT_STOPS[-1][1]
    for i in range(len(GRADIENT_STOPS) - 1):
        loc0, c0 = GRADIENT_STOPS[i]
        loc1, c1 = GRADIENT_STOPS[i + 1]
        if loc0 <= t <= loc1:
            span = max(loc1 - loc0, 1e-9)
            u = (t - loc0) / span
            return (
                lerp(c0[0], c1[0], u),
                lerp(c0[1], c1[1], u),
                lerp(c0[2], c1[2], u),
            )
    return GRADIENT_STOPS[-1][1]


def build_iridescent_layer(size: int) -> Image.Image:
    """RGBA image of the iridescent material.

    The gradient runs from the top-left corner to the bottom-right corner,
    matching SwiftUI's ``startPoint: (0, 0), endPoint: (size, size)``. For a
    square canvas the gradient parameter at pixel ``(x, y)`` reduces to
    ``(u + v) / 2`` where ``u = x/(size-1)`` and ``v = y/(size-1)``.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()

    inv = 1.0 / (size - 1)
    for y in range(size):
        v = y * inv
        for x in range(size):
            u = x * inv
            t = (u + v) * 0.5
            r, g, b = sample_gradient(t)
            px[x, y] = (int(round(r)), int(round(g)), int(round(b)), 255)
    return img


def add_highlight_sheen(img: Image.Image) -> None:
    """Paint a concentrated diagonal specular band across the upper-left of
    the glyph, matching the sheen in ``AppLogoView.drawSheen``.

    ``AppLogoView`` uses a linear gradient with a single non-transparent stop
    at location 0.39 (peak alpha) fading to 0 at 0.26 and 0.52. Along a
    TL→BR linear gradient on a square, ``loc = (u + v) / 2``. So the peak
    sits at ``u + v = 0.78``, with the band width determined by the
    transparent stops (0.26 and 0.52 → ``u + v`` of 0.52 and 1.04). That
    corresponds to a band half-width of ~0.26 in ``u + v`` space.

    Sheen color/alpha matches ``IridescentPalette.earthy``: a soft warm
    off-white at 0.40 alpha peak so the darker earthy base is lifted
    without blowing out.
    """
    size = img.size[0]
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    spx = sheen.load()

    # SwiftUI sheen: warm off-white at 0.40 alpha peak, with symmetric
    # transparent stops 0.13 gradient units away (locations 0.26 and 0.52
    # vs peak 0.39). Color matches ``sheenColor = Color(1.0, 0.98, 0.96)``.
    peak_loc = 0.39
    half_width = 0.13
    peak_alpha = int(round(0.40 * 255))  # ≈ 102
    sheen_rgb = (255, 250, 245)

    inv = 1.0 / (size - 1)
    for y in range(size):
        v = y * inv
        for x in range(size):
            u = x * inv
            loc = (u + v) * 0.5
            dist = abs(loc - peak_loc)
            if dist >= half_width:
                continue
            # Triangular falloff matches SwiftUI's linear gradient interpolation
            # between the peak stop and the adjacent transparent stops.
            intensity = 1.0 - dist / half_width
            alpha = int(round(peak_alpha * intensity))
            if alpha > 0:
                spx[x, y] = (*sheen_rgb, alpha)
    img.alpha_composite(sheen)


# --- Wi-Fi glyph mask -------------------------------------------------------

def build_wifi_mask(size: int) -> Image.Image:
    """Grayscale mask: 255 = opaque glyph, 0 = transparent."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)

    cx = size / 2
    cy = size * GLYPH_CY_FRAC

    # (outer bbox radius fraction, stroke thickness fraction)
    arc_defs = [
        (OUTER_R_FRAC, STROKE_W_FRAC),
        (MID_R_FRAC,   STROKE_W_FRAC),
        (INNER_R_FRAC, STROKE_W_FRAC),
    ]

    # PIL arc convention: angles increase clockwise from east. 225° → 315°
    # draws the lower arc in PIL's coordinate system, which (with y-down
    # screen coords) renders the upper Wi-Fi fan shape.
    start_deg = 225
    end_deg = 315

    import math

    for r_outer_frac, w_frac in arc_defs:
        r_outer = size * r_outer_frac
        w = size * w_frac
        bbox = (cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer)
        d.arc(bbox, start=start_deg, end=end_deg, fill=255, width=int(round(w)))
        # Round caps on each arc endpoint. PIL arc(width=w) draws inward
        # from the bbox radius, so the stroke centerline is at r_outer - w/2.
        r_center = r_outer - w / 2
        cap_r = w / 2
        for ang_deg in (start_deg, end_deg):
            ang = math.radians(ang_deg)
            px_ = cx + r_center * math.cos(ang)
            py_ = cy + r_center * math.sin(ang)
            d.ellipse(
                (px_ - cap_r, py_ - cap_r, px_ + cap_r, py_ + cap_r),
                fill=255,
            )

    dot_r = size * DOT_R_FRAC
    d.ellipse(
        (cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r),
        fill=255,
    )
    return mask


def build_sparkles_mask(size: int) -> Image.Image:
    """Grayscale mask for three 4-pointed sparkle stars in the upper-right.

    Positions match ``AppLogoView.drawSparkles`` exactly so the sparkles
    land in the same spot at any scale.
    """
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    # (x_frac, y_frac, arm_frac) — identical to AppLogoView.swift
    sparkles = [
        (0.810, 0.185, 0.082),
        (0.905, 0.295, 0.050),
        (0.705, 0.095, 0.042),
    ]
    import math as _m
    for xf, yf, af in sparkles:
        cx = size * xf
        cy = size * yf
        arm = size * af
        waist = arm * 0.28
        pts = []
        for i in range(8):
            angle = _m.radians(i * 45 - 90)
            r = arm if i % 2 == 0 else waist
            pts.append((cx + r * _m.cos(angle), cy + r * _m.sin(angle)))
        d.polygon(pts, fill=255)
    return mask


def dim_rgb(img: Image.Image, dim: float) -> Image.Image:
    """Scale RGB channels by ``dim`` (leaving alpha untouched).

    Matches ``Color.dimmed(by:)`` in AppLogoView.swift, which multiplies the
    RGB components and clamps to [0, 1]. Used so sparkles are tinted with a
    slightly muted version of the same gradient rather than a gradient with
    reduced alpha.
    """
    if dim >= 0.9999:
        return img.copy()
    r, g, b, a = img.split()
    scale = max(0.0, min(1.0, dim))
    lut = [int(round(i * scale)) for i in range(256)]
    r = r.point(lut)
    g = g.point(lut)
    b = b.point(lut)
    return Image.merge("RGBA", (r, g, b, a))


# --- Compose ----------------------------------------------------------------

def generate_icon(out_path: str) -> None:
    # Light cream background (full bleed; iOS masks the squircle on device).
    bg = Image.new("RGBA", (SIZE, SIZE), (*BACKGROUND_RGB, 255))

    # Iridescent material + glass sheen (applied before masking so the
    # sheen's diagonal iso-lines read through the glyph identically to the
    # SwiftUI view's "clip to glyph, then draw sheen" pipeline).
    iridescent = build_iridescent_layer(SIZE)
    add_highlight_sheen(iridescent)

    # Wi-Fi glyph punched out of the iridescent material.
    wifi_mask = build_wifi_mask(SIZE)
    wifi_mask = wifi_mask.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.4))
    bg.paste(iridescent, (0, 0), wifi_mask)

    # Sparkles use the same material with RGB dimmed to 0.9, matching
    # ``iridescentShading(..., dim: 0.9)`` in the SwiftUI view.
    sparkle_material = dim_rgb(iridescent, 0.9)
    sparkles_mask = build_sparkles_mask(SIZE)
    sparkles_mask = sparkles_mask.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.3))
    bg.paste(sparkle_material, (0, 0), sparkles_mask)

    # Downsample for final PNG.
    final = bg.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)
    # Icon must be opaque RGB for App Store. Flatten onto the cream bg so
    # any residual alpha from downsampling resolves to the icon background.
    final_rgb = Image.new("RGB", final.size, BACKGROUND_RGB)
    final_rgb.paste(final, mask=final.getchannel("A"))
    final_rgb.save(out_path, format="PNG", optimize=True)


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "icon_1024x1024.png"
    generate_icon(out)
    print(f"wrote {out}")
