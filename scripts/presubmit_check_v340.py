# [paid-approved-by-kureho] v3.4.0 提出前チェック・GET のみ
"""v3.4.0 の提出準備状況を確認（build attach/localization/reviewDetail/screenshots/年齢区分/export compliance）。"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"
V_ID = "ab1d686e-af7c-4a86-a599-880356d02881"  # v3.4.0
BUILD_ID = "cf198723-05aa-4753-a300-124dd0165a99"  # build24

def g(asc, path, params=None, label=""):
    try:
        return asc.get(path, params=params)
    except Exception as e:
        print(f"  [失敗] {label or path}: {str(e)[:90]}")
        return None

def main():
    asc = ASC()
    print("===== v3.4.0 version =====")
    v = g(asc, f"/v1/appStoreVersions/{V_ID}", {"include": "build,appStoreVersionLocalizations,appStoreReviewDetail"})
    if v:
        va = v["data"]["attributes"]
        print(f"  versionString={va.get('versionString')} state={va.get('appStoreState')} "
              f"releaseType={va.get('releaseType')}")
        b = (v["data"]["relationships"].get("build", {}).get("data") or {})
        print(f"  attached build = {b.get('id')} (期待 {BUILD_ID}) -> {'OK' if b.get('id')==BUILD_ID else 'NG'}")
        for inc in v.get("included", []):
            t = inc["type"]; a = inc.get("attributes", {})
            if t == "appStoreVersionLocalizations" and a.get("locale") == "ja":
                print(f"  [ja loc] whatsNew_len={len(a.get('whatsNew') or '')} desc_len={len(a.get('description') or '')} "
                      f"mkt={a.get('marketingUrl')} sup={a.get('supportUrl')}")
                for fld in ("whatsNew", "description"):
                    old = [x for x in ("標準フィルタ","学習フィルタ","自己学習フィルタ","ポップアップ広告対策","強力ポップアップ") if x in (a.get(fld) or "")]
                    print(f"    {fld} 旧名称: {old or 'なし'}")
            if t == "appStoreReviewDetails":
                print(f"  [reviewDetail] {a.get('contactFirstName')} {a.get('contactLastName')} "
                      f"phone={a.get('contactPhone')} email={a.get('contactEmail')} demo={a.get('demoAccountRequired')}")
                old = [x for x in ("標準フィルタ","学習フィルタ","自己学習フィルタ","ポップアップ広告対策","強力ポップアップ") if x in (a.get('notes') or "")]
                print(f"    notes 旧名称: {old or 'なし'} notes_len={len(a.get('notes') or '')}")

    print("\n===== build24 export compliance =====")
    b = g(asc, f"/v1/builds/{BUILD_ID}", {"fields[builds]": "version,processingState,usesNonExemptEncryption,expired"})
    if b:
        print(f"  {b['data']['attributes']}")

    print("\n===== v3.4.0 ja screenshots =====")
    locs = g(asc, f"/v1/appStoreVersions/{V_ID}/appStoreVersionLocalizations")
    if locs:
        ja = next((x for x in locs["data"] if x["attributes"]["locale"]=="ja"), None)
        if ja:
            ss = g(asc, f"/v1/appStoreVersionLocalizations/{ja['id']}/appScreenshotSets",
                   {"include": "appScreenshots", "limit": 20})
            if ss:
                sets = ss.get("data", [])
                shots = [x for x in ss.get("included", []) if x["type"]=="appScreenshots"]
                print(f"  screenshot sets={len(sets)} screenshots={len(shots)}")
                for s in shots[:8]:
                    print(f"    - {s['attributes'].get('fileName')} state={s['attributes'].get('assetDeliveryState',{}).get('state')}")

    print("\n===== appInfos 年齢区分 / カテゴリ =====")
    ai = g(asc, f"/v1/apps/{APP_ID}/appInfos", {"include": "ageRatingDeclaration,primaryCategory,secondaryCategory"})
    if ai:
        for inc in ai.get("included", []):
            if inc["type"] == "ageRatingDeclarations":
                a = inc["attributes"]
                nonzero = {k:v for k,v in a.items() if v not in (None,"NONE",False,0)}
                print(f"  [ageRating] {nonzero or '全て NONE/False（4+相当）'}")
            if inc["type"] == "appCategories":
                print(f"  [category] {inc['id']}")
    print("\n[done]")

if __name__ == "__main__":
    main()
