import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

# Add parent directory to path so we can import toolbox modules
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from toolbox.board_utils import (
    auto_approve_delegation,
    resolve_document_path,
    read_document_preamble,
    write_document_preamble,
    _log_auto_approval,
)


@pytest.fixture
def temp_repo(tmp_path):
    """Create a temporary repository structure for testing."""
    # Create the document directory
    feat_dir = tmp_path / "internal-docs" / "04_planning" / "04b_features"
    feat_dir.mkdir(parents=True, exist_ok=True)

    # Create the logs directory
    log_dir = tmp_path / "logs" / "specialist_logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    return tmp_path


@pytest.fixture
def sample_draft_doc(temp_repo):
    """Create a sample DRAFT document for testing."""
    doc_path = (
        temp_repo / "internal-docs" / "04_planning" / "04b_features"
        / "FEAT-100-test-draft-document.md"
    )
    doc_path.write_text(
        "---\n"
        "id: FEAT-100\n"
        "title: Test Draft Document\n"
        "version: 1.0.0\n"
        "status: DRAFT\n"
        "created: 2026-07-15 10:00:00\n"
        "updated: 2026-07-15 10:00:00\n"
        "related_docs: []\n"
        "---\n"
        "\n"
        "# Test Draft Document\n"
        "\n"
        "This is a test document in DRAFT status.\n"
    )
    return doc_path


@pytest.fixture
def sample_approved_doc(temp_repo):
    """Create a sample APPROVED document for testing."""
    doc_path = (
        temp_repo / "internal-docs" / "04_planning" / "04b_features"
        / "FEAT-101-test-approved-document.md"
    )
    doc_path.write_text(
        "---\n"
        "id: FEAT-101\n"
        "title: Test Approved Document\n"
        "version: 1.0.0\n"
        "status: APPROVED\n"
        "created: 2026-07-15 10:00:00\n"
        "updated: 2026-07-15 10:00:00\n"
        "related_docs: []\n"
        "---\n"
        "\n"
        "# Test Approved Document\n"
        "\n"
        "This is a test document in APPROVED status.\n"
    )
    return doc_path


@pytest.fixture
def sample_in_review_doc(temp_repo):
    """Create a sample IN_REVIEW document for testing."""
    doc_path = (
        temp_repo / "internal-docs" / "04_planning" / "04b_features"
        / "FEAT-102-test-in-review-document.md"
    )
    doc_path.write_text(
        "---\n"
        "id: FEAT-102\n"
        "title: Test In Review Document\n"
        "version: 1.0.0\n"
        "status: IN_REVIEW\n"
        "created: 2026-07-15 10:00:00\n"
        "updated: 2026-07-15 10:00:00\n"
        "related_docs: []\n"
        "---\n"
        "\n"
        "# Test In Review Document\n"
        "\n"
        "This is a test document in IN_REVIEW status.\n"
    )
    return doc_path


class TestResolveDocumentPath:
    """Tests for resolve_document_path function."""

    def test_resolves_known_doc_in_real_repo(self):
        """Test that a known document in the real repo resolves correctly."""
        path = resolve_document_path("FEAT-002")
        assert path is not None
        assert path.exists()
        assert "FEAT-002" in str(path)

    def test_returns_none_for_nonexistent_doc(self):
        """Test that a non-existent document returns None."""
        path = resolve_document_path("FEAT-999")
        assert path is None

    def test_returns_none_for_invalid_format(self):
        """Test that an invalid doc_id format returns None."""
        path = resolve_document_path("not-a-valid-id")
        assert path is None

    def test_returns_none_for_empty_string(self):
        """Test that an empty string returns None."""
        path = resolve_document_path("")
        assert path is None


class TestReadDocumentPreamble:
    """Tests for read_document_preamble function."""

    def test_reads_preamble_from_real_doc(self):
        """Test reading preamble from a real document."""
        path = resolve_document_path("FEAT-002")
        assert path is not None
        metadata = read_document_preamble(path)
        assert metadata["id"] == "FEAT-002"
        assert "status" in metadata

    def test_raises_on_malformed_doc(self, tmp_path):
        """Test that a malformed document raises ValueError."""
        doc_path = tmp_path / "malformed.md"
        doc_path.write_text("# Just a heading\n\nNo preamble here.")
        with pytest.raises(ValueError, match="Missing YAML preamble"):
            read_document_preamble(doc_path)


class TestWriteDocumentPreamble:
    """Tests for write_document_preamble function."""

    def test_updates_preamble_preserving_body(self, tmp_path):
        """Test that preamble is updated while body is preserved."""
        doc_path = tmp_path / "test-doc.md"
        doc_path.write_text(
            "---\n"
            "id: TEST-001\n"
            "status: DRAFT\n"
            "---\n"
            "\n"
            "# Test Body\n"
            "\n"
            "This content should be preserved.\n"
        )

        new_metadata = {"id": "TEST-001", "status": "APPROVED"}
        write_document_preamble(doc_path, new_metadata)

        content = doc_path.read_text()
        assert "APPROVED" in content
        assert "This content should be preserved." in content


