import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_popunder_rules import parse_networks, network_rule


def test_parse_networks_ignores_comments_and_blanks():
    text = "! Title: x\n\n||popads.net^$script\n||jads.co^$script\n"
    assert parse_networks(text) == ["popads.net", "jads.co"]


def test_network_rule_shape_matches_shipped():
    r = network_rule("popads.net")
    assert r == {
        "trigger": {"url-filter": r"^[^:]+://+([^:/]+\.)?popads\.net[/:]", "resource-type": ["script"]},
        "action": {"type": "block"},
    }
