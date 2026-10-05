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
- 基本保護は 2 本目が無効な人（旧版アプリも）の唯一の守りなので、広告ルールだけで埋める
  （重要ルール → 通信の遮断 → 要素隠し）。
  ❌ 変換器の並び（要素隠し → 遮断）のまま詰める → 最後に繋ぐ EasyList の主要な遮断（doubleclick・pagead2・
  ads-twitter）が 2 本目に押し出される。例外は全部入れるので、例外が通した先（gpt.js の先の広告配信）を
  止める規則が基本保護に無くなり、基本保護だけの人の漏れが今より増えた（9/27 計測 116 対 79）。
  要素隠しは日本語フィルタが先に並ぶので、2 本目に回るのは主に海外サイト向けのサイト別の要素隠し。
- セキュリティは 2 本目（両方オン）の末尾（広告の例外に打ち消されない位置）。
  アプリはその後ろにポップアップ対策を並べるので、その例外が通すホストと重なるセキュリティ規則は
  特定サイトの中の部品読み込みに限って打ち消される（詐欺サイトのページを開く操作には効く・9/27 時点で 3 件）。
  ❌ 基本保護にセキュリティ 3 万件の枠を取る → その分の広告ルールが 2 本目へ押し出され、基本保護だけの人の
  漏れが今の 2 倍（9/27 計測 164.5 対 79.0）。今の merged はセキュリティ 0 件なので、2 本目に置いても誰も減らない。

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
SECOND_TOTAL_CAP = 149_000 - 2_000      # 2 本目のうち報告の予約を除いた枠（残り＋ポップアップ対策）
SECURITY_BUDGET = 30_000               # build-security-rules.yml の --limit と同じ

# 1 本のバイト数の上限（2026-10-05）。拡張はファイルを丸ごとメモリに載せて Safari に渡すので、
# バイト数がそのまま拡張のメモリになる。実機で読めた実績 = 20.6MB（A-88 前の基本保護・数か月）・12.6MB、
# 読めなかった = 27.6MB（A-88 ①の基本保護。拡張が jetsam per-process-limit で強制終了＝広告ブロックが全く入らない）。
# 実績の下に置き、アプリが実行時に足す分（報告ルール 2,000 件・ポップアップ対策・一時オフ 200 件）用に 0.5MB 空ける
# ＝拡張が渡す最終の大きさは 20MB（Shared/ReportedRuleBudget.swift の maxListBytes）以下。
# シミュレータには拡張のメモリ上限が無いので、ここで縛らないと見つけられない（tasks/ads-not-blocked-2026-10-05.md）。
LIST_MAX_BYTES = 19_500_000
SECURITY_MAX_BYTES = 4_000_000         # セキュリティ 3 万件の今の大きさ 3.5MB に 1 割強の余裕


def _rule_bytes(rule: dict) -> int:
    return len(json.dumps(rule, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))


def list_bytes(rules: list[dict]) -> int:
    """配信するファイル（`_dump` の書き方）のバイト数＝拡張が Safari に渡すときに載せるメモリの目安。"""
    return 2 + sum(_rule_bytes(r) for r in rules) + max(0, len(rules) - 1)


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


