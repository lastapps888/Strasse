#!/usr/bin/env python3
"""Génère les fichiers SVG du logo Strasse.

Concept : un carré, un grand « S » gris qui est en réalité une route vue de
dessus. À gauche de la route, la campagne (vert, rangées de champs) ; à droite,
la mer (bleu, vagues). La route sépare les deux environnements et les relie.

La ligne centrale de la route est une période de sinusoïde verticale à bols
« arrondis » (exposant < 1) : elle se lit comme un S et traverse le carré de haut
en bas, ce qui permet de colorer proprement la gauche en vert et la droite en
bleu sans simple juxtaposition de deux rectangles.

Usage : python3 tool/generate_logo.py
Sortie : assets/logo/*.svg
Les mêmes constantes géométriques sont reprises dans
lib/core/widgets/strasse_logo.dart (CustomPainter) : en cas de modification,
mettre à jour les deux endroits.
"""
import math
import os

W = 1024
AMPLITUDE = 215.0     # écart horizontal maximal de la route
EXPONENT = 0.82       # < 1 : bols plus pleins, S plus lisible
ROAD_WIDTH = 150.0
SHOULDER_WIDTH = 170.0
OVERSHOOT = 40        # la route dépasse du carré (haut et bas)
STEPS = 260

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "logo")


def centerline(y0=-OVERSHOOT, y1=W + OVERSHOOT, steps=STEPS, amp=AMPLITUDE, cx=512.0):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        y = y0 + (y1 - y0) * t
        s = math.sin(2 * math.pi * t)
        x = cx - amp * math.copysign(abs(s) ** EXPONENT, s)
        pts.append((x, y))
    return pts


def path_d(pts, dx=0.0):
    return "M" + " L".join(f"{x + dx:.1f},{y:.1f}" for x, y in pts)


def region_left(pts):
    return path_d(pts) + f" L0,{W + OVERSHOOT} L0,{-OVERSHOOT} Z"


def region_right(pts):
    return path_d(pts) + f" L{W},{W + OVERSHOOT} L{W},{-OVERSHOOT} Z"


PALETTES = {
    "light": dict(
        green="#7DB251", green_hi="#A3CC62", green_lo="#5A9C48",
        blue="#4B98CC", blue_hi="#A9D3EE",
        shoulder="#4A4F57", road="#707680", marking="#FFFFFF", edge="#F4F6F8",
        frame="#FFFFFF",
    ),
    "dark": dict(
        green="#4F8A45", green_hi="#6CA555", green_lo="#3E7339",
        blue="#2F6FA6", blue_hi="#6FA8D2",
        shoulder="#1B1F25", road="#7A828E", marking="#EEF1F4", edge="#D5DAE0",
        frame="#1B2029",
    ),
}


def build_logo(palette, rounded=True, keyline=None, with_background=True, framed=True):
    p = PALETTES[palette]
    pts = centerline()
    d = path_d(pts)
    clip_shape = (
        f'<rect width="{W}" height="{W}" rx="230" ry="230"/>' if rounded
        else f'<rect width="{W}" height="{W}"/>'
    )
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">',
        "<title>Strasse</title>",
        "<defs>",
        f'<clipPath id="card">{clip_shape}</clipPath>',
        f'<clipPath id="left"><path d="{region_left(pts)}"/></clipPath>',
        f'<clipPath id="right"><path d="{region_right(pts)}"/></clipPath>',
        "</defs>",
        '<g clip-path="url(#card)">',
    ]
    if with_background:
        # Campagne (gauche) : fond vert + rangées de champs parallèles à la route.
        parts.append(f'<path d="{region_left(pts)}" fill="{p["green"]}"/>')
        parts.append('<g clip-path="url(#left)" fill="none" stroke-linejoin="round">')
        for dx, w, col in ((-215, 64, p["green_hi"]), (-345, 64, p["green_lo"]), (-475, 64, p["green_hi"])):
            parts.append(f'<path d="{path_d(pts, dx)}" stroke="{col}" stroke-width="{w}"/>')
        parts.append("</g>")
        # Mer (droite) : fond bleu + vagues fines.
        parts.append(f'<path d="{region_right(pts)}" fill="{p["blue"]}"/>')
        parts.append('<g clip-path="url(#right)" fill="none" stroke-linejoin="round" stroke-linecap="round">')
        for dx in (215, 305, 395, 485):
            parts.append(
                f'<path d="{path_d(pts, dx)}" stroke="{p["blue_hi"]}" stroke-width="12" opacity="0.65"/>'
            )
        parts.append("</g>")
    # Route : accotement sombre, bitume gris, marquage central discret.
    parts.append(
        f'<path d="{d}" fill="none" stroke="{p["shoulder"]}" stroke-width="{SHOULDER_WIDTH}" stroke-linejoin="round"/>'
    )
    parts.append(
        f'<path d="{d}" fill="none" stroke="{p["edge"]}" stroke-width="{ROAD_WIDTH + 14}" stroke-linejoin="round"/>'
    )
    parts.append(
        f'<path d="{d}" fill="none" stroke="{p["road"]}" stroke-width="{ROAD_WIDTH - 12}" stroke-linejoin="round"/>'
    )
    parts.append(
        f'<path d="{d}" fill="none" stroke="{p["marking"]}" stroke-width="9" '
        f'stroke-dasharray="44 36" stroke-linejoin="round"/>'
    )
    parts.append("</g>")
    if rounded and framed:
        # Cadre blanc (clair) ou ardoise (sombre) arrondi, comme sur la maquette.
        parts.append(
            f'<rect x="14" y="14" width="{W - 28}" height="{W - 28}" rx="216" ry="216" fill="none" '
            f'stroke="{p["frame"]}" stroke-width="28"/>'
        )
    if keyline:
        parts.append(
            f'<rect x="3" y="3" width="{W - 6}" height="{W - 6}" rx="227" ry="227" fill="none" '
            f'stroke="{keyline}" stroke-width="6"/>'
        )
    parts.append("</svg>")
    return "\n".join(parts)


