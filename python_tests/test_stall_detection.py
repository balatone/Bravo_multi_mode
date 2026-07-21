"""
Unit tests for FEAT-003: Stall Detection and Recovery Protocol.

Tests cover:
- max_turns_tracker: turn counter triggers stall at limit
- unresponsiveness_monitor: heartbeat detects inactivity
- classify_stall: correct recovery path routing
- log_stall_event: stall event logging
- execute_manual_resume: manual resume recovery path
- execute_re_delegation: re-delegation recovery path
"""

import sys
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

# Add parent directory to path so we can import toolbox modules
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from toolbox.board_utils import (
    # Stall detection
    max_turns_tracker,
    unresponsiveness_monitor,
    classify_stall,
    # Recovery paths
    execute_manual_resume,
    execute_re_delegation,
    # Logging
    log_stall_event,
    # Constants
    STALL_CAUSE_MAX_TURNS,
    STALL_CAUSE_UNRESPONSIVE,
    STALL_CAUSE_ERROR,
    RECOVERY_MANUAL_RESUME,
    RECOVERY_RE_DELEGATION,
    DEFAULT_UNRESPONSIVE_TIMEOUT_SECONDS,
    StallResult,
)


@pytest.fixture
def temp_repo(tmp_path):
    """Create a temporary repository structure for testing."""
    log_dir = tmp_path / "logs" / "specialist_logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    board_dir = tmp_path / ".board"
    board_dir.mkdir(parents=True, exist_ok=True)
    return tmp_path


# ──────────────────────────────────────────────────────────────
# Test: StallResult data class
# ──────────────────────────────────────────────────────────────


class TestStallResult:
    """Tests for the StallResult data class."""

    def test_stalled_result(self):
        result = StallResult(
            is_stalled=True,
            cause=STALL_CAUSE_MAX_TURNS,
            details="test details",
        )
        assert result.is_stalled is True
        assert result.cause == STALL_CAUSE_MAX_TURNS
        assert result.details == "test details"

    def test_not_stalled_result(self):
        result = StallResult(is_stalled=False)
        assert result.is_stalled is False
        assert result.cause is None
        assert result.details == ""

    def test_to_dict(self):
        result = StallResult(
            is_stalled=True,
            cause=STALL_CAUSE_UNRESPONSIVE,
            details="unresponsive",
        )
        d = result.to_dict()
        assert d == {
            "is_stalled": True,
            "cause": STALL_CAUSE_UNRESPONSIVE,
            "details": "unresponsive",
        }

    def test_repr(self):
        result = StallResult(
            is_stalled=True,
            cause=STALL_CAUSE_MAX_TURNS,
            details="test",
        )
        assert "is_stalled=True" in repr(result)
        assert "MAX_TURNS_EXHAUSTED" in repr(result)


# ──────────────────────────────────────────────────────────────
# Test: max_turns_tracker
# ──────────────────────────────────────────────────────────────


class TestMaxTurnsTracker:
    """Tests for max_turns_tracker function."""

    def test_no_stall_within_limit(self):
        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=10,
            max_turns=40,
        )
        assert result.is_stalled is False
        assert result.cause is None

    def test_stall_at_exact_limit(self):
        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=40,
            max_turns=40,
        )
        assert result.is_stalled is True
        assert result.cause == STALL_CAUSE_MAX_TURNS
        assert "40/40" in result.details

    def test_stall_above_limit(self):
        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=41,
            max_turns=40,
        )
        assert result.is_stalled is True
        assert result.cause == STALL_CAUSE_MAX_TURNS

    def test_no_stall_at_zero_turns(self):
        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=0,
            max_turns=40,
        )
        assert result.is_stalled is False

    def test_boundary_low_complexity(self):
        """Test with low complexity max_turns (20)."""
        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=19,
            max_turns=20,
        )
        assert result.is_stalled is False

        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=20,
            max_turns=20,
        )
        assert result.is_stalled is True

    def test_boundary_high_complexity(self):
        """Test with high complexity max_turns (60)."""
        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=60,
            max_turns=60,
        )
        assert result.is_stalled is True

        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=59,
            max_turns=60,
        )
        assert result.is_stalled is False

    def test_negative_current_turns_raises(self):
        with pytest.raises(ValueError, match="non-negative"):
            max_turns_tracker(
                subagent_id="test",
                current_turns=-1,
                max_turns=40,
            )

    def test_zero_max_turns_raises(self):
        with pytest.raises(ValueError, match="positive"):
            max_turns_tracker(
                subagent_id="test",
                current_turns=0,
                max_turns=0,
            )

    def test_negative_max_turns_raises(self):
        with pytest.raises(ValueError, match="positive"):
            max_turns_tracker(
                subagent_id="test",
                current_turns=0,
                max_turns=-10,
            )

    def test_details_contain_subagent_id(self):
        result = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=40,
            max_turns=40,
        )
        assert "role:worker:backend-engineer" in result.details


