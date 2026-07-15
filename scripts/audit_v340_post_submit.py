# [paid-approved-by-kureho] v3.4.0 提出後監査・GET のみ・課金なし
"""v3.4.0 提出後の 4 点監査 + Phase 9（version/submission state・selected build・release方式・既存版影響・価格/IAP）。
Apple transient 5xx はリトライ吸収。"""
import sys, time
from pathlib import Path
sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402
import requests  # noqa: E402

APP_ID = "6774906945"
V_ID = "ab1d686e-af7c-4a86-a599-880356d02881"   # v3.4.0
SUB_ID = "d8de9223-5e61-4b5b-a131-4e264bbf8c13"  # reviewSubmission
BUILD_ID = "cf198723-05aa-4753-a300-124dd0165a99"  # build24

def rget(asc, path, params=None, tries=8, label=""):
    last = None
    for i in range(tries):
        try:
            return asc.get(path, params=params)
        except (requests.HTTPError, requests.exceptions.RequestException) as e:
            code = getattr(getattr(e, "response", None), "status_code", 0)
            if isinstance(e, requests.HTTPError) and code not in (500,502,503,504):
                print(f"  [{label}] {code} 非transient: {str(e)[:80]}"); return None
            last = e; print(f"  [{label}] transient (try {i+1}/{tries}) → 20s"); time.sleep(20)
    print(f"  [{label}] リトライ尽きた: {str(last)[:80]}"); return None

def main():
    asc = ASC()
    print("===== ① reviewSubmission state =====")
    r1 = rget(asc, f"/v1/reviewSubmissions/{SUB_ID}", label="sub")
    if r1:
        a = r1["data"]["attributes"]
        st = a.get("state")
        ok = st in ("WAITING_FOR_REVIEW","IN_REVIEW","APPROVED","COMPLETING","UNRESOLVED_ISSUES")
        print(f"  state={st} submitted={a.get('submittedDate')} -> {'OK' if ok else 'NG'}")

    print("===== v3.4.0 version state + selected build + release方式 =====")
    rv = rget(asc, f"/v1/appStoreVersions/{V_ID}", {"include":"build"}, label="ver")
    if rv:
        a = rv["data"]["attributes"]
        b = (rv["data"]["relationships"].get("build",{}).get("data") or {})
        print(f"  versionString={a.get('versionString')} state={a.get('appStoreState')} "
              f"releaseType={a.get('releaseType')}")
        print(f"  selected build={b.get('id')} (期待{BUILD_ID}) -> {'OK' if b.get('id')==BUILD_ID else 'NG'}")
    print("  [phasedRelease]")
    rp = rget(asc, f"/v1/appStoreVersions/{V_ID}/appStoreVersionPhasedRelease", label="phased")
    if rp is not None:
        d = rp.get("data")
        print(f"    {d['attributes'] if d else 'なし（phased 未設定）'}")

    print("===== build24 processing/compliance =====")
    rb = rget(asc, f"/v1/builds/{BUILD_ID}", {"fields[builds]":"version,processingState,usesNonExemptEncryption,expired"}, label="build")
    if rb:
        print(f"  {rb['data']['attributes']}")

    print("===== ② appAvailabilityV2（territories） =====")
    ra = rget(asc, f"/v1/apps/{APP_ID}/appAvailabilityV2",
              {"include":"territoryAvailabilities","limit[territoryAvailabilities]":50}, label="avail")
    if ra:
        ta = [x for x in ra.get("included",[]) if x["type"]=="territoryAvailabilities"]
        av = sum(1 for x in ta if x["attributes"].get("available"))
        print(f"  availableInNewTerritories={ra['data']['attributes'].get('availableInNewTerritories')} 配信={av}")

    print("===== ③ 価格 appPriceSchedule =====")
    rs = rget(asc, f"/v1/apps/{APP_ID}/appPriceSchedule", {"include":"manualPrices"}, label="price")
    if rs:
        print(f"  priceSchedule data={bool(rs.get('data'))}")
        for inc in rs.get("included",[]):
            if inc["type"] in ("appPrices","appPricePoints"):
                print(f"    {inc['type']} {inc.get('attributes')}")

    print("===== ④ IAP =====")
    ri = rget(asc, f"/v1/apps/{APP_ID}/inAppPurchasesV2", {"limit":10}, label="iap")
    if ri is not None:
        print(f"  IAP 件数={len(ri.get('data',[]))}（買い切り＝0 が正）")

    print("===== 既存配信版（影響なし確認） =====")
    rall = rget(asc, f"/v1/apps/{APP_ID}/appStoreVersions",
                {"limit":6, "fields[appStoreVersions]":"versionString,appStoreState"}, label="vers")
    if rall:
        for v in rall["data"]:
            print(f"  v{v['attributes'].get('versionString')} {v['attributes'].get('appStoreState')}")
    print("\n[done]")

if __name__ == "__main__":
    main()
