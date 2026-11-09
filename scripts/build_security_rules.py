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
選び方（A-218 G0）: docs/superpowers/specs/2026-11-09-scam-link-protection-design.md
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(__file__).resolve().parent / "data"
# 共有ホスト: 手で選んだ物 + 公開のサフィックス一覧（PSL）の共有ホストの節
DEFAULT_SHARED_PARENTS = [DATA_DIR / "shared-hosting-parents.txt", DATA_DIR / "psl-private-suffixes.txt"]
DEFAULT_JP_TOKENS = DATA_DIR / "jp-priority-tokens.txt"
# 重要ドメイン（止めない）の読み先。アプリの判定と同じ一覧を使う
PROTECTED_SWIFT = {
    "safari": [REPO_ROOT / "Shared/CriticalDomainGuard.swift"],
    "dns": [REPO_ROOT / "Shared/CriticalDomainGuard.swift", REPO_ROOT / "Shared/DNS/DNSCriticalGuard.swift"],
}
PROFILES = ("safari", "dns")

# 元データが途中で切れた時に守りが外れないよう、下限を割ったら止める
TRANCO_MIN = 900_000
PHISHING_MIN = 100_000
# DNS では、上が Tranco 上位 10 万の人気サイトのサブドメインは入れない
DNS_POPULAR_TOP = 100_000


@dataclass(frozen=True)
class JPTokens:
    jp: tuple[str, ...]
    jp_token: tuple[str, ...]
    brand: tuple[str, ...]


class SourceTooSmall(Exception):
    """元データが下限を割った（取得が途中で切れた等）。"""


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


_HOST_RE = re.compile(r"^[a-z0-9_-]+(\.[a-z0-9_-]+)+$")


