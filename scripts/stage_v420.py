# [paid-approved-by-kureho] v4.2.0 staging・ASC API・課金なし(DevProgram内)・2026-09-02 kureho「2 は提出しよう。今日してもいいかも」
"""広告消し v4.2.0 の ASC staging（version 作成 → ja localization → reviewNotes → build attach）。
提出（reviewSubmission）は本スクリプトではやらない（precheck ログ後に submit_app_version.py で別実行）。
実行: python3 scripts/stage_v420.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"
VERSION = "4.2.0"
BUILD_NUMBER = "10200"
META = Path(__file__).resolve().parent.parent / "fastlane/metadata/ja"
rd = lambda n: (META / n).read_text().strip()
WHATS_NEW = rd("release_notes.txt")
DESCRIPTION = rd("description.txt")
KEYWORDS = rd("keywords.txt")
PROMO = rd("promotional_text.txt")
MARKETING_URL = rd("marketing_url.txt")
SUPPORT_URL = rd("support_url.txt")

REVIEW_NOTES = """v4.2.0 の変更点は「壊れたサイトの報告」と「アプリ内広告ブロックの一時停止」の 2 点です。

1. 報告の種別を追加しました。従来の「広告が消えない」に加えて「サイトが壊れた（表示が崩れた）」を選んで報告できます。報告はサーバ側で集約・検証したうえでフィルタへ反映され、端末のブロックリストを直接書き換えることはありません（v4.1.0 と同じ経路）。

2. 「サイトが壊れた」と報告したサイトに限り、そのサイトだけ Safari の広告ブロックを一時的にオフにできます（Content Blocker のルールに ignore-previous-rules を追加する方式）。常設の設定画面はなく、報告フローの中からのみ操作できます。

3. アプリ内広告ブロック（既存のアプリ内課金「アプリ内広告ブロック」・非消耗型）を 15 分または 1 時間だけ一時停止できるようになりました。時間が来ると自動で再開します。課金内容・価格に変更はありません。

4. 上記のほか、レビュー依頼の表示条件の調整と、説明文の記述の見直し（外部通信の説明を実装どおりに修正）を行っています。

動作確認の手順:

・「報告」タブを開き、任意の URL（例: https://example.com）を入力し、種別で「サイトが壊れた」を選んで送信すると、送信完了の表示とともに「このサイトだけブロックをオフにする」の選択肢が表示されます。アカウント登録は不要です。

・アプリ内広告ブロックを購入済みの状態で、ホーム画面の「一時停止」から 15 分 / 1 時間を選ぶと、DNS フィルタが停止し、時間経過後に自動で再開します。未購入の状態でも、報告機能を含む他の機能はすべてご利用いただけます。

・Safari の保護を試す場合は、アプリ内の案内に従って 設定 > アプリ > Safari > 機能拡張 から「広告消し」を有効にしてください。"""

NG_WORDS = ("¥", "円", "無料", "Free", "割引", "セール")


def assert_clean(text, label):
    for w in NG_WORDS:
        assert w not in text, f"{label} に価格語: {w}"


def main():
    assert_clean(WHATS_NEW, "whatsNew"); assert_clean(KEYWORDS, "keywords"); assert_clean(PROMO, "promotionalText")
    assert len(KEYWORDS) <= 100 and len(PROMO) <= 170 and len(WHATS_NEW) <= 4000
    asc = ASC()
    vs = asc.get(f"/v1/apps/{APP_ID}/appStoreVersions", params={"limit": 10, "filter[platform]": "IOS"})
    v = next((x for x in vs["data"] if x["attributes"]["versionString"] == VERSION), None)
    if v and v["attributes"]["appStoreState"] not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
        print(f"[!] v{VERSION} は編集不可 state={v['attributes']['appStoreState']} → 中断"); return
    if not v:
        v = asc.post("/v1/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": VERSION},
                     "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
        print(f"[+] v{VERSION} 作成 id={v['id']}")
    else:
        print(f"[=] 既存 v{VERSION} id={v['id']} state={v['attributes']['appStoreState']}")
    vid = v["id"]
    locs = asc.get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", params={"limit": 50})
    ja = next((x for x in locs["data"] if x["attributes"]["locale"] == "ja"), None)
    if ja is None:
        ja = asc.post("/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": "ja"},
                      "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})["data"]
    asc.patch(f"/v1/appStoreVersionLocalizations/{ja['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": ja["id"],
              "attributes": {"whatsNew": WHATS_NEW, "description": DESCRIPTION, "keywords": KEYWORDS, "promotionalText": PROMO,
                             "marketingUrl": MARKETING_URL, "supportUrl": SUPPORT_URL}}})
    print(f"[ok] ja localization 設定 loc={ja['id']}")
    detail = asc.get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    did = detail["data"]["id"]
    asc.patch(f"/v1/appStoreReviewDetails/{did}", {"data": {"type": "appStoreReviewDetails", "id": did, "attributes": {"notes": REVIEW_NOTES}}})
    print(f"[ok] reviewNotes 更新 detail={did}")
    builds = asc.get("/v1/builds", params={"filter[app]": APP_ID, "filter[version]": BUILD_NUMBER, "limit": 5, "fields[builds]": "version,processingState"})
    bd = builds.get("data", [])
    if bd and bd[0]["attributes"].get("processingState") == "VALID":
        asc.patch(f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": bd[0]["id"]}})
        print(f"[ok] build {BUILD_NUMBER} (id={bd[0]['id']}) attach")
    else:
        print(f"[!] build {BUILD_NUMBER}: {bd[0]['attributes'] if bd else '未出現'} → attach スキップ（後で再実行）")
    print(f"[done] VERSION_ID={vid}")


if __name__ == "__main__":
    main()
