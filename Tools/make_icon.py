#!/usr/bin/env python3
"""
Generates the AppIcon-1024.png used by Watch.app.

Design: minimalist black square with bold white "W" letter centered.
Not connected to anime/films — just a clean monogram.

Usage:
    python3 Tools/make_icon.py
"""
from __future__ import annotations
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Pillow is required: pip install Pillow", file=sys.stderr)
    sys.exit(1)


SIZE = 1024
BG = (0, 0, 0, 255)         # pure black
FG = (255, 255, 255, 255)   # pure white


def find_bold_font(size: int) -> ImageFont.FreeTypeFont:
    """Return any heavy/bold sans-serif font available on the runner."""
    candidates = [
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/SFNS.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVu-Sans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "Watch" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "AppIcon-1024.png"

    img = Image.new("RGBA", (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(img)

    font = find_bold_font(int(SIZE * 0.62))

    # Draw a subtle rounded inner box border for character.
    inset = int(SIZE * 0.08)
    radius = int(SIZE * 0.22)
    draw.rounded_rectangle(
        [inset, inset, SIZE - inset, SIZE - inset],
        radius=radius,
        outline=(255, 255, 255, 30),
        width=6,
    )

    # Center the letter "W".
    text = "W"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (SIZE - text_w) // 2 - bbox[0]
    y = (SIZE - text_h) // 2 - bbox[1] - int(SIZE * 0.02)
    draw.text((x, y), text, font=font, fill=FG)

    img = img.convert("RGB")
    img.save(out_path, "PNG", optimize=True)
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
