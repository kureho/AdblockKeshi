#!/usr/bin/env python3
"""Pro IAP（アプリ内広告ブロック）の審査用スクリーンショットを ASC にアップロード。

reserve → chunk PUT → commit（md5）の3段（ChariTabi パターン）。
既存があれば削除して差し替え。実行は Claude（IAP 作成が通ったので upload も可）。
"""
from __future__ import annotations
import os, sys, json, hashlib, urllib.request, urllib.error
from pathlib import Path

os.environ.setdefault("ASC_KEY_ID", "8AQ38HX67R")
sys.path.insert(0, os.path.expanduser("~/claude/MannerCamera4K/scripts"))
from asc_api import make_token  # noqa: E402

IAP_ID = "6791059609"
SCREENSHOT = Path(sys.argv[1] if len(sys.argv) > 1 else
                  "/tmp/claude-501/-Users-oharakureho-claude/4540ce4c-87f8-4802-b080-2aaab8d9a6ed/scratchpad/iap-review.png")


def req(method, path, body=None):
    tok = make_token()
    h = {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body else None
    r = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, headers=h, data=data, method=method)
    try:
        resp = urllib.request.urlopen(r)
        return resp.status, json.loads(resp.read() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "{}")


def md5_of(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if not SCREENSHOT.exists():
        sys.exit(f"screenshot not found: {SCREENSHOT}")
    size = SCREENSHOT.stat().st_size
    name = SCREENSHOT.name

    # 既存削除
    code, existing = req("GET", f"/v2/inAppPurchases/{IAP_ID}/appStoreReviewScreenshot")
    if code == 200 and existing.get("data"):
        eid = existing["data"]["id"]
        dc, _ = req("DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{eid}")
        print(f"既存スクショ削除 HTTP {dc}")

    # reserve
    code, r = req("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {"fileName": name, "fileSize": size},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": IAP_ID}}},
        }
    })
    if code not in (200, 201):
        sys.exit(f"❌ reserve 失敗 HTTP {code}: {json.dumps(r)[:400]}")
    sid = r["data"]["id"]
    ops = r["data"]["attributes"]["uploadOperations"]

    # chunk PUT
    with SCREENSHOT.open("rb") as f:
        for op in ops:
            f.seek(op["offset"])
            chunk = f.read(op["length"])
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            put = urllib.request.Request(op["url"], data=chunk, headers=headers, method=op["method"])
            try:
                urllib.request.urlopen(put)
            except urllib.error.HTTPError as e:
                sys.exit(f"❌ upload PUT 失敗 HTTP {e.code}: {e.read().decode()[:300]}")

    # commit
    code, r = req("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{sid}", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots", "id": sid,
            "attributes": {"uploaded": True, "sourceFileChecksum": md5_of(SCREENSHOT)},
        }
    })
    if code not in (200, 201):
        sys.exit(f"❌ commit 失敗 HTTP {code}: {json.dumps(r)[:400]}")
    print(f"✅ 審査スクショ アップロード完了（id={sid}・{size//1024}KB）")

    # IAP state 再確認
    code, r = req("GET", f"/v2/inAppPurchases/{IAP_ID}")
    print(f"IAP state: {r.get('data',{}).get('attributes',{}).get('state')}")


if __name__ == "__main__":
    main()