def build_foreground():
    """Calque avant d'icône adaptative Android : la route seule, fond transparent."""
    p = PALETTES["light"]
    pts = centerline()
    d = path_d(pts)
    return "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">',
        f'<path d="{d}" fill="none" stroke="{p["shoulder"]}" stroke-width="{SHOULDER_WIDTH}" stroke-linejoin="round"/>',
        f'<path d="{d}" fill="none" stroke="{p["edge"]}" stroke-width="{ROAD_WIDTH + 14}" stroke-linejoin="round"/>',
        f'<path d="{d}" fill="none" stroke="{p["road"]}" stroke-width="{ROAD_WIDTH - 12}" stroke-linejoin="round"/>',
        f'<path d="{d}" fill="none" stroke="{p["marking"]}" stroke-width="9" stroke-dasharray="44 36" stroke-linejoin="round"/>',
        "</svg>",
    ])


def build_adaptive_background():
    """Calque arrière d'icône adaptative : vert à gauche, bleu à droite, sans route."""
    s = build_logo("light", rounded=False, framed=False)
    # On retire la route (dernier groupe de 3 tracés) pour ne garder que les deux environnements.
    lines = s.split("\n")
    keep = [ln for ln in lines if f'stroke-width="{SHOULDER_WIDTH}"' not in ln
            and f'stroke-width="{ROAD_WIDTH + 14}"' not in ln
            and f'stroke-width="{ROAD_WIDTH - 12}"' not in ln
            and 'stroke-dasharray="44 36"' not in ln]
    return "\n".join(keep)


def build_monochrome():
    """Silhouette monochrome (noir) : la route en S seule, contenue dans la zone sûre."""
    pts = centerline(y0=200, y1=824, amp=190.0)
    d = path_d(pts)
    return "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">',
        f'<path d="{d}" fill="none" stroke="#000000" stroke-width="{ROAD_WIDTH}" stroke-linecap="round" stroke-linejoin="round"/>',
        f'<path d="{d}" fill="none" stroke="#FFFFFF" stroke-width="9" stroke-dasharray="44 36" stroke-linejoin="round" '
        f'style="mix-blend-mode:normal" opacity="0"/>',
        "</svg>",
    ])


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    files = {
        "strasse_logo.svg": build_logo("light"),
        "strasse_logo_light.svg": build_logo("light", keyline="#D9DDE3"),
        "strasse_logo_dark.svg": build_logo("dark"),
        "strasse_icon_full_bleed.svg": build_logo("light", rounded=False, framed=False),
        "strasse_icon_full_bleed_dark.svg": build_logo("dark", rounded=False, framed=False),
        "strasse_adaptive_foreground.svg": build_foreground(),
        "strasse_adaptive_background.svg": build_adaptive_background(),
        "strasse_monochrome.svg": build_monochrome(),
        "strasse_splash.svg": build_logo("light"),
        "strasse_splash_dark.svg": build_logo("dark"),
    }
    for name, content in files.items():
        with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8") as f:
            f.write(content)
        print("écrit", name)


if __name__ == "__main__":
    main()
