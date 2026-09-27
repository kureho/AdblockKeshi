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
    build_outputs,
    l2_allowed_hosts,
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


def assert_same_as_single_list(parts: list[list[dict]], single: list[dict]) -> None:
    for url, page in REQUESTS:
        want = evaluate(single, url, page)
        got_blocked = False
        got_sel: set[str] = set()
        for p in parts:
            b, s = evaluate(p, url, page)
            got_blocked = got_blocked or b
            got_sel |= s
        assert (got_blocked, got_sel) == want, (url, page)


def test_every_exception_stays_in_both_lists_in_original_order():
    basic, second, _ = split_rules(FULL, security=[], basic_cap=7, second_cap=100)
    want = [r for r in FULL if is_exc(r)]
    assert [r for r in basic if is_exc(r)] == want
    assert [r for r in second if is_exc(r)] == want


def test_non_exception_rules_go_to_exactly_one_list():
    basic, second, dropped = split_rules(FULL, security=[], basic_cap=7, second_cap=100)
    assert dropped == 0
    non_exc = [r for r in FULL if not is_exc(r)]
    got = [r for r in basic if not is_exc(r)] + [r for r in second if not is_exc(r)]
    assert sorted(map(repr, got)) == sorted(map(repr, non_exc))


def test_both_lists_keep_the_single_list_order():
    basic, second, _ = split_rules(FULL, security=[], basic_cap=7, second_cap=100)
    pos = {repr(r): i for i, r in enumerate(FULL)}
    for part in (basic, second):
        idx = [pos[repr(r)] for r in part]
        assert idx == sorted(idx)


@pytest.mark.parametrize("basic_cap", [4, 5, 6, 7, 8, 9, 10, 11])
def test_two_lists_together_behave_like_one_uncapped_list(basic_cap):
    basic, second, _ = split_rules(FULL, security=[], basic_cap=basic_cap, second_cap=100)
    assert_same_as_single_list([basic, second], FULL)


@pytest.mark.parametrize("basic_cap", [6, 8, 13])
def test_security_goes_last_in_basic_and_is_never_undone_by_ad_exceptions(basic_cap):
    basic, second, _ = split_rules(FULL, security=SECURITY, basic_cap=basic_cap, second_cap=100)
    assert basic[-2:] == SECURITY
    assert_same_as_single_list([basic, second], FULL + SECURITY)


def test_basic_is_filled_important_first_then_in_list_order():
    # 例外 3 本 + 重要 1 本 + 先頭から 2 本（汎用・サイト別の要素隠し）
    basic, second, _ = split_rules(FULL, security=[], basic_cap=6, second_cap=100)
    non_exc = [r for r in basic if not is_exc(r)]
    assert non_exc == [FULL[0], FULL[2], FULL[9]]
    assert FULL[3] in second


def test_basic_never_exceeds_its_cap():
    for cap in range(5, 16):
        basic, _, _ = split_rules(FULL, security=SECURITY, basic_cap=cap, second_cap=100)
        assert len(basic) <= cap


def test_second_overflow_drops_plain_blocks_from_the_end_only():
    # 2 本目の上限を小さくすると、並びの最後の遮断（tail2 → tail1）から捨てる。例外と重要ルールは捨てない
    basic, second, dropped = split_rules(FULL, security=[], basic_cap=6, second_cap=6)
    assert dropped == 2
    assert len(second) == 6
    assert FULL[7] not in second and FULL[6] not in second
    assert [r for r in second if is_exc(r)] == [r for r in FULL if is_exc(r)]


def test_fails_when_exceptions_and_security_do_not_fit_in_basic():
    with pytest.raises(SplitError):
        split_rules(FULL, security=SECURITY, basic_cap=4, second_cap=100)


def test_fails_when_second_cannot_even_hold_the_exceptions():
    with pytest.raises(SplitError):
        split_rules(FULL, security=[], basic_cap=6, second_cap=2)


def test_build_outputs_makes_four_files_with_a_fixed_security_budget():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    assert set(out) == {"basic-ads-sec", "second-ads-sec", "basic-ads", "second-ads"}
    # セキュリティの枠は実際の件数（2）ではなく固定の 3 で確保する＝週ごとの件数で振り分けが揺れない
    sec_ads = [r for r in out["basic-ads-sec"] if not is_exc(r) and r not in SECURITY]
    assert len(sec_ads) == 9 - 3 - 3  # 上限 9 − 例外 3 − セキュリティ枠 3
    assert out["basic-ads-sec"][-2:] == SECURITY
    assert len(out["basic-ads"]) == 9
    assert_same_as_single_list([out["basic-ads-sec"], out["second-ads-sec"]], FULL + SECURITY)
    assert_same_as_single_list([out["basic-ads"], out["second-ads"]], FULL)


