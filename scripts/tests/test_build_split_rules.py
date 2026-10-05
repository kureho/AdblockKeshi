"""Tests for build_split_rules.py（A-88 §1: 上限なし全量を 2 本のコンテンツブロッカーに振り分ける）

守りたい性質は 1 つ: **2 本の合わせ技が「上限なしの 1 本」と同じ効き方になる**こと。
例外（ignore-previous-rules）は同じリストの「それより前」のルールにしか効かないので、
例外は両方のリストに元の並び順のまま全部残し、例外以外のルールだけを振り分ける。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from build_split_rules import (  # noqa: E402
    SplitError,
    _dump,
    build_outputs,
    check_not_shrunk,
    l2_allowed_hosts,
    list_bytes,
    replace_security_tail,
    split_rules,
)


def css(sel: str, domains: list[str] | None = None) -> dict:
    t: dict = {"url-filter": ".*"}
    if domains:
        t["if-domain"] = domains
    return {"trigger": t, "action": {"type": "css-display-none", "selector": sel}}


def block(host: str, domains: list[str] | None = None) -> dict:
    t: dict = {"url-filter": r"^[^:]+://+([^:/]+\.)?" + re.escape(host) + "[/:]"}
    if domains:
        t["if-domain"] = domains
    return {"trigger": t, "action": {"type": "block"}}


def allow(url_filter: str, domains: list[str] | None = None) -> dict:
    t: dict = {"url-filter": url_filter}
    if domains:
        t["if-domain"] = domains
    return {"trigger": t, "action": {"type": "ignore-previous-rules"}}


def is_exc(r: dict) -> bool:
    return r["action"]["type"] == "ignore-previous-rules"


# 変換器（SafariCbBuilder.createEntries）と同じ並びの小さな全量:
# 汎用の要素隠し → 「このサイトでは汎用を隠さない」例外 → サイト別の要素隠し → 遮断 → 通常の例外
# → 重要な遮断 → 重要な例外
FULL = [
    css(".ad-generic"),                                   # 0 汎用
    allow(".*", ["*shop.example"]),                       # 1 shop.example では汎用の要素隠しだけ外す
    css(".ad-news", ["*news.example"]),                   # 2 サイト別
    block("ads.example"),                                 # 3
    block("track.example"),                               # 4
    block("ima.example"),                                 # 5
    block("tail1.example"),                               # 6
    block("tail2.example"),                               # 7
    allow(r"^[^:]+://+([^:/]+\.)?ima\.example[/:]", ["*video.example"]),  # 8 動画サイトでは ima を通す
    block("important.example", ["*video.example"]),       # 9 重要な遮断（例外より後ろ＝打ち消されない）
    allow(r"^[^:]+://+([^:/]+\.)?important\.example[/:]", ["*ok.example"]),  # 10 重要な例外
]
SECURITY = [block("phish1.example"), block("phish2.example")]


def evaluate(rules: list[dict], url: str, page_host: str) -> tuple[bool, set[str]]:
    """WebKit のコンテンツブロッカーの効き方を小さく真似る（並び順どおりに適用・例外は前を消す）。"""
    blocked = False
    selectors: set[str] = set()

    def domain_ok(trigger: dict) -> bool:
        ds = trigger.get("if-domain")
        if not ds:
            return True
        for d in ds:
            base = d.lstrip("*")
            if page_host == base or (d.startswith("*") and page_host.endswith("." + base)):
                return True
        return False

    for r in rules:
        t = r["trigger"]
        if not domain_ok(t) or not re.search(t["url-filter"], url):
            continue
        a = r["action"]["type"]
        if a == "block":
            blocked = True
        elif a == "css-display-none":
            selectors.add(r["action"]["selector"])
        elif a == "ignore-previous-rules":
            blocked = False
            selectors = set()
    return blocked, selectors


REQUESTS = [
    (f"https://{h}/x.js", page)
    for h in ["ads.example", "track.example", "ima.example", "tail1.example", "tail2.example",
              "important.example", "phish1.example", "phish2.example", "benign.example"]
    for page in ["news.example", "shop.example", "video.example", "ok.example", "other.example"]
] + [(f"https://{page}/", page) for page in ["news.example", "shop.example", "video.example"]]


def assert_same_as_single_list(parts: list[list[dict]], single: list[dict], requests=REQUESTS) -> None:
    for url, page in requests:
        want = evaluate(single, url, page)
        got_blocked = False
        got_sel: set[str] = set()
        for p in parts:
            b, s = evaluate(p, url, page)
            got_blocked = got_blocked or b
            got_sel |= s
        assert (got_blocked, got_sel) == want, (url, page)


def test_every_exception_stays_in_both_lists_in_original_order():
    basic, second, _ = split_rules(FULL, basic_cap=7, second_cap=100)
    want = [r for r in FULL if is_exc(r)]
    assert [r for r in basic if is_exc(r)] == want
    assert [r for r in second if is_exc(r)] == want


def test_non_exception_rules_go_to_exactly_one_list():
    basic, second, dropped = split_rules(FULL, basic_cap=7, second_cap=100)
    assert dropped == 0
    non_exc = [r for r in FULL if not is_exc(r)]
    got = [r for r in basic if not is_exc(r)] + [r for r in second if not is_exc(r)]
    assert sorted(map(repr, got)) == sorted(map(repr, non_exc))


def test_both_lists_keep_the_single_list_order():
    basic, second, _ = split_rules(FULL, basic_cap=7, second_cap=100)
    pos = {repr(r): i for i, r in enumerate(FULL)}
    for part in (basic, second):
        idx = [pos[repr(r)] for r in part]
        assert idx == sorted(idx)


@pytest.mark.parametrize("basic_cap", [4, 5, 6, 7, 8, 9, 10, 11])
def test_two_lists_together_behave_like_one_uncapped_list(basic_cap):
    basic, second, _ = split_rules(FULL, basic_cap=basic_cap, second_cap=100)
    assert_same_as_single_list([basic, second], FULL)


def test_basic_is_filled_important_first_then_blocks_before_element_hiding():
    # 例外 3 本 + 重要 1 本 + 遮断を並び順に 2 本。要素隠し（汎用・サイト別）は 2 本目へ
    # 9/27 計測（R_S）: 変換器の並び（要素隠し → 遮断）のまま詰めると、最後のフィルタ（EasyList）の
    # 主要な広告の遮断（doubleclick・pagead2・ads-twitter）が 2 本目に押し出され、全部入れた例外
    # （gpt.js を通す等）の先を止める規則が基本保護に無くなる＝基本保護だけの人の漏れが 116 対 79
    basic, second, _ = split_rules(FULL, basic_cap=6, second_cap=100)
    non_exc = [r for r in basic if not is_exc(r)]
    assert non_exc == [FULL[3], FULL[4], FULL[9]]
    assert FULL[0] in second and FULL[2] in second


def test_generic_element_hiding_comes_before_site_specific_element_hiding():
    # 遮断が全部入った後の余りは、全サイトに効く汎用の要素隠しを先に入れる
    basic, second, _ = split_rules(FULL, basic_cap=10, second_cap=100)
    assert FULL[0] in basic and FULL[2] in second


def test_basic_never_exceeds_its_cap():
    for cap in range(3, 16):
        basic, _, _ = split_rules(FULL, basic_cap=cap, second_cap=100)
        assert len(basic) <= cap


def test_second_overflow_drops_element_hiding_first_then_blocks_from_the_end():
    # 2 本目の上限を小さくすると、優先順の最後（サイト別の要素隠し → 汎用の要素隠し）から捨てる。
    # 遮断・例外・重要ルールは残す
    basic, second, dropped = split_rules(FULL, basic_cap=6, second_cap=6)
    assert dropped == 2
    assert len(second) == 6
    assert FULL[2] not in second and FULL[0] not in second
    assert all(r in basic or r in second for r in FULL[3:8])
    assert [r for r in second if is_exc(r)] == [r for r in FULL if is_exc(r)]


def test_fails_when_exceptions_do_not_fit_in_basic():
    with pytest.raises(SplitError):
        split_rules(FULL, basic_cap=2, second_cap=100)


def test_basic_holds_only_the_exceptions_when_they_fill_the_cap_exactly():
    # 例外の件数 == 上限（余り 0）は失敗ではない。基本保護は例外だけ、広告は全部 2 本目
    n_exc = sum(1 for r in FULL if is_exc(r))
    basic, second, dropped = split_rules(FULL, basic_cap=n_exc, second_cap=100)
    assert all(is_exc(r) for r in basic) and len(basic) == n_exc
    assert [r for r in second if not is_exc(r)] == [r for r in FULL if not is_exc(r)]
    assert dropped == 0


def test_fails_when_second_cannot_even_hold_the_exceptions():
    with pytest.raises(SplitError):
        split_rules(FULL, basic_cap=6, second_cap=2)


def test_build_outputs_puts_security_at_the_end_of_the_second_list():
    # 9/27 計測: セキュリティ 3 万件を基本保護に入れると、その分の広告ルールが 2 本目へ押し出され、
    # 基本保護だけの人（2 本目が無効・旧版アプリ）の漏れが今の 2 倍になった。今の配信の merged は
    # セキュリティ 0 件（旧 build_merged_rules.py が広告の後ろで打ち切っていた）＝2 本目に置いても誰からも減らない
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    assert set(out) == {"basic-ads-sec", "second-ads-sec", "basic-ads", "second-ads"}
    assert out["basic-ads-sec"] == out["basic-ads"]
    assert len(out["basic-ads"]) == 9
    assert not any(r in SECURITY for r in out["basic-ads-sec"])
    assert out["second-ads-sec"][-2:] == SECURITY
    assert out["second-ads-sec"][:-2] == out["second-ads"]
    assert_same_as_single_list([out["basic-ads-sec"], out["second-ads-sec"]], FULL + SECURITY)
    assert_same_as_single_list([out["basic-ads"], out["second-ads"]], FULL)


def test_build_outputs_reserves_a_fixed_security_budget_in_the_second_list():
    # 2 本目（両方オン）はセキュリティの枠を実際の件数（2）ではなく固定の 3 で空ける＝週ごとの件数で振り分けが揺れない。
    # 溢れたら捨てた件数を返す（月次のログに出して、上限の見直しに気づけるようにする）
    dropped: dict[str, int] = {}
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=5, second_cap=7, dropped=dropped)
    ads = len([r for r in FULL if not is_exc(r)])
    assert dropped == {"second-ads-sec": ads - (5 - 3) - (7 - 3 - 3), "second-ads": ads - (5 - 3) - (7 - 3)}
    assert len(out["second-ads-sec"]) == 7 - 3 + 2


def test_build_outputs_rejects_security_over_budget():
    with pytest.raises(SplitError):
        build_outputs(FULL, SECURITY, security_budget=1, basic_cap=9, second_cap=100)


def test_replace_security_tail_swaps_only_the_security_part():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    new_sec = [block("phish3.example")]
    swapped = replace_security_tail(out["second-ads-sec"], old_security=SECURITY, new_security=new_sec)
    assert swapped[:-1] == out["second-ads-sec"][:-2]
    assert swapped[-1:] == new_sec


def test_replace_security_tail_refuses_when_tail_does_not_match():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    with pytest.raises(SplitError):
        replace_security_tail(out["second-ads-sec"], old_security=[block("other.example")],
                              new_security=SECURITY)


def test_replace_security_tail_refuses_new_security_over_budget():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    too_many = [block(f"p{i}.example") for i in range(4)]
    with pytest.raises(SplitError):
        replace_security_tail(out["second-ads-sec"], old_security=SECURITY, new_security=too_many,
                              security_budget=3)


# ── 2 本目のリストはアプリが「広告の残り → ポップアップ対策 → 報告 → 一時オフ」の順に並べる ──
# ポップアップ対策の L2 は「そのサイトでは外部スクリプトを全部止めてから、プレーヤーに要る
# ドメインだけ例外で戻す」作り。例外は同じリストの前のルール全部に効くので、広告の残りを
# 前に置くと、その許可ドメイン宛ての広告ルールまで外してしまう（例: 動画広告の ima）。
# 今日は基本保護とポップアップ対策が別リストなので、この打ち消しは起きていない。
POPUNDER = [
    block("popads.example"),                                           # L1
    {"trigger": {"url-filter": r"\.example/x\.js", "if-domain": ["*tube.example"]},
     "action": {"type": "block"}},                                     # L2 そのサイトの外部スクリプトを全部止める
    allow(r"^[^:]+://+([^:/]+\.)?ima\.example[/:]", ["*tube.example"]),  # L2 プレーヤーに要るので戻す
]
L2_REQUESTS = [
    (f"https://{h}/x.js", page)
    for h in ["ads.example", "ima.example", "tail1.example", "tail2.example", "popads.example",
              "important.example", "benign.example"]
    for page in ["tube.example", "video.example", "other.example"]
] + [(f"https://{page}/", page) for page in ["tube.example", "video.example", "other.example"]]


def assert_same_as_separate_lists(parts, reference_parts, requests):
    # WebKit は要素隠しをページ本体の URL でしか判定しない（部品の読み込みでは遮断だけを見る）
    def union(lists, url, page):
        blocked, sel = False, set()
        for rules in lists:
            b, s = evaluate(rules, url, page)
            blocked, sel = blocked or b, sel | s
        return (blocked, sel) if url == f"https://{page}/" else (blocked, None)
    for url, page in requests:
        assert union(parts, url, page) == union(reference_parts, url, page), (url, page)


def test_l2_allowed_hosts_reads_only_the_popunder_exceptions():
    assert l2_allowed_hosts(POPUNDER) == {"ima.example"}


@pytest.mark.parametrize("basic_cap", [4, 5, 6, 7, 8, 9, 10, 11])
def test_second_plus_popunder_matches_today_on_l2_sites(basic_cap):
    # 今日 = 上限なしの広告 1 本 と ポップアップ対策 が別リスト
    basic, second, _ = split_rules(FULL, basic_cap=basic_cap, second_cap=100,
                                   protected_hosts=l2_allowed_hosts(POPUNDER))
    assert_same_as_separate_lists([basic, second + POPUNDER], [FULL, POPUNDER],
                                  L2_REQUESTS + REQUESTS)


def test_rules_for_l2_allowed_hosts_are_placed_in_basic_first():
    basic, second, _ = split_rules(FULL, basic_cap=4, second_cap=100,
                                   protected_hosts={"ima.example"})
    assert FULL[5] in basic and FULL[5] not in second


def test_build_outputs_protects_l2_allowed_hosts_in_both_toggle_variants():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=8, second_cap=100, popunder=POPUNDER)
    for basic_name, second_name, single in (("basic-ads-sec", "second-ads-sec", FULL + SECURITY),
                                            ("basic-ads", "second-ads", FULL)):
        assert_same_as_separate_lists([out[basic_name], out[second_name] + POPUNDER], [single, POPUNDER],
                                      L2_REQUESTS + REQUESTS)



def test_build_outputs_fails_when_popunder_does_not_fit_behind_the_remainder():
    # アプリは 2 本目に「残り → ポップアップ対策 → 報告（予約 2,000）→ 一時オフ」と並べ、件数では切らない。
    # ポップアップ対策が伸び代（1,000）を超えて伸びたら、配信を止めて気づかせる（15 万件超えで 2 本目が壊れる）。
    # セキュリティは今の件数（2）ではなく予算（3）で数える＝週次で予算いっぱいまで増えても収まることを月次で確かめる
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=8, second_cap=100, popunder=POPUNDER)
    fits = max(len(out["second-ads-sec"]) - len(SECURITY) + 3, len(out["second-ads"])) + len(POPUNDER)
    build_outputs(FULL, SECURITY, security_budget=3, basic_cap=8, second_cap=100, popunder=POPUNDER,
                  second_total_cap=fits)
    with pytest.raises(SplitError):
        build_outputs(FULL, SECURITY, security_budget=3, basic_cap=8, second_cap=100, popunder=POPUNDER,
                      second_total_cap=fits - 1)

# ── 全量の重複（同じルールが複数のフィルタから来る。実データで 6.2 万件）──
# 同じルールが 2 つあるとき、後ろのコピーだけ残せば 1 本のリストとしての効き方は変わらない
# （前のコピーが効く場面では、その後ろに打ち消しが無い限り後ろのコピーも効く）。
# ❌ 前のコピーを残す（build_merged_rules.py のやり方）→ 重要ルールのコピーが消え、例外に打ち消される
FULL_DUP = FULL[:3] + [block("ima.example"), block("ads.example")] + FULL[3:9] + [
    allow(r"^[^:]+://+([^:/]+\.)?ima\.example[/:]", ["*video.example"]),  # 例外 8 の重複
    block("ima.example"),                                 # 重要ルールとしての ima（例外の後ろ＝動画サイトでも止める）
] + FULL[9:]


def test_duplicates_are_removed_keeping_the_last_copy():
    basic, second, _ = split_rules(FULL_DUP, basic_cap=100, second_cap=100)
    keys = [repr(r) for r in basic]
    assert len(keys) == len(set(keys))
    assert len([r for r in basic if not is_exc(r)]) == len({repr(r) for r in FULL_DUP if not is_exc(r)})


@pytest.mark.parametrize("basic_cap", [5, 6, 7, 8, 9, 10, 11])
def test_dedup_keeps_the_single_list_behavior(basic_cap):
    basic, second, _ = split_rules(FULL_DUP, basic_cap=basic_cap, second_cap=100)
    for part in (basic, second):
        keys = [repr(r) for r in part]
        assert len(keys) == len(set(keys))
    assert_same_as_single_list([basic, second], FULL_DUP)
    # 重要ルールとしての ima が残っている＝動画サイトでも止まる（前のコピーを残すと通ってしまう）
    assert evaluate(FULL_DUP, "https://ima.example/x.js", "video.example")[0] is True


def test_a_rule_repeated_later_keeps_the_priority_of_its_first_copy():
    # 同じ遮断が前のフィルタ（日本語）と後ろのフィルタ（汎用）の両方にあると、重複除去で後ろのコピーが残る。
    # 基本保護に入れる優先順は前のコピーの位置で決める＝上限で切った今の 1 本に入っていたルールを落とさない
    # （9/27 計測: 後ろのコピーの位置で並べたら fluct・openx・Google の広告タグが 2 本目に回り、
    #   基本保護だけの人の漏れが今の 2 倍になった）
    full = [block("a.example"), block("dup.example"), block("b.example"), block("c.example"), block("dup.example")]
    basic, second, _ = split_rules(full, basic_cap=2, second_cap=100)
    assert block("dup.example") in basic and block("dup.example") not in second
    assert_same_as_single_list([basic, second], full,
                               [(f"https://{h}.example/x.js", "news.example") for h in ("a", "b", "c", "dup")])


def test_replace_security_tail_refuses_new_security_below_half_of_the_previous():
    # アプリは前回の半分未満の件数のファイルを捨てる（RuleUpdatePlanner.validateRuleCount）。配信側でも止めないと、
    # 元データが一時的に痩せた週に 2 本目（両方オン・約 1,200 万バイト）が毎回ダウンロードされては捨てられる
    old = [block(f"p{i}.example") for i in range(4)]
    out = build_outputs(FULL, old, security_budget=4, basic_cap=9, second_cap=100)
    replace_security_tail(out["second-ads-sec"], old_security=old, new_security=old[:2], security_budget=4)
    with pytest.raises(SplitError):
        replace_security_tail(out["second-ads-sec"], old_security=old, new_security=old[:1], security_budget=4)


# ── バイトの上限（2026-10-05）──
# 拡張はルールのファイルを丸ごとメモリに載せて Safari に渡す。A-88 で基本保護が 20.6MB → 27.6MB になり、
# 実機（iPhone 17 Pro・iOS 26.6.2）で拡張がメモリ上限で強制終了（jetsam per-process-limit）＝広告ブロックが
# 全く入らなかった。件数の上限（15 万）とは別に、1 本のバイト数にも上限を持つ。
# シミュレータには拡張のメモリ上限が無いので、ここで縛らないと見つけられない。
EXCEPTIONS = [r for r in FULL if is_exc(r)]
BIG = 10**9


def test_list_bytes_is_the_size_of_the_published_file(tmp_path):
    rules = FULL + [css(".広告-枠")]
    path = tmp_path / "x.json"
    _dump(rules, path)
    assert list_bytes(rules) == path.stat().st_size
    assert list_bytes([]) == 2


def test_basic_never_exceeds_its_byte_budget():
    for budget in range(list_bytes(EXCEPTIONS), list_bytes(FULL) + 1, 7):
        basic, second, dropped = split_rules(FULL, basic_cap=100, second_cap=100,
                                             basic_max_bytes=budget, second_max_bytes=BIG)
        assert list_bytes(basic) <= budget
        assert [r for r in basic if is_exc(r)] == EXCEPTIONS
        assert dropped == 0
        assert_same_as_single_list([basic, second], FULL)


def test_byte_budget_fills_basic_in_the_same_priority_order_as_the_count_cap():
    # 基本保護に入る順番は件数の上限と同じ（重要 → 遮断 → 汎用の要素隠し → サイト別の要素隠し）。
    # バイトの枠が「件数の上限で入るものちょうど」なら、入るものも同じ
    for cap in range(len(EXCEPTIONS), len(FULL)):
        by_count, _, _ = split_rules(FULL, basic_cap=cap, second_cap=100)
        by_bytes, _, _ = split_rules(FULL, basic_cap=100, second_cap=100,
                                     basic_max_bytes=list_bytes(by_count), second_max_bytes=BIG)
        assert by_bytes == by_count


def test_second_over_its_byte_budget_drops_from_the_end_of_the_priority_order():
    _, by_count, dropped_by_count = split_rules(FULL, basic_cap=6, second_cap=6)
    _, by_bytes, dropped_by_bytes = split_rules(FULL, basic_cap=6, second_cap=100,
                                                basic_max_bytes=BIG, second_max_bytes=list_bytes(by_count))
    assert by_bytes == by_count
    assert dropped_by_bytes == dropped_by_count > 0
    assert list_bytes(by_bytes) <= list_bytes(by_count)


def test_fails_when_the_exceptions_alone_exceed_a_byte_budget():
    with pytest.raises(SplitError):
        split_rules(FULL, basic_cap=100, second_cap=100,
                    basic_max_bytes=list_bytes(EXCEPTIONS) - 1, second_max_bytes=BIG)
    with pytest.raises(SplitError):
        split_rules(FULL, basic_cap=100, second_cap=100,
                    basic_max_bytes=BIG, second_max_bytes=list_bytes(EXCEPTIONS) - 1)


def test_build_outputs_keeps_what_the_extensions_hand_to_safari_within_the_byte_budget():
    # 2 本目はアプリが後ろにポップアップ対策を並べる。両方オンの 2 本目はセキュリティを予算いっぱいで数える
    # （週次は月次を通さずに末尾だけ入れ替える）
    security_max = list_bytes(SECURITY) + 40
    for limit in range(list_bytes(EXCEPTIONS) + security_max + list_bytes(POPUNDER),
                       list_bytes(FULL + SECURITY + POPUNDER) + 1, 11):
        out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=100, second_cap=100,
                            popunder=POPUNDER, list_max_bytes=limit, security_max_bytes=security_max)
        assert list_bytes(out["basic-ads"]) <= limit
        assert list_bytes(out["basic-ads-sec"]) <= limit
        assert list_bytes(out["second-ads"] + POPUNDER) <= limit
        second_ads_part = out["second-ads-sec"][:-len(SECURITY)]
        assert list_bytes(second_ads_part) + security_max + list_bytes(POPUNDER) <= limit + 2


def test_build_outputs_rejects_security_over_its_byte_budget():
    with pytest.raises(SplitError):
        build_outputs(FULL, SECURITY, security_budget=3, basic_cap=100, second_cap=100,
                      list_max_bytes=BIG, security_max_bytes=list_bytes(SECURITY) - 1)


def test_replace_security_tail_refuses_new_security_over_its_byte_budget():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    longer = [block("phish1-much-longer-name.example"), block("phish2-much-longer-name.example")]
    replace_security_tail(out["second-ads-sec"], old_security=SECURITY, new_security=longer,
                          security_budget=3, security_max_bytes=list_bytes(longer))
    with pytest.raises(SplitError):
        replace_security_tail(out["second-ads-sec"], old_security=SECURITY, new_security=longer,
                              security_budget=3, security_max_bytes=list_bytes(longer) - 1)


# アプリ（RuleUpdatePlanner.validateRuleCount）は、前回入れたファイルの半分未満の件数のファイルを
# 壊れたものとして捨てる。バイトの枠で件数が減ったときに半分を割ると、配っても誰にも入らない
# （今の 27.6MB を持ったまま＝広告ブロックが入らないまま）。配信前に同じ線で止める。
def test_check_not_shrunk_accepts_half_or_more_of_the_published_count():
    check_not_shrunk("merged-rules.json", old_count=148_800, new_count=74_400)
    check_not_shrunk("merged-rules.json", old_count=0, new_count=10)


def test_check_not_shrunk_refuses_below_half_of_the_published_count():
    with pytest.raises(SplitError):
        check_not_shrunk("merged-rules.json", old_count=148_800, new_count=74_399)


# アプリは 2 本目の後ろに、配信中のポップアップ対策のファイルを**そのままのバイト列で**繋ぐ（整形済み 7,981 バイト）。
# 詰め直した大きさ（5,163 バイト）で予約すると、その差だけ 2 本目が枠をはみ出す（Codex 指摘 2026-10-05）。
def test_build_outputs_reserves_the_popunder_file_as_published_not_as_recompacted():
    security_max = list_bytes(SECURITY) + 40
    popunder_file_bytes = list_bytes(POPUNDER) + 500   # 整形（改行・字下げ）の分だけ大きい
    for limit in range(list_bytes(EXCEPTIONS) + security_max + popunder_file_bytes,
                       list_bytes(FULL + SECURITY) + popunder_file_bytes + 1, 11):
        out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=100, second_cap=100,
                            popunder=POPUNDER, popunder_bytes=popunder_file_bytes,
                            list_max_bytes=limit, security_max_bytes=security_max)
        assert list_bytes(out["second-ads"]) + popunder_file_bytes - 1 <= limit
        second_ads_part = out["second-ads-sec"][:-len(SECURITY)]
        assert list_bytes(second_ads_part) + security_max + popunder_file_bytes <= limit + 2


# 週次の入れ替えは月次を通さない。手で直した等で前半が枠を超えていても、入れ替えた結果の大きさで止める。
def test_replace_security_tail_refuses_when_the_whole_list_exceeds_the_byte_budget():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    whole = list_bytes(out["second-ads-sec"])
    replace_security_tail(out["second-ads-sec"], old_security=SECURITY, new_security=SECURITY,
                          security_budget=3, list_max_bytes=whole)
    with pytest.raises(SplitError):
        replace_security_tail(out["second-ads-sec"], old_security=SECURITY, new_security=SECURITY,
                              security_budget=3, list_max_bytes=whole - 1)
