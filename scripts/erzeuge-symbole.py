#!/usr/bin/env python3
"""Erzeugt alle App-Symbole von Frames aus Zeichenvorschriften: die wählbaren Symbole für iPhone, iPad und Mac,
die Vorschaubilder für die Einstellungen und die Schichtbilder samt Top-Shelf-Bild für den Apple TV.

Aufruf im Hauptordner: python3 scripts/erzeuge-symbole.py   (braucht Pillow)
Das Standardsymbol „Einzelbilder“ (AppIcon) bleibt unverändert und dient nur als Vorlage für die Vorschau.
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "App", "Assets.xcassets")
FONT = os.path.join(ROOT, "Sources", "FramesUI", "Resources", "Fonts", "SpaceGrotesk.ttf")

BG = (14, 16, 18)
LIME = (198, 242, 78)
DARK_BORDER = (76, 83, 92)
SOFT_BORDER = (169, 176, 184)
WHITE = (232, 234, 237)
INFO = {"author": "xcode", "version": 1}
S = 4  # Überabtastung für glatte Kanten


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def canvas(size, color=None, alpha=False):
    mode = "RGBA" if alpha else "RGB"
    fill = (0, 0, 0, 0) if alpha else color
    return Image.new(mode, (size[0] * S, size[1] * S), fill)


def finish(img, size):
    return img.resize(size, Image.LANCZOS)


def rect(d, box, fill=None, outline=None, width=0):
    x0, y0, x1, y1 = [v * S for v in box]
    if fill is not None:
        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=fill)
    if outline is not None:
        d.rectangle([x0, y0, x1 - 1, y1 - 1], outline=outline, width=width * S)


# --- Logo „Einzelbilder“ in den Maßen des Standardsymbols (1024 × 1024) ---------------------------------
BACK = (190, 214, 620, 575)
MIDDLE = (300, 324, 730, 685)
FRONT = (410, 434, 840, 805)
LOGO_BOX = (190, 214, 840, 805)


def logo_pieces(d, back_color, middle_color, front_color, middle_fill, only=None, offset=(515, 509.5), scale=1.0):
    def mapped(box):
        return tuple(int(round(v)) for v in (
            (box[0] - 515) * scale + offset[0], (box[1] - 509.5) * scale + offset[1],
            (box[2] - 515) * scale + offset[0], (box[3] - 509.5) * scale + offset[1]))
    stroke = max(2, int(round(30 * scale)))
    if only in (None, "back"):
        rect(d, mapped(BACK), outline=back_color, width=stroke)
    if only in (None, "middle"):
        rect(d, mapped(MIDDLE), fill=middle_fill, outline=middle_color, width=stroke)
    if only in (None, "front"):
        rect(d, mapped(FRONT), fill=front_color)


def icon_einzelbilder_limette():
    img = canvas((1024, 1024), LIME)
    d = ImageDraw.Draw(img)
    logo_pieces(d, (155, 192, 52), (92, 122, 20), BG, LIME)
    return finish(img, (1024, 1024))


def icon_schraegstrich():
    """Ein „f“ mit Schrägstrich, als Block auf dem Symbol zentriert."""
    mark = Image.new("L", (1400 * S, 1000 * S), 0)
    d = ImageDraw.Draw(mark)
    font = ImageFont.truetype(FONT, 820 * S)
    try:
        font.set_variation_by_name("Bold")
    except Exception:
        pass
    d.text((40 * S, 500 * S), "f", font=font, fill=255, anchor="lm")
    pts = [(470, 150), (640, 150), (440, 850), (270, 850)]
    d.polygon([((x + 150) * S, y * S) for x, y in pts], fill=255)
    box = mark.getbbox()
    mark = mark.crop(box)
    target = 640 * S
    factor = target / mark.height
    mark = mark.resize((int(mark.width * factor), target), Image.LANCZOS)
    img = canvas((1024, 1024), LIME)
    dark = Image.new("RGB", mark.size, BG)
    img.paste(dark, ((img.width - mark.width) // 2, (img.height - mark.height) // 2), mark)
    return finish(img, (1024, 1024))


def icon_sucher():
    img = canvas((1024, 1024), BG)
    d = ImageDraw.Draw(img)
    t, arm = 46, 190
    x0, y0, x1, y1 = 200, 200, 824, 824
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        rect(d, (min(cx, cx + sx * arm), min(cy, cy + sy * t), max(cx, cx + sx * arm), max(cy, cy + sy * t)) if sy == 1 else
             (min(cx, cx + sx * arm), cy - t, max(cx, cx + sx * arm), cy), fill=WHITE)
        rect(d, (cx if sx == 1 else cx - t, min(cy, cy + sy * arm), cx + t if sx == 1 else cx, max(cy, cy + sy * arm)), fill=WHITE)
    rect(d, (432, 432, 592, 592), fill=LIME)
    return finish(img, (1024, 1024))


def icon_balken_f():
    img = canvas((1024, 1024), LIME)
    d = ImageDraw.Draw(img)
    rect(d, (300, 250, 430, 774), fill=BG)
    rect(d, (470, 250, 760, 380), fill=BG)
    rect(d, (470, 440, 680, 550), fill=BG)
    return finish(img, (1024, 1024))


def icon_zeitleiste():
    img = canvas((1024, 1024), BG)
    d = ImageDraw.Draw(img)
    rect(d, (170, 690, 854, 726), fill=DARK_BORDER)
    rect(d, (170, 690, 580, 726), fill=LIME)
    rect(d, (562, 620, 598, 796), fill=LIME)
    # Vorschaubild über dem Abspielkopf
    rect(d, (400, 330, 760, 560), fill=BG, outline=SOFT_BORDER, width=22)
    rect(d, (500, 400, 660, 490), fill=LIME)
    # Zeiger vom Vorschaubild zum Kopf
    rect(d, (562, 560, 598, 620), fill=SOFT_BORDER)
    return finish(img, (1024, 1024))


def icon_kontaktbogen():
    img = canvas((1024, 1024), BG)
    d = ImageDraw.Draw(img)
    cell, gap = 170, 40
    start = (1024 - (3 * cell + 2 * gap)) // 2
    for row in range(3):
        for col in range(3):
            x = start + col * (cell + gap)
            y = start + row * (cell + gap)
            if (row, col) == (1, 2):
                rect(d, (x, y, x + cell, y + cell), fill=LIME)
            else:
                shade = SOFT_BORDER if (row + col) % 2 == 0 else DARK_BORDER
                rect(d, (x, y, x + cell, y + cell), outline=shade, width=18)
    return finish(img, (1024, 1024))


ICONS = {
    "einzelbilderLimette": icon_einzelbilder_limette,
    "schraegstrich": icon_schraegstrich,
    "sucher": icon_sucher,
    "balkenF": icon_balken_f,
    "zeitleiste": icon_zeitleiste,
    "kontaktbogen": icon_kontaktbogen,
}


def build_phone_icons():
    base = Image.open(os.path.join(ASSETS, "AppIcon.appiconset", "icon-1024.png")).convert("RGB")
    images = {"einzelbilder": base}
    for name, draw in ICONS.items():
        images[name] = draw().convert("RGB")
    for name, img in images.items():
        if name != "einzelbilder":
            folder = os.path.join(ASSETS, f"Icon-{name}.appiconset")
            os.makedirs(folder, exist_ok=True)
            img.save(os.path.join(folder, "icon-1024.png"), optimize=True)
            write_json(os.path.join(folder, "Contents.json"), {
                "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                "info": INFO,
            })
        folder = os.path.join(ASSETS, f"IconVorschau-{name}.imageset")
        os.makedirs(folder, exist_ok=True)
        img.resize((384, 384), Image.LANCZOS).save(os.path.join(folder, "vorschau.png"), optimize=True)
        write_json(os.path.join(folder, "Contents.json"), {
            "images": [{"filename": "vorschau.png", "idiom": "universal"}],
            "info": INFO,
        })


# --- Apple TV: Schichtbilder und Top-Shelf-Bild --------------------------------------------------------
def tv_layer(size, which):
    w, h = size
    scale = (h * 0.6) / (LOGO_BOX[3] - LOGO_BOX[1])
    offset = (w / 2, h / 2)
    if which == "back":
        img = canvas(size, BG)
    else:
        img = canvas(size, alpha=True)
    d = ImageDraw.Draw(img)
    logo_pieces(d, DARK_BORDER, SOFT_BORDER, LIME, BG, only=which, offset=offset, scale=scale)
    return finish(img, size)


def write_layer(folder, name, size_1x, which, with_2x=True):
    layer = os.path.join(folder, f"{name}.imagestacklayer")
    content = os.path.join(layer, "Content.imageset")
    os.makedirs(content, exist_ok=True)
    images = []
    for scale in ([1, 2] if with_2x else [1]):
        size = (size_1x[0] * scale, size_1x[1] * scale)
        filename = f"{which}@{scale}x.png"
        tv_layer(size, which).save(os.path.join(content, filename), optimize=True)
        entry = {"filename": filename, "idiom": "tv"}
        if with_2x:
            entry["scale"] = f"{scale}x"
        images.append(entry)
    write_json(os.path.join(content, "Contents.json"), {"images": images, "info": INFO})
    write_json(os.path.join(layer, "Contents.json"), {"info": INFO})


def write_stack(folder, size_1x, with_2x):
    os.makedirs(folder, exist_ok=True)
    for name, which in (("Front", "front"), ("Middle", "middle"), ("Back", "back")):
        write_layer(folder, name, size_1x, which, with_2x)
    write_json(os.path.join(folder, "Contents.json"), {
        "layers": [{"filename": f"{n}.imagestacklayer"} for n in ("Front", "Middle", "Back")],
        "info": INFO,
    })


def top_shelf(size):
    w, h = size
    img = canvas(size, BG)
    d = ImageDraw.Draw(img)
    scale = (h * 0.34) / (LOGO_BOX[3] - LOGO_BOX[1])
    font = ImageFont.truetype(FONT, int(h * 0.2) * S)
    try:
        font.set_variation_by_name("Bold")
    except Exception:
        pass
    text = "frames"
    text_w = d.textlength(text, font=font) / S
    logo_w = (LOGO_BOX[2] - LOGO_BOX[0]) * scale
    gap = h * 0.06
    total = logo_w + gap + text_w
    left = (w - total) / 2
    logo_cx = left + logo_w / 2
    logo_pieces(d, DARK_BORDER, SOFT_BORDER, LIME, BG, offset=(logo_cx - (515 - 515) * scale, h / 2), scale=scale)
    d.text(((left + logo_w + gap) * S, h / 2 * S), text, font=font, fill=WHITE, anchor="lm")
    return finish(img, size)


def build_tv():
    brand = os.path.join(ASSETS, "App Icon & Top Shelf Image.brandassets")
    write_stack(os.path.join(brand, "App Icon.imagestack"), (400, 240), True)
    write_stack(os.path.join(brand, "App Icon - App Store.imagestack"), (1280, 768), False)
    for name, size in (("Top Shelf Image.imageset", (1920, 720)), ("Top Shelf Image Wide.imageset", (2320, 720))):
        folder = os.path.join(brand, name)
        os.makedirs(folder, exist_ok=True)
        entries = []
        for scale in (1, 2):
            filename = f"shelf@{scale}x.png" if size[0] == 1920 else f"shelf-wide@{scale}x.png"
            top_shelf((size[0] * scale, size[1] * scale)).convert("RGB").save(os.path.join(folder, filename), optimize=True)
            entries.append({"filename": filename, "idiom": "tv", "scale": f"{scale}x"})
        write_json(os.path.join(folder, "Contents.json"), {"images": entries, "info": INFO})
    write_json(os.path.join(brand, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": INFO,
    })


if __name__ == "__main__":
    build_phone_icons()
    build_tv()
