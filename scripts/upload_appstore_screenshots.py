"""App Store 用スクリーンショットを ASC へアップロードする（広告消し 4.4.3・ja のみ）。

サイズは 1290×2796（`APP_IPHONE_67`）。手順は現場カメラの同名スクリプトと同じ（POST → PUT → PATCH）。
`LOCALE` / `SHOTS` は提出前監査（`~/claude/tasks/scripts/audit_version_screenshots.py`）が読む宣言。
置き場 `tasks/screenshot-drafts-v440/final`（緑の電池を黒に直した物・A-162）。

    python3 scripts/upload_appstore_screenshots.py            # 実行
    python3 scripts/upload_appstore_screenshots.py --dry-run  # 何をするかだけ出す
"""
from __future__ import annotations

import hashlib
import sys
import time
from pathlib import Path

import jwt
import requests

KEY_ID = "8AQ38HX67R"
ISSUER_ID = "f75dec40-cdbc-4042-8faa-de413470def6"
KEY_PATH = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com"

APP_ID = "6774906945"  # 学習する広告消し
VERSION = "4.4.3"
LOCALE = "ja"
DISPLAY_TYPE = "APP_IPHONE_67"

ROOT = Path(__file__).resolve().parent.parent
# ★価格の語を焼き込まない（Guideline 2.3.7）。
SHOTS = [
    ROOT / "tasks/screenshot-drafts-v440/final/shot1-appwide.png",
    ROOT / "tasks/screenshot-drafts-v440/final/shot2-setup.png",
    ROOT / "tasks/screenshot-drafts-v440/final/shot3-beforeafter.png",
    ROOT / "tasks/screenshot-drafts-v440/final/shot4-home.png",
    ROOT / "tasks/screenshot-drafts-v440/final/shot5-report.png",
]
EXTRA_LOCALES: dict[str, list[Path]] = {}


def token() -> str:
    # ★`exp` は **20 分（1200 秒）以内**でなければならない。超えると Apple が 401 を返す
    #  （2026-08-12 に 1800 秒で書かれていて、このスクリプトは一度も成功していなかった）。
    return jwt.encode(
        {
            "iss": ISSUER_ID,
            "iat": int(time.time()),
            "exp": int(time.time()) + 1200,
            "aud": "appstoreconnect-v1",
        },
        KEY_PATH.read_text(),
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}


def json_of(response: requests.Response, what: str) -> dict:
    """★エラー本文を握り潰さない。`.json()["data"]` を直接書くと、401 や 409 が
    `KeyError: 'data'` になって**原因が消える**（2026-08-12 に踏んだ）。"""
    if response.status_code >= 300:
        raise SystemExit(f"{what} が失敗: HTTP {response.status_code}\n{response.text[:800]}")
    return response.json()


def version_localization_id(locale: str) -> str:
    versions = json_of(
        requests.get(
            f"{BASE}/v1/apps/{APP_ID}/appStoreVersions?limit=10", headers=headers(), timeout=60
        ),
        "バージョン一覧の取得",
    )["data"]
    # ★`limit=1` の先頭ではなく版番号で選ぶ（配信中の版を誤って触らない）
    target = [v for v in versions if v["attributes"]["versionString"] == VERSION]
    if not target:
        raise SystemExit(f"版 {VERSION} がまだ無い")
    version_id = target[0]["id"]
    locs = json_of(
        requests.get(
            f"{BASE}/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
            headers=headers(),
            timeout=60,
        ),
        "ローカライズ一覧の取得",
    )["data"]
    for loc in locs:
        if loc["attributes"]["locale"] == locale:
            return loc["id"]
    raise SystemExit(f"{locale} のローカライズが無い")


def screenshot_set(localization_id: str) -> str:
    sets = json_of(
        requests.get(
            f"{BASE}/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets",
            headers=headers(),
            timeout=60,
        ),
        "スクショセット一覧の取得",
    )["data"]
    for s in sets:
        if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return s["id"]
    created = requests.post(
        f"{BASE}/v1/appScreenshotSets",
        headers=headers(),
        json={
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
                    }
                },
            }
        },
        timeout=60,
    )
    if created.status_code not in (200, 201):
        raise SystemExit(f"セット作成に失敗 {created.status_code}: {created.text[:600]}")
    return created.json()["data"]["id"]


def clear(set_id: str) -> None:
    existing = json_of(
        requests.get(
            f"{BASE}/v1/appScreenshotSets/{set_id}/appScreenshots", headers=headers(), timeout=60
        ),
        "既存スクショの取得",
    )["data"]
    for item in existing:
        resp = requests.delete(
            f"{BASE}/v1/appScreenshots/{item['id']}", headers=headers(), timeout=60
        )
        print(f"既存 {item['id']} を削除: {resp.status_code}")


def upload(set_id: str, path: Path) -> None:
    blob = path.read_bytes()
    create = requests.post(
        f"{BASE}/v1/appScreenshots",
        headers=headers(),
        json={
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(blob)},
                "relationships": {
                    "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                },
            }
        },
        timeout=60,
    )
    if create.status_code not in (200, 201):
        raise SystemExit(f"POST 失敗 {create.status_code}: {create.text[:600]}")
    created = create.json()["data"]
    for op in created["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"] : op["offset"] + op["length"]]
        request_headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        put = requests.request(
            op["method"], op["url"], headers=request_headers, data=chunk, timeout=300
        )
        if put.status_code not in (200, 201, 204):
            raise SystemExit(f"PUT 失敗 {put.status_code}: {put.text[:400]}")

    commit = requests.patch(
        f"{BASE}/v1/appScreenshots/{created['id']}",
        headers=headers(),
        json={
            "data": {
                "type": "appScreenshots",
                "id": created["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }
        },
        timeout=60,
    )
    if commit.status_code != 200:
        raise SystemExit(f"PATCH 失敗 {commit.status_code}: {commit.text[:600]}")
    print(f"{path.name}: {commit.json()['data']['attributes'].get('assetDeliveryState')}")


def main() -> None:
    dry_run = "--dry-run" in sys.argv
    plan = {LOCALE: SHOTS, **EXTRA_LOCALES}
    only = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--locales=")), None)
    if only:
        wanted = only.split(",")
        unknown = [x for x in wanted if x not in plan]
        if unknown:
            raise SystemExit("宣言に無い言語: " + ", ".join(unknown))
        plan = {x: plan[x] for x in wanted}
    missing = [p for shots in plan.values() for p in shots if not p.is_file()]
    if missing:
        raise SystemExit("ファイルが無い: " + ", ".join(str(p) for p in missing))
    if dry_run:
        for locale, shots in plan.items():
            for p in shots:
                print(f"{locale}\t{p.name}\t{p.stat().st_size} bytes\t{hashlib.md5(p.read_bytes()).hexdigest()}")
        print(f"→ app {APP_ID} / 版 {VERSION} / {DISPLAY_TYPE} に上の順で入れる")
        return

    for locale, shots in plan.items():
        localization_id = version_localization_id(locale)
        set_id = screenshot_set(localization_id)
        print(f"[{locale}] localization={localization_id} set={set_id}")
        clear(set_id)
        for path in shots:
            upload(set_id, path)


if __name__ == "__main__":
    main()
