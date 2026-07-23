import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

# Repository root
REPO_ROOT = Path(__file__).resolve().parent.parent

# luacov.stats.out lives at the repo root after `luacov` runs
DEFAULT_STATS_FILE = REPO_ROOT / "luacov.stats.out"


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------


def _is_structural(stripped: str) -> bool:
    """Return True if the line is a structural/flow-control keyword, not testable logic."""
    if stripped in (
        "end",
        "else",
        "elseif",
        "then",
        "do",
        "until",
        "{",
        "}",
        "nil",
        "",
        "})",
        "},",
    ):
        return True
    if stripped.startswith(("local ", "end ", "else ", "elseif ")):
        return True
    # Simple assignment-only lines (variable = literal) are structural
    if re.fullmatch(r"\w+\s*=\s*\S+\s*$", stripped):
        return True
    return False


def classify_uncovered(counts: list[int], source_lines: list[str] | None) -> list[dict]:
    """Classify each uncovered line into a category.

    Categories:
        - comment_blank  : empty line or line starting with --
        - structural     : local declarations, end, {}, nil, else, elseif
        - executable     : actual logic that should be tested
    """
    result = []
    for idx, count in enumerate(counts):
        if count != 0:
            continue

        line_no = idx + 1
        code = source_lines[idx] if source_lines and idx < len(source_lines) else ""
        stripped = code.strip()

        if stripped == "" or stripped.startswith("--"):
            category = "comment_blank"
        elif _is_structural(stripped):
            category = "structural"
        else:
            category = "executable"

        result.append(
            {
                "line": line_no,
                "code": code.rstrip(),
                "category": category,
            }
        )

    return result


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------


def parse_stats_file(filepath: Path) -> list[dict[str, Any]]:
    """Parse luacov.stats.out into a list of file coverage records.

    Each record:
        {
            "path": str,
            "total_lines": int,
            "counts": list[int],
            "source_lines": list[str] | None,
            "covered": int,
            "uncovered": int,
            "pct": float,
            "uncovered_lines": list[dict],  # {"line": int, "code": str, "category": str}
        }
    """
    records = []
    with open(filepath) as f:
        raw = f.readlines()

    i = 0
    while i < len(raw):
        header = raw[i].strip()
        # Header format: N:/path/to/file.lua
        m = re.match(r"^(\d+):(.+)$", header)
        if not m:
            i += 1
            continue

        total_lines = int(m.group(1))
        path = m.group(2)

        # Next line(s) contain space-separated counts
        counts_text = ""
        i += 1
        while i < len(raw) and len(counts_text.split()) < total_lines:
            next_line = raw[i].strip()
            # Stop if we hit another header
            if re.match(r"^\d+:/", next_line):
                break
            counts_text += " " + next_line
            i += 1

        counts = [int(x) for x in counts_text.split()]

        # Read source lines if file exists
        source_lines = None
        try:
            source_lines = Path(path).read_text().splitlines()
        except (OSError, IOError):
            pass

        covered = sum(1 for c in counts if c > 0)
        uncovered = total_lines - covered
        pct = (covered / total_lines * 100) if total_lines else 0.0

        # Classify uncovered lines
        uncovered_lines = classify_uncovered(counts, source_lines)

        records.append(
            {
                "path": path,
                "total_lines": total_lines,
                "counts": counts,
                "source_lines": source_lines,
                "covered": covered,
                "uncovered": uncovered,
                "pct": round(pct, 1),
                "uncovered_lines": uncovered_lines,
            }
        )

    return records


# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------


def print_summary(records: list[dict[str, Any]], filter_path: str | None = None):
    """Print a coverage summary table."""
    filtered = (
        [r for r in records if filter_path in r["path"]] if filter_path else records
    )

    if not filtered:
        print("No matching files found.")
        return

    # Column widths
    name_w = max(len(Path(r["path"]).name) for r in filtered) + 2
    name_w = max(name_w, 10)

    header = f"{'File':<{name_w}}  {'Covered':>7}  {'Total':>5}  {'%':>6}  {'Effective%':>10}"
    print(header)
    print("-" * len(header))

    for r in filtered:
        name = Path(r["path"]).name
        total = r["total_lines"]
        covered = r["covered"]
        raw_pct = r["pct"]

        # Effective coverage: exclude comments and blanks
        unc = r["uncovered_lines"]
        comment_blank = sum(1 for u in unc if u["category"] == "comment_blank")
        effective_total = total - comment_blank
        eff_pct = (covered / effective_total * 100) if effective_total else 0.0

        print(
            f"{name:<{name_w}}  {covered:>7}  {total:>5}  {raw_pct:>5.1f}%  {eff_pct:>9.1f}%"
        )

    # Totals
    total_total = sum(r["total_lines"] for r in filtered)
    total_covered = sum(r["covered"] for r in filtered)
    total_cb = sum(
        sum(1 for u in r["uncovered_lines"] if u["category"] == "comment_blank")
        for r in filtered
    )
    eff_total = total_total - total_cb
    raw_pct = (total_covered / total_total * 100) if total_total else 0.0
    eff_pct = (total_covered / eff_total * 100) if eff_total else 0.0

    print("-" * len(header))
    print(
        f"{'TOTAL':<{name_w}}  {total_covered:>7}  {total_total:>5}  {raw_pct:>5.1f}%  {eff_pct:>9.1f}%"
    )


