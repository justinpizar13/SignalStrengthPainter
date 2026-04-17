"""Generate the Wi-Fi Buddy app icon (1024x1024).

Design goals (matching the "Apple TV" glass-rebrand icon):
- Pure black squircle background (iOS applies its own corner mask at runtime).
- Wi-Fi glyph visually **centered** and sized to fill the icon the way the
  "tv" letters fill the Apple TV icon background.
- **Subtle rainbow** iridescent material across the glyph: a silvery base
  with pale but visible hints of pink / mint / lavender / peach distributed
  as a bilinear 4-corner tint. Keeps the "shimmery silver" read, not neon.
- Strong glass 3D depth: the top of the glyph is brightened (highlight) and
  the bottom is slightly darkened (shadow), mimicking a form lit from above.
- A concentrated diagonal specular sheen across the upper-left of the glyph
  to read as polished glass.
- Three 4-pointed sparkles in the upper-right painted with the same
  material (slightly dimmed) so they shimmer without pulling focus.

Renders at 4x supersampling and downsamples to 1024x1024 with LANCZOS for
crisp anti-aliased edges.
"""

from PIL import Image, ImageDraw, ImageFilter

# --- Canvas setup -----------------------------------------------------------

FINAL_SIZE = 1024
SCALE = 4
SIZE = FINAL_SIZE * SCALE  # 4096

# --- Glyph geometry ---------------------------------------------------------
# Previously cy=0.575 with r_outer=0.355 placed the glyph high in the icon
# leaving a lot of empty black below. The Apple TV icon fills ~70% of the
# canvas vertically and centers visually. We shift cy lower and grow the
# arcs so the glyph spans roughly y ∈ [0.26, 0.72] — centered around 0.49.

GLYPH_CY_FRAC = 0.635
OUTER_R_FRAC = 0.425
MID_R_FRAC = 0.302
INNER_R_FRAC = 0.180
STROKE_W_FRAC = 0.096
DOT_R_FRAC = 0.064

GLYPH_TOP_FRAC = GLYPH_CY_FRAC - OUTER_R_FRAC    # ~0.26
GLYPH_BOTTOM_FRAC = GLYPH_CY_FRAC + DOT_R_FRAC   # ~0.72


def lerp(a, b, t):
    return a + (b - a) * t


# --- Iridescent material ----------------------------------------------------
# Silvery base with four pastel corner tints. Saturation is intentionally
# moderate — the hues should *hint* of a rainbow, not shout. Corners are
# arranged pink (TL) → mint (TR) → lavender (BR) → peach (BL) so the glyph
# picks up a soft top-left pink wash, a mint/cyan shoulder on the top-right,
# and a warm amber kiss at the bottom — the same vibe as Apple's rainbow
# apple on the TV icon but toned down.

BASE_SILVER = (220, 220, 228)

TINT_TL = (255, 138, 190)   # pink / magenta
TINT_TR = (132, 228, 208)   # mint / cyan
TINT_BR = (170, 150, 252)   # lavender / violet
TINT_BL = (255, 188, 128)   # warm peach / amber

TINT_STRENGTH = 0.92  # 0 = pure silver, 1 = pure tint

# Glass 3D depth: brighten the top of the glyph, darken the bottom.
# Applied as a vertical multiplier over the iridescent layer; only the
# glyph area is visible after masking, so the effect reads as per-glyph
# top-lit shading. Kept modest so the underlying rainbow still reads
# through the highlight (Apple TV reference stays saturated under its
# top light because the underlying color is strong).
TOP_HIGHLIGHT_GAIN = 0.14    # +14% brightness at top of glyph
BOTTOM_SHADOW_GAIN = -0.22   # -22% brightness at bottom of glyph


