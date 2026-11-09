"""Tests for scripts/measure/security_list_report.py（A-218 G0 Task A4）"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "measure"))
from build_security_rules import JPTokens, convert_to_content_blocker_rules  # noqa: E402
from security_list_report import hosts_from_rules, load_hosts, matches, report, to_markdown  # noqa: E402

to_rules = convert_to_content_blocker_rules
NO_TOKENS = JPTokens((), (), ())


def test_report_separates_source_coverage_from_selection():
    r = report(old_rules=to_rules(["a.test"]), new_rules=to_rules(["a.test", "b.test"]),
               urlhaus_hosts=[], phishing_hosts=["a.test", "b.test"], tranco_ranked=["ok.test"],
               protected={"bank.test"}, jp_sample=["x.b.test", "b.test", "gone.test"], second_ads_sec=None)
    assert r["jp_sample"] == {"n": 3, "in_source": 2, "in_source_blockable": 2, "selected_old": 0, "selected_new": 2}


def test_report_jp_sample_in_source_excludes_matches_only_via_shared_hosts():
    # 見本のホストが「共有ホストその物」が元の一覧にあるだけで当たる時は、止められる形では入っていない
    r = report(old_rules=[], new_rules=to_rules(["b.test"]), urlhaus_hosts=[], phishing_hosts=["b.test", "s3.shared.test"],
               tranco_ranked=[], protected=set(), jp_sample=["x.b.test", "bucket.s3.shared.test", "s3.shared.test"],
               second_ads_sec=None, shared_parents={"s3.shared.test"})
    assert r["jp_sample"]["in_source"] == 3 and r["jp_sample"]["in_source_blockable"] == 1


def test_report_counts_false_blocks():
    r = report(old_rules=[], new_rules=to_rules(["ok.test", "bank.test"]), urlhaus_hosts=[], phishing_hosts=[],
               tranco_ranked=["www.ok.test"], protected={"bank.test"}, jp_sample=[], second_ads_sec=None)
    assert r["false_blocks_new"] == {"tranco_top10k": 1, "protected": 1}


def test_hosts_from_rules_round_trips():
    assert hosts_from_rules(convert_to_content_blocker_rules(["a-b.example.co.jp", "1.2.3.4"])) == ["a-b.example.co.jp", "1.2.3.4"]


def test_matches_is_same_or_under():
    assert matches("x.b.test", {"b.test"}) and matches("b.test", {"b.test"})
    assert not matches("b.test", {"x.b.test"}) and not matches("ab.test", {"b.test"})


def test_load_hosts_reads_rules_json_and_plain_text(tmp_path):
    j = tmp_path / "r.json"
    j.write_text('[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\\\.)?a\\\\.test[/:]"},"action":{"type":"block"}}]')
    t = tmp_path / "d.txt"
    t.write_text("# header\nA.test\n\nb.test.\n")
    assert load_hosts(j) == ["a.test"]
    assert load_hosts(t) == ["a.test", "b.test"]


def test_report_counts_shape_and_old_hosts_dropped_by_new_exclusions():
    old = to_rules(["1.2.3.4", "0abc.test", "bit.ly", "login.bank.test", "keep.test"])
    new = to_rules(["keep.test", "rakuten-x.test"])
    r = report(old_rules=old, new_rules=new, urlhaus_hosts=[], phishing_hosts=["keep.test", "rakuten-x.test", "bit.ly"],
               tranco_ranked=[], protected={"bank.test"}, jp_sample=[], second_ads_sec=None,
               shared_parents={"bit.ly"}, jp_tokens=JPTokens(("rakuten",), (), ()))
    assert r["counts"]["old"] == {"total": 5, "ipv4": 1, "digit_start": 2, "alpha_start": 3, "unreadable": 0}
    assert r["tiers_new"] == {"jp": 1, "urlhaus": 0, "brand": 0, "rest": 1}
    assert r["dropped_from_old"]["by_reason"] == {"shared-parent": 1, "protected": 1}
    assert r["old_not_in_source"] == 3   # 1.2.3.4 / 0abc.test / login.bank.test
    assert "| 件数 |" in to_markdown(r)


def test_report_checks_second_list_swap(tmp_path):
    old = to_rules(["a.test"])
    new = to_rules(["b.test", "c.test"])
    second = to_rules(["ad.test"]) + old
    r = report(old_rules=old, new_rules=new, urlhaus_hosts=[], phishing_hosts=[], tranco_ranked=[],
               protected=set(), jp_sample=[], second_ads_sec=second)
    assert r["size"]["second"]["ok"] is True and r["size"]["second"]["count"] == 3
    bad = report(old_rules=old, new_rules=new, urlhaus_hosts=[], phishing_hosts=[], tranco_ranked=[],
                 protected=set(), jp_sample=[], second_ads_sec=to_rules(["ad.test"]))
    assert bad["size"]["second"]["ok"] is False


def test_report_counts_rules_it_cannot_read():
    # 読めない形の規則（例: 全部の URL に当たる「.*」）を黙って落とすと、誤ブロック 0 の偽の合格になる
    bad = {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}}
    r = report(old_rules=to_rules(["a.test"]), new_rules=to_rules(["a.test"]) + [bad], urlhaus_hosts=[],
               phishing_hosts=["a.test"], tranco_ranked=[], protected=set(), jp_sample=[], second_ads_sec=None)
    assert r["counts"]["old"]["unreadable"] == 0
    assert r["counts"]["new"]["unreadable"] == 1
    assert "| 読めない規則 | 0 | 1 |" in to_markdown(r)


def test_report_counts_selected_hosts_under_popular_sites_public_jp_and_protected_tenants():
    # 「誤ブロック 0」は人気サイト・重要ドメインのトップが止まるかだけを見る。人気サイトの中の住所
    # （共有ホストの利用者を除く）・公的機関の .jp・重要ドメインの下の共有ホストの利用者を別に数えて見せる
    tranco = ["big.test", "pages.test"] + [f"f{i}.test" for i in range(20_000)] + ["mid.test"]
    r = report(old_rules=to_rules(["forms.big.test"]),
               new_rules=to_rules(["forms.big.test", "t.pages.test", "x.mid.test", "lab.u.ac.jp", "b.s3.bank.test"]),
               urlhaus_hosts=[], phishing_hosts=[], tranco_ranked=tranco, protected={"bank.test"}, jp_sample=[],
               second_ads_sec=None, shared_parents={"pages.test", "s3.bank.test"}, jp_tokens=NO_TOKENS)
    assert r["under_popular"]["old"] == {"top10k": 1, "top100k": 0, "top1m": 0}
    assert r["under_popular"]["new"] == {"top10k": 1, "top100k": 1, "top1m": 0}
    assert r["public_jp"] == {"old": 0, "new": 1}
    assert r["protected_tenants"] == {"old": 0, "new": 1}
    md = to_markdown(r)
    assert "| 人気サイトの中の住所: 1 万位まで | 1 | 1 |" in md
    assert "| 人気サイトの中の住所: 10 万位まで | 0 | 1 |" in md
    assert "| 公的機関・団体の .jp（go・lg・ac・ed・or） | 0 | 1 |" in md
    assert "| 重要ドメインの下の共有ホストの利用者 | 0 | 1 |" in md
    assert "| 人気サイトのトップが止まる: Tranco 上位 1 万 |" in md
