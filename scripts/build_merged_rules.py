#!/usr/bin/env python3
"""ad-rules + security-rules をマージし重複削除 + ルール数 limit する。

仕様: docs/superpowers/specs/2026-06-02-anti-phishing-design.md §3 事前マージ戦略 / §6
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def merge_rules(
    ad_rules: list[dict],
    security_rules: list[dict],
    limit: int = 130000,
) -> list[dict]:
    """ad → security の順で結合、JSON 完全一致の重複を削除し limit で打切り。"""
    merged: list[dict] = []
    seen: set[str] = set()
    for rule in list(ad_rules) + list(security_rules):
        key = json.dumps(rule, sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        merged.append(rule)
        if len(merged) >= limit:
            break
    return merged


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ad", required=True, type=Path)
    parser.add_argument("--security", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--limit", type=int, default=130000)
    args = parser.parse_args()

    ad_rules = json.loads(args.ad.read_text(encoding="utf-8"))
    security_rules = json.loads(args.security.read_text(encoding="utf-8"))
    merged = merge_rules(ad_rules, security_rules, limit=args.limit)
    args.output.write_text(json.dumps(merged, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {len(merged)} merged rules → {args.output}")


if __name__ == "__main__":
    main()
