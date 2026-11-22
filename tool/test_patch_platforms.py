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


if __name__ == "__main__":
    unittest.main()
