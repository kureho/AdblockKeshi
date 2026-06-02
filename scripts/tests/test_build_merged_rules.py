"""Tests for build_merged_rules.py"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from build_merged_rules import merge_rules  # noqa: E402


def test_merge_concatenates_unique_rules():
    ad = [{"trigger": {"url-filter": "ads\\.example\\.com"}, "action": {"type": "block"}}]
    sec = [{"trigger": {"url-filter": "phish\\.example\\.com"}, "action": {"type": "block"}}]
    merged = merge_rules(ad, sec)
    assert len(merged) == 2


def test_merge_dedupes_identical_rules():
    ad = [{"trigger": {"url-filter": "ads\\.example\\.com"}, "action": {"type": "block"}}]
    sec = [{"trigger": {"url-filter": "ads\\.example\\.com"}, "action": {"type": "block"}}]
    merged = merge_rules(ad, sec)
    assert len(merged) == 1


def test_merge_respects_limit_when_total_exceeds():
    ad = [{"trigger": {"url-filter": f"a{i}"}, "action": {"type": "block"}} for i in range(100)]
    sec = [{"trigger": {"url-filter": f"s{i}"}, "action": {"type": "block"}} for i in range(100)]
    merged = merge_rules(ad, sec, limit=150)
    assert len(merged) == 150


def test_merge_keeps_ad_priority():
    """ad が先に並ぶ → limit 到達時 security が打切られる"""
    ad = [{"trigger": {"url-filter": f"a{i}"}, "action": {"type": "block"}} for i in range(50)]
    sec = [{"trigger": {"url-filter": f"s{i}"}, "action": {"type": "block"}} for i in range(50)]
    merged = merge_rules(ad, sec, limit=60)
    assert len(merged) == 60
    # 最初の 50 件は ad rules であるべき
    for i in range(50):
        assert merged[i]["trigger"]["url-filter"] == f"a{i}"


def test_merge_empty_inputs():
    assert merge_rules([], []) == []
    assert merge_rules([{"trigger": {"url-filter": "x"}, "action": {"type": "block"}}], []) == [
        {"trigger": {"url-filter": "x"}, "action": {"type": "block"}}
    ]