class TestAutoApproveDelegation:
    """Tests for auto_approve_delegation function."""

    def test_approves_draft_document(self, temp_repo, sample_draft_doc):
        """Test that a DRAFT document is approved."""
        with patch("toolbox.board_utils.REPO_ROOT", temp_repo):
            with patch("toolbox.board_utils.stage_board"):
                with patch("toolbox.board_utils.run_git"):
                    result = auto_approve_delegation(
                        "FEAT-100", task_id="TASK-0002"
                    )

        assert result["success"] is True
        assert result["previous_status"] == "DRAFT"
        assert result["new_status"] == "APPROVED"
        assert "auto-approved" in result["message"].lower()
        assert result["error"] is None

        # Verify file was actually updated
        metadata = read_document_preamble(sample_draft_doc)
        assert metadata["status"] == "APPROVED"

    def test_idempotent_on_approved_document(
        self, temp_repo, sample_approved_doc
    ):
        """Test that an already APPROVED document is not modified."""
        with patch("toolbox.board_utils.REPO_ROOT", temp_repo):
            result = auto_approve_delegation("FEAT-101", task_id="TASK-0002")

        assert result["success"] is True
        assert result["previous_status"] == "APPROVED"
        assert result["new_status"] == "APPROVED"
        assert "already" in result["message"].lower()
        assert result["error"] is None

    def test_approves_in_review_document(self, temp_repo, sample_in_review_doc):
        """Test that an IN_REVIEW document is approved."""
        with patch("toolbox.board_utils.REPO_ROOT", temp_repo):
            with patch("toolbox.board_utils.stage_board"):
                with patch("toolbox.board_utils.run_git"):
                    result = auto_approve_delegation(
                        "FEAT-102", task_id="TASK-0002"
                    )

        assert result["success"] is True
        assert result["previous_status"] == "IN_REVIEW"
        assert result["new_status"] == "APPROVED"
        assert result["error"] is None

        # Verify file was actually updated
        metadata = read_document_preamble(sample_in_review_doc)
        assert metadata["status"] == "APPROVED"

    def test_invalid_doc_id_format(self):
        """Test that an invalid doc_id format returns an error."""
        result = auto_approve_delegation("invalid-doc")
        assert result["success"] is False
        assert result["error"] is not None
        assert "Invalid document ID format" in result["error"]

    def test_nonexistent_document(self):
        """Test that a non-existent document returns an error."""
        result = auto_approve_delegation("FEAT-999")
        assert result["success"] is False
        assert result["error"] is not None
        assert "not found" in result["error"].lower()

    def test_returns_dict_with_all_keys(self, temp_repo, sample_draft_doc):
        """Test that the result dict contains all expected keys."""
        expected_keys = {
            "success",
            "doc_id",
            "filepath",
            "previous_status",
            "new_status",
            "message",
            "error",
        }
        with patch("toolbox.board_utils.REPO_ROOT", temp_repo):
            with patch("toolbox.board_utils.stage_board"):
                with patch("toolbox.board_utils.run_git"):
                    result = auto_approve_delegation(
                        "FEAT-100", task_id="TASK-0002"
                    )

        assert set(result.keys()) == expected_keys

    def test_task_id_optional(self, temp_repo, sample_draft_doc):
        """Test that task_id is optional."""
        with patch("toolbox.board_utils.REPO_ROOT", temp_repo):
            with patch("toolbox.board_utils.stage_board"):
                with patch("toolbox.board_utils.run_git"):
                    result = auto_approve_delegation("FEAT-100")

        assert result["success"] is True

    def test_multiple_calls_are_idempotent(
        self, temp_repo, sample_draft_doc
    ):
        """Test that calling auto_approve_delegation twice is safe."""
        with patch("toolbox.board_utils.REPO_ROOT", temp_repo):
            with patch("toolbox.board_utils.stage_board"):
                with patch("toolbox.board_utils.run_git"):
                    result1 = auto_approve_delegation(
                        "FEAT-100", task_id="TASK-0002"
                    )
                    result2 = auto_approve_delegation(
                        "FEAT-100", task_id="TASK-0002"
                    )

        assert result1["success"] is True
        assert result1["previous_status"] == "DRAFT"
        assert result2["success"] is True
        assert result2["previous_status"] == "APPROVED"
        assert "already" in result2["message"].lower()

    def test_git_persistence_after_approval(
        self, temp_repo, sample_draft_doc
    ):
        """Test that stage_board and git commit are called after approval."""
        with patch("toolbox.board_utils.REPO_ROOT", temp_repo):
            with patch("toolbox.board_utils.stage_board") as mock_stage:
                with patch("toolbox.board_utils.run_git") as mock_git:
                    result = auto_approve_delegation(
                        "FEAT-100", task_id="TASK-0002"
                    )

        assert result["success"] is True
        mock_stage.assert_called_once()
        mock_git.assert_called_once_with(
            ["commit", "-m", "chore: auto-approve FEAT-100 for delegation"]
        )

    def test_no_git_persistence_on_already_approved(
        self, temp_repo, sample_approved_doc
    ):
        """Test that no git operations occur when document is already approved."""
        with patch("toolbox.board_utils.REPO_ROOT", temp_repo):
            with patch("toolbox.board_utils.stage_board") as mock_stage:
                with patch("toolbox.board_utils.run_git") as mock_git:
                    result = auto_approve_delegation(
                        "FEAT-101", task_id="TASK-0002"
                    )

        assert result["success"] is True
        assert "already" in result["message"].lower()
        mock_stage.assert_not_called()
        mock_git.assert_not_called()

    def test_no_git_persistence_on_error(self):
        """Test that no git operations occur when document is not found."""
        with patch("toolbox.board_utils.stage_board") as mock_stage:
            with patch("toolbox.board_utils.run_git") as mock_git:
                result = auto_approve_delegation("FEAT-999")

        assert result["success"] is False
        mock_stage.assert_not_called()
        mock_git.assert_not_called()


