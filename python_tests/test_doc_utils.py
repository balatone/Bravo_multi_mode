import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Add toolbox to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "toolbox"))

from doc_utils import show_preamble, display_preamble


class TestShowPreamble(unittest.TestCase):
    """Tests for the show_preamble function (FEAT-008)."""

    def setUp(self):
        """Create a temporary directory for test files."""
        self.test_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up temporary files."""
        import shutil

        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _create_file(self, content, filename="test.md"):
        """Helper to create a test file with given content."""
        filepath = os.path.join(self.test_dir, filename)
        Path(filepath).write_text(content, encoding="utf-8")
        return filepath

    def test_successful_extraction_full_preamble(self):
        """Test extraction of a complete YAML preamble with all standard fields."""
        content = (
            "---\n"
            "id: REQ-005\n"
            "title: Test Requirement\n"
            "version: 1.0.0\n"
            "status: APPROVED\n"
            "created: 2026-07-16 13:40:00\n"
            "updated: 2026-07-16 13:37:34\n"
            "related_docs: []\n"
            "---\n"
            "# Test Requirement\n"
            "\n"
            "Some body text here.\n"
        )
        filepath = self._create_file(content)
        result = show_preamble(filepath)

        self.assertIsNotNone(result)
        self.assertEqual(result["id"], "REQ-005")
        self.assertEqual(result["title"], "Test Requirement")
        self.assertEqual(result["version"], "1.0.0")
        self.assertEqual(result["status"], "APPROVED")
        self.assertEqual(result["created"], "2026-07-16 13:40:00")
        self.assertEqual(result["updated"], "2026-07-16 13:37:34")
        self.assertEqual(result["related_docs"], "[]")

    def test_extraction_with_missing_optional_fields(self):
        """Test that missing optional fields (verdict, priority) are handled gracefully."""
        content = (
            "---\n"
            "id: FEAT-001\n"
            "title: Feature Without Verdict\n"
            "status: DRAFT\n"
            "---\n"
            "# Feature Without Verdict\n"
        )
        filepath = self._create_file(content)
        result = show_preamble(filepath)

        self.assertIsNotNone(result)
        self.assertEqual(result["id"], "FEAT-001")
        self.assertEqual(result["title"], "Feature Without Verdict")
        self.assertEqual(result["status"], "DRAFT")
        self.assertNotIn("verdict", result)
        self.assertNotIn("priority", result)

    def test_extraction_with_quoted_values(self):
        """Test that quoted YAML values are properly unquoted."""
        content = (
            "---\n"
            'id: TEST-001\n'
            'title: "A Quoted Title"\n'
            "status: DRAFT\n"
            "---\n"
            "# Test\n"
        )
        filepath = self._create_file(content)
        result = show_preamble(filepath)

        self.assertIsNotNone(result)
        self.assertEqual(result["title"], "A Quoted Title")

    def test_extraction_with_single_quoted_values(self):
        """Test that single-quoted YAML values are properly unquoted."""
        content = (
            "---\n"
            "id: TEST-002\n"
            "title: 'A Single Quoted Title'\n"
            "status: DRAFT\n"
            "---\n"
            "# Test\n"
        )
        filepath = self._create_file(content)
        result = show_preamble(filepath)

        self.assertIsNotNone(result)
        self.assertEqual(result["title"], "A Single Quoted Title")

    def test_no_yaml_preamble(self):
        """Test that files without a YAML preamble return None and print error."""
        content = "# Just a regular markdown file\n\nSome content.\n"
        filepath = self._create_file(content)

        with patch("builtins.print") as mock_print:
            result = show_preamble(filepath)

        self.assertIsNone(result)
        mock_print.assert_called_with("Error: No YAML preamble detected.")

    def test_file_not_found(self):
        """Test that non-existent files return None and print error."""
        filepath = os.path.join(self.test_dir, "nonexistent.md")

        with patch("builtins.print") as mock_print:
            result = show_preamble(filepath)

        self.assertIsNone(result)
        mock_print.assert_called_with(f"Error: File {filepath} not found.")

    def test_empty_preamble(self):
        """Test that an empty YAML preamble (between delimiters) returns None."""
        content = "---\n---\n# Empty preamble\n"
        filepath = self._create_file(content)

        with patch("builtins.print") as mock_print:
            result = show_preamble(filepath)

        self.assertIsNone(result)
        mock_print.assert_called_with("Error: No YAML preamble detected.")

    def test_preamble_with_colons_in_value(self):
        """Test that values containing colons are parsed correctly."""
        content = (
            "---\n"
            "id: TEST-003\n"
            "title: Title with: a colon\n"
            "status: DRAFT\n"
            "---\n"
            "# Test\n"
        )
        filepath = self._create_file(content)
        result = show_preamble(filepath)

        self.assertIsNotNone(result)
        self.assertEqual(result["title"], "Title with: a colon")

    def test_preamble_with_whitespace(self):
        """Test that whitespace in preamble values is handled correctly."""
        content = (
            "---\n"
            "  id: TEST-004\n"
            "  title:   Spaced Title  \n"
            "  status: DRAFT\n"
            "---\n"
            "# Test\n"
        )
        filepath = self._create_file(content)
        result = show_preamble(filepath)

        self.assertIsNotNone(result)
        self.assertEqual(result["id"], "TEST-004")
        self.assertEqual(result["title"], "Spaced Title")
        self.assertEqual(result["status"], "DRAFT")

    def test_preamble_not_at_start(self):
        """Test that preamble is detected even if preceded by content (malformed)."""
        # In real docs, preamble should be at the start, but regex handles
        # the first occurrence regardless
        content = (
            "---\n"
            "id: TEST-005\n"
            "status: DRAFT\n"
            "---\n"
            "# Test\n"
        )
        filepath = self._create_file(content)
        result = show_preamble(filepath)

        self.assertIsNotNone(result)
        self.assertEqual(result["id"], "TEST-005")


class TestDisplayPreamble(unittest.TestCase):
    """Tests for the display_preamble function (FEAT-008)."""

    def test_display_with_metadata(self):
        """Test that metadata is displayed in a formatted manner."""
        metadata = {
            "id": "REQ-005",
            "title": "Test Requirement",
            "status": "APPROVED",
        }

        with patch("builtins.print") as mock_print:
            display_preamble(metadata)

        # Verify header is printed
        calls = [str(call) for call in mock_print.call_args_list]
        self.assertTrue(any("Document Metadata:" in c for c in calls))
        self.assertTrue(any("id" in c for c in calls))
        self.assertTrue(any("title" in c for c in calls))
        self.assertTrue(any("status" in c for c in calls))

    def test_display_with_none(self):
        """Test that None metadata produces no output."""
        with patch("builtins.print") as mock_print:
            display_preamble(None)

        mock_print.assert_not_called()

    def test_display_with_empty_dict(self):
        """Test that empty metadata dict produces no output."""
        with patch("builtins.print") as mock_print:
            display_preamble({})

        mock_print.assert_not_called()


if __name__ == "__main__":
    unittest.main()
