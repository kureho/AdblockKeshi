# [paid-approved-by-kureho] v4.0.2 metadata-only staging・ASC API・課金なし(DevProgram内)
"""広告消し v4.0.2（メタデータのみ・スクショ全5枚刷新）の ASC staging。

- binary は live 4.0.1 と同一 build 10001 を流用（コード変更なし）
- ja localization: description/keywords/URL/promotionalText は live 4.0.1 から copy、
  whatsNew のみ 4.0.2 用（掲載情報更新の正直表記）
- ja APP_IPHONE_67 の既存スクショ（新 version に複製された旧5枚）を削除し、
  tasks/screenshot-drafts-v402/final/ の新5枚をアップロード
- reviewNotes は「metadata-only・binary は live と同一」を明記

提出（reviewSubmission）は本スクリプトではやらない（precheck ログ後に別実行）。
実行: python3 scripts/stage_v402.py
"""
import hashlib
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
import requests  # noqa: E402
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"  # 広告消し
LIVE_VERSION_ID = "572520eb-3115-4bca-8791-5a4eb9f0e26a"  # 4.0.1 READY_FOR_SALE
LIVE_BUILD_ID = "3ad750a1-ef9c-441f-a9d2-0fa4e127564b"  # build 10001（live で配信中）
NEW_VERSION = "4.0.2"
DISPLAY_TYPE = "APP_IPHONE_67"
SHOTS_DIR = Path.home() / "claude/AdblockKeshi/tasks/screenshot-drafts-v402/final"
SHOT_FILES = [
    ("shot1-appwide.png", "01-appwide.png"),
    ("shot2-setup.png", "02-setup.png"),
    ("shot3-beforeafter.png", "03-before-after.png"),
    ("shot4-home.png", "04-home-blocking.png"),
    ("shot5-report.png", "05-report.png"),
]

WHATS_NEW = "App Store の掲載情報（スクリーンショット）を最新の機能に合わせて更新しました。アプリの機能に変更はありません。"

REVIEW_NOTES = """This is a metadata-only update (4.0.2): we refreshed the App Store screenshots so they reflect the current v4.x feature set (the previous screenshots described the old Safari-only behavior from v3). The binary is identical to the currently live version 4.0.1 (build 10001). No feature, IAP, price, or code changes.

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


def md5_of_file(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def upload_screenshot(asc: ASC, set_id: str, file_path: Path, file_name: str) -> str:
    file_size = file_path.stat().st_size
    r = asc.post(
        "/v1/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": file_name, "fileSize": file_size},
                "relationships": {
                    "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                },
            }
        },
    )
    screenshot_id = r["data"]["id"]
    data = file_path.read_bytes()
    for op in r["data"]["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        chunk = data[op["offset"] : op["offset"] + op["length"]]
        rr = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=120)
        if rr.status_code >= 400:
            raise RuntimeError(f"upload chunk failed: {rr.status_code} {rr.text[:200]}")
    asc.patch(
        f"/v1/appScreenshots/{screenshot_id}",
        {
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {"uploaded": True, "sourceFileChecksum": md5_of_file(file_path)},
            }
        },
    )
    print(f"  uploaded {file_name} ({file_size//1024}KB) -> {screenshot_id}")
    return screenshot_id


def main() -> None:
    assert "掲載情報" in WHATS_NEW
    for ng in NG_WORDS:
        assert ng not in WHATS_NEW, f"NG語: {ng}"
    for src, _ in SHOT_FILES:
        p = SHOTS_DIR / src
        assert p.exists(), f"missing: {p}"

    asc = ASC()

    print("=== 1. appStoreVersion 4.0.2 ===")
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
        print(f"[+] 4.0.2 作成: {target['id']}")
    else:
        print(f"[=] 4.0.2 既存: {target['id']} state={target['attributes']['appStoreState']}")
    vid = target["id"]

    print("=== 2. ja localization（live 4.0.1 copy + whatsNew） ===")
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
        "promotionalText": la["promotionalText"],
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
        ja_loc_id = r["data"]["id"]
        print(f"[+] ja loc 作成: {ja_loc_id}")
    else:
        ja_loc_id = new_ja["id"]
        asc.patch(
            f"/v1/appStoreVersionLocalizations/{ja_loc_id}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": ja_loc_id,
                    "attributes": loc_attrs,
                }
            },
        )
        print(f"[=] ja loc 更新: {ja_loc_id}")
    extra = [l["attributes"]["locale"] for l in new_locs["data"] if l["attributes"]["locale"] != "ja"]
    if extra:
        print(f"[!] 想定外 locale が存在: {extra} → 要確認")

    print("=== 3. build attach（live と同一 build 10001） ===")
    asc.patch(
        f"/v1/appStoreVersions/{vid}/relationships/build",
        {"data": {"type": "builds", "id": LIVE_BUILD_ID}},
    )
    b = asc.get(f"/v1/appStoreVersions/{vid}/build")
    attached = (b.get("data") or {}).get("id")
    assert attached == LIVE_BUILD_ID, f"build attach 不一致: {attached}"
    print(f"[+] attached build 10001: {attached}")

    print("=== 4. reviewNotes 更新 ===")
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

    print("=== 5. ja スクショ差し替え（APP_IPHONE_67・新 version 側のみ / live 無傷） ===")
    sets = asc.get(f"/v1/appStoreVersionLocalizations/{ja_loc_id}/appScreenshotSets")
    set_id = next(
        (s["id"] for s in sets["data"] if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE),
        None,
    )
    if set_id is None:
        r = asc.post(
            "/v1/appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {"type": "appStoreVersionLocalizations", "id": ja_loc_id}
                        }
                    },
                }
            },
        )
        set_id = r["data"]["id"]
        print(f"[+] set 作成: {set_id}")
    else:
        print(f"[=] set 既存: {set_id}")

    existing = asc.get(f"/v1/appScreenshotSets/{set_id}/appScreenshots", params={"limit": 20})
    for sc in existing.get("data", []):
        url = f"https://api.appstoreconnect.apple.com/v1/appScreenshots/{sc['id']}"
        rr = requests.delete(url, headers=asc._headers(), timeout=30)
        print(f"  deleted {sc['attributes'].get('fileName')} ({rr.status_code})")
        time.sleep(0.5)

    for src, dst in SHOT_FILES:
        upload_screenshot(asc, set_id, SHOTS_DIR / src, dst)
        time.sleep(1.0)

    final = asc.get(f"/v1/appScreenshotSets/{set_id}/appScreenshots", params={"limit": 20})
    print(f"\n[verify] set 内スクショ {len(final['data'])}枚:")
    for sc in final["data"]:
        a = sc["attributes"]
        print(f"  - {a.get('fileName')} state={(a.get('assetDeliveryState') or {}).get('state')}")

    print(f"\n[done] VERSION_ID={vid} JA_LOC_ID={ja_loc_id} SET_ID={set_id}")


if __name__ == "__main__":
    main()
