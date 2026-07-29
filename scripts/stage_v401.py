# [paid-approved-by-kureho] v4.0.1 hotfix staging・ASC API・課金なし(DevProgram内)
"""広告消し v4.0.1 hotfix の ASC staging。

1. build 10001 の processingState=VALID を待つ
2. appStoreVersion 4.0.1 作成（releaseType=AFTER_APPROVAL・hotfix は承認即配信）
3. ja localization: description/keywords/URL は live 4.0.0 から copy、
   whatsNew は 4.0.1 用、promotionalText は障害注意書き前のクリーン版に戻す
4. build attach
5. reviewNotes を 4.0.1 の実挙動（システム DNS 優先 + Cloudflare fallback）に更新

提出（reviewSubmission）は本スクリプトではやらない（precheck ログ後に別実行）。
実行: python3 scripts/stage_v401.py
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"  # 広告消し
LIVE_VERSION_ID = "6276f05a-abd9-4838-9d49-75699051b1d2"  # 4.0.0 READY_FOR_SALE
NEW_VERSION = "4.0.1"
BUILD_NUMBER = "10001"

WHATS_NEW = (
    "アプリ内広告ブロックの安定性を改善しました。\n"
    "・一部のモバイル回線（IPv6 専用網）で通信できない問題を修正\n"
    "・Wi-Fi とモバイル回線の切り替え直後の安定性を向上"
)

# 4.0.0 リリース時のクリーン版（fastlane/metadata/ja/promotional_text.txt）。
# live の障害注意書きは 4.0.1 配信と同時に不要になるため、新版でこの文言に戻す。
PROMO_CLEAN = (
    "他のアプリの広告も抑える「アプリ内広告ブロック」を追加（買い切りの追加機能）。\n"
    "Safari の広告・詐欺サイトブロックはそのまま、報告で進化するフィルタが対応。\n"
    "サブスクなし、閲覧履歴も送信しません。"
)

REVIEW_NOTES = """This is a bug-fix update (4.0.1) to the current live version 4.0.0. No feature, IAP, price, or metadata changes.

[Changes in v4.0.1]
- Fixes a connectivity failure of the "In-App Ad Blocking" feature on IPv6-only mobile carrier networks (NAT64/DNS64). The on-device DNS filter now forwards non-blocked queries to the DNS resolvers provided by the current network (system default), and falls back to a well-known public resolver (Cloudflare 1.1.1.1) only when the network's resolvers cannot be obtained. Previously it always used Cloudflare, which bypassed the carrier's DNS64 translation and broke name resolution on those networks. All DNS filtering still happens entirely on-device; no browsing data is sent to our servers.

[App overview]
- Free: Safari Content Blocker features (ad blocking + anti-phishing). No account is required.
- Non-consumable IAP "In-App Ad Blocking" (com.kureho.adblockkeshi.pro): a local on-device DNS content filter (NEPacketTunnelProvider) that reduces ads in other apps and Safari. There is no external VPN server.
- Customers who purchased the app while it was a paid download are automatically granted the Pro entitlement ("grandfathering"). This legacy grant is intentionally DISABLED in the review/sandbox environment so that the full purchase and restore flow is visible to the reviewer.

[How to test the IAP]
1. Open the app, tap "アプリ内広告ブロック" (In-App Ad Blocking).
2. On the paywall, tap the purchase button. (Restore is always available.)
3. After purchase, toggle it on. iOS will ask to allow a VPN configuration (this is the local on-device DNS tunnel - no external VPN server). Allow it.
4. Browse in another app or Safari; common ad domains are blocked.

Note: YouTube / X / Instagram / some games' in-app ads cannot be blocked by design (disclosed in the UI and description)."""

# Guideline 2.3.7 (価格) NG 語チェック（ja 表示テキストのみ対象）
NG_WORDS = ("¥", "円", "無料", "Free", "割引", "セール", "iPhone", "iPad", "Apple", "iOS", "Siri")


def wait_for_valid_build(asc: ASC) -> str:
    """build 10001 が VALID になるまで最大 40 分ポーリング。build id を返す。"""
    for i in range(80):
        res = asc.get(
            "/v1/builds",
            params={
                "filter[app]": APP_ID,
                "filter[version]": BUILD_NUMBER,
                "sort": "-uploadedDate",
                "limit": 3,
            },
        )
        for b in res.get("data", []):
            state = b["attributes"]["processingState"]
            print(f"  [{i}] build {b['attributes']['version']} state={state}", flush=True)
            if state == "VALID":
                return b["id"]
            if state in ("FAILED", "INVALID"):
                raise RuntimeError(f"build processing failed: {state}")
        time.sleep(30)
    raise TimeoutError("build 10001 が 40 分以内に VALID にならなかった")


