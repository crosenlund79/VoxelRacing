#!/usr/bin/env python3
"""Builds docs/ARTWORK_MASTER_LIST.md and the reference sheets docs/artwork/sheet_*.png
from the artwork catalogue (AssetCatalog.SPECS, dumped by dump_catalog.gd).

    godot --headless --path . -s docs/artwork/dump_catalog.gd -- /tmp/catalog.json
    python3 docs/artwork/make_reference.py /tmp/catalog.json

Documentation only: the sheets are never loaded by the game (docs/.gdignore).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "docs", "artwork")
FONT = os.path.join(ROOT, "assets", "fonts", "Fredoka.ttf")

ENVIRONMENTS = {"variant_2": "Wasteland", "variant_3": "Winter", "variant_4": "The Raceway",
                "variant_5": "Tabletop Mayhem"}

GROUPS = [
    ("vehicles", "Vehicles", "Cars: one wheel-free body per car plus the shared wheel. Draw these."),
    ("legacy", "Vehicles - legacy flattened cars", "Older format with wheels painted in, kept only so your older drawings keep working (used when no body drawing exists). There is no packaged picture for these names. Do not draw them for new art."),
    ("weapons", "Weapons and effects", "Projectiles, mines, explosions, smoke, dust, sparks, confetti, tyre marks."),
    ("track", "Track and shared scenery (Green Valley and every circuit)", "Road, grass, barriers, start line, pit sign, decals, trees, lamps, grandstands."),
    ("environments", "Environments", "Per-environment replacements (Green Valley uses the shared set above)."),
    ("ui", "Interface", "Logo, menus, HUD, garage, kill-feed and ranking icons, achievements."),
]


def group_of(logical):
    if logical.startswith("cars/car_"):
        return "legacy"
    if logical.startswith("cars/"):
        return "vehicles"
    if logical.startswith("variant_"):
        return "environments"
    if logical.startswith(("weapons/", "fx/")) or logical == "decals/tire_mark":
        return "weapons"
    if logical.startswith("ui/") or logical == "logo":
        return "ui"
    return "track"


def transparency(logical):
    base = logical.split("/")[-1]
    if base in ("grass", "tarmac"):
        return "opaque, seamless tile (edges must repeat)"
    if base == "garage_backdrop":
        return "opaque (full background)"
    if base in ("hud_panel", "button"):
        return "nine-patch: corners kept, middle stretched (24 px margins)"
    return "transparent background"


def orientation(logical, notes):
    base = logical.split("/")[-1]
    if logical.startswith("cars/"):
        return "top-down, nose pointing right (+X), car centred"
    if base in ("missile", "homing_missile", "super_missile"):
        return "top-down, nose pointing right (+X)"
    if base in ("wall", "kerb"):
        return "horizontal strip that repeats left-right"
    if base == "start_line":
        return "long side = across the road"
    if base in ("grass", "tarmac"):
        return "any (repeating tile)"
    if base == "tire_mark":
        return "mark runs top to bottom (along the car)"
    return "top-down / as seen on screen"


def status(logical, entry):
    if logical.startswith("cars/car_"):
        return "legacy"
    return "primary"


def size_text(v):
    return "%d x %d" % (v[0], v[1]) if v else "-"


def font(size):
    return ImageFont.truetype(FONT, size)


def checker(w, h, cell=8):
    img = Image.new("RGBA", (w, h), (200, 200, 200, 255))
    d = ImageDraw.Draw(img)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if (x // cell + y // cell) % 2:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(170, 170, 170, 255))
    return img


def sheet(name, title, entries, catalog):
    tile_w, tile_h, box_w, box_h = 250, 196, 230, 118
    cols = 5
    rows = (len(entries) + cols - 1) // cols
    head = 70
    img = Image.new("RGBA", (cols * tile_w + 20, head + rows * tile_h + 10), (46, 40, 36, 255))
    d = ImageDraw.Draw(img)
    d.text((14, 12), title, font=font(28), fill=(243, 232, 207, 255))
    d.text((14, 46), "HyperCars artwork reference - actual images in use, with their logical names", font=font(15), fill=(200, 190, 170, 255))
    for i, logical in enumerate(entries):
        e = catalog[logical]
        x0 = 10 + (i % cols) * tile_w
        y0 = head + (i // cols) * tile_h
        d.rounded_rectangle([x0, y0, x0 + tile_w - 10, y0 + tile_h - 10], 10, fill=(70, 62, 56, 255))
        path = os.path.join(ROOT, e["user_drawing"] or e["template"])
        art = Image.open(path).convert("RGBA")
        scale = min(box_w / art.width, box_h / art.height, 6.0)
        tw, th = max(1, int(art.width * scale)), max(1, int(art.height * scale))
        thumb = art.resize((tw, th), Image.LANCZOS if scale < 1.0 else Image.NEAREST)
        bg = checker(box_w, box_h)
        bx, by = x0 + 5, y0 + 6
        img.alpha_composite(bg, (bx, by))
        img.alpha_composite(thumb, (bx + (box_w - tw) // 2, by + (box_h - th) // 2))
        d.text((x0 + 8, y0 + 128), logical, font=font(14), fill=(243, 232, 207, 255))
        info = "%s px" % size_text(e["template_size"])
        if e["frames"] > 1:
            info += ", %d frames" % e["frames"]
        d.text((x0 + 8, y0 + 148), info, font=font(12), fill=(200, 190, 170, 255))
        tag, colour = "", None
        if logical.startswith("cars/car_"):
            tag, colour = "LEGACY - not needed", (230, 110, 90, 255)
        elif e["user_drawing"]:
            tag, colour = "YOUR DRAWING IN USE", (130, 220, 120, 255)
        if tag:
            d.text((x0 + 8, y0 + 165), tag, font=font(12), fill=colour)
    out = os.path.join(OUT_DIR, "sheet_%s.png" % name)
    img.convert("RGB").save(out)
    return os.path.relpath(out, os.path.join(ROOT, "docs"))


def main():
    catalog = json.load(open(sys.argv[1]))
    groups = {g[0]: [] for g in GROUPS}
    for logical in catalog:
        groups[group_of(logical)].append(logical)
    groups["vehicles"].sort(key=lambda k: (k != "cars/wheel", k))
    primary = sum(1 for k in catalog if status(k, catalog[k]) == "primary")
    legacy = len(catalog) - primary
    drawn = [k for k in catalog if catalog[k]["user_drawing"]]
    lines = [
        "# HyperCars artwork master list",
        "",
        "Everything in the game that can be drawn, in one place: what each picture is, where",
        "it goes, how big, and which way up. Generated from the game's own artwork catalogue",
        "(`src/assets/asset_catalog.gd`) by `docs/artwork/make_reference.py`, so it is always",
        "the complete list. Technical contract: `assets/README.md`, `docs/ASSET_SPECS.md`.",
        "",
        "**%d images to draw** (primary, each with a packaged `template_` picture), plus **%d"
        " legacy flattened-car names** you do not need (your older drawings only, no packaged picture):"
        " %d catalogued names in total. Your own drawings already in use: %d." % (primary, legacy, len(catalog), len(drawn)),
        "",
        "## How to replace a picture",
        "",
        "The game looks for each picture in this order (graphics):",
        "",
        "1. `custom/graphics/<name>.png`: your override;",
        "2. `assets/graphics/<name>.png`: your drawing added to the project under the",
        "   plain name;",
        "3. `assets/graphics/<folder>/template_<name>.png`: Claude's template, only the",
        "   fallback.",
        "",
        "`template_` files are never your files and are only used where you have not drawn",
        "something. Files without the prefix (in `custom/` or `assets/`) are yours.",
        "**Settings > ORIGINAL TEMPLATE ARTWORK** (the Artwork Mode, applied at the next",
        "start) shows only the templates, to compare; switch it off to see your drawings",
        "again. Music and voices are not affected.",
        "",
        "Pick one of two places; restart the game to see it.",
        "",
        "1. **`custom/graphics/<name>.png`**: in the project's `custom/` folder while",
        "   developing, or next to the exported Windows / Linux game. This always wins and",
        "   needs no rebuild.",
        "2. **`assets/graphics/<name>.png`**: your drawing added to the project under the",
        "   plain name (no `template_` prefix). It replaces Claude's `template_` picture in",
        "   the packaged game.",
        "",
        "**Rules:**",
        "- Any resolution works if it keeps the template's **shape** (aspect ratio) and",
        "  orientation. Drawing at 2x or 4x the template size is recommended; the game",
        "  scales it to the display size.",
        "- A missing or broken file falls back to the template.",
        "- Claude never edits your files.",
        "",
        "## Cars: draw each car once",
        "",
        "- **What to draw:** one **wheel-free body** per car (`cars/body_*`) and one shared",
        "  **wheel** (`cars/wheel`). The game adds four wheels to every car: they steer up to",
        "  ±30° in races, the tread rolls as the car drives (the game scrolls your one wheel",
        "  drawing inside its outline: a tread that repeats along X rolls best), and the same",
        "  four are composed into every picture of the car (title",
        "  backdrop, standings, results, championship rewards, Nemesis Welcome, arena scrap",
        "  piles). A car drawn once looks the same everywhere.",
        "- **The body:**",
        "  - nose pointing right (+X), centred (the image centre is the car's pivot);",
        "  - no wheels painted in;",
        "  - leave the wheel areas transparent, or let the body edge cover their inner half",
        "    as the templates do.",
        "- **Night lights need nothing painted:** the game places two headlights and two",
        "  red lights a little in from the corners of the car outline (front at +X). Painted",
        "  lamps are decoration only. The one thing that matters is the nose direction: a",
        "  drawing with its nose to the left looks as if it drives backwards, with the",
        "  headlights at its painted tail ([night_lights_before_after.jpg](artwork/night_lights_before_after.jpg),",
        "  last row).",
        "- **Wheel positions** (display px from the car centre): front axle +16.5, rear",
        "  axle −16.5, wheels ±10.5 sideways (mostly under the body, about 2 px of tyre showing).",
        "  For a differently shaped body, set its own",
        "  points in `src/presentation/default_wheel_layout.tres` (`per_car`).",
        "- **Which artwork wins** (the same on every screen):",
        "  1. your body drawing (with wheels);",
        "  2. your older flattened `car_*` drawing (used as it is, never with extra wheels);",
        "  3. Claude's body template (with wheels).",
        "- **Legacy names:** `cars/car_*` exist only so older flattened drawings keep",
        "  working. There is no packaged picture for them: every packaged car is a",
        "  wheel-free body plus the shared wheel.",
        "",
        "Proof that one drawing shows everywhere: [acceptance_car_art.png](artwork/acceptance_car_art.png)",
        "(the real game with test drawings in a scratch override folder):",
        "",
        "- a green 77 player body in the race, the title, the standings and the",
        "  championship / results pictures;",
        "- a legacy flattened car with no extra wheels;",
        "- both files present (the body wins);",
        "- a custom body for Hank;",
        "- a won car and the junker;",
        "- the packaged default restored when the override is removed.",
        "",
    ]
    for key, title, blurb in GROUPS:
        entries = groups[key]
        if not entries:
            continue
        if any(catalog[k]["template"] or catalog[k]["user_drawing"] for k in entries):
            rel = sheet(key, title, entries, catalog)
            lines += ["## %s" % title, "", blurb + " Reference sheet: [%s](%s)" % (rel.split("/")[-1], rel), ""]
        else:
            lines += ["## %s" % title, "", blurb, ""]
        lines += ["| Name | What it is / where it appears | Template (px) | Shown at (world px) | Frames | Orientation | Background | Status | Packaged template | Your replacement |",
                  "|---|---|---|---|---|---|---|---|---|---|"]
        for logical in entries:
            e = catalog[logical]
            env = ENVIRONMENTS.get(logical.split("/")[0], "")
            what = (("**%s:** " % env) if env else "") + e["notes"].replace("|", "/")
            st = status(logical, e)
            if e["user_drawing"]:
                st += "; your drawing in use (`%s`)" % e["user_drawing"]
            lines.append("| `%s` | %s | %s | %s | %s | %s | %s | %s | `%s` | `custom/graphics/%s.png` |" % (
                logical, what, size_text(e["template_size"]), size_text(e["display_size"]),
                e["frames"] if e["frames"] > 1 else "1", orientation(logical, e["notes"]), transparency(logical),
                st, e["template"] or "(none)", logical))
        lines.append("")
    lines += [
        "## Drawn by the game itself (no picture to replace yet)",
        "",
        "These are deliberately drawn in code: shading, light, paint lines and effects that",
        "follow the track geometry. Larger optional artwork opportunities are listed in",
        "`docs/BACKLOG.md`.",
        "",
        "| Visual | Where | Why code |",
        "|---|---|---|",
        "| Pit lane paint: bay frames (gold / red when occupied), PIT 1-3 numbers, limiter lines, \"PIT\" lettering | every pit lane | follow the lane geometry; colours show bay occupancy |",
        "| Divider island fill (its edges use the barrier picture) | pit lanes, split sections | follows the divider shape |",
        "| Bridge shadow and deck shading; jump ramp / ravine shading | elevated crossings, jumps | shading over the tarmac and grass pictures |",
        "| Battle Royale yard floor tint, concrete blocks, hazard stripes, scrap-pile base | the Scrapyard arena | flat shapes; the scrap cars on the piles are the junker picture, the yard uses the environment's grass / tarmac / wall |",
        "| Danger-zone ring | Battle Royale | animated effect |",
        "| Night lighting: ambient tint, lamp and headlight beams, brake lights, high beams, explosion flashes | night races | light, not pictures (the lamp post itself is a picture) |",
        "| Rain and snow | Wasteland, Winter | particles |",
        "| Missile trails, mine pulse, damage smoke / wreck tint | races | effects (smoke puffs use the smoke picture; the damage wear itself is the replaceable `fx/car_wear` picture) |",
        "| Player marker chevron (P1 gold, P2 blue) | above your car | UI marker |",
        "| Rotating circuit preview diorama | GO RACING! setup screen | drawn from the real circuit geometry |",
        "| Rotating Scrapyard diorama (walls, scrap pile, blocks, barriers, tyre posts, stands, lamps) | Battle Royale setup screen | drawn from the real arena geometry (ArenaLayout) |",
        "| Victory trophy and podium steps | the career's ending | drawn shapes (optional future pictures: see the backlog) |",
        "| Garage spotlight under the car, shop pulses and money pop-ups | the garage | light and motion, not pictures (the car is its CarArt picture) |",
        "| Milestone cards, race introduction card, pause menu shade, accent rules | career and races | panels from the HUD panel / button pictures plus text |",
        "| Panels, text, bars (standings, results, garage, Nemesis Welcome) | menus and HUD | theme with the `ui/hud_panel` / `ui/button` pictures and the Fredoka font |",
        "",
    ]
    out = os.path.join(ROOT, "docs", "ARTWORK_MASTER_LIST.md")
    open(out, "w").write("\n".join(lines))
    print("wrote", out, "primary", primary, "legacy", legacy, "drawn", len(drawn))


if __name__ == "__main__":
    main()
