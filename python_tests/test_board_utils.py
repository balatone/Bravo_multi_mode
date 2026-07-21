"""
Unit tests for FEAT-009: Project Board Dashboard (LIST subcommand).

Tests cover:
- collect_tasks: full board scan, active-only filter, last-n filter
- format_table: dynamic column widths, empty rows handling
- list_board: CLI integration, mutual exclusivity, empty board
- Edge cases: missing directories, malformed files, empty board
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

# Add parent directory to path so we can import toolbox modules
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from toolbox.board_utils import (
    collect_tasks,
    format_table,
    list_board,
    _get_dir_status,
    STATUS_ORDER,
)


@pytest.fixture
def temp_board(tmp_path):
    """Create a temporary .board/ directory structure for testing."""
    board_dir = tmp_path / ".board"
    todo_dir = board_dir / "to-do"
    in_progress_dir = board_dir / "in-progress"
    done_dir = board_dir / "done"
    todo_dir.mkdir(parents=True, exist_ok=True)
    in_progress_dir.mkdir(parents=True, exist_ok=True)
    done_dir.mkdir(parents=True, exist_ok=True)
    return board_dir


def _create_task(board_dir, subdir, task_id, title, created="2026-07-15 10:00:00"):
    """Helper to create a task file in the given subdirectory."""
    task_dir = board_dir / subdir
    slug = title.lower().replace(" ", "-")
    filename = f"{task_id}-{slug}.md"
    filepath = task_dir / filename
    filepath.write_text(
        f"---\n"
        f"id: {task_id}\n"
        f"title: \"{title}\"\n"
        f"version: 1.0.0\n"
        f"status: {subdir.upper().replace('-', '-')}\n"
        f"created: \"{created}\"\n"
        f"updated: \"{created}\"\n"
        f"---\n"
        f"\n"
        f"# {title}\n"
        f"\n"
        f"# Activity Log\n"
    )
    return filepath


class TestGetDirStatus:
    """Tests for _get_dir_status helper function."""

    def test_to_do_mapping(self):
        assert _get_dir_status("to-do") == "TO-DO"
        assert _get_dir_status("todo") == "TO-DO"

    def test_in_progress_mapping(self):
        assert _get_dir_status("in-progress") == "IN-PROGRESS"
        assert _get_dir_status("inprogress") == "IN-PROGRESS"

    def test_done_mapping(self):
        assert _get_dir_status("done") == "DONE"

    def test_unknown_directory(self):
        assert _get_dir_status("reviewing") == "REVIEWING"
        assert _get_dir_status("custom-dir") == "CUSTOM-DIR"


class TestStatusOrder:
    """Tests for STATUS_ORDER constant."""

    def test_order_values(self):
        assert STATUS_ORDER["TO-DO"] == 0
        assert STATUS_ORDER["DONE"] == 7
        assert STATUS_ORDER["IMPLEMENTING"] == 4

    def test_all_statuses_present(self):
        expected = {
            "TO-DO", "ANALYSING", "DESIGNING", "PLANNING",
            "IMPLEMENTING", "TESTING", "REVIEWING", "IN-PROGRESS", "DONE",
        }
        assert set(STATUS_ORDER.keys()) == expected


class TestCollectTasks:
    """Tests for collect_tasks function."""

    def test_full_board(self, temp_board):
        """Test collecting all tasks from the full board."""
        _create_task(temp_board, "to-do", "TASK-0010", "Todo Task", "2026-07-15 10:00:00")
        _create_task(temp_board, "in-progress", "TASK-0011", "In Progress Task", "2026-07-15 11:00:00")
        _create_task(temp_board, "done", "TASK-0012", "Done Task", "2026-07-15 12:00:00")

        tasks = collect_tasks(board_dir=temp_board)

        assert len(tasks) == 3
        ids = [t["id"] for t in tasks]
        assert "TASK-0010" in ids
        assert "TASK-0011" in ids
        assert "TASK-0012" in ids

    def test_sorting_by_status(self, temp_board):
        """Test that tasks are sorted by pipeline stage."""
        _create_task(temp_board, "done", "TASK-0012", "Done Task", "2026-07-15 10:00:00")
        _create_task(temp_board, "to-do", "TASK-0010", "Todo Task", "2026-07-15 10:00:00")
        _create_task(temp_board, "in-progress", "TASK-0011", "In Progress Task", "2026-07-15 10:00:00")

        tasks = collect_tasks(board_dir=temp_board)

        statuses = [t["status"] for t in tasks]
        assert statuses == ["TO-DO", "IN-PROGRESS", "DONE"]

    def test_active_only_filter(self, temp_board):
        """Test --active-only returns only TO-DO and IN-PROGRESS tasks."""
        _create_task(temp_board, "to-do", "TASK-0010", "Todo Task")
        _create_task(temp_board, "in-progress", "TASK-0011", "In Progress Task")
        _create_task(temp_board, "done", "TASK-0012", "Done Task")

        tasks = collect_tasks(board_dir=temp_board, active_only=True)

        assert len(tasks) == 2
        statuses = [t["status"] for t in tasks]
        assert "DONE" not in statuses
        assert "TO-DO" in statuses
        assert "IN-PROGRESS" in statuses

    def test_active_only_no_done(self, temp_board):
        """Test --active-only excludes all DONE tasks."""
        _create_task(temp_board, "done", "TASK-0012", "Done Task 1")
        _create_task(temp_board, "done", "TASK-0013", "Done Task 2")
        _create_task(temp_board, "done", "TASK-0014", "Done Task 3")

        tasks = collect_tasks(board_dir=temp_board, active_only=True)

        assert len(tasks) == 0

    def test_last_n_filter(self, temp_board):
        """Test --last-n includes active tasks plus N most recent DONE tasks."""
        _create_task(temp_board, "to-do", "TASK-0010", "Todo Task")
        _create_task(temp_board, "done", "TASK-0012", "Done Task 1", "2026-07-15 10:00:00")
        _create_task(temp_board, "done", "TASK-0013", "Done Task 2", "2026-07-15 11:00:00")
        _create_task(temp_board, "done", "TASK-0014", "Done Task 3", "2026-07-15 12:00:00")

        tasks = collect_tasks(board_dir=temp_board, last_n=2)

        # Should have 1 active + 2 most recent done = 3
        assert len(tasks) == 3
        active = [t for t in tasks if t["status"] != "DONE"]
        done = [t for t in tasks if t["status"] == "DONE"]
        assert len(active) == 1
        assert len(done) == 2

    def test_last_n_fewer_available(self, temp_board):
        """Test --last-n handles fewer DONE tasks than requested gracefully."""
        _create_task(temp_board, "done", "TASK-0012", "Done Task 1")
        _create_task(temp_board, "done", "TASK-0013", "Done Task 2")

        tasks = collect_tasks(board_dir=temp_board, last_n=10)

        # Should return all 2 done tasks even though we asked for 10
        assert len(tasks) == 2

    def test_empty_board(self, temp_board):
        """Test empty board returns empty list."""
        tasks = collect_tasks(board_dir=temp_board)
        assert tasks == []

    def test_missing_board_directory(self, tmp_path):
        """Test missing board directory returns empty list."""
        nonexistent = tmp_path / ".nonexistent"
        tasks = collect_tasks(board_dir=nonexistent)
        assert tasks == []

    def test_skips_status_board_protocol(self, temp_board):
        """Test that status_board_protocol.md is skipped."""
        protocol_file = temp_board / "status_board_protocol.md"
        protocol_file.write_text("---\nid: PROTOCOL\ntitle: Protocol\n---\n\n# Protocol\n")

        tasks = collect_tasks(board_dir=temp_board)
        assert len(tasks) == 0

    def test_task_metadata_extraction(self, temp_board):
        """Test that task metadata is correctly extracted."""
        _create_task(temp_board, "to-do", "TASK-0010", "My Test Task")

        tasks = collect_tasks(board_dir=temp_board)

        assert len(tasks) == 1
        task = tasks[0]
        assert task["id"] == "TASK-0010"
        assert task["title"] == "My Test Task"
        assert task["status"] == "TO-DO"

    def test_last_n_includes_all_active(self, temp_board):
        """Test --last-n includes ALL active tasks regardless of count."""
        _create_task(temp_board, "to-do", "TASK-0010", "Todo 1")
        _create_task(temp_board, "to-do", "TASK-0011", "Todo 2")
        _create_task(temp_board, "in-progress", "TASK-0012", "In Progress")
        _create_task(temp_board, "done", "TASK-0013", "Done 1")
        _create_task(temp_board, "done", "TASK-0014", "Done 2")

        tasks = collect_tasks(board_dir=temp_board, last_n=1)

        active = [t for t in tasks if t["status"] != "DONE"]
        done = [t for t in tasks if t["status"] == "DONE"]
        assert len(active) == 3  # All active tasks included
        assert len(done) == 1    # Only 1 done task


class TestFormatTable:
    """Tests for format_table function."""

    def test_basic_table(self):
        """Test basic table formatting with sample data."""
        rows = [
            {"id": "TASK-0001", "title": "Sample Task", "status": "DONE"},
        ]
        result = format_table(rows)

        assert "TASK-0001" in result
        assert "Sample Task" in result
        assert "DONE" in result
        assert "TASK ID" in result
        assert "TITLE" in result
        assert "STATUS" in result

    def test_dynamic_column_widths(self):
        """Test that column widths adjust to content length."""
        rows = [
            {
                "id": "TASK-0001",
                "title": "A Very Long Task Title That Should Expand The Column Width",
                "status": "DONE",
            },
        ]
        result = format_table(rows)

        lines = result.split("\n")
        # Header and separator should align with data
        assert len(lines) >= 3
        # The title column should be wide enough
        header_line = lines[0]
        data_line = lines[2]
        # Both lines should have the same length
        assert len(header_line) == len(data_line)

    def test_multiple_rows(self):
        """Test table formatting with multiple rows."""
        rows = [
            {"id": "TASK-0001", "title": "Task One", "status": "TO-DO"},
            {"id": "TASK-0002", "title": "Task Two", "status": "DONE"},
            {"id": "TASK-0003", "title": "Task Three", "status": "IN-PROGRESS"},
        ]
        result = format_table(rows)

        assert "TASK-0001" in result
        assert "TASK-0002" in result
        assert "TASK-0003" in result
        assert result.count(" | ") >= 2  # At least header and separator have separators

    def test_empty_rows(self):
        """Test empty rows returns appropriate message."""
        result = format_table([])
        assert "No active tasks found in .board/" in result

    def test_table_alignment(self):
        """Test that all rows in the table are aligned."""
        rows = [
            {"id": "TASK-1", "title": "Short", "status": "DONE"},
            {"id": "TASK-100", "title": "A much longer title here", "status": "TO-DO"},
        ]
        result = format_table(rows)

        lines = result.split("\n")
        # All lines should have the same length
        line_lengths = [len(line) for line in lines]
        assert len(set(line_lengths)) == 1, f"Lines have different lengths: {line_lengths}"

    def test_separator_line(self):
        """Test that separator line uses correct characters."""
        rows = [
            {"id": "TASK-0001", "title": "Test", "status": "DONE"},
        ]
        result = format_table(rows)

        lines = result.split("\n")
        # Second line should be the separator
        assert "-+-" in lines[1]


class TestListBoardCLI:
    """Tests for list_board CLI integration."""

    def test_mutual_exclusivity_error(self, temp_board, capsys):
        """Test that --active-only and --last-n together produce an error."""
        _create_task(temp_board, "to-do", "TASK-0010", "Todo Task")

        with patch("toolbox.board_utils.BOARD_DIR", temp_board):
            with pytest.raises(SystemExit) as exc_info:
                list_board(active_only=True, last_n=5)

        assert exc_info.value.code == 1
        captured = capsys.readouterr()
        assert "mutually exclusive" in captured.err.lower()

    def test_full_board_output(self, temp_board, capsys):
        """Test default list_board shows all tasks."""
        _create_task(temp_board, "to-do", "TASK-0010", "Todo Task")
        _create_task(temp_board, "done", "TASK-0012", "Done Task")

        with patch("toolbox.board_utils.BOARD_DIR", temp_board):
            list_board()

        captured = capsys.readouterr()
        assert "TASK-0010" in captured.out
        assert "TASK-0012" in captured.out

    def test_active_only_output(self, temp_board, capsys):
        """Test --active-only shows only active tasks."""
        _create_task(temp_board, "to-do", "TASK-0010", "Todo Task")
        _create_task(temp_board, "done", "TASK-0012", "Done Task")

        with patch("toolbox.board_utils.BOARD_DIR", temp_board):
            list_board(active_only=True)

        captured = capsys.readouterr()
        assert "TASK-0010" in captured.out
        assert "TASK-0012" not in captured.out

    def test_last_n_output(self, temp_board, capsys):
        """Test --last-n shows active tasks plus N done tasks."""
        _create_task(temp_board, "to-do", "TASK-0010", "Todo Task")
        _create_task(temp_board, "done", "TASK-0012", "Done Task 1")
        _create_task(temp_board, "done", "TASK-0013", "Done Task 2")

        with patch("toolbox.board_utils.BOARD_DIR", temp_board):
            list_board(last_n=1)

        captured = capsys.readouterr()
        assert "TASK-0010" in captured.out

    def test_empty_board_message(self, temp_board, capsys):
        """Test empty board displays appropriate message."""
        with patch("toolbox.board_utils.BOARD_DIR", temp_board):
            list_board()

        captured = capsys.readouterr()
        assert "No active tasks found in .board/" in captured.out

    def test_active_only_empty_board(self, temp_board, capsys):
        """Test --active-only on board with only DONE tasks."""
        _create_task(temp_board, "done", "TASK-0012", "Done Task")

        with patch("toolbox.board_utils.BOARD_DIR", temp_board):
            list_board(active_only=True)

        captured = capsys.readouterr()
        assert "No active tasks found in .board/" in captured.out


class TestIntegrationWithRealBoard:
    """Integration tests against the real .board/ directory."""

    def test_real_board_list(self):
        """Test that the real board can be listed without errors."""
        tasks = collect_tasks()
        assert len(tasks) >= 1  # At least one task exists in the real board

    def test_real_board_has_ids(self):
        """Test that all tasks from the real board have valid IDs."""
        tasks = collect_tasks()
        for task in tasks:
            assert task["id"].startswith("TASK-")
            assert task["title"]
            assert task["status"]

    def test_real_board_statuses(self):
        """Test that statuses from the real board are valid."""
        tasks = collect_tasks()
        for task in tasks:
            assert task["status"] in ("TO-DO", "IN-PROGRESS", "DONE", "REVIEWING", "UNKNOWN")
