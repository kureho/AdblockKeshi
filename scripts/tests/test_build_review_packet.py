"""Tests for scripts/review/build_review_packet.py（A-88 週 1 回判定の束）"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "review"))
import datetime as dt  # noqa: E402

from build_review_packet import (  # noqa: E402
    ad_marked_hosts,
    is_scam_report,
    measure_targets,
    normalize_report_host,
    packets_to_prune,
    page_url_for_measure,
    rdap_candidates,
    rdap_registration_date,
    render_packet,
    results_draft,
    scam_facts,
    suggest_outcome,
    third_party_hosts,
)
from build_security_rules import JPTokens  # noqa: E402


# --- page_url_for_measure: 報告 URL を「開いてよい形」にする ---

def test_page_url_strips_query_and_fragment():
    # クエリには利用者のトークン・メール等が入りうる＝そのまま開かない
    assert page_url_for_measure("https://news.example.jp/a/b?token=abc&mail=x#top") == "https://news.example.jp/a/b"


def test_page_url_keeps_plain_https_path():
    assert page_url_for_measure("https://example.jp/") == "https://example.jp/"


def test_page_url_rejects_non_https():
    assert page_url_for_measure("http://example.jp/") is None
    assert page_url_for_measure("javascript:alert(1)") is None


def test_page_url_rejects_missing_or_blank():
    assert page_url_for_measure(None) is None
    assert page_url_for_measure("") is None


def test_page_url_rejects_host_less_url():
    assert page_url_for_measure("https:///path") is None


def test_page_url_accepts_scheme_less_legacy_url():
    # 旧版・集計済みの報告は「ホスト/パス」の形で保存されている（本番 D1 の 23 件中 15 件・9/27 実測）
    assert page_url_for_measure("thedigestweb.com/a/b?x=1#f") == "https://thedigestweb.com/a/b"
    assert page_url_for_measure("www.example.jp") == "https://www.example.jp/"


def test_page_url_rejects_scheme_less_non_host():
    assert page_url_for_measure("localhost/x") is None
    assert page_url_for_measure("not a url") is None


# --- third_party_hosts: 報告サイト以外の通信先 ---

def test_third_party_hosts_drops_site_and_subdomains():
    hosts = ["example.jp", "www.example.jp", "img.example.jp", "ads.adnet.com", "cdn.other.net"]
    assert third_party_hosts(hosts, "www.example.jp") == ["ads.adnet.com", "cdn.other.net"]


def test_third_party_hosts_does_not_treat_suffix_lookalike_as_first_party():
    # notexample.jp は example.jp のサブドメインではない
    assert third_party_hosts(["notexample.jp"], "example.jp") == ["notexample.jp"]


def test_third_party_hosts_sorted_and_unique():
    assert third_party_hosts(["b.net", "a.net", "b.net"], "example.jp") == ["a.net", "b.net"]


# --- ad_marked_hosts: 既知の広告網に当たる通信先 ---

def test_ad_marked_hosts_matches_host_or_parent_domain():
    ad_domains = {"doubleclick.net", "adnet.com"}
    hosts = ["securepubads.g.doubleclick.net", "adnet.com", "cdn.other.net"]
    assert ad_marked_hosts(hosts, ad_domains) == ["adnet.com", "securepubads.g.doubleclick.net"]


def test_ad_marked_hosts_does_not_match_suffix_lookalike():
    assert ad_marked_hosts(["notadnet.com"], {"adnet.com"}) == []


# --- suggest_outcome: 機械的に決まる結果だけ下書きする ---

def test_suggest_outcome_other_app_is_in_app_ad():
    assert suggest_outcome({"seen_in": "other_app"}) == "in_app_ad"


def test_suggest_outcome_safari_left_for_human():
    assert suggest_outcome({"seen_in": "safari"}) is None
    assert suggest_outcome({"seen_in": None}) is None


# --- results_draft: review/results/ に写す前の下書き ---

def test_results_draft_has_every_report_and_only_known_or_blank_outcomes():
    rows = [
        {"id": "11111111-1111-4111-8111-111111111111", "seen_in": "other_app"},
        {"id": "22222222-2222-4222-8222-222222222222", "seen_in": "safari"},
    ]
    draft = results_draft(rows, "2026-09-28")
    assert draft["reviewed_at"] == "2026-09-28"
    assert [r["report_id"] for r in draft["results"]] == [rows[0]["id"], rows[1]["id"]]
    assert draft["results"][0]["outcome"] == "in_app_ad"
    assert draft["results"][1]["outcome"] == ""


def test_results_draft_never_copies_url_or_memo():
    # 下書きは公開リポジトリの review/results/ に写す前提＝報告の中身を持たせない
    rows = [{"id": "11111111-1111-4111-8111-111111111111", "seen_in": "safari",
             "url": "https://example.jp/private?x=1", "memo": "個人のメモ", "domain": "example.jp"}]
    text = json.dumps(results_draft(rows, "2026-09-28"), ensure_ascii=False)
    assert "example.jp" not in text
    assert "個人のメモ" not in text


# --- render_packet: 判定用の束（手元専用） ---

def _row(**kw):
    base = {"id": "11111111-1111-4111-8111-111111111111", "domain": "example.jp",
            "url": "https://example.jp/a?x=1", "memo": "", "seen_in": "safari",
            "report_kind": "ad_not_blocked", "ad_type": "banner", "status": "pending",
            "created_at": 1790000000, "app_version": "4.3.0"}
    base.update(kw)
    return base


def test_render_packet_lists_count_and_each_report():
    rows = [_row(), _row(id="22222222-2222-4222-8222-222222222222", seen_in="other_app", url=None)]
    md = render_packet("2026-09-28", rows, measurements={}, candidates=[])
    assert "未判定 2 件" in md
    assert rows[0]["id"] in md and rows[1]["id"] in md
    assert "in_app_ad" in md


def test_render_packet_shows_leak_hosts_and_screenshot():
    rows = [_row()]
    m = {rows[0]["id"]: {"opened_url": "https://example.jp/a", "third_party": ["ads.adnet.com", "cdn.x.net"],
                         "ad_marked": ["ads.adnet.com"], "shot": "shots/01.png", "failed": False,
                         "fail_reason": ""}}
    md = render_packet("2026-09-28", rows, measurements=m, candidates=[])
    assert "ads.adnet.com" in md
    assert "shots/01.png" in md
    assert "https://example.jp/a" in md


def test_render_packet_marks_packet_as_local_only():
    md = render_packet("2026-09-28", [_row()], measurements={}, candidates=[])
    assert "公開リポジトリ" in md


def test_render_packet_lists_stalled_rule_candidates():
    cands = [{"id": "c1", "domain": "example.jp", "status": "kureho_queue", "rule_text": "{}",
              "unique_uuid_count": 1, "unique_ip_count": 1, "last_reported_at": 1790000000}]
    md = render_packet("2026-09-28", [], measurements={}, candidates=cands)
    assert "kureho_queue" in md and "c1" in md


def test_render_packet_empty_says_nothing_to_judge():
    md = render_packet("2026-09-28", [], measurements={}, candidates=[])
    assert "未判定 0 件" in md


# --- packets_to_prune: 古い束の掃除（日付名のフォルダだけ） ---

def test_packets_to_prune_keeps_newest_and_ignores_other_names(tmp_path):
    for name in ["2026-09-01", "2026-09-08", "2026-09-15", "2026-09-22", ".bin", "notes"]:
        (tmp_path / name).mkdir()
    (tmp_path / "status.json").write_text("{}")
    pruned = packets_to_prune(tmp_path, keep=2)
    assert sorted(p.name for p in pruned) == ["2026-09-01", "2026-09-08"]


def test_packets_to_prune_nothing_when_under_keep(tmp_path):
    (tmp_path / "2026-09-22").mkdir()
    assert packets_to_prune(tmp_path, keep=8) == []


# --- _wrangler_error: 失敗の理由を空にしない（2026-10-12） ---

def test_wrangler_error_reads_reason_from_stdout_json():
    # wrangler は --json のとき理由を stdout の JSON に出し、stderr は空（実測）。
    # stderr だけ見ていた頃は朝のレポートの失敗理由が毎回空だった。
    from types import SimpleNamespace
    import build_review_packet as b
    proc = SimpleNamespace(stderr="", stdout=json.dumps({"error": {
        "text": "A request to the Cloudflare API failed.",
        "notes": [{"text": "no such table: x: SQLITE_ERROR [code: 7500]"}]}}))
    assert b._wrangler_error(proc) == ("A request to the Cloudflare API failed. / "
                                       "no such table: x: SQLITE_ERROR [code: 7500]")


def test_wrangler_error_falls_back_to_stderr_then_stdout():
    from types import SimpleNamespace
    import build_review_packet as b
    assert b._wrangler_error(SimpleNamespace(stdout="", stderr="You are not logged in.")) == "You are not logged in."
    assert b._wrangler_error(SimpleNamespace(stdout="not json", stderr="")) == "not json"


# --- d1_select: ログインの自動更新の直後に 7403 で断られた 1 回だけ取り直す（2026-10-12） ---

def _fake_run(results):
    """subprocess.run の代わり。呼ばれるたびに results を先頭から 1 つずつ返す（例外なら投げる）。"""
    from types import SimpleNamespace
    calls = []

    def run(cmd, **kwargs):
        calls.append((cmd, kwargs))
        r = results[len(calls) - 1]
        if isinstance(r, BaseException):
            raise r
        code, stdout = r
        return SimpleNamespace(returncode=code, stdout=stdout, stderr="")
    return run, calls


def _refused(note: str) -> str:
    return json.dumps({"error": {"text": "A request to the Cloudflare API failed.", "notes": [{"text": note}]}})


_REFUSED_7403 = _refused("The given account is not valid or is not authorized to access this service [code: 7403]")


def test_d1_select_retries_once_after_refused_right_after_login_refresh(monkeypatch):
    # wrangler が 1 時間ごとのログイン更新をした回の問い合わせは約半分が 7403 で断られる
    # （wrangler の実行ログ 79 回の実測: 更新した 23 回のうち 12 回・更新しなかった回はゼロ）。
    import build_review_packet as b
    run, calls = _fake_run([(1, _REFUSED_7403), (0, json.dumps([{"results": [{"n": 3}]}]))])
    waits = []
    monkeypatch.setattr(b.subprocess, "run", run)
    monkeypatch.setattr(b.time, "sleep", waits.append)
    assert b.d1_select("SELECT 3 AS n") == [{"n": 3}]
    assert waits == [10]
    # 2 回とも本番（--remote）の同じ DB に同じ SQL を、同じ条件で流す
    for cmd, kwargs in calls:
        assert cmd == ["npx", "wrangler", "d1", "execute", "adblockkeshi-reports", "--remote", "--json",
                       "--command", "SELECT 3 AS n"]
        assert kwargs["cwd"] == b.WORKERS and kwargs["timeout"] == 120
    assert len(calls) == 2


def test_d1_select_retry_recognizes_code_field_only(monkeypatch):
    # 理由の文に [code: 7403] が無くても、error.code が 7403 なら取り直す
    import build_review_packet as b
    refused = json.dumps({"error": {"text": "A request to the Cloudflare API failed.", "code": 7403}})
    run, calls = _fake_run([(1, refused), (0, json.dumps([{"results": []}]))])
    monkeypatch.setattr(b.subprocess, "run", run)
    monkeypatch.setattr(b.time, "sleep", lambda s: None)
    assert b.d1_select("SELECT 1") == []
    assert len(calls) == 2


def test_d1_select_gives_up_after_second_failure_with_second_reason(monkeypatch):
    import pytest
    import build_review_packet as b
    run, calls = _fake_run([(1, _REFUSED_7403), (1, _refused("second failure [code: 7403]"))])
    monkeypatch.setattr(b.subprocess, "run", run)
    monkeypatch.setattr(b.time, "sleep", lambda s: None)
    with pytest.raises(RuntimeError, match=r"second failure \[code: 7403\]"):
        b.d1_select("SELECT 1")
    assert len(calls) == 2


def test_d1_select_does_not_retry_other_failures(monkeypatch):
    # 表が無い・SQL の誤りのような直らない失敗は待たずにすぐ止める（朝のレポートを待たせない）
    import pytest
    import build_review_packet as b
    run, calls = _fake_run([(1, _refused("no such table: reports: SQLITE_ERROR [code: 7500]"))])
    monkeypatch.setattr(b.subprocess, "run", run)
    monkeypatch.setattr(b.time, "sleep", lambda s: (_ for _ in ()).throw(AssertionError("待たない")))
    with pytest.raises(RuntimeError, match=r"code: 7500"):
        b.d1_select("SELECT 1")
    assert len(calls) == 1


def test_d1_select_does_not_retry_timeout(monkeypatch):
    # 120 秒のタイムアウトは取り直さずそのまま上げる（取り直すと最悪 4 分待たせる）
    import subprocess
    import pytest
    import build_review_packet as b
    run, calls = _fake_run([subprocess.TimeoutExpired(cmd="npx", timeout=120)])
    monkeypatch.setattr(b.subprocess, "run", run)
    monkeypatch.setattr(b.time, "sleep", lambda s: (_ for _ in ()).throw(AssertionError("待たない")))
    with pytest.raises(subprocess.TimeoutExpired):
        b.d1_select("SELECT 1")
    assert len(calls) == 1


def test_d1_select_does_not_retry_when_first_call_succeeds(monkeypatch):
    import build_review_packet as b
    run, calls = _fake_run([(0, json.dumps([{"results": []}]))])
    monkeypatch.setattr(b.subprocess, "run", run)
    monkeypatch.setattr(b.time, "sleep", lambda s: (_ for _ in ()).throw(AssertionError("待たない")))
    assert b.d1_select("SELECT 1") == []
    assert len(calls) == 1


# --- A-218 詐欺サイトの報告: ページを開かず、ドメインの事実だけを並べる ---

_SCAM_ID = "33333333-3333-4333-8333-333333333333"


def test_is_scam_report_only_phishing_type():
    assert is_scam_report(_row(ad_type="phishing"))
    assert not is_scam_report(_row(ad_type="popup"))
    assert not is_scam_report(_row(ad_type=None))


def test_measure_targets_never_opens_scam_reports_or_other_app():
    # 詐欺サイトのページを開くと、相手に見に来た事が伝わり、悪い仕掛けにも触れ得る（設計 §3-2）
    ad = _row()
    scam = _row(id=_SCAM_ID, ad_type="phishing", domain="evil.top", url="https://evil.top/login")
    in_app = _row(id="22222222-2222-4222-8222-222222222222", seen_in="other_app", url="https://x.jp/")
    targets = measure_targets([scam, ad, in_app], max_pages=30)
    assert [(r["id"], u) for r, u in targets] == [(ad["id"], "https://example.jp/a")]


def test_measure_targets_caps_pages():
    rows = [_row(id=f"{i:08d}-1111-4111-8111-111111111111", url=f"https://s{i}.example.jp/") for i in range(5)]
    assert len(measure_targets(rows, max_pages=2)) == 2


def test_normalize_report_host_lowercases_and_drops_port_and_trailing_dot():
    assert normalize_report_host("Login.Evil.TOP:8443") == "login.evil.top"
    assert normalize_report_host("evil.top.") == "evil.top"


def test_normalize_report_host_rejects_non_hosts():
    # 報告の値は外から来る＝RDAP の問い合わせの URL に入れる前に形を確かめる
    for bad in (None, "", "   ", "evil.top/../x", "evil.top?a=1", "localhost", "[::1]", "a" * 250 + ".top", "ev il.top"):
        assert normalize_report_host(bad) is None, bad


def test_rdap_candidates_go_up_from_two_labels():
    assert rdap_candidates("a.b.example.co.uk") == ["co.uk", "example.co.uk", "b.example.co.uk"]
    assert rdap_candidates("evil.top") == ["evil.top"]


def test_rdap_registration_date_reads_registration_event():
    payload = {"events": [{"eventAction": "last changed", "eventDate": "2026-11-01T00:00:00Z"},
                          {"eventAction": "registration", "eventDate": "2026-10-30T12:34:56Z"}]}
    assert rdap_registration_date(payload) == "2026-10-30"


def test_rdap_registration_date_none_when_missing_or_broken():
    assert rdap_registration_date({"events": [{"eventAction": "expiration", "eventDate": "2027-01-01"}]}) is None
    assert rdap_registration_date({}) is None
    assert rdap_registration_date({"events": "x"}) is None
    assert rdap_registration_date({"events": [{"eventAction": "registration", "eventDate": "yesterday"}]}) is None


_TOKENS = JPTokens(jp=("rakuten", "japan"), jp_token=("jp", "nta"), brand=("amazon", "paypal"))
_TODAY = dt.date(2026, 11, 9)


def _facts(domain, *, served=frozenset(), source=frozenset(), shared=frozenset(), dates=None, source_note=""):
    calls = []

    def lookup(d):
        calls.append(d)
        return (dates or {}).get(d)

    f = scam_facts(domain, served=None if served is None else set(served),
                   source=None if source is None else set(source), tokens=_TOKENS,
                   shared_parents=set(shared), lookup=lookup, today=_TODAY, source_note=source_note)
    return f, calls


def test_scam_facts_served_matches_host_or_parent():
    f, _ = _facts("login.evil.top", served={"evil.top"})
    assert f["served"] == "evil.top" and f["served_known"]
    f, _ = _facts("evil.top", served={"other.top", "notevil.top"})
    assert f["served"] is None and f["served_known"]


def test_scam_facts_served_unknown_when_list_missing():
    f, _ = _facts("evil.top", served=None)
    assert f["served"] is None and not f["served_known"]


def test_scam_facts_source_hit_miss_and_unknown():
    f, _ = _facts("a.evil.top", source={"evil.top"})
    assert f["source"] == "evil.top" and f["source_known"]
    f, _ = _facts("evil.top", source={"good.top"})
    assert f["source"] is None and f["source_known"]
    f, _ = _facts("evil.top", source=None, source_note="取得に失敗")
    assert f["source"] is None and not f["source_known"] and f["source_note"] == "取得に失敗"


def test_scam_facts_brand_words_whole_word_tokens_and_substrings():
    f, _ = _facts("amazon-security-check.top")
    assert f["brand_words"] == ["amazon"]
    f, _ = _facts("nta-tax.top")
    assert f["brand_words"] == ["nta"]
    f, _ = _facts("antana.top")  # 「nta」は語として一致した時だけ
    assert f["brand_words"] == []


def test_scam_facts_registration_date_within_90_days():
    f, calls = _facts("secure.amazon-verify.top", dates={"amazon-verify.top": "2026-10-30"})
    assert calls == ["amazon-verify.top"]
    assert f["registered"] == "2026-10-30" and f["registered_domain"] == "amazon-verify.top"
    assert f["age_days"] == 10


def test_scam_facts_registration_goes_up_until_found():
    f, calls = _facts("a.example.co.uk", dates={"example.co.uk": "2026-11-01"})
    assert calls == ["co.uk", "example.co.uk"]
    assert f["registered_domain"] == "example.co.uk" and f["age_days"] == 8


def test_scam_facts_registration_unknown_when_rdap_has_nothing():
    f, calls = _facts("evil.jp")
    assert calls == ["evil.jp"]
    assert f["registered"] is None and f["age_days"] is None and f["rdap_note"]


def test_scam_facts_under_shared_host_skips_rdap_and_brand_of_platform():
    # 共有ホストの登録日は場所の持ち主の物＝根拠にならない。場所の名前（amazonaws）はブランドの偽装ではない
    f, calls = _facts("paypal-login.s3.amazonaws.com", shared={"s3.amazonaws.com"})
    assert f["shared_parent"] == "s3.amazonaws.com"
    assert calls == []
    assert f["registered"] is None and "共有ホスト" in f["rdap_note"]
    assert f["brand_words"] == ["paypal"]


def test_scam_facts_ipv4_skips_rdap():
    f, calls = _facts("192.0.2.10")
    assert calls == [] and f["registered"] is None and f["brand_words"] == []


def test_scam_facts_invalid_domain_does_no_lookup():
    f, calls = _facts("evil.top/../x")
    assert f["host"] is None and f["invalid"] and calls == []


def test_render_packet_scam_report_shows_facts_and_never_measures():
    row = _row(id=_SCAM_ID, ad_type="phishing", domain="login.evil.top", url="https://login.evil.top/x")
    f, _ = _facts("login.evil.top", source={"evil.top"}, dates={"evil.top": "2026-10-30"})
    md = render_packet("2026-11-09", [row], measurements={}, candidates=[], scam={_SCAM_ID: f})
    assert "ページは開いていない" in md
    assert "配信中の 3 万件: なし" in md
    assert "HaGeZi の全部: **あり**（evil.top）" in md
    assert "2026-10-30" in md and "10 日前" in md
    assert "計測: なし" not in md


def test_render_packet_scam_report_already_served_says_not_to_add():
    row = _row(id=_SCAM_ID, ad_type="phishing", domain="evil.top")
    f, _ = _facts("evil.top", served={"evil.top"})
    md = render_packet("2026-11-09", [row], measurements={}, candidates=[], scam={_SCAM_ID: f})
    assert "配信中の 3 万件: **あり**（evil.top）" in md
    assert "足す話ではない" in md


def test_render_packet_scam_report_marks_unknowns():
    row = _row(id=_SCAM_ID, ad_type="phishing", domain="evil.top")
    f, _ = _facts("evil.top", served=None, source=None, source_note="取得に失敗")
    md = render_packet("2026-11-09", [row], measurements={}, candidates=[], scam={_SCAM_ID: f})
    assert "配信中の 3 万件: 未確認" in md
    assert "HaGeZi の全部: 未確認（取得に失敗）" in md
    assert "登録日（RDAP）: 未確認" in md


def test_render_packet_scam_report_without_facts_says_so():
    row = _row(id=_SCAM_ID, ad_type="phishing", domain="evil.top")
    md = render_packet("2026-11-09", [row], measurements={}, candidates=[])
    assert "ページは開いていない" in md
    assert "ドメインの事実: 取れなかった" in md
