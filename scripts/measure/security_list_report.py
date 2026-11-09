#!/usr/bin/env python3
"""詐欺サイトの一覧を直す前と後で並べて測る（A-218 G0）。

使い方:
  python3 -I scripts/measure/security_list_report.py --old docs/cdn/security-rules.json --new <新しい json|txt> \
      [--urlhaus <txt>] --phishing-db <txt> --tranco <csv> --jp-sample <txt> \
      [--second-ads-sec docs/cdn/second-ads-sec.json] --profile safari|dns --out <md>

--old none で「前」を空にできる（DNS 用の初回）。.json は Safari の規則、.txt は 1 行 1 ドメイン。
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from build_security_rules import (  # noqa: E402
    DEFAULT_JP_TOKENS,
    DEFAULT_SHARED_PARENTS,
    PROTECTED_SWIFT,
    DNS_POPULAR_TOP,
    JPTokens,
    _ancestors,
    _is_tenant_boundary,
    exclusion_reason,
    is_public_jp,
    jp_priority,
    load_jp_tokens,
    load_protected_domains,
    load_shared_parents,
    load_tranco_ranked,
    parse_phishing_db_hosts,
    parse_urlhaus_hosts,
    stable_key,
    tranco_closure,
)
from build_split_rules import (  # noqa: E402
    LIST_MAX_BYTES,
    SECURITY_MAX_BYTES,
    SplitError,
    list_bytes,
    replace_security_tail,
)

SAFARI_MAX_RULES = 150_000           # Safari の 1 本の上限
TRANCO_CHECK_TOP = 10_000            # 誤ブロックを数える人気サイトの範囲
REPORT_TOKENS = ("amazon", "rakuten", "aeon", "nta-", "paypay", "saison", "smbc")
SAMPLES_PER_REASON = 20

_FILTER_RE = re.compile(r"^\^\[\^:\]\+://\+\(\[\^:/\]\+\\\.\)\?(.+)\[/:\]$")
_IPV4_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")


def hosts_from_rules(rules: list[dict]) -> list[str]:
    """規則の url-filter からホストを戻す（convert_to_content_blocker_rules の逆）。"""
    hosts: list[str] = []
    for rule in rules:
        m = _FILTER_RE.match(rule.get("trigger", {}).get("url-filter", ""))
        if m:
            hosts.append(m.group(1).replace("\\.", "."))
    return hosts


def load_hosts(path: Path) -> list[str]:
    """.json は Safari の規則、それ以外は 1 行 1 ドメイン（# の行と空行は飛ばす）。"""
    path = Path(path)
    if path.suffix == ".json":
        return hosts_from_rules(json.loads(path.read_text(encoding="utf-8")))
    hosts: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip().lower().rstrip(".")
        if line and not line.startswith("#"):
            hosts.append(line)
    return hosts


def matches(host: str, selected: set[str]) -> bool:
    """規則と同じ意味: host がどれかと同じか、その下なら当たる。"""
    return host in selected or any(a in selected for a in _ancestors(host))


def _counts(hosts: list[str]) -> dict:
    return {
        "total": len(hosts),
        "ipv4": sum(bool(_IPV4_RE.match(h)) for h in hosts),
        "digit_start": sum(h[:1].isdigit() for h in hosts),
        "alpha_start": sum(h[:1].isalpha() for h in hosts),
    }


def _popular_bucket(host: str, rank: dict[str, int], shared_parents: set[str]) -> str | None:
    """host の上の人気サイト（共有ホストの利用者の物を除く）の一番上の順位の帯。無ければ None。"""
    best = None
    for anc in _ancestors(host):
        if _is_tenant_boundary(anc, shared_parents):
            break
        k = rank.get(anc)
        if k is not None and (best is None or k < best):
            best = k
    if best is None:
        return None
    return "top10k" if best <= 10_000 else "top100k" if best <= 100_000 else "top1m"


def _is_protected_tenant(host: str, protected: set[str], shared_parents: set[str]) -> bool:
    """重要ドメインの下で、間に共有ホストがある利用者の物（S3 のバケット等）。"""
    ancestors = _ancestors(host)
    for i, anc in enumerate(ancestors):
        if anc in protected:
            return any(_is_tenant_boundary(a, shared_parents) for a in ancestors[:i])
    return False


def _false_blocks(selected: set[str], tranco_top: list[str], protected: set[str]) -> dict:
    return {
        "tranco_top10k": sum(matches(d, selected) for d in tranco_top),
        "protected": sum(matches(p, selected) for p in protected),
    }


