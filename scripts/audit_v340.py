# [paid-approved-by-kureho] v3.4.0 提出前 ASC live 監査・GET のみ・課金なし
"""広告消し v3.4.0 提出前の App Store Connect live 監査（read-only / 副作用なし）。

kureho 指示 Phase 2 の各項目を live read で事実確認する。推測・memory 依存しない。
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"  # 広告消し


def section(title):
    print(f"\n===== {title} =====")


def main() -> None:
    asc = ASC()

    section("App 基本情報")
    app = asc.get(f"/v1/apps/{APP_ID}")
    a = app["data"]["attributes"]
    print(f"name(ASC)={a.get('name')} bundleId={a.get('bundleId')} sku={a.get('sku')} "
          f"primaryLocale={a.get('primaryLocale')}")

    section("appStoreVersions（全状態）")
    vers = asc.get(f"/v1/apps/{APP_ID}/appStoreVersions",
                   params={"limit": 50, "include": "build",
                           "fields[appStoreVersions]":
                               "versionString,appStoreState,appVersionState,platform,createdDate,releaseType,build",
                           "fields[builds]": "version,processingState,uploadedDate,expired"})
    included = {x["id"]: x for x in vers.get("included", [])}
    v340_id = None
    for v in vers.get("data", []):
        va = v["attributes"]
        state = va.get("appStoreState") or va.get("appVersionState")
        bid = (v.get("relationships", {}).get("build", {}).get("data") or {})
        bnum = "-"
        if bid:
            b = included.get(bid.get("id"), {})
            bnum = b.get("attributes", {}).get("version", "?")
        print(f"  v{va.get('versionString')} state={state} platform={va.get('platform')} "
              f"releaseType={va.get('releaseType')} build={bnum} created={va.get('createdDate')} id={v['id']}")
        if va.get("versionString") == "3.4.0":
            v340_id = v["id"]
    print(f"  -> v3.4.0 version record id = {v340_id}")

    section("builds（最近10件・build24 状態）")
    builds = asc.get("/v1/builds",
                     params={"filter[app]": APP_ID, "limit": 15, "sort": "-uploadedDate",
                             "fields[builds]": "version,processingState,uploadedDate,expired,usesNonExemptEncryption"})
    b24 = None
    for b in builds.get("data", []):
        ba = b["attributes"]
        print(f"  build {ba.get('version')} processing={ba.get('processingState')} "
              f"uploaded={ba.get('uploadedDate')} expired={ba.get('expired')} "
              f"encryption={ba.get('usesNonExemptEncryption')} id={b['id']}")
        if ba.get("version") == "24":
            b24 = b
    print(f"  -> build24 存在={'YES' if b24 else 'NO'}")
    if b24:
        print(f"     build24 id={b24['id']} processing={b24['attributes'].get('processingState')} "
              f"expired={b24['attributes'].get('expired')}")

    section("reviewSubmissions（審査中/待ち/却下）")
    try:
        subs = asc.get(f"/v1/apps/{APP_ID}/reviewSubmissions",
                       params={"limit": 20, "include": "items",
                               "fields[reviewSubmissions]": "state,platform,submittedDate"})
        for s in subs.get("data", []):
            sa = s["attributes"]
            print(f"  submission state={sa.get('state')} platform={sa.get('platform')} "
                  f"submitted={sa.get('submittedDate')} id={s['id']}")
        if not subs.get("data"):
            print("  (review submissions なし)")
    except Exception as e:
        print(f"  reviewSubmissions 取得失敗: {e}")

    section("配信状況 appAvailabilityV2")
    try:
        av = asc.get(f"/v1/apps/{APP_ID}/appAvailabilityV2",
                     params={"include": "territoryAvailabilities",
                             "limit[territoryAvailabilities]": 200})
        ta = [x for x in av.get("included", []) if x["type"] == "territoryAvailabilities"]
        avail = sum(1 for x in ta if x["attributes"].get("available"))
        print(f"  availableInNewTerritories={av['data']['attributes'].get('availableInNewTerritories')} "
              f"配信territories数={avail}/{len(ta)}")
    except Exception as e:
        print(f"  appAvailabilityV2 取得失敗: {e}")

    section("価格 appPriceSchedule / pricePoints")
    try:
        sched = asc.get(f"/v1/apps/{APP_ID}/appPriceSchedule",
                        params={"include": "manualPrices,baseTerritory"})
        print(f"  priceSchedule あり: {bool(sched.get('data'))}")
        for inc in sched.get("included", []):
            if inc["type"] == "appPrices":
                print(f"    appPrice id={inc['id']} attrs={inc.get('attributes')}")
    except Exception as e:
        print(f"  appPriceSchedule 取得失敗: {e}")

    section("IAP（inAppPurchasesV2）")
    try:
        iaps = asc.get(f"/v1/apps/{APP_ID}/inAppPurchasesV2", params={"limit": 20})
        if iaps.get("data"):
            for i in iaps["data"]:
                print(f"  IAP productId={i['attributes'].get('productId')} "
                      f"state={i['attributes'].get('state')} id={i['id']}")
        else:
            print("  IAP なし（買い切り）")
    except Exception as e:
        print(f"  IAP 取得失敗: {e}")

    if not v340_id:
        print("\n[!] v3.4.0 version record が存在しない → 作成が必要（Phase 監査で対応）")
        return

    section("v3.4.0 詳細（build / localization / reviewDetail / phasedRelease / submission）")
    detail = asc.get(f"/v1/appStoreVersions/{v340_id}",
                     params={"include": "build,appStoreVersionLocalizations,appStoreReviewDetail,"
                                        "appStoreVersionPhasedRelease,ageRatingDeclaration",
                             "fields[appStoreVersions]": "versionString,appStoreState,appVersionState,releaseType,build"})
    da = detail["data"]["attributes"]
    print(f"  v3.4.0 state={da.get('appStoreState') or da.get('appVersionState')} releaseType={da.get('releaseType')}")
    binc = (detail["data"]["relationships"].get("build", {}).get("data") or {})
    print(f"  紐付け build = {binc.get('id') if binc else 'なし（未設定）'}")
    for inc in detail.get("included", []):
        t = inc["type"]
        ia = inc.get("attributes", {})
        if t == "builds":
            print(f"  [build] version={ia.get('version')} processing={ia.get('processingState')}")
        elif t == "appStoreVersionLocalizations":
            print(f"  [loc {ia.get('locale')}] "
                  f"marketingUrl={ia.get('marketingUrl')} supportUrl={ia.get('supportUrl')}")
            print(f"      keywords={ia.get('keywords')}")
            print(f"      promotionalText={(ia.get('promotionalText') or '')[:60]}")
            print(f"      whatsNew={(ia.get('whatsNew') or '')[:80]}")
            print(f"      description(head)={(ia.get('description') or '')[:80]}")
        elif t == "appStoreReviewDetails":
            print(f"  [reviewDetail] contactFirst={ia.get('contactFirstName')} contactLast={ia.get('contactLastName')} "
                  f"phone={ia.get('contactPhone')} email={ia.get('contactEmail')} "
                  f"demoRequired={ia.get('demoAccountRequired')}")
            print(f"      notes={(ia.get('notes') or '')[:120]}")
        elif t == "appStoreVersionPhasedReleases":
            print(f"  [phasedRelease] state={ia.get('phasedReleaseState')}")
        elif t == "ageRatingDeclarations":
            print(f"  [ageRating] {ia}")

    # submission state
    try:
        subm = asc.get(f"/v1/appStoreVersions/{v340_id}/appStoreVersionSubmission")
        print(f"  [versionSubmission] {subm.get('data', {}).get('attributes')}")
    except Exception as e:
        print(f"  versionSubmission なし/取得不可: {e}")

    # localization 詳細（description/keywords 全文・旧名称チェック用）
    section("v3.4.0 localizations 全文（旧名称チェック）")
    locs = asc.get(f"/v1/appStoreVersions/{v340_id}/appStoreVersionLocalizations")
    for loc in locs.get("data", []):
        la = loc["attributes"]
        print(f"  --- locale={la.get('locale')} (id={loc['id']}) ---")
        for k in ("description", "keywords", "promotionalText", "whatsNew", "marketingUrl", "supportUrl"):
            val = la.get(k) or ""
            old = any(x in val for x in ("標準フィルタ", "ポップアップ広告対策", "強力ポップアップ対策"))
            print(f"    {k}: 旧名称={'YES' if old else 'no'} len={len(val)}")

    # screenshots
    section("v3.4.0 screenshots（旧名称含む画像の有無は別途目視）")
    for loc in locs.get("data", []):
        try:
            ss_sets = asc.get(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
                              params={"include": "appScreenshots"})
            n = len([x for x in ss_sets.get("included", []) if x["type"] == "appScreenshots"])
            print(f"  locale={loc['attributes'].get('locale')} screenshot数={n} "
                  f"sets={len(ss_sets.get('data', []))}")
        except Exception as e:
            print(f"  locale={loc['attributes'].get('locale')} screenshot 取得失敗: {e}")

    print("\n[done] live 監査完了")


if __name__ == "__main__":
    main()
