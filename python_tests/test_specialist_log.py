import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from toolbox.specialist_log import (
    ROOT_DIR,
    LOG_DIR,
    REPORTS_DIR,
    LOG_FILE_PATTERN,
    ENTRY_PATTERN,
    VALID_STATUS_LABELS,
    REMEDIATION_GUIDANCE,
    extract_role,
    validate_entry,
    validate_file,
    _calc_compliance_rate,
    _get_issue_description,
    _classify_issue,
    format_entry,
    get_next_log_path,
    create_log,
    show_logs,
    validate_log,
    clean_logs,
    main,
)


class TestConstants(unittest.TestCase):
    """Test module-level constants are properly defined."""

    def test_root_dir_exists(self):
        self.assertTrue(ROOT_DIR.exists())
        self.assertTrue(ROOT_DIR.is_dir())

    def test_log_dir_defined(self):
        self.assertEqual(LOG_DIR, ROOT_DIR / "logs" / "specialist_logs")

    def test_reports_dir_defined(self):
        self.assertEqual(REPORTS_DIR, ROOT_DIR / "logs" / "compliance_audit")

    def test_valid_status_labels(self):
        self.assertEqual(VALID_STATUS_LABELS, {"IN_PROGRESS", "COMPLETE", "FAILED"})

    def test_log_file_pattern_new_naming(self):
        # Valid filenames with new date-first naming: <YYYYMMDD_HHMMSS>_<role>.log
        self.assertIsNotNone(
            LOG_FILE_PATTERN.match("20260715_183000_test-analyst.log")
        )
        self.assertIsNotNone(
            LOG_FILE_PATTERN.match("20260714_120000_backend-engineer.log")
        )
        self.assertIsNotNone(LOG_FILE_PATTERN.match("20260715_000000_role.log"))

        # Invalid filenames
        self.assertIsNone(LOG_FILE_PATTERN.match("test-analyst-2026-07-15.log"))
        self.assertIsNone(LOG_FILE_PATTERN.match("test-analyst.log"))
        self.assertIsNone(
            LOG_FILE_PATTERN.match("Test-Analyst_20260715_183000.log")
        )

        # Old naming convention should not match
        self.assertIsNone(
            LOG_FILE_PATTERN.match("test-analyst_20260715_183000.log")
        )
        self.assertIsNone(
            LOG_FILE_PATTERN.match("backend-engineer_20260714_120000.log")
        )

    def test_entry_pattern(self):
        # Valid entry
        valid = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        self.assertIsNotNone(ENTRY_PATTERN.match(valid))

        # Invalid entries
        self.assertIsNone(
            ENTRY_PATTERN.match(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: INFO] - [Details]"
            )
        )
        self.assertIsNone(ENTRY_PATTERN.match("No format at all"))
        self.assertIsNone(ENTRY_PATTERN.match(""))

    def test_entry_pattern_allows_empty_brackets(self):
        """Permissive variant allows empty brackets for distinct error keys."""
        self.assertIsNotNone(
            ENTRY_PATTERN.match(
                "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - []"
            )
        )

    def test_remediation_guidance_has_entries(self):
        self.assertIn("format_mismatch", REMEDIATION_GUIDANCE)
        self.assertIn("invalid_timestamp", REMEDIATION_GUIDANCE)
        self.assertIn("invalid_status", REMEDIATION_GUIDANCE)


class TestExtractRole(unittest.TestCase):
    """Test extract_role function with new naming convention."""

    def test_valid_filename_new_naming(self):
        self.assertEqual(
            extract_role("20260715_183000_backend-engineer.log"), "backend-engineer"
        )

    def test_valid_filename_with_hyphen(self):
        self.assertEqual(
            extract_role("20260715_183000_test-analyst.log"), "test-analyst"
        )

    def test_valid_filename_with_underscore(self):
        self.assertEqual(
            extract_role("20260715_183000_test_analyst.log"), "test_analyst"
        )

    def test_invalid_filename(self):
        self.assertIsNone(extract_role("test-analyst-2026-07-15.log"))

    def test_invalid_filename_no_timestamp(self):
        self.assertIsNone(extract_role("test-analyst.log"))

    def test_empty_string(self):
        self.assertIsNone(extract_role(""))

    def test_old_naming_not_matched(self):
        """Old naming convention should not match."""
        self.assertIsNone(extract_role("backend-engineer_20260715_183000.log"))


