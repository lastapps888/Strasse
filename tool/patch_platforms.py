#!/usr/bin/env python3
"""Applique la configuration Strasse aux projets Android et iOS générés par `flutter create`.

Idempotent : peut être relancé sans dupliquer les modifications.
Chaque modification qui ne trouve pas son motif affiche un AVERTISSEMENT avec la marche à suivre manuelle
(les gabarits de Flutter évoluent d'une version à l'autre).
"""
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
        for sub in ("AppIcon.appiconset", "LaunchImage.imageset"):
            target = os.path.join(xc, sub)
            os.makedirs(target, exist_ok=True)
            copy_tree(os.path.join("platform_assets/ios_assets", sub), target)
        print("Icônes et image de démarrage iOS copiées.")


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
    kts = "android/app/build.gradle.kts"
    groovy = "android/app/build.gradle"
    if os.path.exists(kts):
        patch_gradle_kts(kts)
    elif os.path.exists(groovy):
        patch_gradle_groovy(groovy)
    else:
        warn("build.gradle(.kts) introuvable : voir INSTALLATION.md (minSdk 24, desugaring, signature).")


def patch_gradle_kts(path):
    s = read(path)
    if "strasse-patched" in s:
        return
    # minSdk 24
    s, n = re.subn(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", s)
    if n == 0 and "minSdk = 24" not in s:
        warn("minSdk non modifié : définir minSdk = 24 dans android/app/build.gradle.kts.")
    # Desugaring (flutter_local_notifications)
    s, n = re.subn(r"(compileOptions\s*\{)", r"\1\n        isCoreLibraryDesugaringEnabled = true", s, count=1)
    if n == 0:
        warn("compileOptions introuvable : ajouter isCoreLibraryDesugaringEnabled = true.")
    if "coreLibraryDesugaring(" not in s:
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    # Signature de production via android/key.properties
    if "key.properties" not in s:
        header = (
            "import java.util.Properties\n\n"
            "val keystoreProperties = Properties().apply {\n"
            '    val f = rootProject.file("key.properties")\n'
            "    if (f.exists()) f.inputStream().use { load(it) }\n"
            "}\n\n"
        )
        s = header + s
        signing = (
            "    signingConfigs {\n"
            '        create("release") {\n'
            '            if (keystoreProperties.isNotEmpty()) {\n'
            '                keyAlias = keystoreProperties["keyAlias"] as String\n'
            '                keyPassword = keystoreProperties["keyPassword"] as String\n'
            '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
            '                storePassword = keystoreProperties["storePassword"] as String\n'
            "            }\n"
            "        }\n"
            "    }\n\n"
        )
        s, n = re.subn(r"(\n\s*buildTypes\s*\{)", "\n" + signing + r"    buildTypes {", s, count=1)
        if n == 0:
            warn("buildTypes introuvable : configurer la signature manuellement (INSTALLATION.md).")
        s, n = re.subn(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = if (keystoreProperties.isNotEmpty()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
            s,
        )
        if n == 0:
            warn("Ligne signingConfig de la release introuvable : la signature de production est à configurer manuellement.")
    s += "\n// strasse-patched\n"
    write(path, s)
    print("build.gradle.kts configuré (minSdk 24, desugaring, signature de production).")


def patch_gradle_groovy(path):
    s = read(path)
    if "strasse-patched" in s:
        return
    s, n = re.subn(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", s)
    if n == 0:
        s, n = re.subn(r"minSdk\s*=?\s*flutter\.minSdkVersion", "minSdk = 24", s)
    if n == 0:
        warn("minSdk non modifié : définir minSdkVersion 24 dans android/app/build.gradle.")
    s, n = re.subn(r"(compileOptions\s*\{)", r"\1\n        coreLibraryDesugaringEnabled true", s, count=1)
    if n == 0:
        warn("compileOptions introuvable : ajouter coreLibraryDesugaringEnabled true.")
    if "coreLibraryDesugaring '" not in s:
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    if "key.properties" not in s:
        header = (
            "def keystoreProperties = new Properties()\n"
            "def keystorePropertiesFile = rootProject.file('key.properties')\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
            "}\n\n"
        )
        s = header + s
        signing = (
            "    signingConfigs {\n"
            "        release {\n"
            "            keyAlias keystoreProperties['keyAlias']\n"
            "            keyPassword keystoreProperties['keyPassword']\n"
            "            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null\n"
            "            storePassword keystoreProperties['storePassword']\n"
            "        }\n"
            "    }\n\n"
        )
        s, n = re.subn(r"(\n\s*buildTypes\s*\{)", "\n" + signing + r"    buildTypes {", s, count=1)
        if n == 0:
            warn("buildTypes introuvable : configurer la signature manuellement (INSTALLATION.md).")
        s, n = re.subn(
            r"signingConfig\s+signingConfigs\.debug",
            "signingConfig keystoreProperties.isEmpty() ? signingConfigs.debug : signingConfigs.release",
            s,
        )
        if n == 0:
            warn("Ligne signingConfig de la release introuvable : signature de production à configurer manuellement.")
    s += "\n// strasse-patched\n"
    write(path, s)
    print("build.gradle configuré (minSdk 24, desugaring, signature de production).")


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
    write(path, s)
    print("Info.plist configuré (nom, permission de localisation en français, arrière-plan, chiffrement).")


def patch_podfile():
    path = "ios/Podfile"
    if not os.path.exists(path):
        return warn("Podfile introuvable.")
    s = read(path)
    s2, n = re.subn(r"^\s*#?\s*platform :ios, '[^']*'", "platform :ios, '13.0'", s, count=1, flags=re.M)
    if n == 0:
        s2 = "platform :ios, '13.0'\n" + s
    write(path, s2)
    print("Podfile : cible iOS 13.0.")


# ---------------------------------------------------------------- Divers
def remove_default_test():
    path = "test/widget_test.dart"
    if os.path.exists(path) and "MyApp" in read(path):
        os.remove(path)
        print("Test par défaut de flutter create supprimé.")


if __name__ == "__main__":
    patch_resources()
    if os.path.isdir("android"):
        patch_manifest()
        patch_gradle()
    if os.path.isdir("ios"):
        patch_info_plist()
        patch_podfile()
    remove_default_test()
    if WARNINGS:
        print(f"\n{len(WARNINGS)} avertissement(s) : voir INSTALLATION.md pour les étapes manuelles.")
        sys.exit(0)
    print("\nConfiguration des plateformes terminée.")
