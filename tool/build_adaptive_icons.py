#!/usr/bin/env python3
"""Produit les icônes adaptatives Android (Android 8+) à partir des 13 icônes PNG de assets/app_icons/.

Problème corrigé : les PNG fournis sont des carrés aux coins arrondis posés sur un fond BLANC. Utilisés tels quels comme
icône d'application, Android les place dans son masque (rond, squircle…) avec une bordure blanche. Ici :
  - le fond blanc des coins est exclu (on ne garde que le centre de l'illustration) ;
  - l'illustration remplit toute la zone visible du masque (72 dp sur 108 dp) ;
  - la couche d'arrière-plan prolonge les couleurs de l'illustration (flou), la couche d'avant-plan porte l'illustration ;
  - une couche monochrome (icônes thématiques d'Android 13+) reprend la silhouette du S.
Les PNG « legacy » (Android 7 et moins) reçoivent des coins transparents au lieu du blanc.

Usage : python3 tool/build_adaptive_icons.py     (écrit dans platform_assets/android_res puis android/app/src/main/res)
"""
import os
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
IDS = ["clair", "sombre", "arc_en_ciel", "retro", "rouge", "vert", "bleu", "violet", "crepuscule", "aurore", "minimaliste", "mignon", "inverse"]
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
LAYER = 432          # 108 dp à xxxhdpi
ART = 304            # 76 dp : l'illustration, légèrement plus grande que la zone visible (72 dp)
CROP = 0.84          # part centrale conservée de l'illustration (exclut les coins blancs)


def central_crop(im):
    w, h = im.size
    c = int(w * CROP)
    x0, y0 = (w - c) // 2, (h - c) // 2
    return im.crop((x0, y0, x0 + c, y0 + c))


def feather_mask(size, margin):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rectangle((margin, margin, size - margin, size - margin), fill=255)
    return m.filter(ImageFilter.GaussianBlur(margin / 2))


def layers(src):
    art = central_crop(src.convert("RGB"))
    # Arrière-plan : l'illustration agrandie et très floue (mêmes couleurs que l'avant-plan, sans motif).
    bg = art.resize((LAYER, LAYER), Image.LANCZOS).filter(ImageFilter.GaussianBlur(40))
    # Avant-plan : l'illustration nette au centre, bord adouci (invisible hors de la zone visible du masque).
    fg = Image.new("RGBA", (LAYER, LAYER), (0, 0, 0, 0))
    a = art.resize((ART, ART), Image.LANCZOS).convert("RGBA")
    off = (LAYER - ART) // 2
    mask = feather_mask(ART, 6)
    fg.paste(a, (off, off), mask)
    return bg, fg


def legacy(src, size, round_):
    im = src.convert("RGBA")
    w = im.width
    inset = int(w * 0.012)
    im = im.crop((inset, inset, w - inset, w - inset))
    w = im.width
    mask = Image.new("L", (w * 2, w * 2), 0)
    d = ImageDraw.Draw(mask)
    if round_:
        d.ellipse((int(w * 0.07), int(w * 0.07), int(w * 2 - w * 0.07), int(w * 2 - w * 0.07)), fill=255)
    else:
        d.rounded_rectangle((0, 0, w * 2 - 1, w * 2 - 1), radius=int(w * 2 * 0.225), fill=255)
    mask = mask.resize((w, w), Image.LANCZOS)
    im.putalpha(mask)
    return im.resize((size, size), Image.LANCZOS)


def mono():
    svg = os.path.join(ROOT, "assets/logo/strasse_monochrome.svg")
    tmp = os.path.join(ROOT, "build_mono_tmp.png")
    subprocess.run(["rsvg-convert", "-w", "288", "-h", "288", svg, "-o", tmp], check=True)
    g = Image.open(tmp).convert("RGBA")
    os.remove(tmp)
    # Toute pixel non transparent devient noir opaque (Android applique sa propre teinte).
    r, gch, b, a = g.split()
    black = Image.new("RGBA", g.size, (0, 0, 0, 255))
    black.putalpha(a)
    out = Image.new("RGBA", (LAYER, LAYER), (0, 0, 0, 0))
    out.paste(black, ((LAYER - 288) // 2, (LAYER - 288) // 2), black)
    return out


XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_bg_%(i)s"/>
    <foreground android:drawable="@drawable/ic_fg_%(i)s"/>
    <monochrome android:drawable="@drawable/ic_mono"/>
</adaptive-icon>
"""


def main():
    targets = [os.path.join(ROOT, "platform_assets/android_res"), os.path.join(ROOT, "android/app/src/main/res")]
    mono_img = mono()
    for res in targets:
        os.makedirs(res, exist_ok=True)
        os.makedirs(os.path.join(res, "drawable-nodpi"), exist_ok=True)
        os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
        mono_img.save(os.path.join(res, "drawable-nodpi/ic_mono.png"), optimize=True)
    for ident in IDS:
        src = Image.open(os.path.join(ROOT, "assets/app_icons", ident + ".png"))
        bg, fg = layers(src)
        for res in targets:
            bg.save(os.path.join(res, "drawable-nodpi/ic_bg_%s.png" % ident), optimize=True)
            fg.save(os.path.join(res, "drawable-nodpi/ic_fg_%s.png" % ident), optimize=True)
            names = ["ic_launcher_" + ident]
            if ident == "clair":
                names += ["ic_launcher", "ic_launcher_round"]
            for n in names:
                with open(os.path.join(res, "mipmap-anydpi-v26", n + ".xml"), "w") as f:
                    f.write(XML % {"i": ident})
            for dens, px in DENSITIES.items():
                d = os.path.join(res, "mipmap-" + dens)
                os.makedirs(d, exist_ok=True)
                legacy(src, px, False).save(os.path.join(d, "ic_launcher_%s.png" % ident), optimize=True)
                if ident == "clair":
                    legacy(src, px, False).save(os.path.join(d, "ic_launcher.png"), optimize=True)
                    legacy(src, px, True).save(os.path.join(d, "ic_launcher_round.png"), optimize=True)
    print("Icônes adaptatives générées :", len(IDS))


if __name__ == "__main__":
    main()