class TestFormatEntry(unittest.TestCase):
    """Test format_entry function."""

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
    """Test validate_entry function with permissive regex."""

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

    def test_legacy_format_without_brackets(self):
        """Test entries from legacy format (no brackets around subtask/status/details)."""
        entry = "[2026-07-14 18:00:00] - FEAT-001 Phase 4 - IN_PROGRESS - Creating tests"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("format", issue)


class TestClassifyIssue(unittest.TestCase):
    """Test _classify_issue helper function."""

    def test_empty_line_classification(self):
        self.assertEqual(_classify_issue("Empty line"), "empty_line")

    def test_format_mismatch_classification(self):
        self.assertEqual(
            _classify_issue(
                "Entry does not match required format: [TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]"
            ),
            "format_mismatch",
        )

    def test_invalid_timestamp_classification(self):
        self.assertEqual(
            _classify_issue("Invalid timestamp value: 9999-99-99 99:99:99"),
            "invalid_timestamp",
        )

    def test_empty_subtask_classification(self):
        self.assertEqual(_classify_issue("SUBTASK field is empty"), "empty_subtask")

    def test_invalid_status_classification(self):
        self.assertEqual(
            _classify_issue(
                "Invalid status label: INFO. Must be one of: {'IN_PROGRESS', 'COMPLETE', 'FAILED'}"
            ),
            "invalid_status",
        )

    def test_empty_details_classification(self):
        self.assertEqual(_classify_issue("DETAILS field is empty"), "empty_details")

    def test_unknown_description_defaults_to_format_mismatch(self):
        self.assertEqual(_classify_issue("Some unknown issue"), "format_mismatch")


