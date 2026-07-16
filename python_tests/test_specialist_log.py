import os
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from toolbox.specialist_log import (
    ROOT_DIR,
    LOG_DIR,
    LOG_FILE_PATTERN,
    get_next_log_path,
    create_log,
    show_logs,
    validate_log,
    clean_logs,
    main,
)

# Import shared module constants used by specialist_log
from toolbox.log_format import (
    VALID_STATUS_LABELS,
    ENTRY_PATTERN,
    validate_entry,
    format_entry,
)


class TestConstants(unittest.TestCase):
    """Test module-level constants are properly defined."""

    def test_root_dir_exists(self):
        self.assertTrue(ROOT_DIR.exists())
        self.assertTrue(ROOT_DIR.is_dir())

    def test_log_dir_defined(self):
        self.assertEqual(LOG_DIR, ROOT_DIR / "logs" / "specialist_logs")

    def test_valid_status_labels(self):
        self.assertEqual(VALID_STATUS_LABELS, {"IN_PROGRESS", "COMPLETE", "FAILED"})

    def test_log_file_pattern(self):
        # Valid filenames
        self.assertIsNotNone(LOG_FILE_PATTERN.match("test-analyst_20260715_183000.log"))
        self.assertIsNotNone(LOG_FILE_PATTERN.match("backend-engineer_20260714_120000.log"))
        self.assertIsNotNone(LOG_FILE_PATTERN.match("role_20260715_000000.log"))

        # Invalid filenames
        self.assertIsNone(LOG_FILE_PATTERN.match("test-analyst-2026-07-15.log"))
        self.assertIsNone(LOG_FILE_PATTERN.match("test-analyst.log"))
        self.assertIsNone(LOG_FILE_PATTERN.match("Test-Analyst_20260715_183000.log"))

    def test_entry_pattern(self):
        # Valid entry
        valid = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        self.assertIsNotNone(ENTRY_PATTERN.match(valid))

        # Invalid entries
        self.assertIsNone(ENTRY_PATTERN.match("[2026-07-15 18:30:38] - [Subtask] - [STATUS: INFO] - [Details]"))
        self.assertIsNone(ENTRY_PATTERN.match("No format at all"))
        self.assertIsNone(ENTRY_PATTERN.match(""))


class TestGetNextLogPath(unittest.TestCase):
    """Test get_next_log_path function."""

    @patch("os.listdir")
    @patch("toolbox.specialist_log.LOG_DIR")
    def test_creates_directory_if_needed(self, mock_log_dir, mock_listdir):
        mock_log_dir.exists.return_value = False
        mock_log_dir.mkdir = MagicMock()
        mock_log_dir.__truediv__ = MagicMock(side_effect=lambda x: Path(f"/tmp/{x}"))
        mock_listdir.return_value = []

        # Just verify it doesn't raise an exception
        try:
            get_next_log_path("test-role")
        except Exception as e:
            self.fail(f"get_next_log_path raised unexpected exception: {e}")

    @patch("toolbox.specialist_log.LOG_DIR")
    @patch("os.listdir")
    def test_returns_existing_file(self, mock_listdir, mock_log_dir):
        mock_listdir.return_value = ["test-role_20260715_183000.log"]
        mock_log_dir.__truediv__ = MagicMock(side_effect=lambda x: Path(f"/tmp/{x}"))
        mock_log_dir.mkdir = MagicMock()

        # Create the file so max() works
        test_file = Path("/tmp/test-role_20260715_183000.log")
        test_file.touch()
        try:
            result = get_next_log_path("test-role")
            self.assertIsNotNone(result)
        finally:
            test_file.unlink(missing_ok=True)


