import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_popunder_rules import parse_networks, network_rule, aggressive_site_rules


def test_parse_networks_ignores_comments_and_blanks():
    text = "! Title: x\n\n||popads.net^$script\n||jads.co^$script\n"
    assert parse_networks(text) == ["popads.net", "jads.co"]


def test_network_rule_shape_matches_shipped():
    r = network_rule("popads.net")
    assert r == {
        "trigger": {"url-filter": r"^[^:]+://+([^:/]+\.)?popads\.net[/:]", "resource-type": ["script"]},
        "action": {"type": "block"},
    }


def test_aggressive_site_rules_order_and_shape():
    rules = aggressive_site_rules({"domain": "tokyomotion.net", "allow": ["fluidplayer.com", "googleapis.com"]})
    # index 0 = block 全third-party script, if-domain 限定
    assert rules[0]["action"] == {"type": "block"}
    assert rules[0]["trigger"]["url-filter"] == ".*"
    assert rules[0]["trigger"]["resource-type"] == ["script"]
    assert rules[0]["trigger"]["load-type"] == ["third-party"]
    assert rules[0]["trigger"]["if-domain"] == ["*tokyomotion.net"]
    # index 1,2 = allow（ignore-previous-rules）1 entry = 1 rule、block の後
    assert rules[1]["action"] == {"type": "ignore-previous-rules"}
    assert rules[1]["trigger"]["if-domain"] == ["*tokyomotion.net"]
    assert "fluidplayer" in rules[1]["trigger"]["url-filter"]
    assert rules[2]["action"] == {"type": "ignore-previous-rules"}
    assert "googleapis" in rules[2]["trigger"]["url-filter"]
    assert len(rules) == 3
