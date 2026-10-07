#!/usr/bin/env python3
"""Generates the launcher icon (and the web icons) for the Flutter project.

Pure standard library: builds an RGBA raster, downsamples it, and writes PNGs
with zlib so the repository does not need any image tooling at build time.

Usage:  python3 tool/generate_icons.py
"""

import os
import struct
import zlib

# --- palette (kept in sync with lib/theme/app_theme.dart) --------------------
BG_TOP = (22, 26, 30)        # #161A1E
BG_BOTTOM = (11, 14, 17)     # #0B0E11
YELLOW = (240, 185, 11)      # #F0B90B
YELLOW_DARK = (196, 150, 8)

SUPERSAMPLE = 3              # 3x3 samples per pixel for anti-aliasing


def write_png(path, width, height, pixels):
    """pixels: flat list of (r, g, b, a) tuples, row major."""

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        row = pixels[y * width:(y + 1) * width]
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)


def rounded_rect_contains(x, y, left, top, right, bottom, radius):
    if x < left or x > right or y < top or y > bottom:
        return False
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    dx = x - cx
    dy = y - cy
    return dx * dx + dy * dy <= radius * radius


def mark_contains(x, y, size):
    """The 'B with strokes' (bitcoin-style) glyph, in `size` x `size` space.

    Coordinates below are expressed for a 512 px canvas and scaled with `s`:

        strokes  |--+  92
        stem     |  |  120
        bowl 1   +--)  260
        bowl 2   +--)  400
                 |  |  428
                 |--+
    """
    s = size / 512.0
    stem_left = 176 * s
    stem_width = 54 * s
    stem_right = stem_left + stem_width
    y_top = 120 * s
    y_mid = 260 * s
    y_bottom = 400 * s
    ring = 18 * s            # half thickness of the bowl strokes
    bar_half = 10 * s        # half thickness of the two bitcoin strokes

    # --- vertical stem ------------------------------------------------------
    if rounded_rect_contains(x, y, stem_left, y_top, stem_right, y_bottom, 10 * s):
        return True

    # --- the two strokes that turn the B into the bitcoin sign --------------
    for bar_x in (stem_left + 16 * s, stem_right - 16 * s):
        if rounded_rect_contains(
            x, y, bar_x - bar_half, 92 * s, bar_x + bar_half, 428 * s, bar_half
        ):
            return True

    # --- bowls: right half of an ellipse, joined to the stem ----------------
    if x >= stem_right:
        for rx, cy, ry in (
            (96 * s, (y_top + y_mid) / 2, (y_mid - y_top) / 2),
            (106 * s, (y_mid + y_bottom) / 2, (y_bottom - y_mid) / 2),
        ):
            nx = (x - stem_right) / rx
            ny = (y - cy) / ry
            t = (nx * nx + ny * ny) ** 0.5
            if abs(t - 1.0) * min(rx, ry) <= ring:
                return True

    return False


def background_color(x, y, size):
    """Dark rounded square with a subtle top-to-bottom gradient."""
    radius = size * 0.225
    if not rounded_rect_contains(x, y, 0, 0, size - 1, size - 1, radius):
        return None
    t = y / size
    return tuple(
        int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)
    )


def render_master(size=512):
    """Renders the rounded dark icon (RGB list, row major)."""
    out = [(0, 0, 0, 0)] * (size * size)
    step = 1.0 / SUPERSAMPLE
    for py in range(size):
        for px in range(size):
            r = g = b = a = 0
            for sy in range(SUPERSAMPLE):
                for sx in range(SUPERSAMPLE):
                    x = px + (sx + 0.5) * step
                    y = py + (sy + 0.5) * step
                    bg = background_color(x, y, size)
                    if bg is None:
                        continue
                    if mark_contains(x, y, size):
                        # Slight vertical gradient inside the mark too.
                        mix = y / size
                        color = tuple(
                            int(YELLOW[i] + (YELLOW_DARK[i] - YELLOW[i]) * mix)
                            for i in range(3)
                        )
                    else:
                        color = bg
                    r += color[0]
                    g += color[1]
                    b += color[2]
                    a += 255
            samples = SUPERSAMPLE * SUPERSAMPLE
            out[py * size + px] = (
                r // samples,
                g // samples,
                b // samples,
                a // samples,
            )
    return out