class TestFormatEntry(unittest.TestCase):
    """Test format_entry function (imported from shared log_format module)."""

    def test_format_entry_returns_string(self):
        result = format_entry("Test subtask", "IN_PROGRESS", "Test details")
        self.assertIsInstance(result, str)

    def test_format_entry_contains_timestamp(self):
        result = format_entry("Test subtask", "IN_PROGRESS", "Test details")
        self.assertIn("[", result)
        self.assertIn("]", result)

    def test_format_entry_contains_subtask(self):
        result = format_entry("Test subtask", "IN_PROGRESS", "Test details")
        self.assertIn("Test subtask", result)

    def test_format_entry_contains_status(self):
        result = format_entry("Test subtask", "IN_PROGRESS", "Test details")
        self.assertIn("STATUS: IN_PROGRESS", result)

    def test_format_entry_contains_details(self):
        result = format_entry("Test subtask", "IN_PROGRESS", "Test details")
        self.assertIn("Test details", result)

    def test_format_entry_validates_correctly(self):
        result = format_entry("Test subtask", "IN_PROGRESS", "Test details")
        is_valid, issue = validate_entry(result)
        self.assertTrue(is_valid)
        self.assertEqual(issue, "")

    def test_format_entry_all_statuses(self):
        for status in VALID_STATUS_LABELS:
            result = format_entry("Test", status, "Details")
            self.assertIn("STATUS: {}".format(status), result)
            is_valid, _ = validate_entry(result)
            self.assertTrue(is_valid)


