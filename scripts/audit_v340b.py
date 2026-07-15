# [paid-approved-by-kureho] v3.4.0 提出前 ASC 監査(続き)・GET のみ・課金なし
"""残り監査項目: 配信 / 価格 / reviewSubmissions / 年齢区分・appInfo / v3.3.0 メタデータ雛形。"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"
V330_ID = "db667023-39b5-4bd4-af74-c9e214783b83"  # 配信中 v3.3.0（雛形元）


def try_get(asc, path, params=None, label=""):
    try:
        return asc.get(path, params=params)
    except Exception as e:
        print(f"  [取得失敗] {label or path}: {e}")
        return None


def main():
    asc = ASC()

    print("===== 配信 appAvailabilityV2 (limit 50) =====")
    av = try_get(asc, f"/v1/apps/{APP_ID}/appAvailabilityV2",
                 {"include": "territoryAvailabilities", "limit[territoryAvailabilities]": 50},
                 "appAvailabilityV2")
    if av:
        ta = [x for x in av.get("included", []) if x["type"] == "territoryAvailabilities"]
        avail = sum(1 for x in ta if x["attributes"].get("available"))
        print(f"  availableInNewTerritories={av['data']['attributes'].get('availableInNewTerritories')} "
              f"配信territories={avail}（取得{len(ta)}件）")

    print("\n===== 価格 appPriceSchedule =====")
    sched = try_get(asc, f"/v1/apps/{APP_ID}/appPriceSchedule",
                    {"include": "manualPrices"}, "appPriceSchedule(include)")
    if sched is None:
        sched = try_get(asc, f"/v1/apps/{APP_ID}/appPriceSchedule", None, "appPriceSchedule(no include)")
    if sched:
        print(f"  priceSchedule data={bool(sched.get('data'))}")
        for inc in sched.get("included", []):
            if inc["type"] in ("appPrices", "appPricePoints"):
                print(f"    {inc['type']} id={inc['id']} attrs={inc.get('attributes')}")
    # price points (territory 数で tier 設定確認)
    pp = try_get(asc, f"/v1/apps/{APP_ID}/appPricePoints", {"limit": 200}, "appPricePoints")
    if pp:
        print(f"  appPricePoints 件数={len(pp.get('data', []))}（territory 数の目安）")

    print("\n===== reviewSubmissions =====")
    subs = try_get(asc, f"/v1/apps/{APP_ID}/reviewSubmissions", {"limit": 20}, "reviewSubmissions")
    if subs:
        if subs.get("data"):
            for s in subs["data"]:
                print(f"  state={s['attributes'].get('state')} platform={s['attributes'].get('platform')} "
                      f"submitted={s['attributes'].get('submittedDate')} id={s['id']}")
        else:
            print("  (open な reviewSubmission なし)")

    print("\n===== appInfos（年齢区分・name/subtitle・カテゴリ・App Privacy 状態） =====")
    ai = try_get(asc, f"/v1/apps/{APP_ID}/appInfos",
                 {"include": "ageRatingDeclaration,appInfoLocalizations,primaryCategory,secondaryCategory"},
                 "appInfos")
    if ai:
        for info in ai.get("data", []):
            ia = info["attributes"]
            print(f"  appInfo id={info['id']} state={ia.get('appStoreState') or ia.get('state')} "
                  f"kidsAge={ia.get('kidsAgeBand')}")
        for inc in ai.get("included", []):
            t = inc["type"]
            a = inc.get("attributes", {})
            if t == "ageRatingDeclarations":
                # 主要フラグだけ表示
                flags = {k: v for k, v in a.items() if v not in (None, "NONE", False)}
                print(f"  [ageRating] {flags}")
            elif t == "appInfoLocalizations":
                print(f"  [appInfoLoc {a.get('locale')}] name={a.get('name')} subtitle={a.get('subtitle')}")
            elif t in ("appCategories",):
                print(f"  [category] {inc['id']}")

    print("\n===== v3.3.0 localizations（v3.4.0 雛形・現行メタデータ全文） =====")
    locs = try_get(asc, f"/v1/appStoreVersions/{V330_ID}/appStoreVersionLocalizations", None, "v330 locs")
    if locs:
        for loc in locs.get("data", []):
            la = loc["attributes"]
            print(f"\n  --- locale={la.get('locale')} (id={loc['id']}) ---")
            print(f"  marketingUrl={la.get('marketingUrl')}")
            print(f"  supportUrl={la.get('supportUrl')}")
            print(f"  keywords={la.get('keywords')}")
            print(f"  promotionalText=\n{la.get('promotionalText')}")
            print(f"  whatsNew=\n{la.get('whatsNew')}")
            print(f"  description=\n{la.get('description')}")

    print("\n===== v3.3.0 reviewDetail（連絡先・demo・notes 雛形） =====")
    rd = try_get(asc, f"/v1/appStoreVersions/{V330_ID}/appStoreReviewDetail", None, "v330 reviewDetail")
    if rd and rd.get("data"):
        a = rd["data"]["attributes"]
        print(f"  contact={a.get('contactFirstName')} {a.get('contactLastName')} phone={a.get('contactPhone')} "
              f"email={a.get('contactEmail')} demoRequired={a.get('demoAccountRequired')}")
        print(f"  notes=\n{a.get('notes')}")

    print("\n[done]")


if __name__ == "__main__":
    main()