def print_gaps(records: list[dict[str, Any]], filter_path: str | None = None):
    """Print uncovered executable lines grouped by file."""
    filtered = (
        [r for r in records if filter_path in r["path"]] if filter_path else records
    )

    found_any = False
    for r in filtered:
        executable_gaps = [
            u for u in r["uncovered_lines"] if u["category"] == "executable"
        ]
        if not executable_gaps:
            continue

        found_any = True
        print(f"\n{r['path']}")
        print(f"  {len(executable_gaps)} executable line(s) not covered:")
        for u in executable_gaps:
            print(f"    {u['line']:>4}: {u['code']}")

    if not found_any:
        print("All executable code is covered.")


def print_all_uncovered(records: list[dict[str, Any]], filter_path: str | None = None):
    """Print all uncovered lines grouped by category, then by file."""
    filtered = (
        [r for r in records if filter_path in r["path"]] if filter_path else records
    )

    for r in filtered:
        unc = r["uncovered_lines"]
        if not unc:
            continue

        categories: dict[str, list] = {
            "executable": [],
            "structural": [],
            "comment_blank": [],
        }
        for u in unc:
            categories[u["category"]].append(u)

        print(f"\n{r['path']}  ({r['covered']}/{r['total_lines']} = {r['pct']}%)")

        for cat in ("executable", "structural", "comment_blank"):
            items = categories[cat]
            if not items:
                continue
            print(f"  [{cat}] ({len(items)} lines)")
            for u in items:
                print(f"    {u['line']:>4}: {u['code']}")


def output_json(records: list[dict[str, Any]], filter_path: str | None = None):
    """Output coverage data as JSON (strips counts/source for compactness)."""
    filtered = (
        [r for r in records if filter_path in r["path"]] if filter_path else records
    )

    # Build compact output
    out = []
    for r in filtered:
        entry = {
            "path": r["path"],
            "total_lines": r["total_lines"],
            "covered": r["covered"],
            "uncovered": r["uncovered"],
            "pct": r["pct"],
            "uncovered_lines": r["uncovered_lines"],
        }
        out.append(entry)

    print(json.dumps(out, indent=2))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Parse and display luacov.stats.out coverage data.",
        epilog="Example: python3 toolbox/luacov_utils.py --gaps --filter decoder",
    )
    parser.add_argument(
        "stats_file",
        nargs="?",
        default=str(DEFAULT_STATS_FILE),
        help="Path to luacov.stats.out (default: repo root)",
    )
    parser.add_argument(
        "--summary",
        "-s",
        action="store_true",
        help="Print coverage summary table (default action)",
    )
    parser.add_argument(
        "--gaps",
        "-g",
        action="store_true",
        help="Show uncovered executable lines only",
    )
    parser.add_argument(
        "--all-uncovered",
        "-a",
        action="store_true",
        help="Show all uncovered lines classified by category",
    )
    parser.add_argument(
        "--json",
        "-j",
        action="store_true",
        help="Output as JSON",
    )
    parser.add_argument(
        "--filter",
        "-f",
        default=None,
        help="Filter files by substring in path (e.g. 'decoder' or 'bravo++')",
    )

    args = parser.parse_args()

    stats_path = Path(args.stats_file)
    if not stats_path.exists():
        print(f"Error: stats file not found: {stats_path}", file=sys.stderr)
        sys.exit(1)

    records = parse_stats_file(stats_path)

    if args.json:
        output_json(records, args.filter)
    elif args.all_uncovered:
        print_all_uncovered(records, args.filter)
    elif args.gaps:
        print_gaps(records, args.filter)
    else:
        print_summary(records, args.filter)


if __name__ == "__main__":
    main()
