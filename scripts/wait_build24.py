# [paid-approved-by-kureho] build24 processing 待ち・GET のみ
"""build 24 の processingState が VALID になるまで polling（GET のみ）。transient 500/timeout は吸収。"""
import sys, time
from pathlib import Path
sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC, make_token  # noqa: E402

APP_ID = "6774906945"
TARGET_BUILD = "24"

def main():
    asc = ASC()
    for attempt in range(40):  # 最大 ~40分
        try:
            asc.token = make_token()  # JWT 失効回避で都度再生成
            r = asc.get("/v1/builds", params={
                "filter[app]": APP_ID, "filter[version]": TARGET_BUILD, "limit": 5,
                "fields[builds]": "version,processingState,uploadedDate,expired"})
            data = r.get("data", [])
            if not data:
                print(f"[{attempt}] build {TARGET_BUILD} まだ ASC に出現せず")
            else:
                b = data[0]
                st = b["attributes"].get("processingState")
                print(f"[{attempt}] build {TARGET_BUILD} id={b['id']} processing={st} "
                      f"uploaded={b['attributes'].get('uploadedDate')}")
                if st == "VALID":
                    print(f"BUILD24_VALID id={b['id']}")
                    return
                if st in ("INVALID", "FAILED"):
                    print(f"BUILD24_BAD state={st}")
                    return
        except Exception as e:
            print(f"[{attempt}] 取得失敗(transient?): {str(e)[:100]}")
        time.sleep(60)
    print("TIMEOUT: build24 が VALID にならず")

if __name__ == "__main__":
    main()