class TestValidateEntry(unittest.TestCase):
    """Test validate_entry function (imported from shared log_format module)."""

    def test_valid_entry(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertTrue(is_valid)
        self.assertEqual(issue, "")

    def test_valid_entry_complete_status(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: COMPLETE] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_valid_entry_failed_status(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: FAILED] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_empty_line(self):
        is_valid, issue = validate_entry("")
        self.assertFalse(is_valid)
        self.assertIn("Empty", issue)

    def test_whitespace_only_line(self):
        is_valid, issue = validate_entry("   ")
        self.assertFalse(is_valid)
        self.assertIn("Empty", issue)

    def test_invalid_format(self):
        is_valid, issue = validate_entry("This has no format")
        self.assertFalse(is_valid)
        self.assertIn("format", issue)

    def test_invalid_status_label(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: INFO] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)

    def test_missing_details(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - []"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("DETAILS", issue)

    def test_missing_subtask(self):
        entry = "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("SUBTASK", issue)

    def test_invalid_timestamp(self):
        entry = "[9999-99-99 99:99:99] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("timestamp", issue)

    def test_entry_with_special_characters(self):
        entry = "[2026-07-15 18:30:38] - [Task #123] - [STATUS: IN_PROGRESS] - [Details with spaces and symbols @#$]"
        is_valid, issue = validate_entry(entry)
        self.assertTrue(is_valid)


class TestCreateLog(unittest.TestCase):
    """Test create_log function."""

    def test_invalid_status(self):
        result = create_log("test-role", "Subtask", "INVALID", "Details")
        self.assertIsNone(result)

    def test_empty_subtask(self):
        result = create_log("test-role", "", "IN_PROGRESS", "Details")
        self.assertIsNone(result)

    def test_empty_details(self):
        result = create_log("test-role", "Subtask", "IN_PROGRESS", "")
        self.assertIsNone(result)

    def test_none_subtask(self):
        result = create_log("test-role", None, "IN_PROGRESS", "Details")
        self.assertIsNone(result)

    def test_none_details(self):
        result = create_log("test-role", "Subtask", "IN_PROGRESS", None)
        self.assertIsNone(result)

    def test_whitespace_only_subtask(self):
        result = create_log("test-role", "   ", "IN_PROGRESS", "Details")
        self.assertIsNone(result)

    def test_whitespace_only_details(self):
        result = create_log("test-role", "Subtask", "IN_PROGRESS", "   ")
        self.assertIsNone(result)

    def test_status_case_insensitive(self):
        # Should work with lowercase status
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                result = create_log("test-role", "Subtask", "in_progress", "Details")
                self.assertIsNotNone(result)

    def test_creates_log_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                result = create_log("test-role", "Subtask", "IN_PROGRESS", "Details")
                self.assertIsNotNone(result)
                self.assertTrue(Path(result).exists())
                content = Path(result).read_text(encoding="utf-8")
                self.assertIn("Subtask", content)
                self.assertIn("IN_PROGRESS", content)
                self.assertIn("Details", content)

    def test_appends_to_existing_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                create_log("test-role", "First entry", "IN_PROGRESS", "Details 1")
                create_log("test-role", "Second entry", "COMPLETE", "Details 2")

                log_files = list(Path(tmpdir).glob("test-role_*.log"))
                self.assertEqual(len(log_files), 1)

                content = log_files[0].read_text(encoding="utf-8")
                lines = [l for l in content.strip().split("\n") if l.strip()]
                self.assertEqual(len(lines), 2)


class TestShowLogs(unittest.TestCase):
    """Test show_logs function."""

    def test_empty_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                result = show_logs()
                self.assertEqual(result, 0)

    def test_no_matching_role(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                result = show_logs(role="nonexistent-role")
                self.assertEqual(result, 0)

    def test_invalid_date_format(self):
        result = show_logs(since="not-a-date")
        self.assertIsNone(result)

    def test_valid_date_filter(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)
            # Create a log file with an entry
            log_file = log_dir / "test-role_20260715_183000.log"
            log_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8"
            )

            with patch("toolbox.specialist_log.LOG_DIR", log_dir):
                result = show_logs(since="2026-07-15")
                self.assertEqual(result, 1)

    def test_creates_directory_if_missing(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            missing_dir = Path(tmpdir) / "nonexistent"
            with patch("toolbox.specialist_log.LOG_DIR", missing_dir):
                result = show_logs()
                self.assertEqual(result, 0)
                self.assertTrue(missing_dir.exists())


class TestValidateLog(unittest.TestCase):
    """Test validate_log function."""

    def test_file_not_found(self):
        result = validate_log("/tmp/nonexistent_file_12345.log")
        self.assertIsNone(result)

    def test_empty_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            temp_path = f.name

        try:
            result = validate_log(temp_path)
            self.assertEqual(result, 0)
        finally:
            os.unlink(temp_path)

    def test_compliant_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n")
            temp_path = f.name

        try:
            result = validate_log(temp_path)
            self.assertEqual(result, 1)
        finally:
            os.unlink(temp_path)

    def test_non_compliant_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n")
            f.write("This line has no format\n")
            temp_path = f.name

        try:
            result = validate_log(temp_path)
            self.assertEqual(result, 1)
        finally:
            os.unlink(temp_path)

    def test_file_with_only_empty_lines(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("\n\n\n")
            temp_path = f.name

        try:
            result = validate_log(temp_path)
            self.assertEqual(result, 0)
        finally:
            os.unlink(temp_path)


class TestCleanLogs(unittest.TestCase):
    """Test clean_logs function."""

    def test_no_log_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            missing_dir = Path(tmpdir) / "nonexistent"
            with patch("toolbox.specialist_log.LOG_DIR", missing_dir):
                result = clean_logs()
                self.assertEqual(result, 0)

    def test_no_old_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)
            # Create a recent log file
            log_file = log_dir / "test-role_20260715_183000.log"
            log_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8"
            )

            with patch("toolbox.specialist_log.LOG_DIR", log_dir):
                result = clean_logs(days=30)
                self.assertEqual(result, 0)
                self.assertTrue(log_file.exists())

    def test_removes_old_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)
            # Create an old log file
            log_file = log_dir / "test-role_20260101_183000.log"
            log_file.write_text(
                "[2026-01-01 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8"
            )
            # Set modification time to 60 days ago
            old_time = __import__("time").time() - (60 * 86400)
            os.utime(log_file, (old_time, old_time))

            with patch("toolbox.specialist_log.LOG_DIR", log_dir):
                result = clean_logs(days=30)
                self.assertEqual(result, 1)
                self.assertFalse(log_file.exists())

    def test_custom_days(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)
            # Create a log file
            log_file = log_dir / "test-role_20260101_183000.log"
            log_file.write_text("test\n", encoding="utf-8")
            old_time = __import__("time").time() - (10 * 86400)
            os.utime(log_file, (old_time, old_time))

            with patch("toolbox.specialist_log.LOG_DIR", log_dir):
                # 10 days old, retention is 7 days -> should be removed
                result = clean_logs(days=7)
                self.assertEqual(result, 1)
                self.assertFalse(log_file.exists())


