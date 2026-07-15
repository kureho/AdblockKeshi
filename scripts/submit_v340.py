# [paid-approved-by-kureho] v3.4.0 提出準備（可逆ステップ）・ASC API・課金なし
"""広告消し v3.4.0 の提出準備（可逆ステップ）。

新 appStoreVersion v3.4.0 を作成し、ja の whatsNew/description/marketingUrl/supportUrl と reviewNotes を設定、
build 24(VALID 必須)を attach する。価格/name/subtitle/keywords は前版コピーを尊重し触らない。
whatsNew/description は提出 main と一致させるため fastlane/metadata/ja から読む。
PREPARE_FOR_SUBMISSION 中は可逆。最終 submit は do_review_submission_v340.py。
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"
VERSION = "3.4.0"
BUILD_NUMBER = "24"
MARKETING_URL = "https://kureho.app/apps/adblock-keshi"
SUPPORT_URL = "https://kureho.app/contact?product=adblockkeshi"

META = Path(__file__).resolve().parent.parent / "fastlane/metadata/ja"
WHATS_NEW = (META / "release_notes.txt").read_text(encoding="utf-8").strip()
DESCRIPTION = (META / "description.txt").read_text(encoding="utf-8").strip()

REVIEW_NOTES = (
    "本アプリは Safari コンテンツブロッカーです。確認手順:\n"
    "1. アプリを起動し、案内に従って iOS の「設定」から Safari の機能拡張（コンテンツブロッカー）を開きます。\n"
    "2. 「広告消し — 基本保護」「広告消し — 報告反映」「広告消し — 遷移保護」をすべてオンにします。\n"
    "3. Safari で一般的な Web ページを開くと広告がブロックされます（adblock-tester.com で動作確認できます）。\n"
    "4. アプリの「報告」タブから、広告が残るページの URL を送信できます。"
    "送信されるのは URL とメモのみで、閲覧履歴・氏名・連絡先・位置情報は送信しません。\n"
    "本バージョンの変更: 保護を「基本保護／報告反映／遷移保護」の 3 つに整理し表示名を統一しました。"
    "報告から反映する広告対策の安全性、ポップアップ（タブ乗っ取り）対策、誤ブロック防止、安定性を改善しています。"
    "アプリ内課金（IAP）はありません。"
)

# whatsNew は公開メタdata → 価格 + Apple 商標 NG。description は買い切り可だが ¥/無料/Free/割引/商標 は NG。
NG_PRICE = ("¥", "円", "無料", "Free", "割引", "セール")
NG_TM = ("iPhone", "iPad", "iOS", "Siri", "Mac")


def assert_clean(text, label, allow_kaikiri=False):
    for ng in NG_PRICE:
        assert ng not in text, f"{label} に価格NG語: {ng}"
    for ng in NG_TM:
        assert ng not in text, f"{label} に商標NG語: {ng}"


def main() -> None:
    assert_clean(WHATS_NEW, "whatsNew")
    assert_clean(DESCRIPTION, "description")
    # 旧名称の残存チェック
    for old in ("標準フィルタ", "学習フィルタ", "自己学習フィルタ", "ポップアップ広告対策", "強力ポップアップ"):
        assert old not in WHATS_NEW, f"whatsNew に旧名称: {old}"
        assert old not in DESCRIPTION, f"description に旧名称: {old}"
        assert old not in REVIEW_NOTES, f"reviewNotes に旧名称: {old}"

    asc = ASC()

    # 1) v3.4.0 を取得 or 作成
    vs = asc.get(f"/v1/apps/{APP_ID}/appStoreVersions", params={"limit": 10})
    v340 = next((v for v in vs["data"] if v["attributes"]["versionString"] == VERSION), None)
    if v340 and v340["attributes"]["appStoreState"] not in (
            "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
        print(f"[!] v{VERSION} は編集不可 state={v340['attributes']['appStoreState']} → 中断")
        return
    if v340:
        version = v340
        print(f"[=] 既存 v{VERSION} 使用 id={version['id']} state={version['attributes']['appStoreState']}")
    else:
        created = asc.post("/v1/appStoreVersions", {
            "data": {"type": "appStoreVersions",
                     "attributes": {"platform": "IOS", "versionString": VERSION},
                     "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
        version = created["data"]
        print(f"[+] v{VERSION} 作成 id={version['id']}")
    vid = version["id"]

    # 2) ja localization PATCH（whatsNew/description/urls）
    locs = asc.get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", params={"limit": 50})
    ja = next((x for x in locs["data"] if x["attributes"]["locale"] == "ja"), None)
    if ja is None:
        ja = asc.post("/v1/appStoreVersionLocalizations", {
            "data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": "ja"},
                     "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})["data"]
        print("[+] ja localization 作成")
    ja_id = ja["id"]
    asc.patch(f"/v1/appStoreVersionLocalizations/{ja_id}", {
        "data": {"type": "appStoreVersionLocalizations", "id": ja_id,
                 "attributes": {"whatsNew": WHATS_NEW, "description": DESCRIPTION,
                                "marketingUrl": MARKETING_URL, "supportUrl": SUPPORT_URL}}})
    print(f"[ok] ja whatsNew/description/marketingUrl/supportUrl 設定 (loc={ja_id})")

    # 3) reviewNotes
    try:
        detail = asc.get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
        did = detail["data"]["id"]
        asc.patch(f"/v1/appStoreReviewDetails/{did}", {
            "data": {"type": "appStoreReviewDetails", "id": did, "attributes": {"notes": REVIEW_NOTES}}})
        print(f"[ok] reviewNotes 更新 (detail={did})")
    except Exception as e:
        print(f"[!] reviewDetail 例外（contactPhone PATCH で作成想定）: {str(e)[:120]}")

    # 4) build 24 を attach（VALID 必須）
    builds = asc.get("/v1/builds", params={
        "filter[app]": APP_ID, "filter[version]": BUILD_NUMBER, "limit": 5,
        "fields[builds]": "version,processingState"})
    bd = builds.get("data", [])
    if not bd:
        print(f"[!] build {BUILD_NUMBER} が ASC に未出現 → attach スキップ")
    else:
        b = bd[0]
        st = b["attributes"].get("processingState")
        if st != "VALID":
            print(f"[!] build {BUILD_NUMBER} processing={st}（VALID でない）→ attach スキップ")
        else:
            asc.patch(f"/v1/appStoreVersions/{vid}/relationships/build", {
                "data": {"type": "builds", "id": b["id"]}})
            print(f"[ok] build {BUILD_NUMBER} (id={b['id']}) を v{VERSION} に attach")

    print(f"\n[done] VERSION_ID={vid} ja_loc={ja_id}")


if __name__ == "__main__":
    main()
