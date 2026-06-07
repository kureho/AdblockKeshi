#!/usr/bin/env python3
# [paid-approved-by-kureho] read-only audit (HTTP GET only), no POST to ASC API
"""Plan D Task 3.1: v3.0 提出時の 4 点監査 + AdblockKeshi 固有の拡張 audit.

既存 ~/claude/tasks/scripts/audit_4points.py の 4 観点 (state /
availability / price / IAP) に加えて、AdblockKeshi v3.0 固有の 6 観点を
追加する 10 点監査。**read-only**: ASC API は GET のみ、変更系 (POST/PATCH/
DELETE) は一切行わない。

観点:
  ① 審査ステータス: 該当バージョンの appStoreState
  ② availability: appAvailabilityV2 + territoryAvailabilities
  ③ price: appPriceSchedule + manualPrices
  ④ IAP: inAppPurchasesV2 (本アプリは IAP なし、確認のみ)
  ⑤ AppStoreVersion build attach: relationships/build の id
  ⑥ Privacy Policy URL canonical: kureho.app/privacy/adblock-keshi 厳密一致
  ⑦ 最新の Apple Review 状態 (reviewSubmissions GET): IN_REVIEW / COMPLETE
  ⑧ category: PRIMARY UTILITIES 継続
  ⑨ CDN feature-flags.json: 200 OK + valid JSON + 必須 key 存在
  ⑩ CDN version.json: reported セクション存在 (moat 表示前提)

Usage:
  python3 tasks/scripts/audit_v3_4points_plus.py
  python3 tasks/scripts/audit_v3_4points_plus.py --version 3.0.0
  python3 tasks/scripts/audit_v3_4points_plus.py --verbose

Exit codes:
  0 = 全観点 ✅
  1 = 1 つでも ⚠️
  2 = ASC auth / network エラー
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

# kureho 共用 ASC class を再利用
sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"
APP_NAME = "広告消し"
EXPECTED_PRIVACY_URL = "https://kureho.app/privacy/adblock-keshi"
EXPECTED_CATEGORY = "UTILITIES"
CDN_FEATURE_FLAGS_URL = (
    "https://kureho.github.io/AdblockKeshi/cdn/feature-flags.json"
)
CDN_VERSION_URL = "https://kureho.github.io/AdblockKeshi/cdn/version.json"


class AuditResult:
    """各観点の結果を貯めて exit code を決定する。"""

    def __init__(self) -> None:
        self.fail_count = 0
        self.results: list[tuple[str, bool, str]] = []

    def add(self, label: str, ok: bool, detail: str) -> None:
        self.results.append((label, ok, detail))
        if not ok:
            self.fail_count += 1

    def summary(self) -> int:
        print()
        print("=== summary ===")
        for label, ok, detail in self.results:
            mark = "✅" if ok else "⚠️"
            print(f"{mark} {label}: {detail}")
        print()
        if self.fail_count == 0:
            print("✅ 全 10 観点 pass。v3.0 提出 audit の枠組みでは「safe to ship」。")
            return 0
        print(f"⚠️ {self.fail_count} 観点が要対応。提出前に解決してください。")
        return 1


def audit_asc_review_state(asc: ASC, version_string: str, r: AuditResult) -> dict | None:
    """① 審査ステータス + 該当 version オブジェクトを返す (⑤ で再利用)。"""
    try:
        versions = asc.get(
            f"/v1/apps/{APP_ID}/appStoreVersions",
            params={"limit": 10},
        )
    except Exception as e:
        r.add("① 審査ステータス", False, f"ASC API error: {e}")
        return None

    target = None
    for v in versions.get("data", []):
        if v["attributes"].get("versionString") == version_string:
            target = v
            break
    if target is None:
        r.add(
            "① 審査ステータス",
            False,
            f"v{version_string} not found in latest 10 versions",
        )
        return None

    state = target["attributes"].get("appStoreState", "?")
    ok = state in {
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "PENDING_DEVELOPER_RELEASE",
        "READY_FOR_SALE",
        "PREPARE_FOR_SUBMISSION",  # 未投入段階も許容、⑦ で 投入状態を別途確認
    }
    r.add("① 審査ステータス", ok, f"state={state}")
    return target


def audit_availability(asc: ASC, r: AuditResult) -> None:
    """② appAvailabilityV2."""
    try:
        avail = asc.get(f"/v1/apps/{APP_ID}/appAvailabilityV2")
    except Exception as e:
        r.add("② availability", False, f"ASC API error: {e}")
        return
    attrs = avail.get("data", {}).get("attributes", {}) or {}
    avail_in_new = attrs.get("availableInNewTerritories")
    try:
        terr = asc.get(
            f"/v1/apps/{APP_ID}/appAvailabilityV2/relationships/territoryAvailabilities",
            params={"limit": 200},
        )
        terr_count = len(terr.get("data", []))
    except Exception:
        terr_count = -1
    ok = bool(avail_in_new) or (terr_count > 0)
    detail = (
        f"availableInNewTerritories={avail_in_new}, "
        f"territoryAvailabilities={terr_count}"
    )
    r.add("② availability", ok, detail)


def audit_price(asc: ASC, r: AuditResult) -> None:
    """③ price tier."""
    try:
        prices = asc.get(f"/v1/apps/{APP_ID}/appPriceSchedule")
        manual = asc.get(
            f"/v1/appPriceSchedules/{prices['data']['id']}/manualPrices",
            params={"limit": 5},
        )
        manual_count = len(manual.get("data", []))
        r.add(
            "③ price",
            manual_count > 0,
            f"manualPrices count={manual_count}",
        )
    except Exception as e:
        r.add("③ price", False, f"ASC API error: {e}")


def audit_iap(asc: ASC, r: AuditResult) -> None:
    """④ IAP availability. 本アプリは IAP なし想定なので「なし=OK」も pass。"""
    try:
        iaps = asc.get(f"/v1/apps/{APP_ID}/inAppPurchasesV2", params={"limit": 5})
    except Exception as e:
        r.add("④ IAP", False, f"ASC API error: {e}")
        return
    if not iaps.get("data"):
        r.add("④ IAP", True, "なし (買い切りアプリの想定通り)")
        return
    details = []
    for iap in iaps["data"]:
        iap_id = iap["id"]
        product_id = iap["attributes"].get("productId")
        state = iap["attributes"].get("state")
        try:
            iap_avail = asc.get(f"/v1/inAppPurchases/{iap_id}/iapPriceSchedule")
            has_price = bool(iap_avail.get("data"))
        except Exception:
            has_price = False
        details.append(
            f"{product_id}={state} price={'OK' if has_price else 'MISSING'}"
        )
    r.add("④ IAP", all("price=OK" in d for d in details), ", ".join(details))


def audit_build_attach(asc: ASC, version_id: str, r: AuditResult) -> None:
    """⑤ AppStoreVersion build attach."""
    try:
        rel = asc.get(f"/v1/appStoreVersions/{version_id}/relationships/build")
    except Exception as e:
        r.add("⑤ build attach", False, f"ASC API error: {e}")
        return
    data = rel.get("data")
    if isinstance(data, dict) and data.get("id"):
        r.add("⑤ build attach", True, f"build id={data['id']}")
    else:
        r.add("⑤ build attach", False, "未 attach")


def audit_privacy_url(asc: ASC, r: AuditResult) -> None:
    """⑥ Privacy Policy URL canonical.

    ASC の Privacy Policy URL は appInfo の attributes ではなく
    `/v1/appInfos/{id}/appInfoLocalizations` の各 locale attributes に格納。
    ja or ja-JP の privacyPolicyUrl を見る。
    """
    try:
        info = asc.get(f"/v1/apps/{APP_ID}/appInfos", params={"limit": 5})
    except Exception as e:
        r.add("⑥ Privacy URL", False, f"ASC API error: {e}")
        return
    # state は appStoreState ではなく state attribute
    editable = None
    for info_obj in info.get("data", []):
        st = info_obj.get("attributes", {}).get("state") or info_obj.get(
            "attributes", {}
        ).get("appStoreState")
        if st in {
            "PREPARE_FOR_SUBMISSION",
            "WAITING_FOR_REVIEW",
            "IN_REVIEW",
            "READY_FOR_DISTRIBUTION",
        }:
            editable = info_obj
            break
    target = editable or (info.get("data") or [None])[0]
    if target is None:
        r.add("⑥ Privacy URL", False, "appInfo not found")
        return
    try:
        locs = asc.get(
            f"/v1/appInfos/{target['id']}/appInfoLocalizations",
            params={"limit": 20},
        )
    except Exception as e:
        r.add("⑥ Privacy URL", False, f"appInfoLocalizations error: {e}")
        return
    ja_url = None
    locale_urls: dict[str, str | None] = {}
    for loc in locs.get("data", []):
        a = loc["attributes"]
        locale = a.get("locale")
        url = a.get("privacyPolicyUrl")
        locale_urls[locale] = url
        if locale in {"ja", "ja-JP"}:
            ja_url = url
    if ja_url is None:
        r.add(
            "⑥ Privacy URL",
            False,
            f"ja locale で privacyPolicyUrl 未設定: locales={list(locale_urls.keys())}",
        )
        return
    ok = ja_url == EXPECTED_PRIVACY_URL
    r.add(
        "⑥ Privacy URL",
        ok,
        f"ja got={ja_url!r} expected={EXPECTED_PRIVACY_URL!r}",
    )


def audit_review_state(asc: ASC, r: AuditResult) -> None:
    """⑦ 最新の Apple Review 状態 (read-only GET)."""
    # [paid-approved-by-kureho] read-only GET to ASC reviewSubmissions list
    try:
        # ASC API は /v1/reviewSubmissions では sort パラメータを受け付けない。
        # filter[app] + limit のみで取得し、createdDate でクライアント側ソート。
        subs = asc.get(
            f"/v1/reviewSubmissions",
            params={"filter[app]": APP_ID, "limit": 20},
        )
    except Exception as e:
        r.add("⑦ Apple Review state", False, f"ASC API error: {e}")
        return
    data = subs.get("data") or []
    if not data:
        r.add("⑦ Apple Review state", False, "未投入 (本 audit 実行が早すぎる可能性)")
        return
    def _ts(item):
        a = item.get("attributes", {})
        return a.get("createdDate") or a.get("submittedDate") or ""
    latest = sorted(data, key=_ts, reverse=True)[0]
    state = latest["attributes"].get("state")
    ok = state in {"IN_REVIEW", "COMPLETE", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW"}
    r.add("⑦ Apple Review state", ok, f"latest state={state} id={latest['id']}")


def audit_category(asc: ASC, r: AuditResult) -> None:
    """⑧ category: PRIMARY が UTILITIES か。"""
    try:
        info = asc.get(
            f"/v1/apps/{APP_ID}/appInfos",
            params={"limit": 5, "include": "primaryCategory"},
        )
    except Exception as e:
        r.add("⑧ category", False, f"ASC API error: {e}")
        return
    primary_id = None
    for info_obj in info.get("data", []):
        rel = info_obj.get("relationships", {}).get("primaryCategory", {})
        primary_id = (rel.get("data") or {}).get("id")
        if primary_id:
            break
    if not primary_id:
        r.add("⑧ category", False, "primaryCategory 未設定")
        return
    ok = primary_id.upper() == EXPECTED_CATEGORY
    r.add("⑧ category", ok, f"primary={primary_id}")


def audit_cdn_url(url: str, label: str, predicate, r: AuditResult) -> None:
    """⑨⑩ CDN URL GET + JSON predicate."""
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            if resp.status != 200:
                r.add(label, False, f"HTTP {resp.status}")
                return
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        r.add(label, False, f"HTTP {e.code}")
        return
    except (urllib.error.URLError, TimeoutError) as e:
        r.add(label, False, f"network error: {e}")
        return
    try:
        obj = json.loads(body)
    except json.JSONDecodeError:
        r.add(label, False, "invalid JSON")
        return
    ok, detail = predicate(obj)
    r.add(label, ok, detail)


def predicate_feature_flags(obj: dict) -> tuple[bool, str]:
    required = {"report_tab_enabled", "emergency_kill_switch", "version"}
    missing = required - set(obj.keys())
    if missing:
        return False, f"missing keys: {missing}"
    return True, f"keys ok, version={obj.get('version')}"


def predicate_version_reported(obj: dict) -> tuple[bool, str]:
    reported = obj.get("reported")
    if not isinstance(reported, dict):
        return False, "reported section absent"
    if "rule_count" not in reported or "added_last_month" not in reported:
        return False, f"reported missing keys: {reported}"
    return True, f"reported={reported}"


def main(version_string: str, verbose: bool) -> int:
    print(f"=== v3.0 audit ({APP_NAME} / {APP_ID} / v{version_string}) ===")
    r = AuditResult()
    try:
        asc = ASC()
    except Exception as e:
        print(f"❌ ASC auth failed: {e}", file=sys.stderr)
        return 2

    target = audit_asc_review_state(asc, version_string, r)
    audit_availability(asc, r)
    audit_price(asc, r)
    audit_iap(asc, r)
    if target is not None:
        audit_build_attach(asc, target["id"], r)
    else:
        r.add("⑤ build attach", False, "version 未検出のため skip")
    audit_privacy_url(asc, r)
    audit_review_state(asc, r)
    audit_category(asc, r)
    audit_cdn_url(
        CDN_FEATURE_FLAGS_URL, "⑨ CDN feature-flags.json", predicate_feature_flags, r
    )
    audit_cdn_url(
        CDN_VERSION_URL, "⑩ CDN version.json reported", predicate_version_reported, r
    )

    return r.summary()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--version",
        default="3.0.0",
        help="audit 対象の appStoreVersion (default: 3.0.0)",
    )
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()
    sys.exit(main(version_string=args.version, verbose=args.verbose))
