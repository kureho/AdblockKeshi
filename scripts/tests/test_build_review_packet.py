"""Tests for scripts/review/build_review_packet.py（A-88 週 1 回判定の束）"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "review"))
from build_review_packet import (  # noqa: E402
    ad_marked_hosts,
    packets_to_prune,
    page_url_for_measure,
    render_packet,
    results_draft,
    suggest_outcome,
    third_party_hosts,
)


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
