import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pytest
from build_popunder_rules import (
    parse_networks,
    network_rule,
    aggressive_site_rules,
    build_rules,
    _domain_anchor,
)


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


def test_build_rules_orders_l1_then_l2():
    rules = build_rules(["popads.net"], [{"domain": "x.net", "allow": ["a.com"]}])
    assert rules[0]["trigger"]["url-filter"] == _domain_anchor("popads.net")  # L1 先
    assert rules[1]["trigger"]["url-filter"] == ".*"  # L2 block
    assert rules[2]["action"]["type"] == "ignore-previous-rules"
    assert len(rules) == 3


def test_build_rules_rejects_over_limit():
    with pytest.raises(ValueError):
        build_rules([f"d{i}.com" for i in range(50001)], [])


def test_streamtape_config_parses_block_then_allows():
    """Phase 2 で追加した streamtape L2 エントリが block→allow(gstatic,google) で生成される。"""
    rules = aggressive_site_rules({"domain": "streamtape.com", "allow": ["gstatic.com", "google.com"]})
    assert rules[0]["action"] == {"type": "block"}
    assert rules[0]["trigger"]["if-domain"] == ["*streamtape.com"]
    assert rules[1]["action"]["type"] == "ignore-previous-rules" and "gstatic" in rules[1]["trigger"]["url-filter"]
    assert rules[2]["action"]["type"] == "ignore-previous-rules" and "google" in rules[2]["trigger"]["url-filter"]
    assert len(rules) == 3


def test_parse_networks_dedups_duplicate_domains():
    text = "||popads.net^$script\n||popads.net^$script\n||jads.co^$script\n"
    assert parse_networks(text) == ["popads.net", "jads.co"]


def test_build_rules_rejects_invalid_network_domain():
    with pytest.raises(ValueError):
        build_rules(["not a domain"], [])


def test_build_rules_rejects_invalid_site_domain():
    with pytest.raises(ValueError):
        build_rules([], [{"domain": "bad domain", "allow": []}])


def test_build_rules_rejects_invalid_allow_domain():
    with pytest.raises(ValueError):
        build_rules([], [{"domain": "x.net", "allow": ["bad/allow"]}])


def test_allow_never_precedes_its_block():
    rules = build_rules([], [{"domain": "x.net", "allow": ["a.com", "b.com"]}])
    block_idx = next(i for i, r in enumerate(rules) if r["action"].get("type") == "block")
    allow_idxs = [i for i, r in enumerate(rules) if r["action"].get("type") == "ignore-previous-rules"]
    assert allow_idxs and all(block_idx < ai for ai in allow_idxs)


def test_output_is_deterministic():
    nets = ["popads.net", "jads.co"]
    sites = [{"domain": "x.net", "allow": ["a.com"]}]
    a = json.dumps(build_rules(nets, sites), ensure_ascii=False, indent=2)
    b = json.dumps(build_rules(nets, sites), ensure_ascii=False, indent=2)
    assert a == b


def test_bundle_and_cdn_outputs_identical_and_match_shipped(tmp_path):
    """同一入力から bundle/cdn を生成して byte 一致し、コミット済み bundle と SHA 一致（再生成漏れ検出）。"""
    import subprocess
    import hashlib

    repo = Path(__file__).resolve().parents[2]
    o1 = tmp_path / "a.json"
    o2 = tmp_path / "b.json"
    subprocess.run([
        sys.executable, str(repo / "scripts/build_popunder_rules.py"),
        "--networks", str(repo / "tasks/b-popunder-script/popunder-script-networks.txt"),
        "--sites", str(repo / "tasks/b-popunder-script/popunder-aggressive-sites.json"),
        "--out", str(o1), "--out", str(o2),
    ], check=True)
    assert o1.read_bytes() == o2.read_bytes(), "bundle と cdn の生成結果が不一致"
    shipped = (repo / "PopunderBlockerExtension/Resources/popunder-rules.json").read_bytes()
    cdn = (repo / "docs/cdn/popunder-rules.json").read_bytes()
    sha = lambda b: hashlib.sha256(b).hexdigest()
    assert sha(o1.read_bytes()) == sha(shipped), "コミット済み bundle が source から再生成した結果と不一致（再生成漏れ）"
    assert sha(shipped) == sha(cdn), "コミット済み bundle と cdn の SHA 不一致"


def test_l1_reproduces_shipped_rules():
    """新ジェネレータの L1 が出荷済み popunder-rules.json の block ルールと等価（v3.3.0追加分除く）。"""
    repo = Path(__file__).resolve().parents[2]
    shipped = json.loads((repo / "PopunderBlockerExtension/Resources/popunder-rules.json").read_text())
    networks = parse_networks((repo / "tasks/b-popunder-script/popunder-script-networks.txt").read_text())
    shipped_set = {json.dumps(r, sort_keys=True) for r in shipped}
    for d in networks:
        if d in ("jads.co", "glssp.net"):  # v3.3.0 で追加する分は出荷形に無い
            continue
        assert json.dumps(network_rule(d), sort_keys=True) in shipped_set, f"{d} の生成ルールが出荷形と不一致"
