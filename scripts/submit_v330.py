# [paid-approved-by-kureho] kureho「go していいよ」承認済み・v3.3.0 サージカル提出準備（可逆ステップ）・ASC API・課金なし
"""広告消し v3.3.0 のサージカル提出準備（可逆ステップのみ）。

deliver の一括上書き（price_tier リセット + 全メタデータ上書き）を避けるため、新 appStoreVersion を
作成し、変更が要る ja の whatsNew / marketingUrl / supportUrl / reviewNotes だけを設定する。
価格・name・subtitle・keywords・description は前版コピーを尊重し触らない。
PREPARE_FOR_SUBMISSION 中はすべて編集可能（= 可逆）。build attach と最終提出は別ステップ。

実行: python3 scripts/submit_v330.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"  # 広告消し
VERSION = "3.3.0"

WHATS_NEW = (
    "タップした瞬間に別タブや別ページへ飛ばす「ポップアップ広告（ポップアンダー）」への対策を強化しました。\n"
    "・広告が多いサイトでは、動画プレーヤーなどの正規機能は残したまま、飛ばし広告のスクリプトをまとめてブロックします。\n"
    "・新たな広告ネットワークをブロック対象に追加しました。\n"
    "・ポップアップ広告対策のブロックリストを、アプリの更新を待たずに最新化できる仕組みを追加しました。\n"
    "「ポップアップ広告対策」はメイン画面のトグルから個別にオン・オフできます。表示に支障が出た場合はオフにできます。"
)
# reviewNotes は v3.2.0（審査通過済み）の UI 表現をベースに v3.3.0 の変更を反映（feedback_review_notes_must_match_version）。
REVIEW_NOTES = (
    "本アプリは Safari コンテンツブロッカーです。設定 > Safari > 拡張機能"
    "（または設定 > アプリ > 広告消し）で「標準フィルタ」「自己学習フィルタ」「ポップアップ広告対策」を "
    "ON にすると Safari の広告がブロックされます。adblock-tester.com で動作確認できます。\n"
    "v3.3.0: 「ポップアップ広告対策」拡張（v3.2.0 で導入済み）のブロックルールを拡充しました。"
    "既知のポップアップ広告ネットワークのスクリプトを宣言型ルール（Safari Content Blocker JSON・bundle 同梱）で制限し、"
    "タップ時の不要な遷移を抑制します。広告が多いサイトでは、サイト自身の機能（動画プレーヤー等）を許可リストで残しつつ"
    "第三者の広告スクリプトを制限します。報告タブを使わない限り外部通信はありません。アプリ内課金（IAP）はありません。"
)
MARKETING_URL = "https://kureho.app/apps/adblock-keshi"
SUPPORT_URL = "https://kureho.app/contact?product=adblockkeshi"

# 価格表記 / Apple 商標の混入チェック（feedback_pricing_metadata_strict / 5.2.5）。whatsNew は公開メタデータ。
NG = ("¥", "円", "無料", "Free", "割引", "セール", "iPhone", "iPad", "iOS", "Siri")


def main() -> None:
    for ng in NG:
        assert ng not in WHATS_NEW, f"whatsNew に NG 語: {ng}"
    asc = ASC()

    # 1) 既存の編集可能版があるか確認。無ければ v3.3.0 を作成。
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