# ──────────────────────────────────────────────────────────────
# Test: unresponsiveness_monitor
# ──────────────────────────────────────────────────────────────


class TestUnresponsivenessMonitor:
    """Tests for unresponsiveness_monitor function."""

    def test_no_stall_recent_activity(self):
        recent = datetime.now() - timedelta(seconds=30)
        result = unresponsiveness_monitor(
            subagent_id="role:worker:backend-engineer",
            last_activity_timestamp=recent,
        )
        assert result.is_stalled is False
        assert result.cause is None

    def test_stall_after_default_timeout(self):
        """Test stall detection with default 15-minute timeout."""
        old = datetime.now() - timedelta(minutes=16)
        result = unresponsiveness_monitor(
            subagent_id="role:worker:backend-engineer",
            last_activity_timestamp=old,
        )
        assert result.is_stalled is True
        assert result.cause == STALL_CAUSE_UNRESPONSIVE

    def test_stall_at_exact_timeout(self):
        """Test stall detection at exactly the timeout threshold."""
        old = datetime.now() - timedelta(
            seconds=DEFAULT_UNRESPONSIVE_TIMEOUT_SECONDS
        )
        result = unresponsiveness_monitor(
            subagent_id="role:worker:backend-engineer",
            last_activity_timestamp=old,
        )
        assert result.is_stalled is True
        assert result.cause == STALL_CAUSE_UNRESPONSIVE

    def test_no_stall_just_before_timeout(self):
        """Test no stall when activity is just before timeout."""
        recent = datetime.now() - timedelta(
            seconds=DEFAULT_UNRESPONSIVE_TIMEOUT_SECONDS - 1
        )
        result = unresponsiveness_monitor(
            subagent_id="role:worker:backend-engineer",
            last_activity_timestamp=recent,
        )
        assert result.is_stalled is False

    def test_custom_timeout(self):
        """Test with a custom timeout value."""
        old = datetime.now() - timedelta(seconds=121)
        result = unresponsiveness_monitor(
            subagent_id="role:worker:backend-engineer",
            last_activity_timestamp=old,
            timeout_seconds=120,
        )
        assert result.is_stalled is True

        recent = datetime.now() - timedelta(seconds=119)
        result = unresponsiveness_monitor(
            subagent_id="role:worker:backend-engineer",
            last_activity_timestamp=recent,
            timeout_seconds=120,
        )
        assert result.is_stalled is False

    def test_negative_timeout_raises(self):
        old = datetime.now() - timedelta(minutes=1)
        with pytest.raises(ValueError, match="positive"):
            unresponsiveness_monitor(
                subagent_id="test",
                last_activity_timestamp=old,
                timeout_seconds=-1,
            )

    def test_zero_timeout_raises(self):
        old = datetime.now() - timedelta(minutes=1)
        with pytest.raises(ValueError, match="positive"):
            unresponsiveness_monitor(
                subagent_id="test",
                last_activity_timestamp=old,
                timeout_seconds=0,
            )

    def test_details_contain_elapsed_time(self):
        old = datetime.now() - timedelta(minutes=20)
        result = unresponsiveness_monitor(
            subagent_id="role:worker:backend-engineer",
            last_activity_timestamp=old,
        )
        assert "role:worker:backend-engineer" in result.details
        # Should contain elapsed time info
        assert "s" in result.details

    def test_default_timeout_value(self):
        """Verify the default timeout is 15 minutes (900 seconds)."""
        assert DEFAULT_UNRESPONSIVE_TIMEOUT_SECONDS == 900


# ──────────────────────────────────────────────────────────────
# Test: classify_stall
# ──────────────────────────────────────────────────────────────


