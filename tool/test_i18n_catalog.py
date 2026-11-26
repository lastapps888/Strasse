import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tool" / "i18n" / "source_fr.json"
REQUIRED_LANGUAGES = ("vi", "hi", "bn", "ur", "id", "tr")


class Beta6TranslationCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with SOURCE.open("r", encoding="utf-8") as stream:
            cls.source = json.load(stream)

    def test_all_required_language_files_exist(self):
        for language in REQUIRED_LANGUAGES:
            with self.subTest(language=language):
                self.assertTrue((ROOT / "assets" / "i18n" / (language + ".json")).is_file())

    def test_every_source_key_has_a_non_empty_translation(self):
        source_keys = set(self.source)
        for language in REQUIRED_LANGUAGES:
            path = ROOT / "assets" / "i18n" / (language + ".json")
            with self.subTest(language=language):
                with path.open("r", encoding="utf-8") as stream:
                    translated = json.load(stream)
                missing = sorted(source_keys.difference(translated))
                empty = sorted(
                    key for key in source_keys
                    if not isinstance(translated.get(key), str) or not translated[key].strip()
                )
                self.assertFalse(missing, "Clés manquantes : " + ", ".join(missing[:20]))
                self.assertFalse(empty, "Traductions vides : " + ", ".join(empty[:20]))


if __name__ == "__main__":
    unittest.main()
