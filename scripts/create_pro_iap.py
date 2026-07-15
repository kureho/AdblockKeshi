#!/usr/bin/env python3
"""広告消し v4.0 の Pro IAP（非消耗型・アプリ内広告ブロック ¥800）を ASC 上で作成。

- productId: com.kureho.adblockkeshi.pro（★コードと一致・変更不可）
- type: NON_CONSUMABLE
- 価格: ¥800（JPN price point 検索）
- ja/en localization 追加

★実行は kureho 権限（Claude の auto-mode 分類器が本番 ASC 書込をブロックするため）:
    ! python3 ~/claude/AdblockKeshi/scripts/create_pro_iap.py

idempotent（既存なら作成スキップ・不足分だけ追加）。
※ 版への「紐付け」と審査用スクショは初回IAPのため ASC Web UI で kureho が実施（MosaicBlur 教訓）。
"""
from __future__ import annotations
import os, sys, json, time, urllib.request, urllib.error
from urllib.parse import urlparse

os.environ.setdefault("ASC_KEY_ID", "8AQ38HX67R")  # Admin ロール
sys.path.insert(0, os.path.expanduser("~/claude/MannerCamera4K/scripts"))
from asc_api import make_token  # noqa: E402

APP_ID = "6774906945"          # 学習する広告消し
PRODUCT_ID = "com.kureho.adblockkeshi.pro"
REF_NAME = "アプリ内広告ブロック"
JA_NAME = "アプリ内広告ブロック"
JA_DESC = "他のアプリや Safari の広告を端末内の DNS で抑えます。ずっと買い切り。"
EN_NAME = "In-App Ad Blocking"
EN_DESC = "On-device DNS ad filter. One-time purchase."
REVIEW_NOTE = ("Non-consumable Pro unlock: an on-device local DNS content filter "
               "(NEPacketTunnelProvider) that reduces ads in other apps and Safari. "
               "All filtering is on-device; no account required.")
PRICE_JPY = 800


def req(method, path, body=None):
    tok = make_token()
    headers = {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body else None
    r = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, headers=headers, data=data, method=method)
    try:
        resp = urllib.request.urlopen(r)
        return resp.status, json.loads(resp.read() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "{}")


def find_iap():
    _, r = req("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2?filter[productId]={PRODUCT_ID}&limit=5")
    for d in r.get("data", []):
        if d["attributes"]["productId"] == PRODUCT_ID:
            return d["id"], d["attributes"].get("state")
    return None, None


def create_iap():
    code, r = req("POST", "/v2/inAppPurchases", {
        "data": {
            "type": "inAppPurchases",
            "attributes": {
                "name": REF_NAME, "productId": PRODUCT_ID,
                "inAppPurchaseType": "NON_CONSUMABLE", "reviewNote": REVIEW_NOTE,
            },
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
        }
    })
    if code not in (200, 201):
        print(f"  ❌ 作成失敗 HTTP {code}: {json.dumps(r)[:400]}"); sys.exit(1)
    return r["data"]["id"]


def existing_locales(iap_id):
    _, r = req("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")
    return {l["attributes"]["locale"] for l in r.get("data", [])}


def add_loc(iap_id, locale, name, desc):
    code, r = req("POST", "/v1/inAppPurchaseLocalizations", {
        "data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {"locale": locale, "name": name, "description": desc},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}},
        }
    })
    print(f"  {'✅' if code in (200,201) else '❌'} loc {locale} HTTP {code}" +
          ("" if code in (200,201) else f": {json.dumps(r)[:200]}"))


def find_price_point(iap_id, amount):
    path = f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=JPN&limit=200"
    while path:
        if path.startswith("http"):
            up = urlparse(path); path = up.path + ("?" + up.query if up.query else "")
        _, r = req("GET", path)
        for pp in r.get("data", []):
            try:
                if int(float(pp["attributes"].get("customerPrice", "0"))) == amount:
                    return pp["id"]
            except (TypeError, ValueError):
                continue
        path = r.get("links", {}).get("next")
    return None


def has_price(iap_id):
    code, r = req("GET", f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule")
    return code == 200 and bool(r.get("data"))


def set_price(iap_id, pp_id):
    code, r = req("POST", "/v1/inAppPurchasePriceSchedules", {
        "data": {
            "type": "inAppPurchasePriceSchedules", "attributes": {},
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p0}"}]},
                "baseTerritory": {"data": {"type": "territories", "id": "JPN"}},
            },
        },
        "included": [{
            "type": "inAppPurchasePrices", "id": "${p0}",
            "attributes": {"startDate": None},
            "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp_id}}},
        }],
    })
    print(f"  {'✅' if code in (200,201) else '❌'} 価格 ¥{PRICE_JPY} HTTP {code}" +
          ("" if code in (200,201) else f": {json.dumps(r)[:300]}"))


def main():
    iap_id, state = find_iap()
    if iap_id:
        print(f"既存 IAP: id={iap_id} state={state}")
    else:
        iap_id = create_iap()
        print(f"✅ IAP 作成: id={iap_id}  productId={PRODUCT_ID}")
    locs = existing_locales(iap_id)
    if "ja" not in locs: add_loc(iap_id, "ja", JA_NAME, JA_DESC)
    else: print("  ja loc 済")
    if "en-US" not in locs: add_loc(iap_id, "en-US", EN_NAME, EN_DESC)
    else: print("  en-US loc 済")
    if has_price(iap_id):
        print("  価格スケジュール 済")
    else:
        pp = find_price_point(iap_id, PRICE_JPY)
        if pp: set_price(iap_id, pp)
        else: print(f"  ⚠️ ¥{PRICE_JPY} price point 未検出 — Web UI で設定")
    print("\n次: ASC Web UI で ①この IAP を 4.0.0 版に紐付け ②審査用スクショ添付（初回IAPの必須手順）")


if __name__ == "__main__":
    main()
