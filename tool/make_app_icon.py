#!/usr/bin/env python3
"""Renders the launcher icon from the brand mark.

The geometry here is the same path `TackLogo` paints in
`app/lib/design/icons.dart` — a four-segment zigzag ascending left to right
with a dot at the end, on a 40x24 viewBox. It is duplicated rather than
imported because Dart cannot be called from a build script, so if the mark
ever changes in one place it has to change in both.

The wordmark is deliberately not here. A launcher icon is 48dp on a real
phone and gets masked into a circle on most Android launchers; "Tack" set
beside the mark would be a few pixels tall and clipped at both ends.

    python3 tool/make_app_icon.py
"""

from PIL import Image, ImageDraw

MAROON = (0x7A, 0x1B, 0x34, 255)  # TackColors.maroon, light palette
CREAM = (0xF1, 0xEF, 0xE8, 255)  # TackColors.sailWhite, light palette

POLY = [(3, 21), (11, 12), (17, 16), (25, 7), (31, 11)]
STROKE = 3.4
DOT, DOT_R = (36, 5), 3.2

# The drawn extent, stroke included, so the mark can be centred on what is
# actually visible rather than on the viewBox.
BOX = (1.3, 1.8, 39.2, 22.7)
BOX_W, BOX_H = BOX[2] - BOX[0], BOX[3] - BOX[1]
BOX_CX, BOX_CY = (BOX[0] + BOX[2]) / 2, (BOX[1] + BOX[3]) / 2

SS = 8  # supersampling; PIL has no round joins, so they are drawn by hand


def render(px: int, width_frac: float, background=None, circle=False) -> Image.Image:
    """One icon. `width_frac` is the mark's width as a fraction of the canvas."""
    n = px * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    if background and circle:
        draw.ellipse([0, 0, n - 1, n - 1], fill=background)
    elif background:
        draw.rectangle([0, 0, n, n], fill=background)

    scale = (width_frac * n) / BOX_W

    def at(x, y):
        return (n / 2 + (x - BOX_CX) * scale, n / 2 + (y - BOX_CY) * scale)

    def disc(centre, r):
        x, y = centre
        draw.ellipse([x - r, y - r, x + r, y + r], fill=MAROON)

    stroke = STROKE * scale
    for a, b in zip(POLY, POLY[1:]):
        draw.line([at(*a), at(*b)], fill=MAROON, width=max(1, round(stroke)))
    # Round caps and joins: a disc at every vertex, including the two ends.
    for point in POLY:
        disc(at(*point), stroke / 2)
    disc(at(*DOT), DOT_R * scale)

    return img.resize((px, px), Image.LANCZOS)


def write(path: str, image: Image.Image, opaque: bool = False) -> None:
    import os

    os.makedirs(os.path.dirname(path), exist_ok=True)
    # iOS rejects an icon with an alpha channel.
    image.convert("RGB" if opaque else "RGBA").save(path)
    print(f"  {path}  {image.width}x{image.height}")


ANDROID = "app/android/app/src/main/res"
IOS = "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"

# Legacy launcher icons, drawn on the brand ground because nothing composites
# a background behind them.
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# The adaptive foreground is a 108dp canvas of which only the middle 72dp is
# guaranteed to survive masking, so the mark is drawn smaller and transparent.
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def main() -> None:
    print("Android legacy:")
    for density, px in DENSITIES.items():
        write(f"{ANDROID}/mipmap-{density}/ic_launcher.png",
              render(px, 0.62, background=CREAM))
        write(f"{ANDROID}/mipmap-{density}/ic_launcher_round.png",
              render(px, 0.58, background=CREAM, circle=True))

    print("Android adaptive foreground:")
    for density, px in ADAPTIVE.items():
        write(f"{ANDROID}/mipmap-{density}/ic_launcher_foreground.png",
              render(px, 0.52))

    print("iOS:")
    for name, px in IOS_SIZES.items():
        write(f"{IOS}/{name}", render(px, 0.62, background=CREAM), opaque=True)

    print("Store / README:")
    write("design/tack-icon-1024.png", render(1024, 0.62, background=CREAM))


if __name__ == "__main__":
    main()
