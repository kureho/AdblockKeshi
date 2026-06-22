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
# 妥当な domain = 英数 / ドット / ハイフンのみ（空白・スキーム・パス・コロンを含まない）。
_VALID_DOMAIN = re.compile(r"^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$")


def _validate_domain(domain: str) -> str:
    """domain 文字列を検証する。不正（空白・スキーム・パス等）なら ValueError。"""
    if not isinstance(domain, str) or not _VALID_DOMAIN.match(domain.strip()):
        raise ValueError(f"invalid domain: {domain!r}")
    return domain.strip()


def _dedup(seq: list[str]) -> list[str]:
    """出現順を保ったまま重複を除去する。"""
    seen: set[str] = set()
    out: list[str] = []
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def parse_networks(text: str) -> list[str]:
    """popunder-script-networks.txt から domain を抽出する（重複は出現順で除去）。

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
    return _dedup(domains)


def _domain_anchor(domain: str) -> str:
    """||domain^ の標準 ABP→WebKit url-filter 変換（出荷形=SafariConverterLib 出力と一致）。

    SafariConverterLib はドットのみをエスケープし、ハイフン等はエスケープしない
    （正規表現の非文字クラス文脈ではハイフンはリテラル）。re.escape は `-` も escape するため使わない。
    """
    escaped = domain.replace(".", r"\.")
    return r"^[^:]+://+([^:/]+\.)?" + escaped + r"[/:]"


def network_rule(domain: str) -> dict:
    """L1: 既知広告網ドメインを resource-type:script で block（出荷29ルールと同形・load-type は付けない）。"""
    domain = _validate_domain(domain)
    return {
        "trigger": {"url-filter": _domain_anchor(domain), "resource-type": ["script"]},
        "action": {"type": "block"},
    }


def aggressive_site_rules(site: dict) -> list[dict]:
    """L2: 1サイト分のルールを順序厳守で生成する。

    block（全 third-party script を if-domain 限定で遮断）→ allow 各 domain ごとに
    ignore-previous-rules 1件（block の後）。allow は「1 entry = 1 ルール」（alternation にしない）。
    """
    domain = _validate_domain(site["domain"])
    if_domain = [f"*{domain}"]
    rules: list[dict] = [{
        "trigger": {
            "url-filter": ".*",
            "resource-type": ["script"],
            "load-type": ["third-party"],
            "if-domain": if_domain,
        },
        "action": {"type": "block"},
    }]
    for allow in site.get("allow", []):
        allow = _validate_domain(allow)
        rules.append({
            "trigger": {"url-filter": _domain_anchor(allow), "if-domain": if_domain},
            "action": {"type": "ignore-previous-rules"},
        })
    return rules


MAX_RULES = 50000  # WebKit content blocker 上限の保守値（別拡張枠・実数は数百）


def build_rules(networks: list[str], sites: list[dict]) -> list[dict]:
    """L1（network block 群）→ L2（サイト別 block→ignore 群）の順で全ルールを組み立てる。"""
    rules = [network_rule(d) for d in networks]
    for site in sites:
        rules.extend(aggressive_site_rules(site))
    if len(rules) > MAX_RULES:
        raise ValueError(f"rule count {len(rules)} exceeds MAX_RULES {MAX_RULES}")
    return rules


def main() -> int:
    p = argparse.ArgumentParser(description="Generate popunder-rules.json from L1+L2 sources.")
    p.add_argument("--networks", required=True, help="popunder-script-networks.txt のパス")
    p.add_argument("--sites", required=True, help="popunder-aggressive-sites.json のパス")
    p.add_argument("--out", action="append", required=True, help="出力先（複数指定可: bundle と cdn）")
    a = p.parse_args()
    networks = parse_networks(Path(a.networks).read_text())
    sites = json.loads(Path(a.sites).read_text())
    rules = build_rules(networks, sites)
    payload = json.dumps(rules, ensure_ascii=False, indent=2) + "\n"
    for out in a.out:
        Path(out).write_text(payload)
    print(f"wrote {len(rules)} rules to {len(a.out)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
