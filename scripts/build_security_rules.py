#!/usr/bin/env python3
"""URLhaus + Phishing.Database からセキュリティルール JSON を構築する。

入力:
- URLhaus host file (text、format: "127.0.0.1\\thost")
- Phishing.Database active domains file (text、format: 1 host / line)
- Tranco top 1M (text、format: rank,domain)

出力: Safari Content Blocker JSON 形式

データソース:
- URLhaus: https://urlhaus.abuse.ch/downloads/hostfile/ (CC0 1.0)
  ※ 2026-10 から 410（取れない）。--urlhaus は省略可
- Phishing.Database: https://raw.githubusercontent.com/mitchellkrogza/Phishing.Database/master/phishing-domains-ACTIVE.txt (MIT)
- Tranco: https://tranco-list.eu/ (誤検知除外用)

仕様: docs/superpowers/specs/2026-06-02-anti-phishing-design.md §6
選び方（A-218 G0）: docs/superpowers/specs/2026-11-09-scam-link-protection-design.md
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

# `python3 -I` でも同じフォルダの build_split_rules を読めるようにする（-I はスクリプトの場所を足さない）
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_split_rules import SECURITY_BUDGET, SECURITY_MAX_BYTES, _rule_bytes  # noqa: E402

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
# 上が Tranco 上位 10 万の人気サイトのサブドメインは入れない（DNS は全部。Safari は共有ホストの利用者の物を除く。
# 名前は DNS 用に作った時のまま）
DNS_POPULAR_TOP = 100_000
# URLhaus（マルウェアの配布元）の段の上限。日本向けの次に入れるが、これ以上は詐欺サイトの枠を取らない
URLHAUS_CAP = 10_000
# 共有ホストの一覧（PSL）に載っていても、すぐ下に事業者自身のサービスが並ぶ入口
# （sts.us-east-1.amazonaws.com・cognito-idp.us-east-1.amazonaws.com など）。
# 利用者の持ち物の境目として扱わない＝重要ドメイン・人気サイトの下で個別のホストを入れる理由にしない
PROVIDER_NAMESPACES: frozenset[str] = frozenset({"us-east-1.amazonaws.com"})
# 登録に資格が要る日本の公的機関（政府・自治体・大学・学校）。元の一覧に載っていれば乗っ取られた本物のサイト
# ＝止めると必要なサイトが開かない（設計 §4 反目標）。Safari・DNS とも入れない
PUBLIC_JP_SUFFIXES = ("go.jp", "lg.jp", "ac.jp", "ed.jp")


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


def _is_tenant_boundary(host: str, shared_parents: set[str]) -> bool:
    """その下が利用者の持ち物になる共有ホストか（事業者自身のサービスが並ぶ入口は除く）。"""
    return _is_shared(host, shared_parents) and host not in PROVIDER_NAMESPACES


def is_public_jp(host: str) -> bool:
    return any(host == s or host.endswith("." + s) for s in PUBLIC_JP_SUFFIXES)


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
    if is_public_jp(host):
        return "public-jp"
    if _is_shared(host, shared_parents):
        return "shared-parent"
    ancestors = _ancestors(host)
    if host in protected or any(p.endswith("." + host) for p in protected):
        return "protected"
    for i, anc in enumerate(ancestors):
        if anc in protected:
            # Safari: 重要ドメインの下でも、間に共有ホストがある個別のホスト（S3 のバケット等）は入れてよい
            # （止めても重要ドメインそのものは止まらない）。DNS は厳しく外す
            if profile == "safari" and any(_is_tenant_boundary(a, shared_parents) for a in ancestors[:i]):
                break
            return "protected"
    if host in tranco_closure:
        return "tranco"
    if profile == "safari":
        # 人気サイトの下は、間か人気サイトその物が共有ホスト（＝利用者の持ち物）の時だけ入れる。
        # 人気サイトの中のサービスの住所（画像配信・メールのクリック計測・フォーム）を止めない
        for anc in ancestors:
            if _is_tenant_boundary(anc, shared_parents):
                break
            if anc in popular:
                return "popular-parent"
    if profile == "dns":
        for anc in ancestors:
            if anc in popular and not _is_shared(anc, shared_parents):
                return "popular-parent"
    return None


def _normalize(host: str) -> str:
    return host.lower().strip().rstrip(".")


def load_jp_tokens(path: Path) -> JPTokens:
    """行頭の印（jp: / jp-token: / brand:）ごとに、空白で区切った語を読む。「#」から後はコメント。"""
    kinds: dict[str, list[str]] = {"jp": [], "jp-token": [], "brand": []}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line or ":" not in line:
            continue
        kind, words = line.split(":", 1)
        kind = kind.strip().lower()
        if kind in kinds:
            kinds[kind].extend(w.lower() for w in words.split())
    return JPTokens(jp=tuple(kinds["jp"]), jp_token=tuple(kinds["jp-token"]), brand=tuple(kinds["brand"]))


_WORD_SPLIT_RE = re.compile(r"[.-]")


