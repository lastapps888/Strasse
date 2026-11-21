#!/usr/bin/env python3
"""Applique la configuration Strasse aux projets Android et iOS générés par `flutter create`.

Idempotent : peut être relancé sans dupliquer les modifications.
Chaque modification qui ne trouve pas son motif affiche un AVERTISSEMENT avec la marche à suivre manuelle
(les gabarits de Flutter évoluent d'une version à l'autre).
"""
import glob
import os
import re
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(ROOT)
WARNINGS = []


def warn(msg):
    WARNINGS.append(msg)
    print("AVERTISSEMENT :", msg)


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def copy_tree(src, dst):
    for base, _dirs, files in os.walk(src):
        rel = os.path.relpath(base, src)
        target = os.path.join(dst, rel) if rel != "." else dst
        os.makedirs(target, exist_ok=True)
        for name in files:
            shutil.copy2(os.path.join(base, name), os.path.join(target, name))


# ---------------------------------------------------------------- Ressources (icônes, démarrage)
def patch_resources():
    res = "android/app/src/main/res"
    if os.path.isdir("android"):
        copy_tree("platform_assets/android_res", res)
        print("Icônes et écran de démarrage Android copiés.")
    xc = "ios/Runner/Assets.xcassets"
    if os.path.isdir(xc):
        subs = sorted(d for d in os.listdir("platform_assets/ios_assets") if d.endswith((".appiconset", ".imageset")))
        for sub in subs:
            target = os.path.join(xc, sub)
            os.makedirs(target, exist_ok=True)
            copy_tree(os.path.join("platform_assets/ios_assets", sub), target)
        print(f"Icônes iOS ({len(subs)} jeux, dont les icônes alternatives) et image de démarrage copiées.")


# ---------------------------------------------------------------- Code natif et icônes alternatives
def patch_native_android():
    """Manifeste complet (alias d'icônes, audio, retour d'authentification) et MainActivity.kt."""
    manifest = "android/app/src/main/AndroidManifest.xml"
    template = "platform_assets/native/AndroidManifest.xml"
    if os.path.exists(manifest) and os.path.exists(template) and "ALIAS_ICONES_DEBUT" not in read(manifest):
        shutil.copy2(template, manifest)
        print("AndroidManifest.xml remplacé par le modèle Strasse (alias d'icônes, audio, authentification).")
    kt = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
    src = "platform_assets/native/MainActivity.kt"
    if not kt or not os.path.exists(src):
        return warn("MainActivity.kt introuvable : copier platform_assets/native/MainActivity.kt à la main.")
    pkg = re.search(r"^package\s+([\w.]+)", read(kt[0]), re.M)
    code = read(src)
    if pkg:
        code = re.sub(r"^package\s+[\w.]+", "package " + pkg.group(1), code, count=1, flags=re.M)
    write(kt[0], code)
    print("MainActivity.kt copié (changement d'icône, musique locale).")


def patch_native_ios():
    """AppDelegate.swift et déclaration des icônes alternatives dans le projet Xcode."""
    src = "platform_assets/native/AppDelegate.swift"
    if os.path.isdir("ios/Runner") and os.path.exists(src):
        shutil.copy2(src, "ios/Runner/AppDelegate.swift")
        print("AppDelegate.swift copié (changement d'icône, MusicKit).")
    pbx = "ios/Runner.xcodeproj/project.pbxproj"
    if not os.path.exists(pbx):
        return warn("ios/Runner.xcodeproj/project.pbxproj introuvable : lancer `flutter create --platforms=ios .` (tool/ci_prepare.sh le fait), puis ce script.")
    names = sorted(
        d[:-len(".appiconset")]
        for d in os.listdir("platform_assets/ios_assets")
        if d.startswith("AppIcon-") and d.endswith(".appiconset")
    )
    s = read(pbx)
    if "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES" not in s:
        line = 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "%s";' % " ".join(names)
        s, n = re.subn(
            r"(\n(\s*)ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;)",
            lambda m: m.group(1) + "\n" + m.group(2) + line,
            s,
        )
        s, n2 = re.subn(
            r"(\n(\s*)ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = [^\n]*;)",
            lambda m: m.group(1) + "\n" + m.group(2) + "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;",
            s,
        )
        write(pbx, s)
        print(f"project.pbxproj : {len(names)} icônes alternatives déclarées dans {n} configuration(s).")
        if n == 0:
            warn("ASSETCATALOG_COMPILER_APPICON_NAME introuvable dans project.pbxproj : icônes alternatives non déclarées.")


