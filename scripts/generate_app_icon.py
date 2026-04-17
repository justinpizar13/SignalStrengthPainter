"""Generate the Wi-Fi Buddy app icon (1024x1024).

Design:
- Pure black background (iOS applies its own squircle mask at runtime).
- Three concentric Wi-Fi arcs + center dot filled with a subtle iridescent
  "Apple glass" gradient: predominantly silvery white (≈80%) with very muted
  pastel hints of pink / lavender / mint / peach.
- A diagonal white highlight sheen across the upper-left of the glyph for
  the glass effect.
- Three 4-pointed sparkle accents in the upper right, also rendered in the
  same subtle iridescent material.

Renders at 4x supersampling (4096x4096) then downsamples to 1024x1024 with
high-quality resampling for crisp anti-aliased edges.
"""

from PIL import Image, ImageDraw, ImageFilter

# --- Canvas setup -----------------------------------------------------------

FINAL_SIZE = 1024
SCALE = 4
SIZE = FINAL_SIZE * SCALE  # 4096


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(c1, c2, t):
    return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(len(c1)))


# --- Iridescent material ----------------------------------------------------
# Base is near-white silver. Corners get very faint pastel tints. Overall
# saturation is kept low so the result reads as "shimmery silver" rather than
# "rainbow".

BASE_SILVER = (230, 230, 234)
TINT_TL = (248, 208, 224)   # pale pink
TINT_TR = (206, 238, 220)   # pale mint
TINT_BR = (208, 216, 246)   # pale lavender / blue
TINT_BL = (248, 224, 204)   # pale peach

TINT_STRENGTH = 0.85  # how much of the tint to mix with silver


def build_iridescent_layer(size: int) -> Image.Image:
    """Build an RGBA image of the iridescent material over full canvas."""
    img = Image.new("RGBA", (size, size), BASE_SILVER + (255,))
    px = img.load()
    for y in range(size):
        for x in range(size):
            u = x / (size - 1)
            v = y / (size - 1)
            # Bilinear tint weights
            w_tl = (1 - u) * (1 - v)
            w_tr = u * (1 - v)
            w_br = u * v
            w_bl = (1 - u) * v
            tr = (
                TINT_TL[0] * w_tl + TINT_TR[0] * w_tr + TINT_BR[0] * w_br + TINT_BL[0] * w_bl
            )
            tg = (
                TINT_TL[1] * w_tl + TINT_TR[1] * w_tr + TINT_BR[1] * w_br + TINT_BL[1] * w_bl
            )
            tb = (
                TINT_TL[2] * w_tl + TINT_TR[2] * w_tr + TINT_BR[2] * w_br + TINT_BL[2] * w_bl
            )
            r = int(round(BASE_SILVER[0] * (1 - TINT_STRENGTH) + tr * TINT_STRENGTH))
            g = int(round(BASE_SILVER[1] * (1 - TINT_STRENGTH) + tg * TINT_STRENGTH))
            b = int(round(BASE_SILVER[2] * (1 - TINT_STRENGTH) + tb * TINT_STRENGTH))
            px[x, y] = (r, g, b, 255)
    return img


def add_highlight_sheen(img: Image.Image) -> None:
    """Overlay a soft diagonal bright sheen in the upper-left for glassiness."""
    size = img.size[0]
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    spx = sheen.load()
    # Sheen aligned along a diagonal band targeting the upper-left of the
    # Wi-Fi glyph area (roughly u+v ≈ 0.85 with glyph centered at ~(0.5, 0.6)).
    for y in range(size):
        for x in range(size):
            u = x / (size - 1)
            v = y / (size - 1)
            band = abs((u + v) - 0.85)
            intensity = max(0.0, 1.0 - band / 0.22)
            intensity = intensity ** 2
            alpha = int(150 * intensity)  # peak ~59% white, localized band
            if alpha > 0:
                spx[x, y] = (255, 255, 255, alpha)
    img.alpha_composite(sheen)


# --- Wi-Fi glyph mask -------------------------------------------------------

def build_wifi_mask(size: int) -> Image.Image:
    """Grayscale (L) mask where 255 = fully opaque glyph, 0 = transparent."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)

    cx = size / 2
    cy = size * 0.575

    # Outer bbox radius and stroke thickness (PIL draws stroke inward from bbox).
    arc_defs = [
        (0.355, 0.080),  # outer
        (0.255, 0.080),  # middle
        (0.155, 0.080),  # inner
    ]

    start_deg = 225  # upper-left
    end_deg = 315    # upper-right

    import math

    for r_outer_frac, w_frac in arc_defs:
        r_outer = size * r_outer_frac
        w = size * w_frac
        bbox = (cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer)
        d.arc(bbox, start=start_deg, end=end_deg, fill=255, width=int(round(w)))
        # Round caps: stamp a filled disk at each arc endpoint.
        # PIL arc(width=w) draws the stroke band inward from bbox radius,
        # so the stroke centerline is at (r_outer - w/2).
        r_center = r_outer - w / 2
        cap_r = w / 2
        for ang_deg in (start_deg, end_deg):
            ang = math.radians(ang_deg)
            px = cx + r_center * math.cos(ang)
            py = cy + r_center * math.sin(ang)
            d.ellipse(
                (px - cap_r, py - cap_r, px + cap_r, py + cap_r),
                fill=255,
            )

    # center dot
    dot_r = size * 0.055
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
        (0.810, 0.185, 0.082),
        (0.905, 0.295, 0.050),
        (0.705, 0.095, 0.042),
    ]
    for xf, yf, af in sparkles:
        cx = size * xf
        cy = size * yf
        arm = size * af
        waist = arm * 0.28
        # 4-pointed star as a polygon (arm, waist, arm, waist, ...)
        pts = []
        import math as _m
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

    # Iridescent material layer.
    iridescent = build_iridescent_layer(SIZE)
    add_highlight_sheen(iridescent)

    # Wi-Fi glyph masked out of the iridescent material onto black.
    wifi_mask = build_wifi_mask(SIZE)
    # Soften the mask very slightly to avoid aliasing on curves.
    wifi_mask = wifi_mask.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.4))
    bg.paste(iridescent, (0, 0), wifi_mask)

    # Sparkles use the same material but dimmed a touch for subtlety.
    sparkle_material = iridescent.copy()
    alpha = sparkle_material.getchannel("A").point(lambda a: int(a * 0.9))
    sparkle_material.putalpha(alpha)
    sparkles_mask = build_sparkles_mask(SIZE)
    sparkles_mask = sparkles_mask.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.3))
    bg.paste(sparkle_material, (0, 0), sparkles_mask)

    # Downsample to 1024 with high-quality resampling for crisp edges.
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