def test_build_outputs_rejects_security_over_budget():
    with pytest.raises(SplitError):
        build_outputs(FULL, SECURITY, security_budget=1, basic_cap=9, second_cap=100)


def test_replace_security_tail_swaps_only_the_security_part():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    new_sec = [block("phish3.example")]
    swapped = replace_security_tail(out["basic-ads-sec"], old_security=SECURITY, new_security=new_sec)
    assert swapped[:-1] == out["basic-ads-sec"][:-2]
    assert swapped[-1:] == new_sec


def test_replace_security_tail_refuses_when_tail_does_not_match():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    with pytest.raises(SplitError):
        replace_security_tail(out["basic-ads-sec"], old_security=[block("other.example")],
                              new_security=SECURITY)


def test_replace_security_tail_refuses_new_security_over_budget():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=9, second_cap=100)
    too_many = [block(f"p{i}.example") for i in range(4)]
    with pytest.raises(SplitError):
        replace_security_tail(out["basic-ads-sec"], old_security=SECURITY, new_security=too_many,
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
    basic, second, _ = split_rules(FULL, security=[], basic_cap=basic_cap, second_cap=100,
                                   protected_hosts=l2_allowed_hosts(POPUNDER))
    assert_same_as_separate_lists([basic, second + POPUNDER], [FULL, POPUNDER],
                                  L2_REQUESTS + REQUESTS)


def test_rules_for_l2_allowed_hosts_are_placed_in_basic_first():
    basic, second, _ = split_rules(FULL, security=[], basic_cap=4, second_cap=100,
                                   protected_hosts={"ima.example"})
    assert FULL[5] in basic and FULL[5] not in second


def test_build_outputs_protects_l2_allowed_hosts_in_both_toggle_variants():
    out = build_outputs(FULL, SECURITY, security_budget=3, basic_cap=8, second_cap=100, popunder=POPUNDER)
    for basic_name, second_name, single in (("basic-ads-sec", "second-ads-sec", FULL + SECURITY),
                                            ("basic-ads", "second-ads", FULL)):
        assert_same_as_separate_lists([out[basic_name], out[second_name] + POPUNDER], [single, POPUNDER],
                                      L2_REQUESTS + REQUESTS)


# ── 全量の重複（同じルールが複数のフィルタから来る。実データで 6.2 万件）──
# 同じルールが 2 つあるとき、後ろのコピーだけ残せば 1 本のリストとしての効き方は変わらない
# （前のコピーが効く場面では、その後ろに打ち消しが無い限り後ろのコピーも効く）。
# ❌ 前のコピーを残す（build_merged_rules.py のやり方）→ 重要ルールのコピーが消え、例外に打ち消される
FULL_DUP = FULL[:3] + [block("ima.example"), block("ads.example")] + FULL[3:9] + [
    allow(r"^[^:]+://+([^:/]+\.)?ima\.example[/:]", ["*video.example"]),  # 例外 8 の重複
    block("ima.example"),                                 # 重要ルールとしての ima（例外の後ろ＝動画サイトでも止める）
] + FULL[9:]


def test_duplicates_are_removed_keeping_the_last_copy():
    basic, second, _ = split_rules(FULL_DUP, security=[], basic_cap=100, second_cap=100)
    keys = [repr(r) for r in basic]
    assert len(keys) == len(set(keys))
    assert len([r for r in basic if not is_exc(r)]) == len({repr(r) for r in FULL_DUP if not is_exc(r)})


@pytest.mark.parametrize("basic_cap", [5, 6, 7, 8, 9, 10, 11])
def test_dedup_keeps_the_single_list_behavior(basic_cap):
    basic, second, _ = split_rules(FULL_DUP, security=[], basic_cap=basic_cap, second_cap=100)
    for part in (basic, second):
        keys = [repr(r) for r in part]
        assert len(keys) == len(set(keys))
    assert_same_as_single_list([basic, second], FULL_DUP)
    # 重要ルールとしての ima が残っている＝動画サイトでも止まる（前のコピーを残すと通ってしまう）
    assert evaluate(FULL_DUP, "https://ima.example/x.js", "video.example")[0] is True
