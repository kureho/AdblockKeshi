"""広告消し ja promotionalText をモバイル回線障害の注意書きに差し替える（2026-07-29 kureho 承認済み）。

- 背景: v4.0.0「アプリ内広告ブロック」がモバイル回線（IPv6 単独 + NAT64/DNS64 網）で
  全通信断を起こす障害。4.0.1 hotfix 提出までの間の被害軽減として告知する
- promotionalText は READY_FOR_SALE のままレビュー無しで即反映される
- 2.3.7（価格表記禁止）NG 語チェックを assert で内蔵
  ※「Safari」は live 文面で既に使用実績あり（機能の事実記述）のため NG 対象外

実行: python3 scripts/set_promo_mobile_notice_v400.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC

APP_ID = "6774906945"  # 広告消し
PROMO = (
    "【お知らせ】モバイル回線では「アプリ内広告ブロック」が正しく動作しない場合があります。"
    "修正版を準備中です。\n"
    "Safari の広告・詐欺サイトブロックは通常どおり利用できます。"
    "サブスクなし、閲覧履歴も送信しません。"
)

# Guideline 2.3.7 (価格) + 5.2.5 (Apple 商標名の濫用) の NG 語チェック
NG_WORDS = ("¥", "円", "無料", "Free", "割引", "セール",
            "iPhone", "iPad", "Apple", "iOS", "Siri")


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
