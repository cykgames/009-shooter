"""Generate self-authored (CC0) UI textures for 009-shooter.

- assets/images/gui/title_logo.png : crosshair emblem for the title screen.
- assets/images/gui/pickup_halo.png: soft pulsing ring drawn under pickups so
  weapon drops read clearly on the dark arena floor (unarmed onboarding).

Usage: python tools/gen_ui_textures.py
"""
import math
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
GUI = ROOT / "addons" / "top_down" / "assets" / "images" / "gui"


def title_logo() -> None:
    S = 128
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2.0
    # outer ring
    d.ellipse([c - 56, c - 56, c + 56, c + 56], outline=(255, 214, 90, 255), width=8)
    # crosshair ticks
    for (x0, y0, x1, y1) in [
        (c - 62, c - 3, c - 40, c + 3), (c + 40, c - 3, c + 62, c + 3),
        (c - 3, c - 62, c + 3, c - 40), (c - 3, c + 40, c + 3, c + 62),
    ]:
        d.rectangle([x0, y0, x1, y1], fill=(255, 214, 90, 255))
    # inner dot
    d.ellipse([c - 12, c - 12, c + 12, c + 12], fill=(255, 255, 255, 255))
    img.save(GUI / "title_logo.png")
    print("wrote", GUI / "title_logo.png")


def pickup_halo() -> None:
    S = 96
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    c = S / 2.0
    for y in range(S):
        for x in range(S):
            r = math.hypot(x + 0.5 - c, y + 0.5 - c)
            # ring band centered at r=34, soft falloff both sides
            band = max(0.0, 1.0 - abs(r - 34.0) / 12.0)
            a = int(200 * band ** 1.5)
            px[x, y] = (255, 224, 110, a)
    img.save(GUI / "pickup_halo.png")
    print("wrote", GUI / "pickup_halo.png")


if __name__ == "__main__":
    GUI.mkdir(parents=True, exist_ok=True)
    title_logo()
    pickup_halo()
