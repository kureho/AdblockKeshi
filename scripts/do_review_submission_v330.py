# [paid-approved-by-kureho] kureho「go していいよ」承認済み・v3.3.0 reviewSubmission(最終提出)・ASC API・課金なし(DevProgram内)
"""広告消し v3.3.0 の reviewSubmission を作成 → item 追加 → submit する（最終提出）。

precheck ログ（2026-06-17-adblockkeshi-build23.json）書き出し済み・kureho 承認済み。
実行: python3 scripts/do_review_submission_v330.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402

APP_ID = "6774906945"
VERSION_ID = "db667023-39b5-4bd4-af74-c9e214783b83"  # v3.3.0


def main() -> None:
    asc = ASC()

    # 0) 既存の未完了 reviewSubmission を確認（重複作成回避）
    existing = asc.get("/v1/reviewSubmissions", params={
        "filter[app]": APP_ID, "filter[platform]": "IOS", "limit": 10,
    })
    rs = None
    for s in existing.get("data", []):
        st = s["attributes"].get("state")
        if st not in ("COMPLETE", "CANCELING", "CANCELED"):
            rs = s
            print(f"[=] 既存の未完了 reviewSubmission を再利用: id={s['id']} state={st}")
            break

    # 1) 無ければ作成
    if rs is None:
        created = asc.post("/v1/reviewSubmissions", {
            "data": {"type": "reviewSubmissions",
                     "attributes": {"platform": "IOS"},
                     "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}
        })
        rs = created["data"]
        print(f"[+] reviewSubmission 作成: id={rs['id']} state={rs['attributes'].get('state')}")
    rsid = rs["id"]

    # 2) v3.3.0 を item として追加（既に入っていなければ）
    items = asc.get(f"/v1/reviewSubmissions/{rsid}/items", params={"limit": 50})
    has_version = any(
        (it.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == VERSION_ID
        for it in items.get("data", [])
    )
    if has_version:
        print("[=] v3.3.0 は既に submission item に含まれている")
    else:
        asc.post("/v1/reviewSubmissionItems", {
            "data": {"type": "reviewSubmissionItems",
                     "relationships": {
                         "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rsid}},
                         "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}},
                     }}
        })
        print(f"[+] v3.3.0 を submission item に追加")

    # 3) submit
    asc.patch(f"/v1/reviewSubmissions/{rsid}", {
        "data": {"type": "reviewSubmissions", "id": rsid,
                 "attributes": {"submitted": True}}
    })
    # 確認
    after = asc.get(f"/v1/reviewSubmissions/{rsid}")
    state = after["data"]["attributes"].get("state")
    submitted = after["data"]["attributes"].get("submittedDate")
    print(f"\n[done] reviewSubmission id={rsid} state={state} submittedDate={submitted}")


if __name__ == "__main__":
    main()
