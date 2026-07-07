#!/usr/bin/env python3
"""Generate doc/testplan.md from testplan/features/*.md checkpoint files.

See the `testplan` Claude Code skill for the authoring format this parses:
one `#` feature title per file under testplan/features/, one `##` section
per checkpoint (`## CP-xx — <title>`), with labeled bullet fields
(Category, Source, Precondition, Stimulus, Expected, Test, Coverage).

Usage: scripts/gen_testplan.py   (run from the repo root)
"""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FEATURES_DIR = REPO_ROOT / "testplan" / "features"
OUTPUT_FILE = REPO_ROOT / "doc" / "testplan.md"

FEATURE_TITLE_RE = re.compile(r"^#\s*Feature:\s*(.+)$")
# Separator between the CP id and the title accepts hyphen-minus, en dash or
# em dash — a hand-typed '-' must not silently drop the checkpoint.
CHECKPOINT_RE = re.compile(r"^##\s*(CP-\d+)\s*[-–—]+\s*(.+)$")
# Anything starting with '## CP-' that CHECKPOINT_RE didn't match is an error.
CHECKPOINT_LOOSE_RE = re.compile(r"^##\s*CP-")
FIELD_RE = re.compile(r"^-\s*\*\*([A-Za-z]+):\*\*\s*(.+)$")

ORDERED_SINGLE_FIELDS = ("Category", "Source", "Precondition", "Stimulus", "Expected")


def parse_feature_file(path):
    """Parse one testplan/features/<feature>.md file into (feature_title, [checkpoints])."""
    feature_title = path.stem
    checkpoints = []
    current = None
    for line in path.read_text().splitlines():
        title_match = FEATURE_TITLE_RE.match(line)
        if title_match:
            feature_title = title_match.group(1).strip()
            continue
        cp_match = CHECKPOINT_RE.match(line)
        if cp_match:
            if current is not None:
                checkpoints.append(current)
            current = {"id": cp_match.group(1), "title": cp_match.group(2).strip(), "fields": {}}
            continue
        if CHECKPOINT_LOOSE_RE.match(line):
            sys.exit(
                f"error: {path}: unparseable checkpoint heading {line!r} — "
                "expected '## CP-<nn> — <title>' (silently dropping it would "
                "hide the checkpoint from doc/testplan.md)"
            )
        field_match = FIELD_RE.match(line)
        if field_match and current is not None:
            key, value = field_match.group(1), field_match.group(2).strip()
            current["fields"].setdefault(key, []).append(value)
    if current is not None:
        checkpoints.append(current)
    return feature_title, checkpoints


def field(checkpoint, name):
    values = checkpoint["fields"].get(name)
    return values[0] if values else ""


def field_list(checkpoint, name):
    return checkpoint["fields"].get(name, [])


def render_index_table(all_checkpoints):
    lines = ["| Checkpoint | Category | Title | Source |", "|---|---|---|---|"]
    for cp in all_checkpoints:
        lines.append(f"| {cp['id']} | {field(cp, 'Category')} | {cp['title']} | {field(cp, 'Source')} |")
    return "\n".join(lines)


def render_checkpoint(cp):
    lines = [f"### {cp['id']} — {cp['title']}", ""]
    for label in ORDERED_SINGLE_FIELDS:
        value = field(cp, label)
        if value:
            lines.append(f"- **{label}:** {value}")
    tests = field_list(cp, "Test")
    if tests:
        for test in tests:
            lines.append(f"- **Test:** {test}")
    else:
        lines.append("- **Test:** _not yet written_")
    for coverage in field_list(cp, "Coverage"):
        lines.append(f"- **Coverage:** {coverage}")
    lines.append("")
    return "\n".join(lines)


def main():
    if not FEATURES_DIR.is_dir():
        sys.exit(f"error: {FEATURES_DIR} does not exist")

    feature_files = sorted(FEATURES_DIR.glob("*.md"))
    if not feature_files:
        sys.exit(f"error: no *.md files found under {FEATURES_DIR}")

    features = [parse_feature_file(p) for p in feature_files]

    all_checkpoints = []
    for _, checkpoints in features:
        all_checkpoints.extend(checkpoints)
    all_checkpoints.sort(key=lambda cp: int(cp["id"].split("-")[1]))

    out = ["# Testplan", "", "## Index", "", render_index_table(all_checkpoints), ""]
    for feature_title, checkpoints in features:
        if not checkpoints:
            continue
        out.append(f"## Feature: {feature_title}")
        out.append("")
        for cp in checkpoints:
            out.append(render_checkpoint(cp))

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text("\n".join(out))
    print(f"wrote {OUTPUT_FILE} ({len(all_checkpoints)} checkpoints from {len(feature_files)} files)")


if __name__ == "__main__":
    main()
