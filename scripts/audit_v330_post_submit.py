# [paid-approved-by-kureho] v3.3.0 提出後 4 点監査・ASC GET のみ・課金なし
"""広告消し v3.3.0 の提出後 4 点監査（auditing-apple-submission）。GET のみ・副作用なし。"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"  # 広告消し
SUB_ID = "f8b6ffe5-04ca-4490-93ce-6948688ad2d2"


def main() -> None:
    asc = ASC()
    results = []

    # ① 審査ステータス
    r1 = asc.get(f"/v1/reviewSubmissions/{SUB_ID}")
    state = r1["data"]["attributes"]["state"]
    ok1 = state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED", "COMPLETING")
    results.append(("① 審査ステータス", ok1,
                    f"state={state} submitted={r1['data']['attributes'].get('submittedDate')}"))

    # ② アプリ配信ステータス（territories が空でないか）
    r2 = asc.get(f"/v1/apps/{APP_ID}/appAvailabilityV2",
                 params={"include": "territoryAvailabilities",
                         "limit[territoryAvailabilities]": 50})
    attrs = r2["data"]["attributes"]
    ta = [x for x in r2.get("included", []) if x["type"] == "territoryAvailabilities"]
    avail_count = sum(1 for x in ta if x["attributes"].get("available"))
    ok2 = (attrs.get("availableInNewTerritories") is True) or avail_count > 0
    results.append(("② アプリ配信ステータス", ok2,
                    f"availableInNewTerritories={attrs.get('availableInNewTerritories')} "
                    f"配信territories={avail_count}"))

    # ③ 価格 tier
    r3 = asc.get(f"/v1/apps/{APP_ID}/appPricePoints", params={"limit": 200})
    n_pp = len(r3.get("data", []))
    ok3 = n_pp >= 100
    results.append(("③ 価格 tier", ok3, f"price points territories={n_pp}"))

    # ④ IAP（広告消しは買い切り・IAP なし → N/A）
    results.append(("④ IAP availability", None, "N/A（買い切り・IAP なし）"))

    print("=== v3.3.0 提出後 4 点監査 ===")
    allpass = True
    for name, ok, detail in results:
        mark = "OK" if ok is True else ("N/A" if ok is None else "NG")
        if ok is False:
            allpass = False
        print(f"[{mark}] {name}: {detail}")
    print()
    print("4 点監査 ALL PASS" if allpass else "監査 NG あり -- 未完了")


if __name__ == "__main__":
    main()
