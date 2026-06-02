#!/usr/bin/env python3
"""URLhaus + Phishing.Database からセキュリティルール JSON を構築する。

入力:
- URLhaus host file (text、format: "127.0.0.1\\thost")
- Phishing.Database active domains file (text、format: 1 host / line)
- Tranco top 1M (text、format: rank,domain)

出力: Safari Content Blocker JSON 形式

データソース:
- URLhaus: https://urlhaus.abuse.ch/downloads/hostfile/ (CC0 1.0)
- Phishing.Database: https://raw.githubusercontent.com/mitchellkrogza/Phishing.Database/master/phishing-domains-ACTIVE.txt (MIT)
- Tranco: https://tranco-list.eu/ (誤検知除外用)

仕様: docs/superpowers/specs/2026-06-02-anti-phishing-design.md §6
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable


def parse_urlhaus_hosts(text: str) -> list[str]:
    """URLhaus host file の各行から host を抽出。コメント・空行・IP は除外。"""
    hosts: list[str] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        host = parts[1]
        if host in ("127.0.0.1", "0.0.0.0", "localhost"):
            continue
        hosts.append(host)
    return hosts


def parse_phishing_db_hosts(text: str) -> list[str]:
    """Phishing.Database active domains の各行から host を抽出。
    各行は 1 host のみ（例: phish-example.tk）。コメント (#) はスキップ。"""
    hosts: list[str] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # 念のため空白で split して先頭 token を採用（保険）
        host = line.split()[0]
        if host in ("127.0.0.1", "0.0.0.0", "localhost"):
            continue
        hosts.append(host)
    return hosts


def load_tranco_set(text: str) -> set[str]:
    """Tranco CSV (rank,domain) から domain set を作る。"""
    result: set[str] = set()
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(",")
        if len(parts) >= 2:
            result.add(parts[1].strip().lower())
    return result


def convert_to_content_blocker_rules(hosts: Iterable[str]) -> list[dict]:
    """host のリストを Safari Content Blocker JSON ルールに変換。"""
    rules: list[dict] = []
    seen: set[str] = set()
    for host in hosts:
        host = host.lower().strip()
        if not host or host in seen:
            continue
        seen.add(host)
        # url-filter regex で host を含む URL を block
        escaped = re.escape(host)
        rules.append({
            "trigger": {"url-filter": f"https?://([^/]+\\.)?{escaped}(/|$)"},
            "action": {"type": "block"},
        })
    return rules


def build_security_rules(
    urlhaus_text: str,
    phishing_db_text: str,
    tranco_text: str,
    limit: int = 30000,
) -> list[dict]:
    """全パイプライン実行。Tranco 除外 → host 重複削除 → ルール数 limit。"""
    tranco = load_tranco_set(tranco_text)
    urlhaus_hosts = parse_urlhaus_hosts(urlhaus_text)
    phishing_hosts = parse_phishing_db_hosts(phishing_db_text)

    # 統合 + Tranco 除外（誤検知避け）
    all_hosts: list[str] = []
    seen: set[str] = set()
    for h in urlhaus_hosts + phishing_hosts:
        h = h.lower().strip()
        if not h or h in seen or h in tranco:
            continue
        seen.add(h)
        all_hosts.append(h)
        if len(all_hosts) >= limit:
            break
    return convert_to_content_blocker_rules(all_hosts)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--urlhaus", required=True, type=Path,
                        help="URLhaus host file path")
    parser.add_argument("--phishing-db", required=True, type=Path,
                        dest="phishing_db",
                        help="Phishing.Database active domains text file path")
    parser.add_argument("--tranco", required=True, type=Path,
                        help="Tranco top 1M CSV path")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--limit", type=int, default=30000)
    args = parser.parse_args()

    urlhaus_text = args.urlhaus.read_text(encoding="utf-8")
    phishing_db_text = args.phishing_db.read_text(encoding="utf-8")
    tranco_text = args.tranco.read_text(encoding="utf-8")

    rules = build_security_rules(
        urlhaus_text, phishing_db_text, tranco_text, limit=args.limit
    )
    args.output.write_text(json.dumps(rules, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {len(rules)} rules → {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
