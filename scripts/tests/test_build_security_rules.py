"""Tests for build_security_rules.py (Phishing.Database 切替版)"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from build_security_rules import (  # noqa: E402
    build_security_rules,
    convert_to_content_blocker_rules,
    load_tranco_set,
    parse_phishing_db_hosts,
    parse_urlhaus_hosts,
)

FIXTURES = Path(__file__).parent / "fixtures"


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
    assert all("url-filter" in r["trigger"] for r in rules)
    assert "malware\\-example\\-1\\.com" in rules[0]["trigger"]["url-filter"]


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