def main() -> None:
    for text in (WHATS_NEW, PROMO_CLEAN):
        for ng in NG_WORDS:
            assert ng not in text, f"NG語: {ng} in {text[:30]}"

    asc = ASC()

    print("=== 1. build 10001 の VALID 待ち ===", flush=True)
    build_id = wait_for_valid_build(asc)
    print(f"[+] build VALID: {build_id}")

    print("=== 2. appStoreVersion 4.0.1 ===")
    vers = asc.get(f"/v1/apps/{APP_ID}/appStoreVersions", params={"limit": 5})
    target = next(
        (v for v in vers["data"] if v["attributes"]["versionString"] == NEW_VERSION), None
    )
    if target is None:
        created = asc.post(
            "/v1/appStoreVersions",
            {
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {
                        "platform": "IOS",
                        "versionString": NEW_VERSION,
                        "releaseType": "AFTER_APPROVAL",
                    },
                    "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
                }
            },
        )
        target = created["data"]
        print(f"[+] 4.0.1 作成: {target['id']}")
    else:
        print(f"[=] 4.0.1 既存: {target['id']} state={target['attributes']['appStoreState']}")
    vid = target["id"]

    print("=== 3. ja localization（live copy + whatsNew + promo クリーン版） ===")
    live_locs = asc.get(f"/v1/appStoreVersions/{LIVE_VERSION_ID}/appStoreVersionLocalizations")
    live_ja = next(l for l in live_locs["data"] if l["attributes"]["locale"] == "ja")
    la = live_ja["attributes"]

    new_locs = asc.get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    new_ja = next((l for l in new_locs["data"] if l["attributes"]["locale"] == "ja"), None)
    loc_attrs = {
        "description": la["description"],
        "keywords": la["keywords"],
        "supportUrl": la["supportUrl"],
        "marketingUrl": la["marketingUrl"],
        "promotionalText": PROMO_CLEAN,
        "whatsNew": WHATS_NEW,
    }
    if new_ja is None:
        r = asc.post(
            "/v1/appStoreVersionLocalizations",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": "ja", **loc_attrs},
                    "relationships": {
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}
                    },
                }
            },
        )
        print(f"[+] ja loc 作成: {r['data']['id']}")
    else:
        asc.patch(
            f"/v1/appStoreVersionLocalizations/{new_ja['id']}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": new_ja["id"],
                    "attributes": loc_attrs,
                }
            },
        )
        print(f"[=] ja loc 更新: {new_ja['id']}")
    # ja 以外の紛れ込み localization が無いか（batch 提出 409 の罠）
    extra = [l["attributes"]["locale"] for l in new_locs["data"] if l["attributes"]["locale"] != "ja"]
    if extra:
        print(f"[!] 想定外 locale が存在: {extra} → 要確認（削除 or metadata 充填）")

    print("=== 4. build attach ===")
    asc.patch(
        f"/v1/appStoreVersions/{vid}/relationships/build",
        {"data": {"type": "builds", "id": build_id}},
    )
    b = asc.get(f"/v1/appStoreVersions/{vid}/build")
    attached = b.get("data") or {}
    print(f"[+] attached build: {attached.get('id')} (= {build_id})")
    assert attached.get("id") == build_id, "build attach 不一致"

    print("=== 5. reviewNotes 更新 ===")
    rd = asc.get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    rd_data = rd.get("data")
    if rd_data is None:
        r = asc.post(
            "/v1/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": {"notes": REVIEW_NOTES},
                    "relationships": {
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}
                    },
                }
            },
        )
        print(f"[+] reviewDetail 作成: {r['data']['id']}")
    else:
        asc.patch(
            f"/v1/appStoreReviewDetails/{rd_data['id']}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": rd_data["id"],
                    "attributes": {"notes": REVIEW_NOTES},
                }
            },
        )
        print(f"[=] reviewDetail 更新: {rd_data['id']}")

    print(f"\n[done] VERSION_ID={vid} BUILD_ID={build_id}")


if __name__ == "__main__":
    main()