class TestClassifyStall:
    """Tests for classify_stall function."""

    def test_max_turns_routes_to_manual_resume(self):
        path = classify_stall(STALL_CAUSE_MAX_TURNS)
        assert path == RECOVERY_MANUAL_RESUME

    def test_unresponsive_routes_to_manual_resume(self):
        path = classify_stall(STALL_CAUSE_UNRESPONSIVE)
        assert path == RECOVERY_MANUAL_RESUME

    def test_error_routes_to_re_delegation(self):
        path = classify_stall(STALL_CAUSE_ERROR)
        assert path == RECOVERY_RE_DELEGATION

    def test_unknown_cause_routes_to_re_delegation(self):
        """Any unknown cause should route to re-delegation."""
        path = classify_stall("UNKNOWN_CAUSE")
        assert path == RECOVERY_RE_DELEGATION

    def test_empty_string_routes_to_re_delegation(self):
        path = classify_stall("")
        assert path == RECOVERY_RE_DELEGATION

    def test_crash_cause_routes_to_re_delegation(self):
        path = classify_stall("CRASH")
        assert path == RECOVERY_RE_DELEGATION

    def test_network_error_routes_to_re_delegation(self):
        path = classify_stall("NETWORK_ERROR")
        assert path == RECOVERY_RE_DELEGATION


# ──────────────────────────────────────────────────────────────
# Test: log_stall_event
# ──────────────────────────────────────────────────────────────


class TestLogStallEvent:
    """Tests for log_stall_event function."""

    def test_creates_log_file(self, temp_repo):
        log_path = log_stall_event(
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_MAX_TURNS,
            recovery_path=RECOVERY_MANUAL_RESUME,
            task_id="TASK-0002",
            repo_root=temp_repo,
        )
        assert log_path.exists()
        assert log_path.parent.name == "specialist_logs"
        assert log_path.name.startswith("orchestrator_")

    def test_log_format(self, temp_repo):
        log_path = log_stall_event(
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_MAX_TURNS,
            recovery_path=RECOVERY_MANUAL_RESUME,
            task_id="TASK-0002",
            details="40/40 turns",
            repo_root=temp_repo,
        )
        content = log_path.read_text()
        assert "[STATUS: FAILED]" in content
        assert "TASK-0002" in content
        assert "role:worker:backend-engineer" in content
        assert "MAX_TURNS_EXHAUSTED" in content
        assert "MANUAL_RESUME" in content
        assert "40/40 turns" in content

    def test_log_without_task_id(self, temp_repo):
        log_path = log_stall_event(
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_ERROR,
            recovery_path=RECOVERY_RE_DELEGATION,
            repo_root=temp_repo,
        )
        content = log_path.read_text()
        assert "unknown" in content

    def test_log_without_details(self, temp_repo):
        log_path = log_stall_event(
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_UNRESPONSIVE,
            recovery_path=RECOVERY_MANUAL_RESUME,
            task_id="TASK-0002",
            repo_root=temp_repo,
        )
        content = log_path.read_text()
        # Should not have ", details=" in the output
        assert "details=" not in content

    def test_multiple_logs_append(self, temp_repo):
        with patch("toolbox.board_utils.datetime") as mock_dt:
            mock_now = MagicMock()
            mock_now.strftime.side_effect = lambda fmt: {
                "%Y-%m-%d %H:%M:%S": "2026-07-15 12:00:00",
                "%Y%m%d_%H%M%S": "20260715_120000",
            }.get(fmt, fmt)
            mock_dt.now.return_value = mock_now

            log_stall_event(
                subagent_id="agent-1",
                cause=STALL_CAUSE_MAX_TURNS,
                recovery_path=RECOVERY_MANUAL_RESUME,
                task_id="TASK-0002",
                repo_root=temp_repo,
            )
            log_stall_event(
                subagent_id="agent-2",
                cause=STALL_CAUSE_ERROR,
                recovery_path=RECOVERY_RE_DELEGATION,
                task_id="TASK-0002",
                repo_root=temp_repo,
            )

        log_dir = temp_repo / "logs" / "specialist_logs"
        log_files = sorted(log_dir.glob("orchestrator_*.log"))
        assert len(log_files) >= 1
        content = log_files[-1].read_text()
        assert "agent-1" in content
        assert "agent-2" in content
        lines = [line for line in content.strip().split("\n") if line]
        assert len(lines) >= 2


# ──────────────────────────────────────────────────────────────
# Test: execute_manual_resume
# ──────────────────────────────────────────────────────────────


