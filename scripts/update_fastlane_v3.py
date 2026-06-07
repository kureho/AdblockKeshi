#!/usr/bin/env python3
"""Plan D Task 2.1: v3.0 metadata draft を fastlane/metadata/ja/ に反映する。

Source of truth:
  tasks/v3-metadata-draft.md (PR #21)

各 fastlane フィールド (name / subtitle / keywords / promotional_text /
description / release_notes) ごとに対応する ## セクションの最初の ```
コードブロック内容を抜き出し、fastlane/metadata/ja/*.txt に上書きする。
完了後に pre-flight grep を実行し、Apple 商標 / 価格表記 / 未確定文字
(TBD/TODO/XXX) を検出したら exit 1 でロールバック可能な diff を表示。

Usage:
  python3 scripts/update_fastlane_v3.py --dry-run   # diff のみ表示
  python3 scripts/update_fastlane_v3.py             # 実反映 + pre-flight grep
  python3 scripts/update_fastlane_v3.py --verify    # 反映後の grep のみ実行

Exit codes:
  0 = 反映 OK + pre-flight pass
  1 = pre-flight grep で禁止語句検出 (詳細を stderr に出力)
  2 = draft 構造異常 / fastlane dir 不在 / draft 不在
"""
from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DRAFT_MD = REPO_ROOT / "tasks" / "v3-metadata-draft.md"
FASTLANE_JA = REPO_ROOT / "fastlane" / "metadata" / "ja"

# fastlane field name → draft md の section heading (正規表現)
FIELDS: list[tuple[str, str]] = [
    ("name.txt", r"^## 1\. name\.txt"),
    ("subtitle.txt", r"^## 2\. subtitle\.txt"),
    ("keywords.txt", r"^## 3\. keywords\.txt"),
    ("promotional_text.txt", r"^## 4\. promotional_text\.txt"),
    ("description.txt", r"^## 5\. description\.txt"),
    ("release_notes.txt", r"^## 6\. release_notes\.txt"),
]

# pre-flight grep patterns
APPLE_TRADEMARK_RE = re.compile(
    r"\b(safari|iphone|ipad|ios|apple|siri|imessage|macos|airpods)\b",
    re.IGNORECASE,
)
PRICE_RE = re.compile(r"[¥￥]|\b(free|無料|割引|円|yen)\b", re.IGNORECASE)
TBD_RE = re.compile(r"\b(tbd|todo|xxx|fixme)\b", re.IGNORECASE)


def extract_code_block(draft: str, heading_re: str) -> str | None:
    """Find the first ``` code block under the matching heading."""
    lines = draft.splitlines()
    in_section = False
    in_code = False
    captured: list[str] = []
    for line in lines:
        if re.match(heading_re, line):
            in_section = True
            continue
        if in_section:
            # 次の ## section に到達したら終了
            if line.startswith("## ") and captured:
                break
            if line.strip().startswith("```"):
                if in_code:
                    return "\n".join(captured).rstrip() + "\n"
                in_code = True
                continue
            if in_code:
                captured.append(line)
    if captured:
        return "\n".join(captured).rstrip() + "\n"
    return None


def show_diff(path: Path, new_content: str) -> bool:
    """Return True if there is a change."""
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    if old == new_content:
        return False
    diff = difflib.unified_diff(
        old.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile=f"a/{path.name}",
        tofile=f"b/{path.name}",
        n=2,
    )
    sys.stdout.write("".join(diff))
    return True


def pre_flight_grep(path: Path) -> list[str]:
    """Return a list of violations (empty = clean)."""
    text = path.read_text(encoding="utf-8")
    violations: list[str] = []
    for m in APPLE_TRADEMARK_RE.finditer(text):
        violations.append(f"  apple-trademark: '{m.group(0)}' at pos {m.start()}")
    for m in PRICE_RE.finditer(text):
        violations.append(f"  price-token: '{m.group(0)}' at pos {m.start()}")
    for m in TBD_RE.finditer(text):
        violations.append(f"  unfinalised: '{m.group(0)}' at pos {m.start()}")
    return violations


def cmd_verify_only() -> int:
    print(f"=== pre-flight grep over {FASTLANE_JA}/ ===")
    rc = 0
    for fname, _ in FIELDS:
        path = FASTLANE_JA / fname
        if not path.exists():
            print(f"⚠️  not found: {path.name}", file=sys.stderr)
            continue
        violations = pre_flight_grep(path)
        if violations:
            print(f"❌ {path.name}")
            for v in violations:
                print(v, file=sys.stderr)
            rc = 1
        else:
            print(f"✅ {path.name}")
    return rc


def main(dry_run: bool) -> int:
    if not DRAFT_MD.exists():
        print(f"❌ draft not found: {DRAFT_MD}", file=sys.stderr)
        print(
            "PR #21 (feat/v3-plan-d-metadata-draft) を merge してから実行してください。",
            file=sys.stderr,
        )
        return 2

    if not FASTLANE_JA.exists():
        print(f"❌ fastlane dir not found: {FASTLANE_JA}", file=sys.stderr)
        return 2

    draft = DRAFT_MD.read_text(encoding="utf-8")

    print(f"=== {'DRY RUN' if dry_run else 'APPLY'}: {DRAFT_MD.name} → {FASTLANE_JA}/ ===\n")

    changed = 0
    missing: list[str] = []
    for fname, heading_re in FIELDS:
        target = FASTLANE_JA / fname
        new_content = extract_code_block(draft, heading_re)
        if new_content is None:
            missing.append(f"{fname} (heading: {heading_re})")
            continue
        if show_diff(target, new_content):
            changed += 1
            if not dry_run:
                target.write_text(new_content, encoding="utf-8")

    if missing:
        print("⚠️  draft から抽出できなかった field:")
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        return 2

    print(f"\n{'(dry-run) ' if dry_run else ''}{changed} files would change.\n")

    if dry_run:
        return 0

    print("=== pre-flight grep ===")
    rc = 0
    for fname, _ in FIELDS:
        path = FASTLANE_JA / fname
        violations = pre_flight_grep(path)
        if violations:
            print(f"❌ {path.name}")
            for v in violations:
                print(v, file=sys.stderr)
            rc = 1
        else:
            print(f"✅ {path.name}")

    if rc == 0:
        print("\n✅ 全 fastlane field が禁止語句なしで反映完了。次は fastlane deliver で投入。")
    else:
        print(
            "\n⚠️  pre-flight grep で禁止語句検出。draft を見直してから再実行してください。",
            file=sys.stderr,
        )
    return rc


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--dry-run", action="store_true", help="diff のみ表示、ファイル書き換えなし"
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="現状の fastlane/metadata/ja/ に対して pre-flight grep のみ実行",
    )
    args = parser.parse_args()

    if args.verify:
        sys.exit(cmd_verify_only())
    sys.exit(main(dry_run=args.dry_run))