def build_iridescent_layer(size: int) -> Image.Image:
    """Build an RGBA image of the iridescent material with vertical 3D shading."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()

    top_y = GLYPH_TOP_FRAC
    bot_y = GLYPH_BOTTOM_FRAC
    span = max(bot_y - top_y, 1e-6)

    for y in range(size):
        v = y / (size - 1)
        # Vertical depth multiplier, clamped outside the glyph band so a
        # single ambient tone is used above/below (it's masked out anyway,
        # but sparkles above the glyph should stay neutral-bright).
        if v <= top_y:
            depth = 1.0 + TOP_HIGHLIGHT_GAIN
        elif v >= bot_y:
            depth = 1.0 + BOTTOM_SHADOW_GAIN
        else:
            t = (v - top_y) / span
            depth = lerp(1.0 + TOP_HIGHLIGHT_GAIN, 1.0 + BOTTOM_SHADOW_GAIN, t)

        for x in range(size):
            u = x / (size - 1)
            # Bilinear 4-corner tint.
            w_tl = (1 - u) * (1 - v)
            w_tr = u * (1 - v)
            w_br = u * v
            w_bl = (1 - u) * v
            tr = (
                TINT_TL[0] * w_tl + TINT_TR[0] * w_tr
                + TINT_BR[0] * w_br + TINT_BL[0] * w_bl
            )
            tg = (
                TINT_TL[1] * w_tl + TINT_TR[1] * w_tr
                + TINT_BR[1] * w_br + TINT_BL[1] * w_bl
            )
            tb = (
                TINT_TL[2] * w_tl + TINT_TR[2] * w_tr
                + TINT_BR[2] * w_br + TINT_BL[2] * w_bl
            )
            r = BASE_SILVER[0] * (1 - TINT_STRENGTH) + tr * TINT_STRENGTH
            g = BASE_SILVER[1] * (1 - TINT_STRENGTH) + tg * TINT_STRENGTH
            b = BASE_SILVER[2] * (1 - TINT_STRENGTH) + tb * TINT_STRENGTH
            r = max(0.0, min(255.0, r * depth))
            g = max(0.0, min(255.0, g * depth))
            b = max(0.0, min(255.0, b * depth))
            px[x, y] = (int(round(r)), int(round(g)), int(round(b)), 255)
    return img


def add_highlight_sheen(img: Image.Image) -> None:
    """Paint a concentrated diagonal specular band across the upper-left of the
    glyph. The band is aimed so its hot-spot falls just inside the top of the
    outer Wi-Fi arc, giving a polished-glass read once masked to the glyph.
    """
    size = img.size[0]
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    spx = sheen.load()

    # Glyph top-center ≈ (0.5, 0.26). A narrow diagonal ridge at u+v ≈ 0.78
    # passes through the upper-left shoulder of the outer arc and the top-
    # center crown. Kept tight so the specular reads as a polished glass
    # highlight rather than a wash — preserves the rainbow underneath.
    band_center = 0.78
    band_width = 0.17
    peak_alpha = 205  # ~80% white at the very center of the band

    for y in range(size):
        for x in range(size):
            u = x / (size - 1)
            v = y / (size - 1)
            band = abs((u + v) - band_center)
            intensity = max(0.0, 1.0 - band / band_width)
            intensity = intensity ** 2.2
            alpha = int(peak_alpha * intensity)
            if alpha > 0:
                spx[x, y] = (255, 255, 255, alpha)
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
    """Grayscale mask for three 4-pointed sparkle stars in the upper-right."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    # (x_frac, y_frac, arm_frac)
    sparkles = [
        (0.810, 0.175, 0.082),
        (0.905, 0.285, 0.050),
        (0.705, 0.090, 0.042),
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


# --- Compose ----------------------------------------------------------------

def generate_icon(out_path: str) -> None:
    # Black background (full bleed; iOS masks the squircle on device).
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))

    # Iridescent material + glass sheen.
    iridescent = build_iridescent_layer(SIZE)
    add_highlight_sheen(iridescent)

    # Wi-Fi glyph punched out of the iridescent material.
    wifi_mask = build_wifi_mask(SIZE)
    wifi_mask = wifi_mask.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.4))
    bg.paste(iridescent, (0, 0), wifi_mask)

    # Sparkles use the same material dimmed slightly for a softer read.
    sparkle_material = iridescent.copy()
    alpha = sparkle_material.getchannel("A").point(lambda a: int(a * 0.92))
    sparkle_material.putalpha(alpha)
    sparkles_mask = build_sparkles_mask(SIZE)
    sparkles_mask = sparkles_mask.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.3))
    bg.paste(sparkle_material, (0, 0), sparkles_mask)

    # Downsample for final PNG.
    final = bg.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)
    # Icon must be opaque RGB for App Store.
    final_rgb = Image.new("RGB", final.size, (0, 0, 0))
    final_rgb.paste(final, mask=final.getchannel("A"))
    final_rgb.save(out_path, format="PNG", optimize=True)


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "icon_1024x1024.png"
    generate_icon(out)
    print(f"wrote {out}")