class TestExecuteManualResume:
    """Tests for execute_manual_resume function."""

    def test_returns_manual_resume_path(self, temp_repo):
        result = execute_manual_resume(
            task_id="TASK-0002",
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_MAX_TURNS,
            details="40/40 turns",
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["recovery_path"] == RECOVERY_MANUAL_RESUME
        assert result["task_id"] == "TASK-0002"
        assert result["subagent_id"] == "role:worker:backend-engineer"
        assert result["cause"] == STALL_CAUSE_MAX_TURNS

    def test_creates_log_file(self, temp_repo):
        result = execute_manual_resume(
            task_id="TASK-0002",
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_UNRESPONSIVE,
            repo_root=temp_repo,
        )
        log_path = Path(result["log_path"])
        assert log_path.exists()
        content = log_path.read_text()
        assert "UNRESPONSIVE_TIMEOUT" in content
        assert "MANUAL_RESUME" in content

    def test_unresponsive_cause_routes_to_manual_resume(self, temp_repo):
        result = execute_manual_resume(
            task_id="TASK-0002",
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_UNRESPONSIVE,
            repo_root=temp_repo,
        )
        assert result["recovery_path"] == RECOVERY_MANUAL_RESUME

    def test_message_contains_key_info(self, temp_repo):
        result = execute_manual_resume(
            task_id="TASK-0002",
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_MAX_TURNS,
            repo_root=temp_repo,
        )
        assert "TASK-0002" in result["message"]
        assert "MANUAL_RESUME" in result["message"]
        assert "role:worker:backend-engineer" in result["message"]

    def test_missing_task_does_not_raise(self, temp_repo):
        """Test that a missing task on the board does not raise an error."""
        result = execute_manual_resume(
            task_id="TASK-9999",
            subagent_id="role:worker:backend-engineer",
            cause=STALL_CAUSE_MAX_TURNS,
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["recovery_path"] == RECOVERY_MANUAL_RESUME


# ──────────────────────────────────────────────────────────────
# Test: execute_re_delegation
# ──────────────────────────────────────────────────────────────


class TestExecuteReDelegation:
    """Tests for execute_re_delegation function."""

    def test_re_delegation_with_new_agent(self, temp_repo):
        result = execute_re_delegation(
            task_id="TASK-0002",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id="role:worker:frontend-engineer",
            cause=STALL_CAUSE_ERROR,
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["recovery_path"] == RECOVERY_RE_DELEGATION
        assert result["new_subagent_id"] == "role:worker:frontend-engineer"
        assert result["escalated"] is False

    def test_re_delegation_creates_log(self, temp_repo):
        result = execute_re_delegation(
            task_id="TASK-0002",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id="role:worker:frontend-engineer",
            cause=STALL_CAUSE_ERROR,
            repo_root=temp_repo,
        )
        log_path = Path(result["log_path"])
        assert log_path.exists()
        content = log_path.read_text()
        assert "ERROR" in content
        assert "RE_DELEGATION" in content

    def test_escalation_when_no_alternative(self, temp_repo):
        result = execute_re_delegation(
            task_id="TASK-0002",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id=None,
            cause=STALL_CAUSE_ERROR,
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["recovery_path"] == RECOVERY_RE_DELEGATION
        assert result["new_subagent_id"] is None
        assert result["escalated"] is True

    def test_escalation_message(self, temp_repo):
        result = execute_re_delegation(
            task_id="TASK-0002",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id=None,
            cause=STALL_CAUSE_ERROR,
            repo_root=temp_repo,
        )
        assert "escalated" in result["message"].lower()
        assert "human operator" in result["message"].lower()

    def test_default_cause_is_error(self, temp_repo):
        result = execute_re_delegation(
            task_id="TASK-0002",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id="role:worker:frontend-engineer",
            repo_root=temp_repo,
        )
        assert result["cause"] == STALL_CAUSE_ERROR

    def test_re_delegation_with_custom_cause(self, temp_repo):
        result = execute_re_delegation(
            task_id="TASK-0002",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id="role:worker:frontend-engineer",
            cause="NETWORK_ERROR",
            repo_root=temp_repo,
        )
        assert result["cause"] == "NETWORK_ERROR"

    def test_missing_task_does_not_raise(self, temp_repo):
        """Test that a missing task on the board does not raise an error."""
        result = execute_re_delegation(
            task_id="TASK-9999",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id="role:worker:frontend-engineer",
            cause=STALL_CAUSE_ERROR,
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["recovery_path"] == RECOVERY_RE_DELEGATION


# ──────────────────────────────────────────────────────────────
# Integration Tests: End-to-end stall detection and recovery
# ──────────────────────────────────────────────────────────────


class TestStallDetectionIntegration:
    """Integration tests for the full stall detection and recovery flow."""

    def test_max_turns_detection_and_recovery(self, temp_repo):
        """Test: max_turns exhaustion -> detect -> classify -> manual resume."""
        # Step 1: Detect stall via turn counter
        detection = max_turns_tracker(
            subagent_id="role:worker:backend-engineer",
            current_turns=40,
            max_turns=40,
        )
        assert detection.is_stalled is True
        assert detection.cause == STALL_CAUSE_MAX_TURNS

        # Step 2: Classify the stall
        recovery_path = classify_stall(detection.cause)
        assert recovery_path == RECOVERY_MANUAL_RESUME

        # Step 3: Execute recovery
        result = execute_manual_resume(
            task_id="TASK-0002",
            subagent_id="role:worker:backend-engineer",
            cause=detection.cause,
            details=detection.details,
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["recovery_path"] == RECOVERY_MANUAL_RESUME

        # Step 4: Verify log was created
        log_path = Path(result["log_path"])
        assert log_path.exists()

    def test_unresponsive_detection_and_recovery(self, temp_repo):
        """Test: unresponsiveness -> detect -> classify -> manual resume."""
        old = datetime.now() - timedelta(minutes=20)

        # Step 1: Detect stall via heartbeat
        detection = unresponsiveness_monitor(
            subagent_id="role:worker:backend-engineer",
            last_activity_timestamp=old,
        )
        assert detection.is_stalled is True
        assert detection.cause == STALL_CAUSE_UNRESPONSIVE

        # Step 2: Classify
        recovery_path = classify_stall(detection.cause)
        assert recovery_path == RECOVERY_MANUAL_RESUME

        # Step 3: Execute recovery
        result = execute_manual_resume(
            task_id="TASK-0002",
            subagent_id="role:worker:backend-engineer",
            cause=detection.cause,
            details=detection.details,
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["recovery_path"] == RECOVERY_MANUAL_RESUME

    def test_error_detection_and_re_delegation(self, temp_repo):
        """Test: error/crash -> classify -> re-delegation."""
        # Step 1: Classify error cause
        recovery_path = classify_stall(STALL_CAUSE_ERROR)
        assert recovery_path == RECOVERY_RE_DELEGATION

        # Step 2: Execute re-delegation
        result = execute_re_delegation(
            task_id="TASK-0002",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id="role:worker:frontend-engineer",
            cause=STALL_CAUSE_ERROR,
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["recovery_path"] == RECOVERY_RE_DELEGATION
        assert result["escalated"] is False

    def test_error_escalation_when_no_alternative(self, temp_repo):
        """Test: error/crash -> classify -> escalation (no alternative agent)."""
        recovery_path = classify_stall(STALL_CAUSE_ERROR)
        assert recovery_path == RECOVERY_RE_DELEGATION

        result = execute_re_delegation(
            task_id="TASK-0002",
            original_subagent_id="role:worker:backend-engineer",
            new_subagent_id=None,
            cause=STALL_CAUSE_ERROR,
            repo_root=temp_repo,
        )
        assert result["success"] is True
        assert result["escalated"] is True

    def test_full_recovery_routing_table(self):
        """Verify the complete recovery routing table matches FEAT-003 spec."""
        routing_table = {
            STALL_CAUSE_MAX_TURNS: RECOVERY_MANUAL_RESUME,
            STALL_CAUSE_UNRESPONSIVE: RECOVERY_MANUAL_RESUME,
            STALL_CAUSE_ERROR: RECOVERY_RE_DELEGATION,
            "UNKNOWN": RECOVERY_RE_DELEGATION,
            "CRASH": RECOVERY_RE_DELEGATION,
        }
        for cause, expected_path in routing_table.items():
            actual_path = classify_stall(cause)
            assert actual_path == expected_path, (
                f"Routing mismatch for cause={cause!r}: "
                f"expected {expected_path!r}, got {actual_path!r}"
            )