def _priority(rules: list[dict], protected_hosts=frozenset(), first_seen: list[int] | None = None) -> list[int]:
    """例外以外のルールの位置を、基本保護に入れる優先順に並べる。

    変換器の並びは 要素隠し → 遮断 → 例外 → 重要な遮断 → 重要な例外（SafariCbBuilder.createEntries）。
    1. ポップアップ対策の例外が通すホスト宛てのルール（2 本目に置くと、後ろに並ぶ
       ポップアップ対策の例外に打ち消される＝今日は効いている遮断が外れる）
    2. 「最初の遮断より後ろに出てくる最初の例外」より後ろにある例外以外のルール＝重要ルール
    3. 残りの遮断（要素隠し以外）→ 汎用の要素隠し → サイト別の要素隠し。それぞれの中は並び順。
       重複を消して後ろのコピーを残したルールは、`first_seen`（重複除去前の最初のコピーの位置）で並べる
       ＝前のフィルタ（日本語）にもあるルールはその位置で数える
    どれを基本保護に入れても効き方は変わらない（例外は両方に全部あり、各ルールの後ろには上限なしの
    1 本と同じ例外が並ぶ）。優先順は「基本保護だけの人に何を残すか」だけを決める。
    """
    first_block = next((i for i, r in enumerate(rules) if r["action"]["type"] == "block"), len(rules))
    tail_start = next(
        (i for i in range(first_block, len(rules)) if _is_exception(rules[i])), len(rules))
    candidates = [i for i in range(len(rules)) if not _is_exception(rules[i])]
    protected = [i for i in candidates if protected_hosts and _is_protected(rules[i], protected_hosts)]
    taken = set(protected)
    important = [i for i in candidates if i >= tail_start and i not in taken]
    rest = [i for i in candidates if i < tail_start and i not in taken]
    seen = first_seen if first_seen is not None else list(range(len(rules)))

    def kind(i: int) -> int:
        r = rules[i]
        if r["action"]["type"] != "css-display-none":
            return 0
        t = r["trigger"]
        return 2 if ("if-domain" in t or "unless-domain" in t) else 1

    rest.sort(key=lambda i: (kind(i), seen[i]))
    return protected + important + rest


def split_rules(
    full: list[dict],
    basic_cap: int = BASIC_CAP,
    second_cap: int = SECOND_CAP,
    protected_hosts: set[str] | frozenset[str] = frozenset(),
    basic_max_bytes: int = LIST_MAX_BYTES,
    second_max_bytes: int = LIST_MAX_BYTES,
) -> tuple[list[dict], list[dict], int]:
    """全量 `full`（変換器の並び）を 基本保護 / 2 本目 に振り分ける（広告ルールだけ。セキュリティは build_outputs）。

    - 件数（`*_cap`）とバイト数（`*_max_bytes`）の両方の枠に収める。優先順の先頭から入る分だけ入れる。
    - 2 本目が上限を超えたら、優先順の最後（サイト別の要素隠しの最後）から捨てる。例外は捨てない。
    - `protected_hosts` 宛てのルールは基本保護に最優先で入れる（`_priority` の 1）。
    - 重複は後ろのコピーだけ残す（`dedup_keep_last`）。基本保護に入れる優先順は前のコピーの位置で決める。
    - Returns: (基本保護, 2 本目, 2 本目で捨てた件数)
    """
    first_copy: dict[str, int] = {}
    for i, r in enumerate(full):
        first_copy.setdefault(json.dumps(r, sort_keys=True), i)
    full = dedup_keep_last(full)
    first_seen = [first_copy[json.dumps(r, sort_keys=True)] for r in full]
    exceptions = [i for i, r in enumerate(full) if _is_exception(r)]
    basic_room = basic_cap - len(exceptions)
    if basic_room < 0:
        raise SplitError(f"basic cap {basic_cap} cannot hold {len(exceptions)} exceptions")
    second_room = second_cap - len(exceptions)
    if second_room < 0:
        raise SplitError(f"second cap {second_cap} cannot hold {len(exceptions)} exceptions")

    exception_bytes = list_bytes([full[i] for i in exceptions])
    if exception_bytes > basic_max_bytes:
        raise SplitError(f"basic max bytes {basic_max_bytes} cannot hold exceptions of {exception_bytes} bytes")
    if exception_bytes > second_max_bytes:
        raise SplitError(f"second max bytes {second_max_bytes} cannot hold exceptions of {exception_bytes} bytes")

    def take(candidates: list[int], room: int, room_bytes: int) -> list[int]:
        """優先順の先頭から、件数とバイトの枠に入る分だけ（1 件足すごとに区切りの "," が 1 バイト増える）。"""
        taken, used = [], 0
        for i in candidates:
            size = _rule_bytes(full[i]) + 1
            if len(taken) >= room or used + size > room_bytes:
                break
            taken.append(i)
            used += size
        return taken

    order = _priority(full, protected_hosts, first_seen)
    basic_taken = take(order, basic_room, basic_max_bytes - exception_bytes)
    to_basic = set(basic_taken)
    rest = order[len(basic_taken):]
    to_second = take(rest, second_room, second_max_bytes - exception_bytes)
    dropped = len(rest) - len(to_second)
    to_second_set = set(to_second)
    exception_set = set(exceptions)

    basic = [r for i, r in enumerate(full) if i in exception_set or i in to_basic]
    second = [r for i, r in enumerate(full) if i in exception_set or i in to_second_set]
    return basic, second, dropped