class TestMain(unittest.TestCase):
    """Test main CLI entry point."""

    def test_no_arguments(self):
        with patch("sys.argv", ["specialist_log.py"]):
            result = main()
            self.assertIsNone(result)

    def test_unknown_command(self):
        with patch("sys.argv", ["specialist_log.py", "UNKNOWN"]):
            result = main()
            self.assertIsNone(result)

    def test_log_missing_role(self):
        with patch("sys.argv", ["specialist_log.py", "LOG", "--subtask", "Test", "--status", "IN_PROGRESS", "--details", "Details"]):
            result = main()
            self.assertIsNone(result)

    def test_log_missing_subtask(self):
        with patch("sys.argv", ["specialist_log.py", "LOG", "--role", "test", "--status", "IN_PROGRESS", "--details", "Details"]):
            result = main()
            self.assertIsNone(result)

    def test_log_missing_status(self):
        with patch("sys.argv", ["specialist_log.py", "LOG", "--role", "test", "--subtask", "Test", "--details", "Details"]):
            result = main()
            self.assertIsNone(result)

    def test_log_missing_details(self):
        with patch("sys.argv", ["specialist_log.py", "LOG", "--role", "test", "--subtask", "Test", "--status", "IN_PROGRESS"]):
            result = main()
            self.assertIsNone(result)

    def test_validate_missing_filepath(self):
        with patch("sys.argv", ["specialist_log.py", "VALIDATE"]):
            result = main()
            self.assertIsNone(result)

    def test_show_no_arguments(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                with patch("sys.argv", ["specialist_log.py", "SHOW"]):
                    result = main()
                    self.assertEqual(result, 0)

    def test_clean_default(self):
        with patch("sys.argv", ["specialist_log.py", "CLEAN"]):
            with tempfile.TemporaryDirectory() as tmpdir:
                with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                    result = main()
                    self.assertEqual(result, 0)

    def test_clean_with_days(self):
        with patch("sys.argv", ["specialist_log.py", "CLEAN", "--days", "7"]):
            with tempfile.TemporaryDirectory() as tmpdir:
                with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                    result = main()
                    self.assertEqual(result, 0)

    def test_clean_invalid_days(self):
        with patch("sys.argv", ["specialist_log.py", "CLEAN", "--days", "not-a-number"]):
            result = main()
            self.assertIsNone(result)


class TestIntegration(unittest.TestCase):
    """Integration tests for end-to-end workflows."""

    def test_create_and_validate(self):
        """Test that entries created by create_log pass validation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                log_path = create_log("test-role", "Integration test", "COMPLETE", "Full integration test")
                self.assertIsNotNone(log_path)

                result = validate_log(log_path)
                self.assertEqual(result, 1)

    def test_create_multiple_entries(self):
        """Test creating multiple entries and validating all."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                create_log("test-role", "Entry 1", "IN_PROGRESS", "First entry")
                create_log("test-role", "Entry 2", "COMPLETE", "Second entry")
                create_log("test-role", "Entry 3", "FAILED", "Third entry")

                log_files = list(Path(tmpdir).glob("test-role_*.log"))
                self.assertEqual(len(log_files), 1)

                # Validate the file
                result = validate_log(str(log_files[0]))
                self.assertEqual(result, 3)

                # Check all entries are present
                content = log_files[0].read_text(encoding="utf-8")
                lines = [l for l in content.strip().split("\n") if l.strip()]
                self.assertEqual(len(lines), 3)

    def test_shared_module_imports(self):
        """Verify specialist_log imports from shared log_format module."""
        from toolbox import specialist_log
        from toolbox import log_format

        # Verify the functions are the same objects
        self.assertIs(specialist_log.validate_entry, log_format.validate_entry)
        self.assertIs(specialist_log.format_entry, log_format.format_entry)
        self.assertIs(specialist_log.VALID_STATUS_LABELS, log_format.VALID_STATUS_LABELS)
        self.assertIs(specialist_log.ENTRY_PATTERN, log_format.ENTRY_PATTERN)


if __name__ == "__main__":
    unittest.main()
