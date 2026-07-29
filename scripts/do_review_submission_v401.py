# [paid-approved-by-kureho] v4.0.1 reviewSubmission(最終提出)・ASC API・課金なし(DevProgram内)
"""広告消し v4.0.1 の reviewSubmission 作成 → item 追加 → submit。Apple transient 5xx をリトライ吸収。

前提: scripts/stage_v401.py 完了（version 作成 + build attach + reviewNotes 済み）
     + patch_review_contact_phone.py --apply + audit_asc_urls.py + precheck ログ。
実行: python3 scripts/do_review_submission_v401.py <VERSION_ID>
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC  # noqa: E402
import requests  # noqa: E402

APP_ID = "6774906945"


def retry(fn, tries=8, label=""):
    last = None
    for i in range(tries):
        try:
            return fn()
        except requests.HTTPError as e:
            code = e.response.status_code if e.response is not None else 0
            if code in (500, 502, 503, 504):
                last = e
                print(f"  [{label}] transient {code} (try {i+1}/{tries}) → 25s 待機")
                time.sleep(25)
                continue
            raise
        except requests.exceptions.RequestException as e:
            last = e
            print(f"  [{label}] network {type(e).__name__} (try {i+1}/{tries}) → 25s 待機")
            time.sleep(25)
    raise last


def main() -> None:
    version_id = sys.argv[1]
    asc = ASC()
    existing = retry(lambda: asc.get("/v1/reviewSubmissions", params={
        "filter[app]": APP_ID, "filter[platform]": "IOS", "limit": 10}), label="list")
    rs = None
    for s in existing.get("data", []):
        st = s["attributes"].get("state")
        if st not in ("COMPLETE", "CANCELING", "CANCELED"):
            rs = s
            print(f"[=] 既存未完了 reviewSubmission 再利用: id={s['id']} state={st}")
            break
    if rs is None:
        created = retry(lambda: asc.post("/v1/reviewSubmissions", {
            "data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                     "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}}), label="create")
        rs = created["data"]
        print(f"[+] reviewSubmission 作成: id={rs['id']} state={rs['attributes'].get('state')}")
    rsid = rs["id"]
    items = retry(lambda: asc.get(f"/v1/reviewSubmissions/{rsid}/items", params={"limit": 50}), label="items")
    has = any((it.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == version_id
              for it in items.get("data", []))
    if has:
        print("[=] v4.0.1 は既に item に含まれる")
    else:
        retry(lambda: asc.post("/v1/reviewSubmissionItems", {
            "data": {"type": "reviewSubmissionItems",
                     "relationships": {
                         "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rsid}},
                         "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}}), label="add-item")
        print("[+] v4.0.1 を item に追加")
    retry(lambda: asc.patch(f"/v1/reviewSubmissions/{rsid}", {
        "data": {"type": "reviewSubmissions", "id": rsid, "attributes": {"submitted": True}}}), label="submit")
    after = retry(lambda: asc.get(f"/v1/reviewSubmissions/{rsid}"), label="verify")
    a = after["data"]["attributes"]
    print(f"\n[done] reviewSubmission id={rsid} state={a.get('state')} submittedDate={a.get('submittedDate')}")
    print(f"SUBMISSION_ID={rsid}")


if __name__ == "__main__":
    main()
