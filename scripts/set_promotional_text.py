"""広告消し ja の promotionalText を設定する（kureho 承認後に実行）。

- promotionalText は READY_FOR_SALE のままレビュー無しで即反映されるフィールド
- 2.3.7（価格表記禁止）/ 5.2.5（Apple 商標禁止）の NG 語チェックを assert で内蔵
- 文面の根拠: tasks/aso-improvement-2026-06-11.md §1

実行: python3 scripts/set_promotional_text.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC

APP_ID = "6774906945"  # 広告消し
PROMO = (
    "消えない広告は、報告するだけ。みんなの報告で進化する学習フィルタが、"
    "しつこい広告も詐欺・フィッシングサイトもまとめてブロック。"
    "標準フィルタ15万ルール同梱、自動更新。買い切り型・追跡なし。"
)

# Guideline 2.3.7 (価格) + 5.2.5 (Apple 商標) の NG 語チェック
NG_WORDS = ("¥", "円", "無料", "Free", "割引", "セール",
            "Safari", "iPhone", "iPad", "Apple", "iOS", "Siri")


def main() -> None:
    assert len(PROMO) <= 170, f"170字超過: {len(PROMO)}"
    for ng in NG_WORDS:
        assert ng not in PROMO, f"NG語が含まれている: {ng}"

    asc = ASC()
    vs = asc.get(
        f"/v1/apps/{APP_ID}/appStoreVersions",
        params={"filter[appStoreState]": "READY_FOR_SALE", "limit": 1},
    )
    version = vs["data"][0]
    locs = asc.get(
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
        params={"limit": 50},
    )
    ja = next(l for l in locs["data"] if l["attributes"]["locale"] == "ja")
    before = ja["attributes"].get("promotionalText")
    r = asc.patch(
        f"/v1/appStoreVersionLocalizations/{ja['id']}",
        {"data": {"type": "appStoreVersionLocalizations", "id": ja["id"],
                  "attributes": {"promotionalText": PROMO}}},
    )
    print(f"version: {version['attributes']['versionString']}")
    print(f"before: {before!r}")
    print(f"after : {r['data']['attributes']['promotionalText']!r}")


if __name__ == "__main__":
    main()
