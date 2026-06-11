"""広告消しの本体価格を ¥700 → ¥500 に変更する（kureho 承認済み 2026-06-11）。

根拠: 自社 Sales 実データで ¥500 期 = 2 件/月、¥700 期（v3.0 以降）= 0 件/月。
価格変更はレビュー不要・即時反映・いつでも再変更可能。
パターン: MannerCamera4K/scripts/change_app_price_to_free.py と同じ
POST /v1/appPriceSchedules（baseTerritory=JPN, startDate=None で即時適用）。

実行: python3 scripts/change_price_to_500.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC, BASE  # noqa: E402

APP_ID = "6774906945"  # 広告消し
TARGET_PRICE = "500"


def find_price_point(asc: ASC, customer_price: str) -> str | None:
    next_url = f"/v1/apps/{APP_ID}/appPricePoints?filter[territory]=JPN&limit=200"
    while next_url:
        resp = asc.get(next_url)
        for pp in resp.get("data", []):
            price = str(pp.get("attributes", {}).get("customerPrice", ""))
            if price in (customer_price, f"{customer_price}.0", f"{customer_price}.00"):
                return pp["id"]
        next_link = resp.get("links", {}).get("next")
        next_url = next_link.replace(BASE, "") if next_link else None
    return None


def show_current_price(asc: ASC) -> None:
    # appPriceSchedule の id は app id と同一
    resp = asc.get(
        f"/v1/appPriceSchedules/{APP_ID}/manualPrices",
        params={"include": "appPricePoint", "limit": 5},
    )
    for inc in resp.get("included", []):
        if inc["type"] == "appPricePoints":
            print(f"現在価格: ¥{inc['attributes'].get('customerPrice')}")


def main() -> None:
    asc = ASC()
    show_current_price(asc)
    pp_id = find_price_point(asc, TARGET_PRICE)
    if not pp_id:
        print(f"¥{TARGET_PRICE} の price point が見つからない", file=sys.stderr)
        sys.exit(1)
    body = {
        "data": {
            "type": "appPriceSchedules",
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${price-1}"}]},
                "baseTerritory": {"data": {"type": "territories", "id": "JPN"}},
            },
        },
        "included": [
            {
                "id": "${price-1}",
                "type": "appPrices",
                "attributes": {"startDate": None},
                "relationships": {
                    "appPricePoint": {"data": {"type": "appPricePoints", "id": pp_id}}
                },
            }
        ],
    }
    asc.post("/v1/appPriceSchedules", body)
    print("POST OK — 反映確認:")
    show_current_price(asc)


if __name__ == "__main__":
    main()