def report(
    old_rules: list[dict],
    new_rules: list[dict],
    *,
    urlhaus_hosts: list[str],
    phishing_hosts: list[str],
    tranco_ranked: list[str],
    protected: set[str],
    jp_sample: list[str],
    second_ads_sec: list[dict] | None,
    shared_parents: set[str] | None = None,
    jp_tokens: JPTokens | None = None,
    profile: str = "safari",
    old_hosts: list[str] | None = None,
    new_hosts: list[str] | None = None,
) -> dict:
    """直す前と後の数字を dict で返す。second_ads_sec が None なら 2 本目の確かめは飛ばす（DNS 用）。

    old_hosts / new_hosts を渡すと規則の代わりにそれを使う（DNS 用の 1 行 1 ドメイン）。
    """
    if shared_parents is None:
        shared_parents = set()
        for p in DEFAULT_SHARED_PARENTS:
            shared_parents |= load_shared_parents(p)
    if jp_tokens is None:
        jp_tokens = load_jp_tokens(DEFAULT_JP_TOKENS)
    old = old_hosts if old_hosts is not None else hosts_from_rules(old_rules)
    new = new_hosts if new_hosts is not None else hosts_from_rules(new_rules)
    old_set, new_set = set(old), set(new)
    norm = lambda h: h.lower().strip().rstrip(".")  # noqa: E731
    urlhaus = {norm(h) for h in urlhaus_hosts if h.strip()}
    phishing = {norm(h) for h in phishing_hosts if h.strip()}
    source = urlhaus | phishing

    tiers = Counter()
    sites = set(tranco_ranked)
    for h in new:
        prio = jp_priority(h, jp_tokens, shared_parents, sites)
        tiers["jp" if prio == 0 else "urlhaus" if h in urlhaus else "brand" if prio == 1 else "rest"] += 1

    tranco_top = tranco_ranked[:TRANCO_CHECK_TOP]
    closure = tranco_closure(tranco_ranked)
    popular = set(tranco_ranked[:DNS_POPULAR_TOP])

    def reason(h: str) -> str | None:
        return exclusion_reason(h, profile=profile, tranco_closure=closure, popular=popular,
                                protected=protected, shared_parents=shared_parents)

    sample = sorted({norm(h) for h in jp_sample if h.strip()})
    # 見本に当たる元の一覧のホストのうち、除外を通る物（＝止められる形で入っている物）
    source_blockable = {m for h in sample for m in [h, *_ancestors(h)] if m in source and reason(m) is None}
    jp = {
        "n": len(sample),
        "in_source": sum(matches(h, source) for h in sample),
        "in_source_blockable": sum(matches(h, source_blockable) for h in sample),
        "selected_old": sum(matches(h, old_set) for h in sample),
        "selected_new": sum(matches(h, new_set) for h in sample),
    }

    tokens = {t: {"source": sum(t in h for h in source), "old": sum(t in h for h in old),
                  "new": sum(t in h for h in new)} for t in REPORT_TOKENS}

    rank: dict[str, int] = {}
    for i, d in enumerate(tranco_ranked):
        rank.setdefault(d, i + 1)
    under_popular: dict = {"samples_new": {}}
    for name, hosts in (("old", old), ("new", new)):
        buckets = {"top10k": [], "top100k": [], "top1m": []}
        for h in hosts:
            b = _popular_bucket(h, rank, shared_parents)
            if b:
                buckets[b].append(h)
        under_popular[name] = {k: len(v) for k, v in buckets.items()}
        if name == "new":
            under_popular["samples_new"] = {k: sorted(v, key=stable_key)[:SAMPLES_PER_REASON] for k, v in buckets.items()}

    dropped: dict[str, list[str]] = {}
    for h in old:
        why = reason(h)
        if why:
            dropped.setdefault(why, []).append(h)

    size: dict = {"security_bytes": list_bytes(new_rules) if new_hosts is None else None,
                  "security_max_bytes": SECURITY_MAX_BYTES, "second": None}
    size["security_ok"] = size["security_bytes"] is None or size["security_bytes"] <= SECURITY_MAX_BYTES
    if second_ads_sec is not None:
        try:
            swapped = replace_security_tail(second_ads_sec, old_rules, new_rules)
            b = list_bytes(swapped)
            size["second"] = {"ok": len(swapped) <= SAFARI_MAX_RULES and b <= LIST_MAX_BYTES,
                              "count": len(swapped), "bytes": b, "error": None}
        except SplitError as e:
            size["second"] = {"ok": False, "count": None, "bytes": None, "error": str(e)}

    return {
        "profile": profile,
        "sources": {"urlhaus": len(urlhaus), "phishing": len(phishing), "tranco": len(tranco_ranked)},
        "counts": {
            "old": {**_counts(old), "unreadable": len(old_rules) - len(old) if old_hosts is None else 0},
            "new": {**_counts(new), "unreadable": len(new_rules) - len(new) if new_hosts is None else 0},
        },
        "tiers_new": {k: tiers.get(k, 0) for k in ("jp", "urlhaus", "brand", "rest")},
        "jp_sample": jp,
        "tokens": tokens,
        "false_blocks_old": _false_blocks(old_set, tranco_top, protected),
        "false_blocks_new": _false_blocks(new_set, tranco_top, protected),
        "under_popular": under_popular,
        "public_jp": {"old": sum(map(is_public_jp, old)), "new": sum(map(is_public_jp, new))},
        "protected_tenants": {"old": sum(_is_protected_tenant(h, protected, shared_parents) for h in old),
                              "new": sum(_is_protected_tenant(h, protected, shared_parents) for h in new)},
        "dropped_from_old": {
            "by_reason": {k: len(v) for k, v in sorted(dropped.items())},
            "samples": {k: sorted(v, key=stable_key)[:SAMPLES_PER_REASON] for k, v in sorted(dropped.items())},
        },
        "old_not_in_source": sum(h not in source for h in old),
        "size": size,
    }


