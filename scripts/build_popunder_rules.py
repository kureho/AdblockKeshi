#!/usr/bin/env python3
"""popunder-rules.json を L1（既知網 $script）+ L2（サイト別アグレッシブ）から生成。

手書き決定論ジェネレータ。本体フィルタの scripts/convert.sh（SafariConverterLib）とは別物。
L2 の url-filter:".*" は SafariConverterLib が emit しない手書き形で、かつ block→ignore の順序を
完全制御する必要があるため、専用ジェネレータで Content Blocker JSON を直接生成する。

Spec: docs/superpowers/specs/2026-06-17-adblockkeshi-v33-popunder-aggressive-design.md
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

_NETWORK_LINE = re.compile(r"^\|\|([^/^]+)\^\$script$")


def parse_networks(text: str) -> list[str]:
    """popunder-script-networks.txt から domain を抽出する。

    `!` 始まりの行（コメント/セクションヘッダ）と空行は無視し、
    `||domain^$script` 形の行のみをパースする（入力契約）。
    """
    domains: list[str] = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("!"):
            continue
        m = _NETWORK_LINE.match(s)
        if m:
            domains.append(m.group(1))
    return domains


def _domain_anchor(domain: str) -> str:
    """||domain^ の標準 ABP→WebKit url-filter 変換（出荷形と一致）。"""
    return r"^[^:]+://+([^:/]+\.)?" + re.escape(domain) + r"[/:]"


def network_rule(domain: str) -> dict:
    """L1: 既知広告網ドメインを resource-type:script で block（出荷29ルールと同形・load-type は付けない）。"""
    return {
        "trigger": {"url-filter": _domain_anchor(domain), "resource-type": ["script"]},
        "action": {"type": "block"},
    }
