#!/usr/bin/env python3
"""dns-rules.json（DNS ブロック用ドメイン配列）と version-dns.json（manifest）を生成する。

入力 `scripts/dns-adservers.txt`（1 行 1 ドメイン）を検証・重複除去・ソートし、
JSON 配列（`["doubleclick.net", ...]`）として 2 箇所へ書き出す:
  1. bundle 同梱用: PacketTunnelExtension/Resources/dns-rules.json（fresh install の初期リスト）
  2. CDN 配信用:   docs/cdn/dns-rules.json（GitHub Pages）+ docs/cdn/version-dns.json（sha256 manifest）

Content Blocker JSON（scripts/build_popunder_rules.py 等）とは別物。DNS トンネルは
DNSBlocklist([String]) を使うため、ここでは url-filter オブジェクトではなくドメイン文字列配列を出す。

Spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §DNSBlocklist / self-fetch 更新
"""
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

# 妥当な domain = 英数 / ドット / ハイフンのみ（build_popunder_rules.py と同一契約）。
_VALID_DOMAIN = re.compile(r"^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$")

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scripts" / "dns-adservers.txt"
BUNDLE_OUT = ROOT / "PacketTunnelExtension" / "Resources" / "dns-rules.json"
CDN_RULES = ROOT / "docs" / "cdn" / "dns-rules.json"
CDN_MANIFEST = ROOT / "docs" / "cdn" / "version-dns.json"


def parse_domains(text: str) -> list[str]:
    """ソースから domain を抽出（`#` コメント・空行を無視・小文字化・検証・重複除去・ソート）。"""
    seen: set[str] = set()
    for raw in text.splitlines():
        s = raw.strip().lower()
        if not s or s.startswith("#"):
            continue
        if not _VALID_DOMAIN.match(s):
            raise ValueError(f"invalid domain in {SOURCE.name}: {raw!r}")
        seen.add(s)
    return sorted(seen)


def _write_json_array(path: Path, domains: list[str]) -> bytes:
    """domain 配列を安定整形（2 space・末尾改行）で書き、書いたバイト列を返す。"""
    payload = (json.dumps(domains, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return payload


def main() -> None:
    domains = parse_domains(SOURCE.read_text(encoding="utf-8"))
    payload = _write_json_array(BUNDLE_OUT, domains)
    _write_json_array(CDN_RULES, domains)   # bundle と CDN は同一内容

    manifest = {
        "dns-rules_sha256": hashlib.sha256(payload).hexdigest(),
        "dns-rules_bytes": len(payload),
        "dns-rules_count": len(domains),
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    CDN_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"dns-rules: {len(domains)} domains, {len(payload)} bytes, sha256={manifest['dns-rules_sha256'][:12]}…")
    print(f"  bundle:   {BUNDLE_OUT.relative_to(ROOT)}")
    print(f"  cdn:      {CDN_RULES.relative_to(ROOT)}")
    print(f"  manifest: {CDN_MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