# ---------------------------------------------------------------- Android
ANDROID_PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
]


def patch_manifest():
    path = "android/app/src/main/AndroidManifest.xml"
    if not os.path.exists(path):
        return warn("AndroidManifest.xml introuvable.")
    s = read(path)
    if "FOREGROUND_SERVICE_LOCATION" not in s:
        lines = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in ANDROID_PERMISSIONS)
        lines += '    <uses-feature android:name="android.hardware.location.gps" android:required="false"/>\n'
        s = re.sub(r"(<manifest[^>]*>\s*\n)", lambda m: m.group(1) + lines, s, count=1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="Strasse"', s, count=1)
    if "android:icon=" not in s:
        s = s.replace("<application", '<application\n        android:icon="@mipmap/ic_launcher"', 1)
    if "android:roundIcon=" not in s:
        s = s.replace("<application", '<application\n        android:roundIcon="@mipmap/ic_launcher_round"', 1)
    if "usesCleartextTraffic" not in s:
        s = s.replace("<application", '<application\n        android:usesCleartextTraffic="false"', 1)
    write(path, s)
    print("AndroidManifest.xml configuré (permissions, nom, icônes, HTTPS obligatoire).")


def patch_gradle():
    """Copie les fichiers Gradle de référence de Strasse (AGP 9.3.1, Gradle 9.5.0, Kotlin 2.4.10, compileSdk 36, Java 17).

    Ils remplacent entièrement ceux du gabarit de `flutter create` : leur structure change d'une version de Flutter à l'autre,
    et une modification par expressions régulières casserait à la première évolution. `local.properties` n'est jamais touché.
    """
    src = "platform_assets/android_gradle"
    if not os.path.isdir(src) or not os.path.isdir("android"):
        return warn("platform_assets/android_gradle ou android/ introuvable : configuration Gradle non appliquée.")
    mapping = {
        "settings.gradle.kts": "android/settings.gradle.kts",
        "build.gradle.kts": "android/build.gradle.kts",
        "app.build.gradle.kts": "android/app/build.gradle.kts",
        "gradle.properties": "android/gradle.properties",
        "gradle-wrapper.properties": "android/gradle/wrapper/gradle-wrapper.properties",
    }
    for name, dst in mapping.items():
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(src, name), dst)
    # Les anciens fichiers Groovy du gabarit ne doivent pas coexister avec les .kts.
    for old in ("android/build.gradle", "android/settings.gradle", "android/app/build.gradle"):
        if os.path.exists(old):
            os.remove(old)
    print("Fichiers Gradle de référence copiés (AGP 9.3.1, Gradle 9.5.0, Kotlin 2.4.10, compileSdk 36, Java 17).")


# ---------------------------------------------------------------- iOS
LOCATION_TEXT = (
    "Strasse utilise votre position pour afficher votre emplacement sur la carte, calculer des itinéraires "
    "et vous guider, y compris lorsque l'écran est verrouillé pendant une navigation. "
    "Votre position n'est jamais vendue ni envoyée à un serveur publicitaire."
)


def plist_set(s, key, value_xml):
    """Ajoute ou remplace une clé de premier niveau dans un Info.plist."""
    pattern = re.compile(r"<key>%s</key>\s*(<string>.*?</string>|<true/>|<false/>|<array>.*?</array>)" % re.escape(key), re.S)
    entry = f"<key>{key}</key>\n\t{value_xml}"
    if pattern.search(s):
        return pattern.sub(lambda _m: entry, s, count=1)
    return re.sub(r"</dict>\s*</plist>", lambda _m: f"\t{entry}\n</dict>\n</plist>", s, count=1)


