import json
import os
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch, MagicMock, mock_open

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from toolbox.compliance_audit import (
    ROOT_DIR,
    LOG_DIR,
    REPORTS_DIR,
    LOG_FILE_PATTERN,
    VALID_STATUS_LABELS,
    ENTRY_PATTERN,
    REMEDIATION_GUIDANCE,
    extract_role,
    validate_entry,
    validate_file,
    scan_log_files,
    aggregate_results,
    generate_markdown_report,
    generate_json_report,
    save_report,
    _calc_compliance_rate,
    _get_issue_description,
    run_audit,
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

    def test_log_file_pattern(self):
        # Valid filenames
        self.assertIsNotNone(LOG_FILE_PATTERN.match("test-analyst_20260715_183000.log"))
        self.assertIsNotNone(LOG_FILE_PATTERN.match("backend-engineer_20260714_120000.log"))

        # Invalid filenames
        self.assertIsNone(LOG_FILE_PATTERN.match("test-analyst-2026-07-15.log"))
        self.assertIsNone(LOG_FILE_PATTERN.match("test-analyst.log"))

    def test_entry_pattern(self):
        # Valid entry
        valid = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        self.assertIsNotNone(ENTRY_PATTERN.match(valid))

        # Invalid entries
        self.assertIsNone(ENTRY_PATTERN.match("[2026-07-15 18:30:38] - [Subtask] - [STATUS: INFO] - [Details]"))
        self.assertIsNone(ENTRY_PATTERN.match("No format at all"))

    def test_remediation_guidance_has_entries(self):
        self.assertIn("format_mismatch", REMEDIATION_GUIDANCE)
        self.assertIn("invalid_timestamp", REMEDIATION_GUIDANCE)
        self.assertIn("invalid_status", REMEDIATION_GUIDANCE)


class TestExtractRole(unittest.TestCase):
    """Test extract_role function."""

    def test_valid_filename(self):
        self.assertEqual(extract_role("backend-engineer_20260715_183000.log"), "backend-engineer")

    def test_valid_filename_with_hyphen(self):
        self.assertEqual(extract_role("test-analyst_20260715_183000.log"), "test-analyst")

    def test_valid_filename_with_underscore(self):
        self.assertEqual(extract_role("test_analyst_20260715_183000.log"), "test_analyst")

    def test_invalid_filename(self):
        self.assertIsNone(extract_role("test-analyst-2026-07-15.log"))

    def test_invalid_filename_no_timestamp(self):
        self.assertIsNone(extract_role("test-analyst.log"))

    def test_empty_string(self):
        self.assertIsNone(extract_role(""))


class TestValidateEntry(unittest.TestCase):
    """Test validate_entry function (returns issue keys for remediation mapping)."""

    def test_valid_entry_in_progress(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertTrue(is_valid)
        self.assertEqual(issue, "")

    def test_valid_entry_complete(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: COMPLETE] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_valid_entry_failed(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: FAILED] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_empty_line(self):
        is_valid, issue = validate_entry("")
        self.assertFalse(is_valid)
        self.assertEqual(issue, "empty_line")

    def test_whitespace_only_line(self):
        is_valid, issue = validate_entry("   ")
        self.assertFalse(is_valid)
        self.assertEqual(issue, "empty_line")

    def test_format_mismatch(self):
        is_valid, issue = validate_entry("This has no format")
        self.assertFalse(is_valid)
        self.assertEqual(issue, "format_mismatch")

    def test_invalid_status_label(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: INFO] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertEqual(issue, "format_mismatch")

    def test_missing_details(self):
        entry = "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - []"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertEqual(issue, "empty_details")

    def test_missing_subtask(self):
        entry = "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertEqual(issue, "empty_subtask")

    def test_invalid_timestamp(self):
        entry = "[9999-99-99 99:99:99] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertEqual(issue, "invalid_timestamp")

    def test_entry_with_special_characters(self):
        entry = "[2026-07-15 18:30:38] - [Task #123] - [STATUS: IN_PROGRESS] - [Details with spaces and symbols @#$]"
        is_valid, issue = validate_entry(entry)
        self.assertTrue(is_valid)

    def test_legacy_format_without_brackets(self):
        """Test entries from legacy format (no brackets around subtask/status/details)."""
        entry = "[2026-07-14 18:00:00] - FEAT-001 Phase 4 - IN_PROGRESS - Creating tests"
        is_valid, issue = validate_entry(entry)
        self.assertFalse(is_valid)
        self.assertEqual(issue, "format_mismatch")


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

    def test_file_with_role(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a file with the exact naming pattern
            filepath = Path(tmpdir) / "backend-engineer_20260715_183000.log"
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


class TestScanLogFiles(unittest.TestCase):
    """Test scan_log_files function."""

    def test_existing_directory(self):
        files = scan_log_files()
        self.assertIsInstance(files, list)
        self.assertTrue(len(files) > 0)

    def test_returns_path_objects(self):
        files = scan_log_files()
        for f in files:
            self.assertIsInstance(f, Path)

    def test_empty_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.compliance_audit.LOG_DIR", Path(tmpdir)):
                files = scan_log_files()
                self.assertEqual(files, [])

    def test_nonexistent_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            fake_dir = Path(tmpdir) / "nonexistent"
            with patch("toolbox.compliance_audit.LOG_DIR", fake_dir):
                files = scan_log_files()
                self.assertEqual(files, [])


class TestAggregateResults(unittest.TestCase):
    """Test aggregate_results function."""

    def test_empty_results(self):
        summary = aggregate_results([])
        self.assertEqual(summary["total_files"], 0)
        self.assertEqual(summary["total_entries"], 0)
        self.assertEqual(summary["total_violations"], 0)

    def test_single_compliant_file(self):
        results = [{
            "filepath": "/tmp/test.log",
            "filename": "test-role_20260715_183000.log",
            "role": "test-role",
            "total_entries": 5,
            "compliant_entries": 5,
            "violations": [],
        }]
        summary = aggregate_results(results)
        self.assertEqual(summary["total_files"], 1)
        self.assertEqual(summary["total_entries"], 5)
        self.assertEqual(summary["compliant_entries"], 5)
        self.assertEqual(summary["total_violations"], 0)
        self.assertEqual(summary["compliant_files"], 1)
        self.assertEqual(summary["non_compliant_files"], 0)
        self.assertIn("test-role", summary["per_role"])

    def test_single_non_compliant_file(self):
        results = [{
            "filepath": "/tmp/test.log",
            "filename": "test-role_20260715_183000.log",
            "role": "test-role",
            "total_entries": 5,
            "compliant_entries": 3,
            "violations": [
                {"line_number": 3, "issue_type": "format_mismatch"},
                {"line_number": 5, "issue_type": "empty_details"},
            ],
        }]
        summary = aggregate_results(results)
        self.assertEqual(summary["total_violations"], 2)
        self.assertEqual(summary["non_compliant_files"], 1)

    def test_multiple_roles(self):
        results = [
            {
                "filepath": "/tmp/a.log",
                "filename": "backend-engineer_20260715_183000.log",
                "role": "backend-engineer",
                "total_entries": 10,
                "compliant_entries": 8,
                "violations": [{"line_number": 1, "issue_type": "format_mismatch"}],
            },
            {
                "filepath": "/tmp/b.log",
                "filename": "test-analyst_20260715_183000.log",
                "role": "test-analyst",
                "total_entries": 5,
                "compliant_entries": 5,
                "violations": [],
            },
        ]
        summary = aggregate_results(results)
        self.assertEqual(summary["total_files"], 2)
        self.assertEqual(summary["total_entries"], 15)
        self.assertEqual(summary["compliant_entries"], 13)
        self.assertEqual(len(summary["per_role"]), 2)
        self.assertEqual(summary["per_role"]["backend-engineer"]["total_entries"], 10)
        self.assertEqual(summary["per_role"]["test-analyst"]["total_entries"], 5)

    def test_unknown_role(self):
        results = [{
            "filepath": "/tmp/test.log",
            "filename": "test.log",
            "role": None,
            "total_entries": 3,
            "compliant_entries": 2,
            "violations": [{"line_number": 3, "issue_type": "format_mismatch"}],
        }]
        summary = aggregate_results(results)
        self.assertIn("unknown", summary["per_role"])


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


class TestGenerateMarkdownReport(unittest.TestCase):
    """Test generate_markdown_report function."""

    def test_report_contains_summary(self):
        summary = {
            "total_files": 5,
            "total_entries": 20,
            "compliant_entries": 15,
            "total_violations": 5,
            "compliant_files": 3,
            "non_compliant_files": 2,
            "per_role": {"backend-engineer": {
                "total_files": 3,
                "total_entries": 10,
                "compliant_entries": 8,
                "total_violations": 2,
                "compliant_files": 2,
                "non_compliant_files": 1,
            }},
            "file_results": [],
        }
        report = generate_markdown_report(summary)
        self.assertIn("# Compliance Audit Report", report)
        self.assertIn("**Feature**: FEAT-006", report)
        self.assertIn("| Total log files audited | 5 |", report)
        self.assertIn("| Overall compliance rate | 75.0% |", report)

    def test_report_contains_per_role(self):
        summary = {
            "total_files": 2,
            "total_entries": 10,
            "compliant_entries": 8,
            "total_violations": 2,
            "compliant_files": 1,
            "non_compliant_files": 1,
            "per_role": {
                "backend-engineer": {
                    "total_files": 1,
                    "total_entries": 5,
                    "compliant_entries": 4,
                    "total_violations": 1,
                    "compliant_files": 0,
                    "non_compliant_files": 1,
                },
                "test-analyst": {
                    "total_files": 1,
                    "total_entries": 5,
                    "compliant_entries": 5,
                    "total_violations": 0,
                    "compliant_files": 1,
                    "non_compliant_files": 0,
                },
            },
            "file_results": [],
        }
        report = generate_markdown_report(summary)
        self.assertIn("### backend-engineer", report)
        self.assertIn("### test-analyst", report)

    def test_report_contains_violations(self):
        summary = {
            "total_files": 1,
            "total_entries": 2,
            "compliant_entries": 1,
            "total_violations": 1,
            "compliant_files": 0,
            "non_compliant_files": 1,
            "per_role": {},
            "file_results": [{
                "filename": "test.log",
                "violations": [{
                    "line_number": 2,
                    "content": "Invalid line",
                    "issue_type": "format_mismatch",
                    "issue_description": "Entry does not match required format",
                    "remediation": "Use specialist_log.py LOG command",
                }],
            }],
        }
        report = generate_markdown_report(summary)
        self.assertIn("## Non-Compliant Entries", report)
        self.assertIn("### test.log", report)
        self.assertIn("Line 2", report)
        self.assertIn("Remediation", report)

    def test_report_contains_remediation_guidance(self):
        summary = {
            "total_files": 1,
            "total_entries": 1,
            "compliant_entries": 1,
            "total_violations": 0,
            "compliant_files": 1,
            "non_compliant_files": 0,
            "per_role": {},
            "file_results": [],
        }
        report = generate_markdown_report(summary)
        self.assertIn("## Remediation Guidance", report)
        self.assertIn("specialist_log.py LOG", report)
        self.assertIn("specialist-log-formatting.md", report)

    def test_report_contains_trend_tracking(self):
        summary = {
            "total_files": 1,
            "total_entries": 1,
            "compliant_entries": 1,
            "total_violations": 0,
            "compliant_files": 1,
            "non_compliant_files": 0,
            "per_role": {},
            "file_results": [],
        }
        report = generate_markdown_report(summary)
        self.assertIn("## Trend Tracking", report)
        self.assertIn(">=95%", report)

    def test_report_trend_tracking_path(self):
        """Verify trend tracking references the new logs/compliance_audit path."""
        summary = {
            "total_files": 1,
            "total_entries": 1,
            "compliant_entries": 1,
            "total_violations": 0,
            "compliant_files": 1,
            "non_compliant_files": 0,
            "per_role": {},
            "file_results": [],
        }
        report = generate_markdown_report(summary)
        self.assertIn("logs/compliance_audit/", report)
        self.assertNotIn("internal-docs/05_reports/", report)

    def test_no_violations_message(self):
        summary = {
            "total_files": 1,
            "total_entries": 5,
            "compliant_entries": 5,
            "total_violations": 0,
            "compliant_files": 1,
            "non_compliant_files": 0,
            "per_role": {},
            "file_results": [],
        }
        report = generate_markdown_report(summary)
        self.assertIn("No violations found", report)


class TestGenerateJsonReport(unittest.TestCase):
    """Test generate_json_report function."""

    def test_json_is_valid(self):
        summary = {
            "total_files": 2,
            "total_entries": 10,
            "compliant_entries": 8,
            "total_violations": 2,
            "compliant_files": 1,
            "non_compliant_files": 1,
            "per_role": {
                "backend-engineer": {
                    "total_files": 1,
                    "total_entries": 5,
                    "compliant_entries": 4,
                    "total_violations": 1,
                    "compliant_files": 0,
                    "non_compliant_files": 1,
                },
            },
            "file_results": [{
                "filename": "test.log",
                "violations": [{
                    "line_number": 3,
                    "issue_type": "format_mismatch",
                    "issue_description": "Entry does not match required format",
                }],
            }],
        }
        json_str = generate_json_report(summary)
        data = json.loads(json_str)

        self.assertEqual(data["feature"], "FEAT-006")
        self.assertEqual(data["summary"]["total_files"], 2)
        self.assertEqual(data["summary"]["overall_compliance_rate"], 80.0)
        self.assertIn("backend-engineer", data["per_role"])
        self.assertEqual(len(data["violations"]), 1)
        self.assertEqual(data["violations"][0]["line_number"], 3)

    def test_json_zero_entries(self):
        summary = {
            "total_files": 0,
            "total_entries": 0,
            "compliant_entries": 0,
            "total_violations": 0,
            "compliant_files": 0,
            "non_compliant_files": 0,
            "per_role": {},
            "file_results": [],
        }
        json_str = generate_json_report(summary)
        data = json.loads(json_str)
        self.assertIsNone(data["summary"]["overall_compliance_rate"])

    def test_json_per_role_rate(self):
        summary = {
            "total_files": 1,
            "total_entries": 10,
            "compliant_entries": 7,
            "total_violations": 3,
            "compliant_files": 0,
            "non_compliant_files": 1,
            "per_role": {
                "test-role": {
                    "total_files": 1,
                    "total_entries": 10,
                    "compliant_entries": 7,
                    "total_violations": 3,
                    "compliant_files": 0,
                    "non_compliant_files": 1,
                },
            },
            "file_results": [],
        }
        json_str = generate_json_report(summary)
        data = json.loads(json_str)
        self.assertEqual(data["per_role"]["test-role"]["compliance_rate"], 70.0)


class TestSaveReport(unittest.TestCase):
    """Test save_report function."""

    def test_save_markdown_report(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.compliance_audit.REPORTS_DIR", Path(tmpdir)):
                report_path = save_report("# Test Report", "markdown")
                self.assertTrue(report_path.exists())
                self.assertTrue(report_path.name.startswith("compliance_audit_"))
                self.assertTrue(report_path.name.endswith(".md"))
                content = report_path.read_text(encoding="utf-8")
                self.assertIn("# Test Report", content)

    def test_save_json_report(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("toolbox.compliance_audit.REPORTS_DIR", Path(tmpdir)):
                report_path = save_report('{"test": true}', "json")
                self.assertTrue(report_path.exists())
                self.assertTrue(report_path.name.endswith(".json"))

    def test_creates_directory_if_needed(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            new_dir = Path(tmpdir) / "nonexistent" / "subdir"
            with patch("toolbox.compliance_audit.REPORTS_DIR", new_dir):
                report_path = save_report("# Test Report", "markdown")
                self.assertTrue(new_dir.exists())
                self.assertTrue(report_path.exists())


class TestRunAudit(unittest.TestCase):
    """Test run_audit function."""

    def test_audit_returns_results(self):
        result = run_audit(format="markdown")
        self.assertIn("summary", result)
        self.assertIn("report_path", result)
        self.assertIn("report_format", result)
        self.assertEqual(result["report_format"], "markdown")

    def test_audit_json_format(self):
        result = run_audit(format="json")
        self.assertEqual(result["report_format"], "json")
        self.assertTrue(Path(result["report_path"]).exists())

    def test_audit_summary_structure(self):
        result = run_audit(format="markdown")
        summary = result["summary"]
        self.assertIn("total_files", summary)
        self.assertIn("total_entries", summary)
        self.assertIn("compliant_entries", summary)
        self.assertIn("total_violations", summary)
        self.assertIn("per_role", summary)

    def test_audit_report_saved(self):
        result = run_audit(format="markdown")
        report_path = Path(result["report_path"])
        self.assertTrue(report_path.exists())
        content = report_path.read_text(encoding="utf-8")
        self.assertIn("Compliance Audit Report", content)

    def test_audit_report_in_logs_dir(self):
        """Verify reports are saved to logs/compliance_audit/ not internal-docs."""
        result = run_audit(format="markdown")
        report_path = Path(result["report_path"])
        self.assertIn("logs/compliance_audit", str(report_path))


class TestSharedModule(unittest.TestCase):
    """Test that compliance_audit uses shared log_format module."""

    def test_uses_shared_valid_status_labels(self):
        from toolbox import log_format
        from toolbox import compliance_audit

        self.assertIs(compliance_audit.VALID_STATUS_LABELS, log_format.VALID_STATUS_LABELS)

    def test_uses_shared_format_entry(self):
        from toolbox import log_format
        from toolbox import compliance_audit

        self.assertIs(compliance_audit.format_entry, log_format.format_entry)

    def test_compliance_audit_has_own_entry_pattern(self):
        """Verify compliance_audit has its own permissive ENTRY_PATTERN
        that allows empty brackets for distinct error key detection."""
        from toolbox import log_format
        from toolbox import compliance_audit

        # They should be different - compliance_audit uses [^\\]]* (allows empty)
        # while log_format uses [^\\]]+ (requires non-empty)
        self.assertIsNot(
            compliance_audit.ENTRY_PATTERN,
            log_format.ENTRY_PATTERN,
            "compliance_audit should have its own permissive ENTRY_PATTERN"
        )

        # Verify compliance_audit pattern allows empty brackets
        self.assertIsNotNone(
            compliance_audit.ENTRY_PATTERN.match(
                "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - []"
            )
        )

        # Verify log_format pattern rejects empty brackets
        self.assertIsNone(
            log_format.ENTRY_PATTERN.match(
                "[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - []"
            )
        )


class TestIntegration(unittest.TestCase):
    """Integration tests for end-to-end audit workflow."""

    def test_full_audit_workflow(self):
        """Test complete audit workflow with temporary log directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir) / "logs"
            reports_dir = Path(tmpdir) / "reports"

            # Create test log files
            log_dir.mkdir(parents=True)

            # Compliant file
            compliant_file = log_dir / "backend-engineer_20260715_183000.log"
            compliant_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8",
            )

            # Non-compliant file
            non_compliant_file = log_dir / "test-analyst_20260715_183000.log"
            non_compliant_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: COMPLETE] - [Details]\n"
                "Invalid line without format\n"
                "[2026-07-15 18:31:00] - [Subtask2] - [STATUS: FAILED] - [More details]\n",
                encoding="utf-8",
            )

            with patch("toolbox.compliance_audit.LOG_DIR", log_dir):
                with patch("toolbox.compliance_audit.REPORTS_DIR", reports_dir):
                    result = run_audit(format="markdown")

                    summary = result["summary"]
                    self.assertEqual(summary["total_files"], 2)
                    self.assertEqual(summary["total_entries"], 4)
                    self.assertEqual(summary["compliant_entries"], 3)
                    self.assertEqual(summary["total_violations"], 1)
                    self.assertEqual(summary["compliant_files"], 1)
                    self.assertEqual(summary["non_compliant_files"], 1)

                    # Check per-role breakdown
                    self.assertIn("backend-engineer", summary["per_role"])
                    self.assertIn("test-analyst", summary["per_role"])
                    self.assertEqual(
                        summary["per_role"]["backend-engineer"]["compliant_entries"], 1
                    )
                    self.assertEqual(
                        summary["per_role"]["test-analyst"]["compliant_entries"], 2
                    )

                    # Check report was saved
                    self.assertTrue(Path(result["report_path"]).exists())

    def test_audit_with_json_output(self):
        """Test audit with JSON format output."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log_dir = Path(tmpdir) / "logs"
            reports_dir = Path(tmpdir) / "reports"

            log_dir.mkdir(parents=True)
            log_file = log_dir / "backend-engineer_20260715_183000.log"
            log_file.write_text(
                "[2026-07-15 18:30:38] - [Subtask] - [STATUS: IN_PROGRESS] - [Details]\n",
                encoding="utf-8",
            )

            with patch("toolbox.compliance_audit.LOG_DIR", log_dir):
                with patch("toolbox.compliance_audit.REPORTS_DIR", reports_dir):
                    result = run_audit(format="json")

                    # Verify JSON is valid
                    report_content = Path(result["report_path"]).read_text(encoding="utf-8")
                    data = json.loads(report_content)

                    self.assertEqual(data["summary"]["overall_compliance_rate"], 100.0)
                    self.assertEqual(data["summary"]["total_violations"], 0)


if __name__ == "__main__":
    unittest.main()
