#!/usr/bin/env python3
"""上限なしで変換した広告ルール全量を、2 本のコンテンツブロッカーに振り分ける（A-88 §1）。

- 基本保護（`.blocker`・全員）と 2 本目（`.popunderblocker`）はどちらも 15 万件が上限。
  今まではその上限で全量の 34% を捨てていて、捨てた中に例外（サイトが崩れないための
  「止めないで」）の 79% と、サイト丸ごとの例外・重要ルールが全部入っていた。
- 例外（ignore-previous-rules）は **同じリストの、それより前のルールにしか効かない**。
  そこで例外は 2 本の両方に元の並び順のまま全部残し、例外以外のルールだけを振り分ける。
  どのルールも「上限なしの 1 本」のときと同じ例外が自分の後ろに並ぶので、
  2 本の合わせ技は上限なしの 1 本と同じ効き方になる。
  ❌ 例外を末尾へ集める → 変換器が「直前の汎用要素隠しだけを消す」位置に置いた
  `.*`＋`if-domain` の例外が、そのサイトの遮断まで全部消してしまう（9/27 の C3 案で発覚）。
- 基本保護は 2 本目が無効な人の唯一の守りなので、重要ルール → 要素隠し → 遮断の順
  （変換器の並びどおり＝今の配信と同じ優先順）で埋める。セキュリティは基本保護の末尾
  （広告の例外に打ち消されない位置）。

設計: tasks/a88-design-2026-09-27.md §1 / tasks/todo.md ①
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

# 1 リストの上限は 150,000。アプリは実行時に後ろへ足す（一時オフ 最大 200 件・
# 2 本目にはポップアップと報告ルールの予約 2,000 件）ので、その分を空けて作る。
# 値の根拠: Shared/ReportedRuleBudget.swift（totalCap 149,000・reportedReserve 2,000）
# と Shared/SiteExceptionsStore.swift（maxDomains 200）。
BASIC_CAP = 149_000 - 200
SECOND_CAP = 149_000 - 2_000 - 1_000   # ポップアップ（今 40 件）の伸び代 1,000
SECURITY_BUDGET = 30_000               # build-security-rules.yml の --limit と同じ


class SplitError(Exception):
    """振り分けられない（上限に収まらない・入力が想定と違う）。配信を止めて気づかせる。"""


def _is_exception(rule: dict) -> bool:
    return rule.get("action", {}).get("type") == "ignore-previous-rules"


# `^[^:]+://+([^:/]+\.)?<ホスト>` で始まる url-filter（変換器・ポップアップ対策とも同じ書き方）
_HOST_ANCHORED = re.compile(r"^\^\[\^:\]\+://\+\(\[\^:/\]\+\\\.\)\?((?:[a-z0-9-]+\\\.)+[a-z0-9-]+)")


def _anchored_host(url_filter: str) -> str | None:
    m = _HOST_ANCHORED.match(url_filter)
    return m.group(1).replace("\\.", ".") if m else None


def l2_allowed_hosts(popunder: list[dict]) -> set[str]:
    """ポップアップ対策（2 本目の後ろに並ぶ）の例外が通すホスト。

    Swift 側 PopunderReportedFilter.l2AllowedDomains と同じ読み方。
    """
    hosts = set()
    for r in popunder:
        if _is_exception(r):
            h = _anchored_host(r["trigger"].get("url-filter", ""))
            if h:
                hosts.add(h)
    return hosts


def dedup_keep_last(rules: list[dict]) -> list[dict]:
    """まったく同じルールの重複を、後ろのコピーだけ残して消す（例外も含む）。

    1 本のリストとしての効き方は変わらない: 前のコピーが効く場面では、後ろのコピーも効く
    （間に打ち消しがあれば前のコピーは消えていて、後ろのコピーだけが効いていた）。
    ❌ 前のコピーを残す → 例外より後ろにある重要ルールのコピーが消え、例外に打ち消される。
    全量には複数のフィルタから来た重複が 6.2 万件ある（2026-09-27 実測）。
    """
    last = {}
    for i, r in enumerate(rules):
        last[json.dumps(r, sort_keys=True)] = i
    keep = set(last.values())
    return [r for i, r in enumerate(rules) if i in keep]


def _is_protected(rule: dict, protected_hosts) -> bool:
    h = _anchored_host(rule["trigger"].get("url-filter", ""))
    return h is not None and any(h == p or h.endswith("." + p) for p in protected_hosts)


def _priority(rules: list[dict], protected_hosts=frozenset()) -> list[int]:
    """例外以外のルールの位置を、基本保護に入れる優先順に並べる。

    変換器の並びは 要素隠し → 遮断 → 例外 → 重要な遮断 → 重要な例外（SafariCbBuilder.createEntries）。
    1. ポップアップ対策の例外が通すホスト宛てのルール（2 本目に置くと、後ろに並ぶ
       ポップアップ対策の例外に打ち消される＝今日は効いている遮断が外れる）
    2. 「最初の遮断より後ろに出てくる最初の例外」より後ろにある例外以外のルール＝重要ルール
    3. 残りを並び順のまま（上限で切るときの今の優先順と同じ）
    """
    first_block = next((i for i, r in enumerate(rules) if r["action"]["type"] == "block"), len(rules))
    tail_start = next(
        (i for i in range(first_block, len(rules)) if _is_exception(rules[i])), len(rules))
    candidates = [i for i in range(len(rules)) if not _is_exception(rules[i])]
    protected = [i for i in candidates if protected_hosts and _is_protected(rules[i], protected_hosts)]
    taken = set(protected)
    important = [i for i in candidates if i >= tail_start and i not in taken]
    rest = [i for i in candidates if i < tail_start and i not in taken]
    return protected + important + rest


def split_rules(
    full: list[dict],
    security: list[dict],
    basic_cap: int = BASIC_CAP,
    second_cap: int = SECOND_CAP,
    security_budget: int | None = None,
    protected_hosts: set[str] | frozenset[str] = frozenset(),
) -> tuple[list[dict], list[dict], int]:
    """全量 `full`（変換器の並び）を 基本保護 / 2 本目 に振り分ける。

    - `security` は基本保護の末尾に付ける。広告に回せる枠は `security_budget`
      （省略時は実際の件数）を引いて決める。
    - 2 本目が上限を超えたら、優先順の最後（並びの最後の遮断）から捨てる。例外は捨てない。
    - `protected_hosts` 宛てのルールは基本保護に最優先で入れる（`_priority` の 1）。
    - 重複は後ろのコピーだけ残す（`dedup_keep_last`）。
    - Returns: (基本保護, 2 本目, 2 本目で捨てた件数)
    """
    full = dedup_keep_last(full)
    exceptions = [i for i, r in enumerate(full) if _is_exception(r)]
    reserved_security = len(security) if security_budget is None else security_budget
    if len(security) > reserved_security:
        raise SplitError(f"security {len(security)} exceeds budget {reserved_security}")

    basic_room = basic_cap - len(exceptions) - reserved_security
    if basic_room < 0:
        raise SplitError(
            f"basic cap {basic_cap} cannot hold {len(exceptions)} exceptions + {reserved_security} security")
    second_room = second_cap - len(exceptions)
    if second_room < 0:
        raise SplitError(f"second cap {second_cap} cannot hold {len(exceptions)} exceptions")

    order = _priority(full, protected_hosts)
    to_basic = set(order[:basic_room])
    to_second = order[basic_room:]
    dropped = max(0, len(to_second) - second_room)
    if dropped:
        to_second = to_second[:second_room]
    to_second_set = set(to_second)
    exception_set = set(exceptions)

    basic = [r for i, r in enumerate(full) if i in exception_set or i in to_basic] + list(security)
    second = [r for i, r in enumerate(full) if i in exception_set or i in to_second_set]
    return basic, second, dropped


def build_outputs(
    full: list[dict],
    security: list[dict],
    security_budget: int = SECURITY_BUDGET,
    basic_cap: int = BASIC_CAP,
    second_cap: int = SECOND_CAP,
    popunder: list[dict] | None = None,
) -> dict[str, list[dict]]:
    """トグル（広告・セキュリティ）別の 4 リストを作る。

    - basic-ads-sec / second-ads-sec: 広告とセキュリティ両方オン（既定）
    - basic-ads / second-ads: 広告だけオン
    セキュリティの枠は実際の件数ではなく `security_budget` で固定する
    （週ごとのセキュリティ件数の増減で広告の振り分けが揺れない＝2 本目は月 1 回しか変わらない）。
    `popunder` を渡すと、その例外が通すホスト宛てのルールを基本保護に寄せる（アプリは
    2 本目の後ろにポップアップ対策を並べるため）。
    """
    protected = l2_allowed_hosts(popunder or [])
    basic_sec, second_sec, _ = split_rules(
        full, security, basic_cap=basic_cap, second_cap=second_cap, security_budget=security_budget,
        protected_hosts=protected)
    basic_ads, second_ads, _ = split_rules(full, [], basic_cap=basic_cap, second_cap=second_cap,
                                           protected_hosts=protected)
    return {
        "basic-ads-sec": basic_sec,
        "second-ads-sec": second_sec,
        "basic-ads": basic_ads,
        "second-ads": second_ads,
    }


def replace_security_tail(
    basic_ads_sec: list[dict],
    old_security: list[dict],
    new_security: list[dict],
    security_budget: int = SECURITY_BUDGET,
) -> list[dict]:
    """週次のセキュリティ更新: 基本保護（両方オン）の末尾のセキュリティ部分だけを入れ替える。

    末尾が前回のセキュリティと一致しないとき（手で直した・月次が未実行等）は入れ替えずに止める。
    """
    if len(new_security) > security_budget:
        raise SplitError(f"security {len(new_security)} exceeds budget {security_budget}")
    n = len(old_security)
    if n > len(basic_ads_sec) or basic_ads_sec[len(basic_ads_sec) - n:] != old_security:
        raise SplitError("basic-ads-sec does not end with the previous security rules")
    return basic_ads_sec[: len(basic_ads_sec) - n] + list(new_security)


def _load(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))


def _dump(rules: list[dict], path: Path) -> None:
    path.write_text(json.dumps(rules, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build", help="上限なし全量 + セキュリティ → 4 リスト（月次）")
    b.add_argument("--full", required=True, type=Path)
    b.add_argument("--security", required=True, type=Path)
    b.add_argument("--popunder", required=True, type=Path,
                   help="2 本目の後ろに並ぶポップアップ対策（docs/cdn/popunder-rules.json）")
    b.add_argument("--out-dir", required=True, type=Path)

    s = sub.add_parser("swap-security", help="基本保護（両方オン）の末尾のセキュリティだけ入れ替える（週次）")
    s.add_argument("--basic", required=True, type=Path)
    s.add_argument("--old-security", required=True, type=Path)
    s.add_argument("--new-security", required=True, type=Path)
    s.add_argument("--output", required=True, type=Path)

    args = parser.parse_args()
    if args.cmd == "build":
        outs = build_outputs(_load(args.full), _load(args.security), popunder=_load(args.popunder))
        args.out_dir.mkdir(parents=True, exist_ok=True)
        for name, rules in outs.items():
            _dump(rules, args.out_dir / f"{name}.json")
            print(f"{name}: {len(rules)} rules")
    else:
        swapped = replace_security_tail(
            _load(args.basic), _load(args.old_security), _load(args.new_security))
        _dump(swapped, args.output)
        print(f"basic-ads-sec: {len(swapped)} rules")


if __name__ == "__main__":
    main()