def render_foreground(size=512):
    """Transparent PNG with only the glyph, scaled into the adaptive safe area."""
    out = [(0, 0, 0, 0)] * (size * size)
    step = 1.0 / SUPERSAMPLE
    inner = size * 0.68           # keep the mark inside the 66% safe circle
    offset = (size - inner) / 2
    for py in range(size):
        for px in range(size):
            r = g = b = a = 0
            for sy in range(SUPERSAMPLE):
                for sx in range(SUPERSAMPLE):
                    x = px + (sx + 0.5) * step
                    y = py + (sy + 0.5) * step
                    mx = (x - offset) / inner * size
                    my = (y - offset) / inner * size
                    if 0 <= mx < size and 0 <= my < size and mark_contains(mx, my, size):
                        mix = y / size
                        color = tuple(
                            int(YELLOW[i] + (YELLOW_DARK[i] - YELLOW[i]) * mix)
                            for i in range(3)
                        )
                        r += color[0]
                        g += color[1]
                        b += color[2]
                        a += 255
            samples = SUPERSAMPLE * SUPERSAMPLE
            out[py * size + px] = (
                r // samples,
                g // samples,
                b // samples,
                a // samples,
            )
    return out


def downsample(source, source_size, target_size):
    """Box filter (area average) resize, good enough for icons."""
    if target_size == source_size:
        return list(source)
    out = [(0, 0, 0, 0)] * (target_size * target_size)
    ratio = source_size / target_size
    for ty in range(target_size):
        for tx in range(target_size):
            x0 = int(tx * ratio)
            x1 = max(x0 + 1, int((tx + 1) * ratio))
            y0 = int(ty * ratio)
            y1 = max(y0 + 1, int((ty + 1) * ratio))
            r = g = b = a = count = 0
            for y in range(y0, min(y1, source_size)):
                for x in range(x0, min(x1, source_size)):
                    pixel = source[y * source_size + x]
                    r += pixel[0]
                    g += pixel[1]
                    b += pixel[2]
                    a += pixel[3]
                    count += 1
            if count == 0:
                count = 1
            out[ty * target_size + tx] = (
                r // count,
                g // count,
                b // count,
                a // count,
            )
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res = os.path.join(root, "android", "app", "src", "main", "res")

    print("rendering master icon ...")
    master = render_master(512)

    densities = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in densities.items():
        pixels = downsample(master, 512, size)
        path = os.path.join(res, f"mipmap-{density}", "ic_launcher.png")
        write_png(path, size, size, pixels)
        print(f"  wrote {os.path.relpath(path, root)} ({size}x{size})")

    print("rendering adaptive foreground ...")
    foreground = render_foreground(512)
    path = os.path.join(res, "drawable-nodpi", "ic_launcher_foreground.png")
    write_png(path, 512, 512, foreground)
    print(f"  wrote {os.path.relpath(path, root)} (512x512)")

    # ---- web icons (used by `flutter run -d chrome`) ----------------------
    web = os.path.join(root, "web")
    for name, size in (
        ("favicon.png", 32),
        ("icons/Icon-192.png", 192),
        ("icons/Icon-512.png", 512),
        ("icons/Icon-maskable-192.png", 192),
        ("icons/Icon-maskable-512.png", 512),
    ):
        pixels = downsample(master, 512, size)
        path = os.path.join(web, name)
        write_png(path, size, size, pixels)
        print(f"  wrote {os.path.relpath(path, root)} ({size}x{size})")

    print("done.")


if __name__ == "__main__":
    main()
