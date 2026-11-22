import os
import tempfile
import unittest
from pathlib import Path

import patch_platforms


class PatchNativeIosTests(unittest.TestCase):
    def setUp(self):
        self.original_cwd = os.getcwd()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        os.chdir(self.root)
        patch_platforms.WARNINGS.clear()

        icons = self.root / "platform_assets" / "ios_assets"
        (icons / "AppIcon-bleu.appiconset").mkdir(parents=True)
        (icons / "AppIcon-sombre.appiconset").mkdir(parents=True)

        project = self.root / "ios" / "Runner.xcodeproj"
        project.mkdir(parents=True)
        self.pbx = project / "project.pbxproj"

    def tearDown(self):
        os.chdir(self.original_cwd)
        self.temp_dir.cleanup()

    def test_adds_alternate_icon_names_and_includes_assets_to_every_configuration(self):
        self.pbx.write_text(
            """BuildSettingsRelease = {
    ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
};
BuildSettingsDebug = {
    ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
};
""",
            encoding="utf-8",
        )

        patch_platforms.patch_native_ios()
        generated = self.pbx.read_text(encoding="utf-8")

        self.assertEqual(
            generated.count(
                'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIcon-bleu AppIcon-sombre";'
            ),
            2,
        )
        self.assertEqual(
            generated.count("ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;"),
            2,
        )

    def test_repairs_existing_alternate_icon_names_without_duplicating_settings(self):
        self.pbx.write_text(
            """BuildSettingsRelease = {
    ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "OldIcon";
};
""",
            encoding="utf-8",
        )

        patch_platforms.patch_native_ios()
        patch_platforms.patch_native_ios()
        generated = self.pbx.read_text(encoding="utf-8")

        self.assertEqual(
            generated.count(
                'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIcon-bleu AppIcon-sombre";'
            ),
            1,
        )
        self.assertEqual(
            generated.count("ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;"),
            1,
        )
        self.assertNotIn("OldIcon", generated)



class PatchIosDeploymentTargetTests(unittest.TestCase):
    def setUp(self):
        self.original_cwd = os.getcwd()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        os.chdir(self.root)
        patch_platforms.WARNINGS.clear()

        ios = self.root / "ios"
        ios.mkdir()
        (ios / "Podfile").write_text("platform :ios, '14.0'\n", encoding="utf-8")

        project = ios / "Runner.xcodeproj"
        project.mkdir()
        (project / "project.pbxproj").write_text(
            "IPHONEOS_DEPLOYMENT_TARGET = 14.0;\n"
            "IPHONEOS_DEPLOYMENT_TARGET = 14.0;\n",
            encoding="utf-8",
        )

        flutter = ios / "Flutter"
        flutter.mkdir()
        (flutter / "AppFrameworkInfo.plist").write_text(
            '<?xml version="1.0"?><plist><dict>'
            '<key>MinimumOSVersion</key><string>14.0</string>'
            '</dict></plist>',
            encoding="utf-8",
        )

    def tearDown(self):
        os.chdir(self.original_cwd)
        self.temp_dir.cleanup()

    def test_sets_ios_15_minimum_for_pods_project_and_flutter_framework(self):
        patch_platforms.patch_podfile()

        podfile = (self.root / "ios" / "Podfile").read_text(encoding="utf-8")
        project = (self.root / "ios" / "Runner.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        framework = (self.root / "ios" / "Flutter" / "AppFrameworkInfo.plist").read_text(encoding="utf-8")

        self.assertIn("platform :ios, '15.0'", podfile)
        self.assertEqual(project.count("IPHONEOS_DEPLOYMENT_TARGET = 15.0;"), 2)
        self.assertNotIn("IPHONEOS_DEPLOYMENT_TARGET = 14.0;", project)
        self.assertIn("<string>15.0</string>", framework)


if __name__ == "__main__":
    unittest.main()
