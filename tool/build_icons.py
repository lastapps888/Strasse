#!/usr/bin/env python3
"""Intègre les 13 icônes fournies (PNG 1024x1024) dans l'application.

Les images originales ne sont jamais retouchées : elles sont copiées telles quelles dans assets/app_icons/ et
dans les jeux d'icônes iOS. Seules les tailles réduites exigées par Android (une par densité d'écran) et par
l'écran de démarrage sont produites par simple redimensionnement.

Usage : python3 tool/build_icons.py chemin/vers/le/dossier_des_png
"""
import os
import shutil
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# identifiant -> (fichier fourni, libellé affiché)
ICONS = [
    ("clair", "strasse_01_mode_clair.png", "Mode clair"),
    ("sombre", "strasse_02_mode_sombre.png", "Mode sombre"),
    ("arc_en_ciel", "strasse_03_arc_en_ciel.png", "Arc-en-ciel"),
    ("retro", "strasse_04_retro.png", "Rétro"),
    ("rouge", "strasse_05_rouge.png", "Rouge"),
    ("vert", "strasse_06_vert.png", "Vert"),
    ("bleu", "strasse_07_bleu.png", "Bleu"),
    ("violet", "strasse_08_violet.png", "Violet"),
    ("crepuscule", "strasse_09_crepuscule.png", "Crépuscule"),
    ("aurore", "strasse_10_aurore.png", "Aurore"),
    ("minimaliste", "strasse_11_minimaliste.png", "Minimaliste"),
    ("mignon", "strasse_12_mignon.png", "Mignon"),
    ("inverse", "strasse_13_inverse.png", "Inversé"),
]
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def resized(src, size, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    Image.open(src).convert("RGBA").resize((size, size), Image.LANCZOS).save(dst, optimize=True)


def main(src_dir):
    out_assets = os.path.join(ROOT, "assets/app_icons")
    shutil.rmtree(out_assets, ignore_errors=True)
    os.makedirs(out_assets)
    android = os.path.join(ROOT, "platform_assets/android_res")
    ios = os.path.join(ROOT, "platform_assets/ios_assets")

    # Anciennes ressources d'icône adaptative : elles masqueraient les PNG fournis sur Android 8+.
    for sub in os.listdir(android):
        d = os.path.join(android, sub)
        for name in os.listdir(d):
            if name.startswith("ic_launcher"):
                os.remove(os.path.join(d, name))
    for sub in list(os.listdir(android)):
        d = os.path.join(android, sub)
        if not os.listdir(d):
            os.rmdir(d)
    for f in os.listdir(ios + "/AppIcon.appiconset") if os.path.isdir(ios + "/AppIcon.appiconset") else []:
        pass
    shutil.rmtree(ios + "/AppIcon.appiconset", ignore_errors=True)
    for d in os.listdir(ios):
        if d.startswith("AppIcon-"):
            shutil.rmtree(os.path.join(ios, d))

    contents = '{\n  "images": [\n    {\n      "filename": "icon.png",\n      "idiom": "universal",\n      "platform": "ios",\n      "size": "1024x1024"\n    }\n  ],\n  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n'
    for ident, fname, _label in ICONS:
        src = os.path.join(src_dir, fname)
        shutil.copyfile(src, os.path.join(out_assets, ident + ".png"))
        set_dir = os.path.join(ios, "AppIcon.appiconset" if ident == "clair" else "AppIcon-" + ident + ".appiconset")
        os.makedirs(set_dir)
        shutil.copyfile(src, os.path.join(set_dir, "icon.png"))
        with open(os.path.join(set_dir, "Contents.json"), "w") as f:
            f.write(contents)
        for dens, px in DENSITIES.items():
            resized(src, px, os.path.join(android, "mipmap-" + dens, "ic_launcher_%s.png" % ident))
        if ident == "clair":
            for dens, px in DENSITIES.items():
                resized(src, px, os.path.join(android, "mipmap-" + dens, "ic_launcher.png"))
                resized(src, px, os.path.join(android, "mipmap-" + dens, "ic_launcher_round.png"))

    # Écrans de démarrage : même icône que l'application (clair par défaut, sombre en mode nuit).
    resized(os.path.join(src_dir, ICONS[0][1]), 512, os.path.join(android, "drawable-nodpi/splash_logo.png"))
    resized(os.path.join(src_dir, ICONS[1][1]), 512, os.path.join(android, "drawable-nodpi/splash_logo_dark.png"))
    launch = ios + "/LaunchImage.imageset"
    for suffix, px in (("", 128), ("@2x", 256), ("@3x", 384)):
        resized(os.path.join(src_dir, ICONS[0][1]), px, os.path.join(launch, "LaunchImage%s.png" % suffix))
    print("Icônes intégrées :", len(ICONS))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