def build_outputs(
    full: list[dict],
    security: list[dict],
    security_budget: int = SECURITY_BUDGET,
    basic_cap: int = BASIC_CAP,
    second_cap: int = SECOND_CAP,
    popunder: list[dict] | None = None,
    dropped: dict[str, int] | None = None,
    second_total_cap: int = SECOND_TOTAL_CAP,
    list_max_bytes: int = LIST_MAX_BYTES,
    security_max_bytes: int = SECURITY_MAX_BYTES,
) -> dict[str, list[dict]]:
    """トグル（広告・セキュリティ）別の 4 リストを作る。

    - basic-ads-sec / second-ads-sec: 広告とセキュリティ両方オン（既定）
    - basic-ads / second-ads: 広告だけオン
    基本保護は両方とも同じ（広告ルールだけ）。セキュリティは second-ads-sec の末尾に付ける。
    その枠は実際の件数ではなく `security_budget` で固定する
    （週ごとのセキュリティ件数の増減で広告の振り分けが揺れない＝週次は末尾だけ入れ替える）。
    `popunder` を渡すと、その例外が通すホスト宛てのルールを基本保護に寄せる（アプリは
    2 本目の後ろにポップアップ対策を並べるため）。
    `dropped` を渡すと、2 本目にも入り切らず捨てた件数を 2 本目のファイル名ごとに書き込む。
    """
    protected = l2_allowed_hosts(popunder or [])
    if len(security) > security_budget:
        raise SplitError(f"security {len(security)} exceeds budget {security_budget}")
    if list_bytes(security) > security_max_bytes:
        raise SplitError(f"security {list_bytes(security)} bytes exceeds {security_max_bytes}")
    # リストの後ろに別のリストを繋ぐと、繋いだ側のバイト数 - 1（括弧 2 つが消え、区切り 1 つが増える）だけ増える。
    # 2 本目はアプリが後ろにポップアップ対策を並べ、両方オンはセキュリティを予算いっぱいで数える。
    popunder_add = list_bytes(popunder) - 1 if popunder else 0
    security_add = security_max_bytes - 1
    basic_ads, second_ads, dropped_ads = split_rules(
        full, basic_cap=basic_cap, second_cap=second_cap, protected_hosts=protected,
        basic_max_bytes=list_max_bytes, second_max_bytes=list_max_bytes - popunder_add)
    basic_sec, second_sec_ads, dropped_sec = split_rules(
        full, basic_cap=basic_cap, second_cap=second_cap - security_budget, protected_hosts=protected,
        basic_max_bytes=list_max_bytes, second_max_bytes=list_max_bytes - popunder_add - security_add)
    second_sec = second_sec_ads + list(security)
    if dropped is not None:
        dropped.update({"second-ads-sec": dropped_sec, "second-ads": dropped_ads})
    # アプリは残りの後ろにポップアップ対策をそのまま並べる（件数では切らない）。伸び代を超えたら止める。
    # セキュリティは予算いっぱいで数える（週次は月次を通さずに末尾だけ入れ替えるので、ここで最大の形を確かめる）
    for name, worst in (("second-ads-sec", len(second_sec_ads) + security_budget), ("second-ads", len(second_ads))):
        if worst + len(popunder or []) > second_total_cap:
            raise SplitError(f"{name} {worst} + popunder {len(popunder or [])} exceeds {second_total_cap}")
    return {
        "basic-ads-sec": basic_sec,
        "second-ads-sec": second_sec,
        "basic-ads": basic_ads,
        "second-ads": second_ads,
    }


