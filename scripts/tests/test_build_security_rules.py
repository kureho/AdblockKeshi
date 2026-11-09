"""Tests for build_security_rules.py (Phishing.Database 切替版)"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import pytest  # noqa: E402

from build_security_rules import (  # noqa: E402
    DEFAULT_JP_TOKENS,
    DEFAULT_SHARED_PARENTS,
    URLHAUS_CAP,
    JPTokens,
    SourceTooSmall,
    build_parser,
    build_security_rules,
    check_rule_count,
    check_sources,
    convert_to_content_blocker_rules,
    jp_priority,
    load_jp_tokens,
    load_protected_domains,
    load_shared_parents,
    load_tranco_ranked,
    load_tranco_set,
    parse_phishing_db_hosts,
    parse_urlhaus_hosts,
    select_hosts,
    stable_key,
)
from build_split_rules import list_bytes  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"
ROOT = Path(__file__).resolve().parents[2]
NO_TOKENS = JPTokens((), (), ())


def test_parse_urlhaus_hosts_skips_comments_and_ips():
    hosts = parse_urlhaus_hosts((FIXTURES / "urlhaus-sample.txt").read_text())
    assert "malware-example-1.com" in hosts
    assert "google.com" in hosts
    assert "127.0.0.1" not in hosts
    assert "localhost" not in hosts


def test_parse_phishing_db_hosts_skips_comments():
    hosts = parse_phishing_db_hosts((FIXTURES / "phishing-db-sample.txt").read_text())
    assert "phish-example-1.tk" in hosts
    assert "phish-example-2.ml" in hosts
    assert "google.com" in hosts
    # コメント行 (# で始まる) は除外
    assert not any(h.startswith("#") for h in hosts)


def test_parse_phishing_db_hosts_skips_empty_lines():
    text = "phish.example\n\n   \nanother.example\n"
    hosts = parse_phishing_db_hosts(text)
    assert hosts == ["phish.example", "another.example"]


def test_load_tranco_set():
    tranco = load_tranco_set((FIXTURES / "tranco-sample.txt").read_text())
    assert "google.com" in tranco
    assert "example-tranco-top.com" in tranco


def test_convert_url_to_rule_format():
    rules = convert_to_content_blocker_rules(["malware-example-1.com", "phish-example-1.tk"])
    assert len(rules) == 2
    assert all(r["action"] == {"type": "block"} for r in rules)
    # 他の配信リスト（popunder-rules.json・変換器の出力）と同じ書き方
    assert rules[0]["trigger"]["url-filter"] == "^[^:]+://+([^:/]+\\.)?malware-example-1\\.com[/:]"


def test_convert_never_emits_disjunction():
    # WebKit のコンテンツブロッカーは「|」（どちらか）を解釈できず、1 本でもあると
    # リスト全体のコンパイルが失敗する（"Disjunctions are not supported yet"・2026-09-27 実測）
    rules = convert_to_content_blocker_rules(["a.example", "b-c.example"])
    assert all("|" not in r["trigger"]["url-filter"] for r in rules)


def test_convert_skips_hosts_with_unexpected_characters():
    # ホスト名に使えない文字が混ざった行は正規表現を壊しうるので入れない
    rules = convert_to_content_blocker_rules(["ok.example", "bad(host).example", "a|b.example", "sp ace.example"])
    assert [r["trigger"]["url-filter"] for r in rules] == ["^[^:]+://+([^:/]+\\.)?ok\\.example[/:]"]


def test_convert_dedupes():
    rules = convert_to_content_blocker_rules(
        ["malware.com", "MALWARE.COM", "malware.com"]
    )
    assert len(rules) == 1


def test_build_security_rules_excludes_tranco_hosts():
    urlhaus_text = (FIXTURES / "urlhaus-sample.txt").read_text()
    phishing_db_text = (FIXTURES / "phishing-db-sample.txt").read_text()
    tranco_text = (FIXTURES / "tranco-sample.txt").read_text()
    rules = build_security_rules(
        urlhaus_text, phishing_db_text, tranco_text, limit=30000
    )
    filters = [r["trigger"]["url-filter"] for r in rules]
    # Tranco に含まれるドメインは出力に出ない
    assert not any("google.com" in f.replace("\\", "") for f in filters)
    assert not any("example-tranco-top.com" in f.replace("\\", "") for f in filters)
    # 採用されるべきもの (URLhaus + Phishing.Database 両方)
    assert any("malware-example-1.com" in f.replace("\\", "") for f in filters)
    assert any("phish-example-1.tk" in f.replace("\\", "") for f in filters)


def test_build_security_rules_limits_count():
    urlhaus_text = "\n".join(f"127.0.0.1\tmalware-{i}.com" for i in range(500))
    phishing_db_text = ""
    tranco_text = ""
    rules = build_security_rules(
        urlhaus_text, phishing_db_text, tranco_text, limit=100
    )
    assert len(rules) <= 100


def test_build_security_rules_fills_limit_even_with_malformed_hosts():
    # 壊れた行を上限の後で捨てると件数が上限を割る＝壊れた行は上限を数える前に捨てる
    phishing_db_text = "%20bad.example\n40.70.42.104?rid=x\n" + "\n".join(f"phish-{i}.example" for i in range(10))
    rules = build_security_rules("", phishing_db_text, "", limit=5)
    hosts = {r["trigger"]["url-filter"] for r in rules}
    assert len(rules) == 5
    assert hosts <= {f"^[^:]+://+([^:/]+\\.)?phish-{i}\\.example[/:]" for i in range(10)}


def test_build_security_rules_drops_trailing_dot():
    rules = build_security_rules("", "phish.example.\n", "", limit=5)
    assert [r["trigger"]["url-filter"] for r in rules] == ["^[^:]+://+([^:/]+\\.)?phish\\.example[/:]"]


def test_build_security_rules_returns_empty_for_empty_input():
    rules = build_security_rules("", "", "", limit=30000)
    assert rules == []


def test_build_security_rules_combines_both_sources():
    urlhaus_text = "127.0.0.1\tmal1.com\n127.0.0.1\tmal2.com"
    phishing_db_text = "phish1.tk\nphish2.ml"
    tranco_text = ""
    rules = build_security_rules(
        urlhaus_text, phishing_db_text, tranco_text, limit=30000
    )
    assert len(rules) == 4
    joined = " ".join(r["trigger"]["url-filter"].replace("\\", "") for r in rules)
    for h in ["mal1.com", "mal2.com", "phish1.tk", "phish2.ml"]:
        assert h in joined


# --- A-218 G0 Task A2: 除外と下限の守り ---

def test_check_sources_rejects_truncated_tranco():
    with pytest.raises(SourceTooSmall):
        check_sources(tranco_count=1_000, phishing_count=392_178)


def test_check_sources_rejects_truncated_phishing_db():
    with pytest.raises(SourceTooSmall):
        check_sources(tranco_count=1_000_000, phishing_count=50_000)
    check_sources(tranco_count=1_000_000, phishing_count=392_178)  # 例外なし


def test_load_protected_domains_reads_set_literals_only():
    safari = load_protected_domains([ROOT / "Shared/CriticalDomainGuard.swift"])
    assert {"apple.com", "smbc.co.jp", "kureho.app"} <= safari
    assert "github.io" not in safari
    dns = load_protected_domains([ROOT / "Shared/CriticalDomainGuard.swift", ROOT / "Shared/DNS/DNSCriticalGuard.swift"])
    assert "github.io" in dns and len(safari) >= 50


def test_select_drops_shared_hosts_and_keeps_their_subdomains_on_safari():
    out = select_hosts([], ["github.io", "evil-login.github.io", "storage.googleapis.com", "lin.ee", "bit.ly", "x.weebly.com"],
                       [], protected=set(), shared_parents={"github.io", "storage.googleapis.com", "lin.ee", "bit.ly", "weebly.com"},
                       jp_tokens=NO_TOKENS, profile="safari", limit=100)
    assert sorted(out) == ["evil-login.github.io", "x.weebly.com"]


def test_select_never_blocks_a_tranco_domain_or_protected_domain():
    out = select_hosts([], ["example.com", "smbc.co.jp", "login.smbc.co.jp", "co.jp", "smbc-co-jp.evil.test"],
                       ["shop.example.com"], protected={"smbc.co.jp"}, shared_parents=set(),
                       jp_tokens=NO_TOKENS, profile="safari", limit=100)
    assert out == ["smbc-co-jp.evil.test"]


def test_dns_profile_is_stricter_than_safari():
    src = ["1.2.3.4", "hacked.popular.test", "evil.weebly.com", "evil-login.github.io"]
    kw = dict(protected={"github.io"}, shared_parents={"weebly.com", "github.io"}, jp_tokens=NO_TOKENS, limit=100)
    tranco = ["popular.test", "weebly.com"]
    assert sorted(select_hosts([], src, tranco, profile="dns", **kw)) == ["evil.weebly.com"]
    assert "hacked.popular.test" in select_hosts([], src, tranco, profile="safari", **kw)


def test_load_shared_parents_strips_inline_comments_and_keeps_wildcards(tmp_path):
    p = tmp_path / "shared.txt"
    p.write_text("# comment\ngithub.io   # PSL\n*.r.appspot.com\n\n  BIT.LY \n")
    assert load_shared_parents(p) == {"github.io", "*.r.appspot.com", "bit.ly"}


def test_select_treats_wildcard_parent_and_its_direct_children_as_shared():
    out = select_hosts([], ["r.appspot.com", "ey.r.appspot.com", "evil.ey.r.appspot.com"], [],
                       protected=set(), shared_parents={"*.r.appspot.com"},
                       jp_tokens=NO_TOKENS, profile="safari", limit=100)
    assert out == ["evil.ey.r.appspot.com"]


def test_default_shared_parents_cover_curated_and_psl_private_hosts():
    shared = set().union(*(load_shared_parents(p) for p in DEFAULT_SHARED_PARENTS))
    assert {"bit.ly", "lin.ee", "weebly.com", "s3.us-east-2.amazonaws.com", "*.r.appspot.com"} <= shared


def test_load_tranco_ranked_keeps_rank_order():
    assert load_tranco_ranked("2,b.com\n1,a.com\n\n3,C.com\n") == ["b.com", "a.com", "c.com"]


def test_cli_urlhaus_is_optional_and_other_args_unchanged():
    args = build_parser().parse_args(["--phishing-db", "p.txt", "--tranco", "t.csv", "--output", "o.json"])
    assert args.urlhaus is None and args.limit == 30000
    args = build_parser().parse_args(["--urlhaus", "u.txt", "--phishing-db", "p.txt", "--tranco", "t.csv",
                                      "--output", "o.json", "--limit", "30000"])
    assert str(args.urlhaus) == "u.txt"


# --- A-218 G0 Task A3: 並べ方（日本向けを優先・残りは偏らない順） ---

TOKENS = JPTokens(jp=("smbc", "rakuten"), jp_token=("nta", "au", "jp"), brand=("amazon",))


def test_jp_priority():
    assert jp_priority("smbc-card-login.test", TOKENS) == 0
    assert jp_priority("foo.co.jp", TOKENS) == 0
    assert jp_priority("au-pay-check.test", TOKENS) == 0
    assert jp_priority("amazon-verify.test", TOKENS) == 1
    assert jp_priority("santa-claus.test", TOKENS) == 2   # nta は語の完全一致だけ
    assert jp_priority("shop.com.au", TOKENS) == 2       # 最後のラベルは見ない
    assert jp_priority("random-site.test", TOKENS) == 2


def test_select_orders_jp_then_urlhaus_then_brand_then_rest():
    out = select_hosts(["mal.test"], ["zz.test", "amazon-x.test", "rakuten-x.test"], [],
                       protected=set(), shared_parents=set(), jp_tokens=TOKENS, profile="safari", limit=10)
    assert out == ["rakuten-x.test", "mal.test", "amazon-x.test", "zz.test"]


def test_select_remainder_follows_stable_hash_not_alphabet():
    src = [f"{c}{i}.test" for c in "0123456789abcdefghij" for i in range(50)]  # 名前順の 1,000 件
    out = select_hosts([], src, [], protected=set(), shared_parents=set(), jp_tokens=NO_TOKENS, profile="safari", limit=100)
    assert out == sorted(src, key=stable_key)[:100]


def test_select_is_independent_of_input_order():
    src = [f"h{i}.test" for i in range(300)]
    kw = dict(protected=set(), shared_parents=set(), jp_tokens=TOKENS, profile="safari", limit=50)
    assert select_hosts([], src, [], **kw) == select_hosts([], list(reversed(src)), [], **kw)


def test_urlhaus_tier_is_capped():
    out = select_hosts([f"m{i}.test" for i in range(30)], [f"p{i}.test" for i in range(30)], [],
                       protected=set(), shared_parents=set(), jp_tokens=NO_TOKENS, profile="safari", limit=40, urlhaus_cap=10)
    assert sum(h.startswith("m") for h in out) == 10
    assert URLHAUS_CAP == 10_000


def test_build_security_rules_output_format_unchanged_for_old_clients():
    rules = build_security_rules("", "\n".join(f"phish-{i}.example" for i in range(50)), "", limit=30)
    assert len(rules) == 30
    assert all(re.fullmatch(r"\^\[\^:\]\+://\+\(\[\^:/\]\+\\\.\)\?[a-z0-9_\\.-]+\[/:\]", r["trigger"]["url-filter"]) for r in rules)
    assert all(r["action"] == {"type": "block"} for r in rules)


def test_build_security_rules_stops_before_byte_cap_in_priority_order():
    src = "\n".join(f"phish-{i}.example" for i in range(10))
    full = build_security_rules("", src, "", limit=10)
    cap = list_bytes(full[:5])
    capped = build_security_rules("", src, "", limit=10, max_bytes=cap)
    assert capped == full[:5]


def test_load_jp_tokens_reads_three_kinds(tmp_path):
    p = tmp_path / "t.txt"
    p.write_text("# c\njp: rakuten aeon  # x\njp-token: jp nta\nbrand: amazon\n\n")
    assert load_jp_tokens(p) == JPTokens(jp=("rakuten", "aeon"), jp_token=("jp", "nta"), brand=("amazon",))
    default = load_jp_tokens(DEFAULT_JP_TOKENS)
    assert "rakuten" in default.jp and "nta" in default.jp_token and "amazon" in default.brand


def test_build_security_rules_skips_default_shared_and_protected_hosts():
    rules = build_security_rules("", "bit.ly\nlogin.smbc.co.jp\nok-phish.example\n", "", limit=10)
    assert [r["trigger"]["url-filter"] for r in rules] == ["^[^:]+://+([^:/]+\\.)?ok-phish\\.example[/:]"]


def test_check_rule_count_rejects_below_half_of_budget():
    with pytest.raises(SourceTooSmall):
        check_rule_count(14_999)
    check_rule_count(15_000)


def test_safari_keeps_tenants_of_shared_hosts_under_protected_domains():
    # 設計 §G0「共有ホストの親その物は入れない（その下の個別のサブドメインは入れてよい）」。
    # S3 の個別のバケットを止めても amazonaws.com は止まらない。DNS は計画どおり厳しく外す
    kw = dict(protected={"amazonaws.com", "smbc.co.jp"}, shared_parents={"s3.amazonaws.com"}, jp_tokens=NO_TOKENS, limit=100)
    src = ["evil-bucket.s3.amazonaws.com", "s3.amazonaws.com", "signin.amazonaws.com", "login.smbc.co.jp"]
    assert select_hosts([], src, [], profile="safari", **kw) == ["evil-bucket.s3.amazonaws.com"]
    assert select_hosts([], src, [], profile="dns", **kw) == []


def test_jp_priority_looks_only_left_of_a_shared_parent():
    # 共有ホストの下では、攻撃者が決めた部分（共有ホストより左）だけで語を見る。
    # 「amazonaws」は S3 の名前で、Amazon の偽装ではない
    shared = {"s3.amazonaws.com", "*.r.appspot.com"}
    assert jp_priority("xyz123.s3.amazonaws.com", TOKENS, shared) == 2
    assert jp_priority("amazon-verify.s3.amazonaws.com", TOKENS, shared) == 1
    assert jp_priority("rakuten-card.ey.r.appspot.com", TOKENS, shared) == 0
    assert jp_priority("amazon-verify.test", TOKENS, shared) == 1   # 共有ホストの下でなければ今まで通り


def test_select_does_not_promote_plain_s3_buckets_to_brand_tier():
    out = select_hosts([], ["aaa.s3.amazonaws.com", "zz.test"], [], protected={"amazonaws.com"},
                       shared_parents={"s3.amazonaws.com"}, jp_tokens=TOKENS, profile="safari", limit=10)
    assert out == sorted(["aaa.s3.amazonaws.com", "zz.test"], key=stable_key)   # 両方「その他」の段
