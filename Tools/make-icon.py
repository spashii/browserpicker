#!/usr/bin/env python3
"""Draws Resources/AppIcon.iconset. One link at the bottom, three places it could go."""
import os
from PIL import Image, ImageDraw

S = 1024
SS = 4  # supersample
NAVY_TOP = (26, 40, 72)
NAVY_BOTTOM = (10, 17, 36)
LINE = (255, 255, 255)
ACCENT = (255, 158, 66)


def squircle(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def gradient(size):
    base = Image.new("RGB", (1, size))
    px = base.load()
    for y in range(size):
        t = y / (size - 1)
        px[0, y] = tuple(int(a + (b - a) * t) for a, b in zip(NAVY_TOP, NAVY_BOTTOM))
    return base.resize((size, size))


def bezier(p0, p1, p2, steps=64):
    out = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        out.append((x, y))
    return out


def draw_icon():
    size = S * SS
    margin = int(size * 0.085)
    inner = size - margin * 2
    art = gradient(inner)
    art.putalpha(squircle(inner, int(inner * 0.225)))

    d = ImageDraw.Draw(art)
    k = inner / 1024
    width = int(58 * k)

    stem_bottom = (512 * k, 838 * k)
    junction = (512 * k, 560 * k)
    arms = [(196 * k, 292 * k), (512 * k, 236 * k), (828 * k, 292 * k)]

    d.line([stem_bottom, junction], fill=LINE, width=width)
    for arm in arms:
        control = (arm[0], junction[1])
        d.line(bezier(junction, control, arm), fill=LINE, width=width, joint="curve")

    for i, arm in enumerate(arms):
        r = 96 * k
        colour = ACCENT if i == 1 else LINE
        d.ellipse([arm[0] - r, arm[1] - r, arm[0] + r, arm[1] + r], fill=colour)
    r = 78 * k
    d.ellipse([stem_bottom[0] - r, stem_bottom[1] - r, stem_bottom[0] + r, stem_bottom[1] + r], fill=LINE)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(art, (margin, margin), art)
    return canvas.resize((S, S), Image.LANCZOS)


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "Resources", "AppIcon.iconset")
    os.makedirs(out, exist_ok=True)
    icon = draw_icon()
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            icon.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
    print("wrote", out)


if __name__ == "__main__":
    main()