def patch_info_plist():
    path = "ios/Runner/Info.plist"
    if not os.path.exists(path):
        return warn("Info.plist introuvable.")
    s = read(path)
    s = plist_set(s, "CFBundleDisplayName", "<string>Strasse</string>")
    s = plist_set(s, "CFBundleName", "<string>Strasse</string>")
    s = plist_set(s, "NSLocationWhenInUseUsageDescription", f"<string>{LOCATION_TEXT}</string>")
    s = plist_set(
        s,
        "UIBackgroundModes",
        "<array>\n\t\t<string>location</string>\n\t\t<string>audio</string>\n\t</array>",
    )
    s = plist_set(s, "ITSAppUsesNonExemptEncryption", "<false/>")
    s = plist_set(
        s,
        "NSAppleMusicUsageDescription",
        "<string>Strasse accède à votre bibliothèque Apple Music uniquement pour lire votre musique pendant le trajet. Rien n'est envoyé ailleurs.</string>",
    )
    s = plist_set(s, "LSApplicationQueriesSchemes", "<array>\n\t\t<string>spotify</string>\n\t\t<string>music</string>\n\t\t<string>deezer</string>\n\t</array>")
    # Cycle de vie UIScene (Flutter 3.38+) : indispensable à l'enregistrement des canaux natifs (voir AppDelegate.swift).
    if "UIApplicationSceneManifest" not in s and "_UIApplicationSceneManifest" not in s:
        scene = (
            "<dict>\n\t\t<key>UIApplicationSupportsMultipleScenes</key>\n\t\t<false/>\n\t\t<key>UISceneConfigurations</key>\n\t\t<dict>\n"
            "\t\t\t<key>UIWindowSceneSessionRoleApplication</key>\n\t\t\t<array>\n\t\t\t\t<dict>\n"
            "\t\t\t\t\t<key>UISceneClassName</key>\n\t\t\t\t\t<string>UIWindowScene</string>\n"
            "\t\t\t\t\t<key>UISceneDelegateClassName</key>\n\t\t\t\t\t<string>FlutterSceneDelegate</string>\n"
            "\t\t\t\t\t<key>UISceneConfigurationName</key>\n\t\t\t\t\t<string>flutter</string>\n"
            "\t\t\t\t\t<key>UISceneStoryboardFile</key>\n\t\t\t\t\t<string>Main</string>\n"
            "\t\t\t\t</dict>\n\t\t\t</array>\n\t\t</dict>\n\t</dict>"
        )
        s = plist_set(s, "UIApplicationSceneManifest", scene)
    write(path, s)
    print("Info.plist configuré (nom, permission de localisation en français, arrière-plan, chiffrement).")


def patch_podfile():
    path = "ios/Podfile"
    if not os.path.exists(path):
        return warn("Podfile introuvable.")
    s = read(path)
    s2, n = re.subn(r"^\s*#?\s*platform :ios, '[^']*'", "platform :ios, '14.0'", s, count=1, flags=re.M)
    if n == 0:
        s2 = "platform :ios, '14.0'\n" + s
    write(path, s2)

    # file_picker >=12 exige iOS 14 : aligner aussi la cible de l'application générée.
    pbx = "ios/Runner.xcodeproj/project.pbxproj"
    if os.path.exists(pbx):
        project = read(pbx)
        project, count = re.subn(
            r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;",
            "IPHONEOS_DEPLOYMENT_TARGET = 14.0;",
            project,
        )
        if count:
            write(pbx, project)
            print(f"project.pbxproj : cible iOS 14.0 appliquée ({count} réglages).")
        else:
            warn("IPHONEOS_DEPLOYMENT_TARGET introuvable dans project.pbxproj : définir manuellement la cible iOS 14.0.")
    else:
        warn("project.pbxproj absent : la cible iOS 14.0 devra être vérifiée après génération du projet Xcode.")

    framework = "ios/Flutter/AppFrameworkInfo.plist"
    if os.path.exists(framework):
        info = read(framework)
        info, count = re.subn(
            r"(<key>MinimumOSVersion</key>\\s*<string>)[^<]+(</string>)",
            r"\\g<1>14.0\\g<2>",
            info,
            count=1,
        )
        if count:
            write(framework, info)
        else:
            warn("MinimumOSVersion introuvable dans AppFrameworkInfo.plist : vérifier manuellement la cible iOS 14.0.")
    else:
        warn("AppFrameworkInfo.plist introuvable : vérifier manuellement la cible iOS 14.0.")

    print("Cible iOS 14.0 appliquée au Podfile et aux réglages natifs.")


# ---------------------------------------------------------------- Divers
def remove_default_test():
    path = "test/widget_test.dart"
    if os.path.exists(path) and "MyApp" in read(path):
        os.remove(path)
        print("Test par défaut de flutter create supprimé.")


if __name__ == "__main__":
    patch_resources()
    if os.path.isdir("android"):
        patch_native_android()
        patch_manifest()
        patch_gradle()
    if os.path.isdir("ios"):
        patch_native_ios()
        patch_info_plist()
        patch_podfile()
    remove_default_test()
    if WARNINGS:
        print(f"\n{len(WARNINGS)} avertissement(s) : voir INSTALLATION.md pour les étapes manuelles.")
        sys.exit(0)
    print("\nConfiguration des plateformes terminée.")