class TestLogAutoApproval:
    """Tests for _log_auto_approval function."""

    def test_creates_log_file(self, temp_repo):
        """Test that a log file is created in the correct directory."""
        log_dir = temp_repo / "logs" / "specialist_logs"
        test_path = temp_repo / "test-doc.md"

        _log_auto_approval(
            "FEAT-100", test_path, "TASK-0002", was_approved=True,
            repo_root=temp_repo
        )

        # Check that a log file was created
        log_files = list(log_dir.glob("backend-engineer_*.log"))
        assert len(log_files) >= 1

    def test_log_format(self, temp_repo):
        """Test that log entries follow the required format."""
        log_dir = temp_repo / "logs" / "specialist_logs"
        test_path = temp_repo / "test-doc.md"

        _log_auto_approval(
            "FEAT-100", test_path, "TASK-0002", was_approved=True,
            repo_root=temp_repo
        )

        # Read the last created log file
        log_files = sorted(log_dir.glob("backend-engineer_*.log"))
        log_content = log_files[-1].read_text()

        # Verify format: [TIMESTAMP] - [TASK-...] - [STATUS: INFO] - [DETAILS]
        assert "[STATUS: INFO]" in log_content
        assert "FEAT-100" in log_content

    def test_log_append_preserves_multiple_entries(self, temp_repo):
        """Test that multiple calls to _log_auto_approval append entries instead of overwriting."""
        test_path = temp_repo / "test-doc.md"

        with patch("toolbox.board_utils.datetime") as mock_dt:
            mock_now = MagicMock()
            mock_now.strftime.side_effect = lambda fmt: {
                "%Y-%m-%d %H:%M:%S": "2026-07-15 12:00:00",
                "%Y%m%d_%H%M%S": "20260715_120000",
            }.get(fmt, fmt)
            mock_dt.now.return_value = mock_now

            _log_auto_approval(
                "FEAT-100", test_path, "TASK-0002", was_approved=True,
                repo_root=temp_repo
            )
            _log_auto_approval(
                "FEAT-101", test_path, "TASK-0002", was_approved=False,
                repo_root=temp_repo
            )

        # Read the log file - should contain both entries
        log_files = sorted(
            (temp_repo / "logs" / "specialist_logs").glob("backend-engineer_*.log")
        )
        assert len(log_files) >= 1
        log_content = log_files[-1].read_text()

        # Both entries should be present
        assert "FEAT-100" in log_content
        assert "FEAT-101" in log_content

        # Count the number of log lines
        lines = [line for line in log_content.strip().split("\n") if line]
        assert len(lines) >= 2, (
            f"Expected at least 2 log lines, got {len(lines)}: {lines}"
        )

    def test_log_append_with_explicit_same_file(self, temp_repo):
        """Test that appending to an existing file preserves previous content."""
        log_dir = temp_repo / "logs" / "specialist_logs"
        test_path = temp_repo / "test-doc.md"

        # Create a pre-existing log file with content
        existing_log = log_dir / "backend-engineer_20260715_120000.log"
        existing_log.write_text(
            "[2026-07-15 12:00:00] - [existing] - [STATUS: INFO] - "
            "[Previous entry]\n"
        )

        # Call _log_auto_approval with a fixed timestamp
        with patch("toolbox.board_utils.datetime") as mock_dt:
            mock_now = MagicMock()
            mock_now.strftime.side_effect = lambda fmt: {
                "%Y-%m-%d %H:%M:%S": "2026-07-15 12:00:00",
                "%Y%m%d_%H%M%S": "20260715_120000",
            }.get(fmt, fmt)
            mock_dt.now.return_value = mock_now

            _log_auto_approval(
                "FEAT-200", test_path, "TASK-0002", was_approved=True,
                repo_root=temp_repo
            )

        # The existing entry should still be present
        log_content = existing_log.read_text()
        assert "Previous entry" in log_content
        assert "FEAT-200" in log_content