def convert_to_content_blocker_rules(hosts: Iterable[str]) -> list[dict]:
    """host のリストを Safari Content Blocker JSON ルールに変換。"""
    rules: list[dict] = []
    seen: set[str] = set()
    for host in hosts:
        host = host.lower().strip()
        if not host or host in seen:
            continue
        seen.add(host)
        if not _HOST_RE.match(host):
            continue  # ホスト名に使えない文字が混ざった行は正規表現を壊しうるので入れない
        # 他の配信リスト（popunder-rules.json・変換器の出力）と同じ書き方。
        # ★「(/|$)」のような「|」は WebKit が解釈できず、1 本でもあるとリスト全体の
        #   コンパイルが失敗する（"Disjunctions are not supported yet"・2026-09-27 実測）
        escaped = host.replace(".", "\\.")
        rules.append({
            "trigger": {"url-filter": f"^[^:]+://+([^:/]+\\.)?{escaped}[/:]"},
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
        h = h.lower().strip().rstrip(".")
        # 壊れた行は上限を数える前に捨てる（後で捨てると件数が上限を割る）
        if not h or h in seen or h in tranco or not _HOST_RE.match(h):
            continue
        seen.add(h)
        all_hosts.append(h)
        if len(all_hosts) >= limit:
            break
    return convert_to_content_blocker_rules(all_hosts)


def check_sources(tranco_count: int, phishing_count: int) -> None:
    """Tranco と Phishing.Database の件数が下限を割っていたら止める。"""
    if tranco_count < TRANCO_MIN:
        raise SourceTooSmall(f"Tranco {tranco_count} < {TRANCO_MIN}")
    if phishing_count < PHISHING_MIN:
        raise SourceTooSmall(f"Phishing.Database {phishing_count} < {PHISHING_MIN}")


_SWIFT_SET_RE = re.compile(r"Set<String>\s*=\s*\[(.*?)\]", re.S)
_SWIFT_STRING_RE = re.compile(r'"([^"\\]*)"')


def load_protected_domains(swift_paths: list[Path]) -> set[str]:
    """Swift の `Set<String> = [ ... ]` の中の文字列だけを読む（// のコメントは除く）。"""
    result: set[str] = set()
    for path in swift_paths:
        text = "\n".join(line.split("//", 1)[0] for line in Path(path).read_text(encoding="utf-8").splitlines())
        for body in _SWIFT_SET_RE.findall(text):
            result.update(d.strip().lower() for d in _SWIFT_STRING_RE.findall(body) if d.strip())
    return result


def load_shared_parents(path: Path) -> set[str]:
    """1 行 1 ホスト。「#」から後はコメント。「*.」で始まる行はそのまま残す（その物と 1 つ下の全てが共有ホスト）。"""
    result: set[str] = set()
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        host = line.split("#", 1)[0].strip().lower().rstrip(".")
        if host:
            result.add(host)
    return result


def load_tranco_ranked(text: str) -> list[str]:
    """Tranco CSV (rank,domain) をファイルの順（＝順位の順）で返す。"""
    ranked: list[str] = []
    for line in text.splitlines():
        parts = line.strip().split(",")
        if len(parts) >= 2 and parts[1].strip():
            ranked.append(parts[1].strip().lower())
    return ranked


def _ancestors(host: str) -> list[str]:
    """host の上のドメイン（「.」を含む物だけ）。a.b.example.com → [b.example.com, example.com]"""
    parts = host.split(".")
    return [".".join(parts[i:]) for i in range(1, len(parts) - 1)]


def tranco_closure(tranco_ranked: Iterable[str]) -> set[str]:
    """Tranco の全ドメインと、その上の全て（その上を止めると人気サイトごと止まる）。"""
    closure: set[str] = set()
    for domain in tranco_ranked:
        closure.add(domain)
        closure.update(_ancestors(domain))
    return closure


def _is_shared(host: str, shared_parents: set[str]) -> bool:
    if host in shared_parents or ("*." + host) in shared_parents:
        return True
    parent = host.split(".", 1)[1] if "." in host else ""
    return bool(parent) and ("*." + parent) in shared_parents


_IPV4_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")


def exclusion_reason(
    host: str,
    *,
    profile: str,
    tranco_closure: set[str],
    popular: set[str],
    protected: set[str],
    shared_parents: set[str],
) -> str | None:
    """一覧に入れない理由の短い名前か None。計測の表もこの名前を使う。"""
    if not _HOST_RE.match(host):
        return "invalid"
    if profile == "dns" and _IPV4_RE.match(host):
        return "ip"
    if _is_shared(host, shared_parents):
        return "shared-parent"
    if host in protected or any(a in protected for a in _ancestors(host)) \
            or any(p.endswith("." + host) for p in protected):
        return "protected"
    if host in tranco_closure:
        return "tranco"
    if profile == "dns":
        for anc in _ancestors(host):
            if anc in popular and not _is_shared(anc, shared_parents):
                return "popular-parent"
    return None


def _normalize(host: str) -> str:
    return host.lower().strip().rstrip(".")


def select_hosts(
    urlhaus_hosts: list[str],
    phishing_hosts: list[str],
    tranco_ranked: list[str],
    *,
    protected: set[str],
    shared_parents: set[str],
    jp_tokens: JPTokens,
    profile: str,
    limit: int,
    urlhaus_cap: int = 10_000,
) -> list[str]:
    """除外を通ったホストを返す（Task A2: 元の並び順のまま）。"""
    if profile not in PROFILES:
        raise ValueError(f"unknown profile: {profile}")
    closure = tranco_closure(tranco_ranked)
    popular = set(tranco_ranked[:DNS_POPULAR_TOP])
    out: list[str] = []
    seen: set[str] = set()
    for raw in list(urlhaus_hosts) + list(phishing_hosts):
        host = _normalize(raw)
        if not host or host in seen:
            continue
        seen.add(host)
        if exclusion_reason(host, profile=profile, tranco_closure=closure, popular=popular,
                            protected=protected, shared_parents=shared_parents) is None:
            out.append(host)
            if len(out) >= limit:
                break
    return out


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    # URLhaus は 2026-10 から取れない（410）。渡されない時は無しで作る
    parser.add_argument("--urlhaus", type=Path, default=None,
                        help="URLhaus host file path（省略可）")
    parser.add_argument("--phishing-db", required=True, type=Path,
                        dest="phishing_db",
                        help="Phishing.Database active domains text file path")
    parser.add_argument("--tranco", required=True, type=Path,
                        help="Tranco top 1M CSV path")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--limit", type=int, default=30000)
    return parser


def main() -> None:
    args = build_parser().parse_args()

    urlhaus_text = args.urlhaus.read_text(encoding="utf-8") if args.urlhaus else ""
    phishing_db_text = args.phishing_db.read_text(encoding="utf-8")
    tranco_text = args.tranco.read_text(encoding="utf-8")
    check_sources(len(load_tranco_ranked(tranco_text)), len(parse_phishing_db_hosts(phishing_db_text)))

    rules = build_security_rules(
        urlhaus_text, phishing_db_text, tranco_text, limit=args.limit
    )
    args.output.write_text(json.dumps(rules, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {len(rules)} rules → {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