def _pct(n: int, d: int) -> str:
    return f"{n:,}（{n / d * 100:.1f}%）" if d else f"{n:,}"


def to_markdown(r: dict) -> str:
    o, n = r["counts"]["old"], r["counts"]["new"]
    lines = [
        f"## 計測（profile = {r['profile']}）",
        "",
        f"元データ: URLhaus {r['sources']['urlhaus']:,} 件 / 詐欺サイトの元の一覧 {r['sources']['phishing']:,} 件 / "
        f"Tranco {r['sources']['tranco']:,} 件",
        "",
        "| | 前 | 後 |",
        "|---|---:|---:|",
        f"| 件数 | {o['total']:,} | {n['total']:,} |",
        f"| IPv4 | {_pct(o['ipv4'], o['total'])} | {_pct(n['ipv4'], n['total'])} |",
        f"| 数字始まり | {_pct(o['digit_start'], o['total'])} | {_pct(n['digit_start'], n['total'])} |",
        f"| 英字始まり | {_pct(o['alpha_start'], o['total'])} | {_pct(n['alpha_start'], n['total'])} |",
        f"| 読めない規則 | {o['unreadable']:,} | {n['unreadable']:,} |",
        f"| 人気サイトのトップが止まる: Tranco 上位 1 万 | {r['false_blocks_old']['tranco_top10k']} | {r['false_blocks_new']['tranco_top10k']} |",
        f"| 重要ドメインのトップが止まる | {r['false_blocks_old']['protected']} | {r['false_blocks_new']['protected']} |",
    ]
    up = r["under_popular"]
    for key, label in (("top10k", "1 万位まで"), ("top100k", "10 万位まで"), ("top1m", "100 万位まで")):
        lines.append(f"| 人気サイトの中の住所: {label} | {up['old'][key]:,} | {up['new'][key]:,} |")
    lines += [
        f"| 公的機関・団体の .jp（go・lg・ac・ed・or） | {r['public_jp']['old']:,} | {r['public_jp']['new']:,} |",
        f"| 重要ドメインの下の共有ホストの利用者 | {r['protected_tenants']['old']:,} | {r['protected_tenants']['new']:,} |",
        "",
        "「人気サイトの中の住所」は、人気サイト（Tranco）のサブドメインのうち、共有ホストの利用者の物でない物。"
        "数えるのは一番上の順位の帯。",
        "",
        "### 新しい一覧の段",
        "",
        "| 日本向け | URLhaus | 海外ブランド | その他 |",
        "|---:|---:|---:|---:|",
        "| {jp:,} | {urlhaus:,} | {brand:,} | {rest:,} |".format(**r["tiers_new"]),
        "",
    ]
    j = r["jp_sample"]
    lines += [
        "### 日本向けの見本",
        "",
        "| 見本 | 元の一覧にある | うち止められる形（共有ホスト・人気サイト等でない） | 前に選ばれていた | 後に選ばれる |",
        "|---:|---:|---:|---:|---:|",
        f"| {j['n']:,} | {_pct(j['in_source'], j['n'])} | {_pct(j['in_source_blockable'], j['n'])} | "
        f"{_pct(j['selected_old'], j['n'])} | {_pct(j['selected_new'], j['n'])} |",
        "",
        f"止められる形で元の一覧にある物のうち: 前 {_pct(j['selected_old'], j['in_source_blockable'])} → "
        f"後 {_pct(j['selected_new'], j['in_source_blockable'])}",
        "",
        "### 語を含む件数",
        "",
        "| 語 | 元の一覧 | 前 | 後 |",
        "|---|---:|---:|---:|",
    ]
    for t, c in r["tokens"].items():
        lines.append(f"| `{t}` | {c['source']:,} | {c['old']:,} | {c['new']:,} |")
    d = r["dropped_from_old"]
    lines += ["", "### 前の一覧のうち、新しい除外で外れる物", ""]
    if d["by_reason"]:
        lines += ["| 理由 | 件数 | 見本 |", "|---|---:|---|"]
        for k, v in d["by_reason"].items():
            lines.append(f"| {k} | {v:,} | {' '.join(d['samples'][k])} |")
    else:
        lines.append("無し")
    lines += ["", "### 人気サイトの中の住所（後・見本）", ""]
    for key, label in (("top10k", "1 万位まで"), ("top100k", "10 万位まで"), ("top1m", "100 万位まで")):
        lines.append(f"- {label}: {' '.join(up['samples_new'][key]) or '無し'}")
    lines += ["", f"前の一覧のうち、今日の元データに無い物: {_pct(r['old_not_in_source'], o['total'])}", ""]
    s = r["size"]
    lines += ["### 大きさ", ""]
    if s["security_bytes"] is not None:
        lines.append(f"- 詐欺サイトの部分: {s['security_bytes']:,} バイト（上限 {s['security_max_bytes']:,}）→ "
                     f"{'OK' if s['security_ok'] else '超過'}")
    if s["second"] is not None:
        sec = s["second"]
        if sec["error"]:
            lines.append(f"- 2 本目の末尾の入れ替え: 失敗（{sec['error']}）")
        else:
            lines.append(f"- 2 本目の末尾の入れ替え: 成功・{sec['count']:,} 件（上限 {SAFARI_MAX_RULES:,}）・"
                         f"{sec['bytes']:,} バイト（上限 {LIST_MAX_BYTES:,}）→ {'OK' if sec['ok'] else '超過'}")
    return "\n".join(lines) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--old", required=True, help="前の一覧（.json / .txt / none）")
    ap.add_argument("--new", required=True, type=Path)
    ap.add_argument("--urlhaus", type=Path, default=None)
    ap.add_argument("--phishing-db", required=True, type=Path, dest="phishing_db")
    ap.add_argument("--tranco", required=True, type=Path)
    ap.add_argument("--jp-sample", required=True, type=Path, dest="jp_sample")
    ap.add_argument("--second-ads-sec", type=Path, default=None, dest="second_ads_sec")
    ap.add_argument("--profile", choices=("safari", "dns"), default="safari")
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()

    def rules_or_hosts(path: Path | None) -> tuple[list[dict], list[str] | None]:
        """(規則, ホスト)。.json は規則を返しホストは None（規則から戻す）。none は両方空。"""
        if path is None:
            return [], []
        if path.suffix == ".json":
            return json.loads(path.read_text(encoding="utf-8")), None
        return [], load_hosts(path)

    old_rules, old_hosts = rules_or_hosts(None if a.old == "none" else Path(a.old))
    new_rules, new_hosts = rules_or_hosts(a.new)
    r = report(
        old_rules, new_rules,
        urlhaus_hosts=parse_urlhaus_hosts(a.urlhaus.read_text(encoding="utf-8")) if a.urlhaus else [],
        phishing_hosts=parse_phishing_db_hosts(a.phishing_db.read_text(encoding="utf-8")),
        tranco_ranked=load_tranco_ranked(a.tranco.read_text(encoding="utf-8")),
        protected=load_protected_domains(PROTECTED_SWIFT[a.profile]),
        jp_sample=load_hosts(a.jp_sample),
        second_ads_sec=json.loads(a.second_ads_sec.read_text(encoding="utf-8")) if a.second_ads_sec else None,
        profile=a.profile,
        old_hosts=old_hosts,
        new_hosts=new_hosts,
    )
    a.out.write_text(to_markdown(r), encoding="utf-8")
    a.out.with_suffix(".json").write_text(json.dumps(r, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {a.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
