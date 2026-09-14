"""Regression coverage for versioned website URLs and semantic headings."""
from pathlib import Path
import unittest

from release_pages import has_page_heading, local_asset_path


class ReleasePagesTests(unittest.TestCase):
    def test_versioned_asset_and_fragment_resolve_to_the_file(self):
        root = Path("site").resolve()
        for url in ("style.css?v=abc123", "style.css#theme", "style.css?v=abc#theme"):
            self.assertEqual(local_asset_path(root, url), root / "style.css")

    def test_encoded_path_and_missing_asset_remain_distinct(self):
        root = Path("site").resolve()
        self.assertEqual(local_asset_path(root, "assets/game%20view.png?v=2"),
                         root / "assets" / "game view.png")
        self.assertEqual(local_asset_path(root, "missing.css?v=2"), root / "missing.css")

    def test_external_and_same_page_links_are_not_files(self):
        for url in ("https://example.com/a", "//example.com/a", "mailto:support@example.com",
                    "#screenshots", "?lang=en"):
            self.assertIsNone(local_asset_path(Path("site"), url))

    def test_heading_accepts_attributes_and_nested_markup(self):
        self.assertTrue(has_page_heading('<h1 id="hero">Small beginnings. <span>Sky-high ambitions.</span></h1>'))
        self.assertTrue(has_page_heading('<H1 class="title">Airline Empire</H1>'))

    def test_missing_empty_and_commented_headings_are_rejected(self):
        for html in ('<h2>Airline Empire</h2>', '<!-- <h1>Hidden</h1> -->', '<h1>  </h1>'):
            self.assertFalse(has_page_heading(html))


if __name__ == "__main__":
    unittest.main()