def replace_security_tail(
    second_ads_sec: list[dict],
    old_security: list[dict],
    new_security: list[dict],
    security_budget: int = SECURITY_BUDGET,
    security_max_bytes: int = SECURITY_MAX_BYTES,
) -> list[dict]:
    """週次のセキュリティ更新: 2 本目（両方オン）の末尾のセキュリティ部分だけを入れ替える。

    末尾が前回のセキュリティと一致しないとき（手で直した・月次が未実行等）は入れ替えずに止める。
    新しい件数が前回の半分未満のときも止める（アプリも前回の半分未満のファイルは捨てる＝配信すると
    2 本目を毎回ダウンロードしては捨てることになる。止めれば CDN は前の週のまま）。
    """
    if len(new_security) > security_budget:
        raise SplitError(f"security {len(new_security)} exceeds budget {security_budget}")
    if list_bytes(new_security) > security_max_bytes:
        raise SplitError(f"security {list_bytes(new_security)} bytes exceeds {security_max_bytes}")
    if len(new_security) * 2 < len(old_security):
        raise SplitError(f"security {len(new_security)} is below half of the previous {len(old_security)}")
    n = len(old_security)
    if n > len(second_ads_sec) or second_ads_sec[len(second_ads_sec) - n:] != old_security:
        raise SplitError("second-ads-sec does not end with the previous security rules")
    return second_ads_sec[: len(second_ads_sec) - n] + list(new_security)


def check_not_shrunk(name: str, old_count: int, new_count: int) -> None:
    """新しいファイルの件数が今配信中の半分未満なら止める。

    アプリ（RuleUpdatePlanner.validateRuleCount）は前回入れたファイルの半分未満を壊れたものとして捨てる
    ＝配っても誰にも入らない。同じ線で配信前に止めて気づかせる。
    """
    if new_count * 2 < old_count:
        raise SplitError(f"{name}: {new_count} rules is below half of the published {old_count}")


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

    c = sub.add_parser("check-shrink", help="新しいファイルが今配信中の半分未満の件数なら止める")
    c.add_argument("--published", required=True, type=Path, help="今配信中のファイル（無ければ確かめない）")
    c.add_argument("--new", required=True, type=Path)

    s = sub.add_parser("swap-security", help="2 本目（両方オン）の末尾のセキュリティだけ入れ替える（週次）")
    s.add_argument("--second", required=True, type=Path, help="docs/cdn/second-ads-sec.json")
    s.add_argument("--old-security", required=True, type=Path)
    s.add_argument("--new-security", required=True, type=Path)
    s.add_argument("--output", required=True, type=Path)

    args = parser.parse_args()
    if args.cmd == "build":
        dropped: dict[str, int] = {}
        outs = build_outputs(_load(args.full), _load(args.security), popunder=_load(args.popunder),
                             dropped=dropped)
        args.out_dir.mkdir(parents=True, exist_ok=True)
        for name, rules in outs.items():
            _dump(rules, args.out_dir / f"{name}.json")
            note = f" (dropped {dropped[name]} that fit neither list)" if dropped.get(name) else ""
            print(f"{name}: {len(rules)} rules, {list_bytes(rules)} bytes{note}")
    elif args.cmd == "check-shrink":
        old = len(_load(args.published)) if args.published.exists() else 0
        check_not_shrunk(args.published.name, old_count=old, new_count=len(_load(args.new)))
    else:
        swapped = replace_security_tail(
            _load(args.second), _load(args.old_security), _load(args.new_security))
        _dump(swapped, args.output)
        print(f"second-ads-sec: {len(swapped)} rules")


if __name__ == "__main__":
    main()