class TestValidateFile(unittest.TestCase):
    """Test validate_file function."""

    def test_nonexistent_file(self):
        result = validate_file(Path("/tmp/nonexistent_audit_test.log"))
        self.assertEqual(result["total_entries"], 0)
        self.assertEqual(result["violations"], [])

    def test_empty_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertEqual(result["total_entries"], 0)
            self.assertEqual(result["violations"], [])
        finally:
            os.unlink(temp_path)

    def test_compliant_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertEqual(result["total_entries"], 1)
            self.assertEqual(result["compliant_entries"], 1)
            self.assertEqual(len(result["violations"]), 0)
        finally:
            os.unlink(temp_path)

    def test_non_compliant_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n")
            f.write("This line has no format\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertEqual(result["total_entries"], 2)
            self.assertEqual(result["compliant_entries"], 1)
            self.assertEqual(len(result["violations"]), 1)
            self.assertEqual(result["violations"][0]["line_number"], 2)
            self.assertEqual(result["violations"][0]["issue_type"], "format_mismatch")
        finally:
            os.unlink(temp_path)

    def test_file_with_role_new_naming(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a file with the new naming pattern
            filepath = Path(tmpdir) / "20260715_183000_backend-engineer.log"
            filepath.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: COMPLETE] - [Details]\n",
                encoding="utf-8",
            )

            result = validate_file(filepath)
            self.assertEqual(result["role"], "backend-engineer")

    def test_file_with_invalid_role_name(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("[2026-07-15 18:30:38] - [Subtask] - [STATUS: COMPLETE] - [Details]\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertIsNone(result["role"])
        finally:
            os.unlink(temp_path)

    def test_mixed_compliance_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("[2026-07-15 18:30:38] - [Subtask 1] - [STATUS: IN_PROGRESS] - [Details 1]\n")
            f.write("[2026-07-15 18:31:00] - [Subtask 2] - [STATUS: COMPLETE] - [Details 2]\n")
            f.write("Invalid line\n")
            f.write("[2026-07-15 18:32:00] - [Subtask 3] - [STATUS: FAILED] - [Details 3]\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertEqual(result["total_entries"], 4)
            self.assertEqual(result["compliant_entries"], 3)
            self.assertEqual(len(result["violations"]), 1)
        finally:
            os.unlink(temp_path)


class TestCalcComplianceRate(unittest.TestCase):
    """Test _calc_compliance_rate function."""

    def test_full_compliance(self):
        self.assertEqual(_calc_compliance_rate(10, 10), "100.0%")

    def test_partial_compliance(self):
        self.assertEqual(_calc_compliance_rate(9, 10), "90.0%")

    def test_zero_compliance(self):
        self.assertEqual(_calc_compliance_rate(0, 10), "0.0%")

    def test_no_entries(self):
        self.assertEqual(_calc_compliance_rate(0, 0), "N/A (no entries)")

    def test_one_decimal_precision(self):
        self.assertEqual(_calc_compliance_rate(1, 3), "33.3%")


class TestGetIssueDescription(unittest.TestCase):
    """Test _get_issue_description function."""

    def test_format_mismatch(self):
        desc = _get_issue_description("format_mismatch")
        self.assertIn("required format", desc)

    def test_invalid_status(self):
        desc = _get_issue_description("invalid_status")
        self.assertIn("IN_PROGRESS", desc)

    def test_unknown_type(self):
        desc = _get_issue_description("unknown_type")
        self.assertEqual(desc, "unknown_type")


class TestGetNextLogPath(unittest.TestCase):
    """Test get_next_log_path function with new naming convention."""

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
            self.fail("get_next_log_path raised unexpected exception: {}".format(e))

    @patch("toolbox.specialist_log.LOG_DIR")
    @patch("os.listdir")
    def test_returns_existing_file(self, mock_listdir, mock_log_dir):
        mock_listdir.return_value = ["20260715_183000_test-role.log"]
        mock_log_dir.__truediv__ = MagicMock(side_effect=lambda x: Path(f"/tmp/{x}"))
        mock_log_dir.mkdir = MagicMock()

        # Create the file so max() works
        test_file = Path("/tmp/20260715_183000_test-role.log")
        test_file.touch()
        try:
            result = get_next_log_path("test-role")
            self.assertIsNotNone(result)
        finally:
            test_file.unlink(missing_ok=True)

    def test_new_naming_convention(self):
        """Verify new log files use date-first naming."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                result = get_next_log_path("test-role")
                # Filename should start with YYYYMMDD_HHMMSS_<role>.log
                self.assertIsNotNone(
                    LOG_FILE_PATTERN.match(result.name),
                    "Filename '{}' should match new naming pattern".format(result.name),
                )
                # Verify role is at the end
                self.assertTrue(
                    result.name.endswith("_test-role.log"),
                    "Filename should end with _<role>.log",
                )


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

                log_files = list(Path(tmpdir).glob("*_test-role.log"))
                self.assertEqual(len(log_files), 1)

                content = log_files[0].read_text(encoding="utf-8")
                lines = [line for line in content.strip().split("\n") if line.strip()]
                self.assertEqual(len(lines), 2)

    def test_new_file_naming_convention(self):
        """Verify created log file uses date-first naming."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                result = create_log("test-role", "Subtask", "IN_PROGRESS", "Details")
                filename = Path(result).name
                # Should match YYYYMMDD_HHMMSS_<role>.log
                self.assertIsNotNone(
                    LOG_FILE_PATTERN.match(filename),
                    "Filename '{}' should match new naming pattern".format(filename),
                )


class TestShowLogs(unittest.TestCase):
    """Test show_logs function with new naming convention."""

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
            # Create a log file with new naming convention
            log_file = log_dir / "20260715_183000_test-role.log"
            log_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8",
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

    def test_role_filtering_with_new_naming(self):
        """Verify role filtering works with date-first naming."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)
            # Create log files with new naming convention
            log_file_a = log_dir / "20260715_183000_backend-engineer.log"
            log_file_a.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8",
            )
            log_file_b = log_dir / "20260715_183000_test-analyst.log"
            log_file_b.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: COMPLETE] - [Details]\n",
                encoding="utf-8",
            )

            with patch("toolbox.specialist_log.LOG_DIR", log_dir):
                result = show_logs(role="backend-engineer")
                self.assertEqual(result, 1)


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
            # Create a recent log file with new naming
            log_file = log_dir / "20260715_183000_test-role.log"
            log_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8",
            )

            with patch("toolbox.specialist_log.LOG_DIR", log_dir):
                result = clean_logs(days=30)
                self.assertEqual(result, 0)
                self.assertTrue(log_file.exists())

    def test_removes_old_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)
            # Create an old log file with new naming
            log_file = log_dir / "20260101_183000_test-role.log"
            log_file.write_text(
                "[2026-01-01 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8",
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
            # Create a log file with new naming
            log_file = log_dir / "20260101_183000_test-role.log"
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


class TestPermissiveRegex(unittest.TestCase):
    """Test permissive regex variant allows empty brackets for distinct error keys."""

    def test_empty_subtask_bracket_matches_pattern(self):
        """Permissive regex matches entries with empty subtask brackets."""
        entry = "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - [Details]"
        self.assertIsNotNone(ENTRY_PATTERN.match(entry))

    def test_empty_details_bracket_matches_pattern(self):
        """Permissive regex matches entries with empty details brackets."""
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - []"
        self.assertIsNotNone(ENTRY_PATTERN.match(entry))

    def test_both_empty_brackets_matches_pattern(self):
        """Permissive regex matches entries with both empty brackets."""
        entry = "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - []"
        self.assertIsNotNone(ENTRY_PATTERN.match(entry))

    def test_empty_subtask_detected_by_validate_entry(self):
        """validate_entry rejects empty subtask even though regex matches."""
        entry = "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("SUBTASK", issue)

    def test_empty_details_detected_by_validate_entry(self):
        """validate_entry rejects empty details even though regex matches."""
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - []"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("DETAILS", issue)

    def test_both_empty_detected_by_validate_entry(self):
        """validate_entry rejects both empty subtask and details."""
        entry = "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - []"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("SUBTASK", issue)


class TestValidateEntryEdgeCases(unittest.TestCase):
    """Additional edge cases for validate_entry."""

    def test_valid_entry_with_long_subtask(self):
        entry = "[2026-07-15 18:30:38] - [This is a very long subtask description that goes on for a while] - [STATUS: COMPLETE] - [Details]"
        is_valid, _ = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_valid_entry_with_long_details(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: COMPLETE] - [This is a very long details description that includes multiple sentences and special characters like @#$%]"
        is_valid, _ = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_valid_entry_with_numbers_in_subtask(self):
        entry = "[2026-07-15 18:30:38] - [Task #123: Fix bug 456] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, _ = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_valid_entry_with_colons_in_details(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Error: Connection refused on port 5432]"
        is_valid, _ = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_valid_entry_midnight_timestamp(self):
        entry = "[2026-07-15 00:00:00] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, _ = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_valid_entry_end_of_day_timestamp(self):
        entry = "[2026-07-15 23:59:59] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, _ = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_invalid_date_feb_30(self):
        entry = "[2026-02-30 12:00:00] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("timestamp", issue)

    def test_invalid_date_feb_29_leap_year(self):
        """Feb 29 is valid in a leap year."""
        entry = "[2024-02-29 12:00:00] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, _ = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_invalid_date_feb_29_non_leap_year(self):
        """Feb 29 is invalid in a non-leap year."""
        entry = "[2023-02-29 12:00:00] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("timestamp", issue)

    def test_missing_brackets_around_subtask(self):
        entry = "[2026-07-15 18:30:38] - Subtask - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("format", issue)

    def test_missing_status_prefix(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("format", issue)

    def test_missing_details_section(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertIn("format", issue)


class TestExtractRoleEdgeCases(unittest.TestCase):
    """Additional edge cases for extract_role."""

    def test_role_with_numbers(self):
        self.assertEqual(
            extract_role("20260715_183000_role123.log"), "role123"
        )

    def test_role_with_multiple_hyphens(self):
        self.assertEqual(
            extract_role("20260715_183000_my-test-role.log"), "my-test-role"
        )

    def test_role_with_multiple_underscores(self):
        self.assertEqual(
            extract_role("20260715_183000_my_test_role.log"), "my_test_role"
        )

    def test_uppercase_role_rejected(self):
        self.assertIsNone(extract_role("20260715_183000_Backend.log"))

    def test_role_with_spaces_rejected(self):
        self.assertIsNone(extract_role("20260715_183000_test role.log"))

    def test_missing_timestamp(self):
        self.assertIsNone(extract_role("backend-engineer.log"))

    def test_partial_timestamp(self):
        self.assertIsNone(extract_role("20260715_backend-engineer.log"))

    def test_extra_underscores_in_role(self):
        """Role part can contain underscores, so this is valid."""
        self.assertEqual(
            extract_role("20260715_183000_000_backend-engineer.log"),
            "000_backend-engineer",
        )


class TestValidateFileEdgeCases(unittest.TestCase):
    """Additional edge cases for validate_file."""

    def test_file_with_all_violations(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("Invalid line 1\n")
            f.write("Invalid line 2\n")
            f.write("Invalid line 3\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertEqual(result["total_entries"], 3)
            self.assertEqual(result["compliant_entries"], 0)
            self.assertEqual(len(result["violations"]), 3)
        finally:
            os.unlink(temp_path)

    def test_file_with_empty_lines_only(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("\n\n\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertEqual(result["total_entries"], 0)
            self.assertEqual(result["violations"], [])
        finally:
            os.unlink(temp_path)

    def test_file_with_mixed_empty_and_valid_lines(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("\n")
            f.write("[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n")
            f.write("\n")
            f.write("[2026-07-15 18:31:00] - [Subtask2] - [STATUS: COMPLETE] - [Details2]\n")
            f.write("\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertEqual(result["total_entries"], 2)
            self.assertEqual(result["compliant_entries"], 2)
            self.assertEqual(len(result["violations"]), 0)
        finally:
            os.unlink(temp_path)

    def test_violation_contains_remediation(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("Invalid line\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            self.assertIn("remediation", result["violations"][0])
            self.assertIn("specialist_log.py", result["violations"][0]["remediation"])
        finally:
            os.unlink(temp_path)

    def test_violation_issue_types(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - [Details]\n")
            f.write("[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - []\n")
            f.write("[9999-99-99 99:99:99] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n")
            f.write("No format\n")
            temp_path = f.name

        try:
            result = validate_file(Path(temp_path))
            issue_types = [v["issue_type"] for v in result["violations"]]
            self.assertIn("empty_subtask", issue_types)
            self.assertIn("empty_details", issue_types)
            self.assertIn("invalid_timestamp", issue_types)
            self.assertIn("format_mismatch", issue_types)
        finally:
            os.unlink(temp_path)


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

                log_files = list(Path(tmpdir).glob("*_test-role.log"))
                self.assertEqual(len(log_files), 1)

                # Validate the file
                result = validate_log(str(log_files[0]))
                self.assertEqual(result, 3)

                # Check all entries are present
                content = log_files[0].read_text(encoding="utf-8")
                lines = [line for line in content.strip().split("\n") if line.strip()]
                self.assertEqual(len(lines), 3)

    def test_validate_file_integration(self):
        """Test validate_file with new naming convention."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)
            # Create a file with new naming convention
            log_file = log_dir / "20260715_183000_backend-engineer.log"
            log_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n"
                "Invalid line\n"
                "[2026-07-15 18:31:00] - [Subtask2] - [STATUS: COMPLETE] - [More details]\n",
                encoding="utf-8",
            )

            result = validate_file(log_file)
            self.assertEqual(result["role"], "backend-engineer")
            self.assertEqual(result["total_entries"], 3)
            self.assertEqual(result["compliant_entries"], 2)
            self.assertEqual(len(result["violations"]), 1)

    def test_full_workflow_new_naming(self):
        """Test complete workflow with new naming convention."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                # Create log entries
                log_path = create_log(
                    "backend-engineer",
                    "Implement endpoint",
                    "IN_PROGRESS",
                    "Starting work",
                )
                self.assertIsNotNone(log_path)

                # Verify naming convention
                filename = Path(log_path).name
                self.assertIsNotNone(
                    LOG_FILE_PATTERN.match(filename),
                    "Filename '{}' should match new naming pattern".format(filename),
                )

                # Show logs for the role
                result = show_logs(role="backend-engineer")
                self.assertEqual(result, 1)

                # Validate the file
                result = validate_log(log_path)
                self.assertEqual(result, 1)

    def test_multiple_roles_workflow(self):
        """Test workflow with multiple roles."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                # Create logs for two roles
                path_a = create_log("backend-engineer", "Task A", "IN_PROGRESS", "Work A")
                path_b = create_log("test-analyst", "Task B", "COMPLETE", "Work B")

                self.assertIsNotNone(path_a)
                self.assertIsNotNone(path_b)
                self.assertNotEqual(path_a, path_b)

                # Show all logs
                result = show_logs()
                self.assertEqual(result, 2)

                # Show only backend-engineer logs
                result = show_logs(role="backend-engineer")
                self.assertEqual(result, 1)

                # Show only test-analyst logs
                result = show_logs(role="test-analyst")
                self.assertEqual(result, 1)

    def test_cli_log_command_workflow(self):
        """Test CLI LOG command end-to-end."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.specialist_log.LOG_DIR", Path(tmpdir)):
                with patch(
                    "sys.argv",
                    [
                        "specialist_log.py",
                        "LOG",
                        "--role",
                        "test-role",
                        "--subtask",
                        "CLI test",
                        "--status",
                        "COMPLETE",
                        "--details",
                        "CLI workflow test",
                    ],
                ):
                    result = main()
                    self.assertIsNotNone(result)
                    self.assertTrue(Path(result).exists())

                    # Validate created file
                    validate_result = validate_log(result)
                    self.assertEqual(validate_result, 1)

    def test_cli_validate_command_workflow(self):
        """Test CLI VALIDATE command end-to-end."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
            f.write("[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n")
            temp_path = f.name

        try:
            with patch("sys.argv", ["specialist_log.py", "VALIDATE", temp_path]):
                result = main()
                self.assertEqual(result, 1)
        finally:
            os.unlink(temp_path)

    def test_cli_show_command_workflow(self):
        """Test CLI SHOW command end-to-end."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)
            log_file = log_dir / "20260715_183000_test-role.log"
            log_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8",
            )

            with patch("toolbox.specialist_log.LOG_DIR", log_dir):
                with patch("sys.argv", ["specialist_log.py", "SHOW"]):
                    result = main()
                    self.assertEqual(result, 1)

    def test_compliance_rate_calculation(self):
        """Test compliance rate calculation across multiple files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir)

            # File 1: 100% compliant
            file1 = log_dir / "20260715_183000_role-a.log"
            file1.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n"
                "[2026-07-15 18:31:00] - [Subtask2] - [STATUS: COMPLETE] - [Details2]\n",
                encoding="utf-8",
            )

            # File 2: 50% compliant
            file2 = log_dir / "20260715_183000_role-b.log"
            file2.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n"
                "Invalid line\n",
                encoding="utf-8",
            )

            result1 = validate_file(file1)
            result2 = validate_file(file2)

            # Calculate compliance rates
            rate1 = _calc_compliance_rate(
                result1["compliant_entries"], result1["total_entries"]
            )
            rate2 = _calc_compliance_rate(
                result2["compliant_entries"], result2["total_entries"]
            )

            self.assertEqual(rate1, "100.0%")
            self.assertEqual(rate2, "50.0%")

    def test_validate_file_with_new_naming_and_role(self):
        """Test validate_file correctly extracts role from new naming."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log_file = Path(tmpdir) / "20260716_120000_backend-engineer.log"
            log_file.write_text(
                "[2026-07-16 12:00:00] - [Task] - [STATUS: COMPLETE] - [Done]\n",
                encoding="utf-8",
            )

            result = validate_file(log_file)
            self.assertEqual(result["role"], "backend-engineer")
            self.assertEqual(result["filename"], "20260716_120000_backend-engineer.log")
            self.assertEqual(result["compliant_entries"], 1)


if __name__ == "__main__":
    unittest.main()
