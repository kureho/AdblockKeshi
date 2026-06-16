# [paid-approved-by-kureho] kureho承認済み・v3.2.0 サージカル提出準備（可逆ステップ）・ASC API・課金なし
"""広告消し v3.2.0 のサージカル提出準備（可逆ステップのみ）。

deliver の一括上書き（price_tier:4 で価格リセット + 全メタデータ上書き）を避けるため、
新 appStoreVersion を作成し、変更が要る ja の whatsNew / marketingUrl / supportUrl /
reviewNotes だけを設定する。価格・name・subtitle・keywords・description は前版コピーを尊重し触らない。

これらは PREPARE_FOR_SUBMISSION 中はすべて編集可能（= 可逆）。最終提出は別途。

実行: python3 scripts/submit_v320.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"  # 広告消し
VERSION = "3.2.0"

WHATS_NEW = (
    "報告した広告を、その端末ですぐにブロックへ反映できるようになりました。\n"
    "・気になる広告の URL を報告すると、あなたの端末で即座にブロック\n"
    "・報告は検証のうえ、ほかの利用者にも共有されます\n"
    "・決済・銀行など重要なサイトは、誤って報告してもブロックしない安全装置を追加\n"
    "使うほど、あなたの環境に広告ブロックが育っていきます。"
)
REVIEW_NOTES = (
    "本アプリは Safari コンテンツブロッカーです。設定 > Safari > 拡張機能"
    "（または設定 > アプリ > 広告消し）で「標準フィルタ」と「自己学習フィルタ」を ON にすると "
    "Safari の広告がブロックされます。adblock-tester.com で動作確認できます。\n"
    "v3.2.0: 「報告」タブで広告 URL を報告すると、その端末で即座にブロックへ反映されます。"
    "報告タブを使わない限り外部通信はありません。アプリ内課金（IAP）はありません。"
)
MARKETING_URL = "https://kureho.app/apps/adblock-keshi"
SUPPORT_URL = "https://kureho.app/contact?product=adblockkeshi"

# 価格表記 / Apple 商標の混入チェック（feedback_pricing_metadata_strict / 5.2.5）
NG = ("¥", "円", "無料", "Free", "割引", "セール", "iPhone", "iPad", "iOS", "Siri")


def main() -> None:
    for ng in NG:
        assert ng not in WHATS_NEW, f"whatsNew に NG 語: {ng}"
    asc = ASC()

    # 1) 既存の編集可能版があるか確認。無ければ v3.2.0 を作成。
    vs = asc.get(f"/v1/apps/{APP_ID}/appStoreVersions", params={"limit": 5})
    editable = next(
        (v for v in vs["data"]
         if v["attributes"]["appStoreState"] in
         ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")),
        None,
    )
    if editable and editable["attributes"]["versionString"] == VERSION:
        version = editable
        print(f"[=] 既存の編集可能版を使用: v{VERSION} id={version['id']} "
              f"state={version['attributes']['appStoreState']}")
    elif editable:
        version = editable
        print(f"[!] 編集可能版が v{editable['attributes']['versionString']} (!={VERSION})。"
              f"versionString を {VERSION} に更新する。")
        asc.patch(f"/v1/appStoreVersions/{version['id']}",
                  {"data": {"type": "appStoreVersions", "id": version["id"],
                            "attributes": {"versionString": VERSION}}})
    else:
        print(f"[+] v{VERSION} を新規作成する")
        created = asc.post("/v1/appStoreVersions", {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": VERSION},
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
            }
        })
        version = created["data"]
        print(f"    作成 id={version['id']}")

    vid = version["id"]

    # 2) ja localization を取得（無ければ作成）し whatsNew/URL を PATCH
    locs = asc.get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations",
                   params={"limit": 50})
    ja = next((x for x in locs["data"] if x["attributes"]["locale"] == "ja"), None)
    if ja is None:
        print("[+] ja localization を作成")
        ja = asc.post("/v1/appStoreVersionLocalizations", {
            "data": {"type": "appStoreVersionLocalizations",
                     "attributes": {"locale": "ja"},
                     "relationships": {"appStoreVersion":
                                       {"data": {"type": "appStoreVersions", "id": vid}}}}
        })["data"]
    ja_id = ja["id"]
    asc.patch(f"/v1/appStoreVersionLocalizations/{ja_id}", {
        "data": {"type": "appStoreVersionLocalizations", "id": ja_id,
                 "attributes": {"whatsNew": WHATS_NEW,
                                "marketingUrl": MARKETING_URL,
                                "supportUrl": SUPPORT_URL}}
    })
    print(f"[ok] ja whatsNew / marketingUrl / supportUrl 設定 (loc={ja_id})")

    # 3) reviewNotes（appStoreReviewDetail）。contactPhone は別スクリプトで法人化PATCH。
    try:
        detail = asc.get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
        did = detail["data"]["id"]
        asc.patch(f"/v1/appStoreReviewDetails/{did}", {
            "data": {"type": "appStoreReviewDetails", "id": did,
                     "attributes": {"notes": REVIEW_NOTES}}})
        print(f"[ok] reviewNotes 更新 (detail={did})")
    except Exception as e:
        print(f"[!] reviewDetail 取得/更新で例外（後続の contactPhone PATCH で作成される想定）: {str(e)[:120]}")

    print(f"\n[done] v{VERSION} version_id={vid} ja_loc={ja_id} -- 可逆ステップ完了。")
    print(f"VERSION_ID={vid}")


if __name__ == "__main__":
    main()
