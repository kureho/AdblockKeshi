#!/usr/bin/env python3
"""Content Blocker 空ルール JSON を出力。両 toggle OFF 時に使う no-op rules。"""
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.write_text("[]", encoding="utf-8")
    print(f"Wrote empty rules → {args.output}")


if __name__ == "__main__":
    main()