def jp_priority(host: str, tokens: JPTokens, shared_parents: Iterable[str] = frozenset()) -> int:
    """0 = 日本向け（.jp で終わる・jp の語を含む・jp-token の語と完全一致）／1 = 海外ブランド／2 = その他。
    語は最後のラベル（.com など）を除いた部分で見る。共有ホストの下では、共有ホストより左
    （攻撃者が決めた部分）だけで見る（xyz.s3.amazonaws.com の「amazonaws」は Amazon の偽装ではない）。"""
    if host.endswith(".jp"):
        return 0
    body = None
    if shared_parents:
        shared = shared_parents if isinstance(shared_parents, (set, frozenset)) else set(shared_parents)
        for anc in _ancestors(host):
            if _is_shared(anc, shared):
                body = host[: -(len(anc) + 1)]
                break
    if body is None:
        body = host.rsplit(".", 1)[0] if "." in host else host
    if any(t in body for t in tokens.jp):
        return 0
    words = set(_WORD_SPLIT_RE.split(body))
    if any(t in words for t in tokens.jp_token):
        return 0
    if any(t in body for t in tokens.brand):
        return 1
    return 2


def stable_key(host: str) -> str:
    """段の中の並び。名前の順（元の一覧の並び）に左右されず、毎週同じ物は同じ位置に来る。"""
    return hashlib.sha256(host.encode()).hexdigest()


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
    urlhaus_cap: int = URLHAUS_CAP,
) -> list[str]:
    """除外を通ったホストを優先順に上から limit 件返す（元の一覧に無いホストは足さない）。

    段 0 日本向け（両方の元データ）→ 段 1 URLhaus の残り（urlhaus_cap まで）→ 段 2 海外ブランド → 段 3 その他。
    各段の中は stable_key の順。URLhaus だけにあって段 1 の上限を超えた物は入れない。
    """
    if profile not in PROFILES:
        raise ValueError(f"unknown profile: {profile}")
    closure = tranco_closure(tranco_ranked)
    popular = set(tranco_ranked[:DNS_POPULAR_TOP])

    def accepted(raw_hosts: list[str]) -> set[str]:
        out: set[str] = set()
        for raw in raw_hosts:
            host = _normalize(raw)
            if host and host not in out and exclusion_reason(
                host, profile=profile, tranco_closure=closure, popular=popular,
                protected=protected, shared_parents=shared_parents,
            ) is None:
                out.add(host)
        return out

    urlhaus = accepted(urlhaus_hosts)
    phishing = accepted(phishing_hosts)
    tiers: list[list[str]] = [[], [], [], []]
    prio = {host: jp_priority(host, jp_tokens, shared_parents) for host in urlhaus | phishing}
    for host in urlhaus | phishing:
        if prio[host] == 0:
            tiers[0].append(host)
    jp = set(tiers[0])
    urlhaus_rest = sorted(urlhaus - jp, key=stable_key)
    tiers[1] = urlhaus_rest[:urlhaus_cap]
    taken = jp | set(tiers[1])
    for host in phishing - taken:
        tiers[2 if prio[host] == 1 else 3].append(host)
    ordered: list[str] = []
    for tier in tiers:
        ordered.extend(sorted(tier, key=stable_key))
    return ordered[:limit]


def build_security_rules(
    urlhaus_text: str,
    phishing_db_text: str,
    tranco_text: str,
    limit: int = SECURITY_BUDGET,
    max_bytes: int = SECURITY_MAX_BYTES,
) -> list[dict]:
    """Safari 用の詐欺サイトの規則。優先順に足していき、件数 limit か大きさ max_bytes の手前で止める。

    重要ドメイン・共有ホスト・日本向けの語は既定の場所（Swift と scripts/data）から読む。
    """
    shared: set[str] = set()
    for path in DEFAULT_SHARED_PARENTS:
        shared |= load_shared_parents(path)
    hosts = select_hosts(
        parse_urlhaus_hosts(urlhaus_text),
        parse_phishing_db_hosts(phishing_db_text),
        load_tranco_ranked(tranco_text),
        protected=load_protected_domains(PROTECTED_SWIFT["safari"]),
        shared_parents=shared,
        jp_tokens=load_jp_tokens(DEFAULT_JP_TOKENS),
        profile="safari",
        limit=limit,
    )
    rules: list[dict] = []
    size = 2  # "[" と "]"（build_split_rules.list_bytes と同じ数え方）
    for rule in convert_to_content_blocker_rules(hosts):
        add = _rule_bytes(rule) + (1 if rules else 0)
        if size + add > max_bytes:
            break
        size += add
        rules.append(rule)
    return rules


def check_rule_count(count: int, limit: int = SECURITY_BUDGET) -> None:
    """件数が枠の半分未満なら止める（2 本目の入れ替え replace_security_tail の「前回の半分未満」と同じ線）。"""
    if count * 2 < limit:
        raise SourceTooSmall(f"security rules {count} < half of {limit}")


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
    # 違う名前の数で見る（取得が壊れて同じ行が繰り返されても、人気サイトの除外が消えたまま配らない）
    check_sources(len(set(load_tranco_ranked(tranco_text))), len(set(parse_phishing_db_hosts(phishing_db_text))))

    rules = build_security_rules(
        urlhaus_text, phishing_db_text, tranco_text, limit=args.limit
    )
    check_rule_count(len(rules), args.limit)
    args.output.write_text(json.dumps(rules, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {len(rules)} rules → {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
