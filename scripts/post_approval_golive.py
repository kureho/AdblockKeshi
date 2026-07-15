# [paid-approved-by-kureho] kureho 依頼で承認後 go-live を1本化（2026-07-15）。dry-run 既定・実行は承認後 --apply のみ。
"""広告消し v4.0 承認後の go-live を1本化（価格¥0化→検証→手動リリース）。

★実行タイミング: **Apple が v4.0 を承認して version が PENDING_DEVELOPER_RELEASE になってから**。
  それ以前（WAITING_FOR_REVIEW/IN_REVIEW）は preflight で必ず中断する（無料化を早まらない安全弁）。

順序（runbook 準拠）:
  0) preflight（READ・ゲート）: version=PENDING_DEVELOPER_RELEASE かつ IAP=APPROVED を必須。
     → どちらか未達なら中断（承認前 / IAP 未承認で無料化・リリースを走らせない）。
  1) 価格 → ¥0（POST /v1/appPriceSchedules・即時）
  2) 価格 ¥0 を検証
  3) 手動リリース（POST /v1/appStoreVersionReleaseRequests）
  4) LP deploy は別 repo（app-support）なので最後に手順を印字（このスクリプトは触らない）

使い方:
  python3 scripts/post_approval_golive.py            # dry-run（preflight と予定を表示するだけ）
  python3 scripts/post_approval_golive.py --apply    # 実行（preflight PASS 時のみ mutate）

不可逆注意: 無料化は実質戻せない。--apply は承認後・深夜帯に kureho 立ち会いで。
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / "claude/MannerCamera4K/scripts"))
from asc_api import ASC, BASE  # noqa: E402

APP_ID = "6774906945"                                  # 広告消し
VID = "6276f05a-abd9-4838-9d49-75699051b1d2"           # v4.0.0
IAP_ID = "6791059609"                                  # com.kureho.adblockkeshi.pro
RELEASABLE_STATES = {"PENDING_DEVELOPER_RELEASE"}      # 手動リリース待ち＝承認済
IAP_OK_STATES = {"APPROVED", "PENDING_DEVELOPER_RELEASE"}


def find_free_price_point(asc: ASC) -> str | None:
    next_url = f"/v1/apps/{APP_ID}/appPricePoints?filter[territory]=JPN&limit=200"
    while next_url:
        resp = asc.get(next_url)
        for pp in resp.get("data", []):
            price = str(pp.get("attributes", {}).get("customerPrice", ""))
            if price in ("0", "0.0", "0.00"):
                return pp["id"]
        nxt = resp.get("links", {}).get("next")
        next_url = nxt.replace(BASE, "") if nxt else None
    return None


def current_price(asc: ASC) -> str:
    resp = asc.get(f"/v1/appPriceSchedules/{APP_ID}/manualPrices",
                   params={"include": "appPricePoint", "limit": 5})
    for inc in resp.get("included", []):
        if inc["type"] == "appPricePoints":
            return str(inc["attributes"].get("customerPrice"))
    return "?"


def preflight(asc: ASC) -> tuple[bool, str, str]:
    v = asc.get(f"/v1/appStoreVersions/{VID}",
                params={"fields[appStoreVersions]": "appStoreState,versionString"})
    vst = v["data"]["attributes"].get("appStoreState")
    iap = asc.get(f"/v2/inAppPurchases/{IAP_ID}")
    ist = iap["data"]["attributes"].get("state")
    ok = (vst in RELEASABLE_STATES) and (ist in IAP_OK_STATES)
    return ok, vst, ist


def main() -> None:
    apply = "--apply" in sys.argv
    asc = ASC()

    print("=== preflight（承認状態ゲート）===")
    ok, vst, ist = preflight(asc)
    print(f"  version 4.0.0 state = {vst}（必須: PENDING_DEVELOPER_RELEASE）")
    print(f"  IAP state          = {ist}（必須: APPROVED）")
    print(f"  現在価格           = ¥{current_price(asc)}")
    if not ok:
        print("\n⛔ 未承認 or IAP 未承認。go-live は実行しません（早まった無料化を防止）。")
        print("   Apple 承認後（version=PENDING_DEVELOPER_RELEASE・IAP=APPROVED）に再実行してください。")
        sys.exit(1)

    if not apply:
        print("\n[dry-run] preflight PASS。--apply で以下を順に実行:")
        print("  1) 価格 → ¥0（appPriceSchedules）")
        print("  2) ¥0 検証")
        print("  3) 手動リリース（appStoreVersionReleaseRequests）")
        print("  4) LP deploy 手順を印字（別 repo・手動確認）")
        return

    # 1) 価格 ¥0
    pp = find_free_price_point(asc)
    if not pp:
        print("¥0 の price point が見つからない", file=sys.stderr)
        sys.exit(1)
    asc.post("/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": APP_ID}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${price-1}"}]},
            "baseTerritory": {"data": {"type": "territories", "id": "JPN"}},
        }},
        "included": [{"id": "${price-1}", "type": "appPrices",
                      "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": pp}}}}],
    })
    # 2) 検証
    price = current_price(asc)
    print(f"[1-2] 価格変更後 = ¥{price}")
    if price not in ("0", "0.0", "0.00"):
        print("⛔ ¥0 反映を確認できず。リリースを中断。", file=sys.stderr)
        sys.exit(1)

    # 3) 手動リリース
    asc.post("/v1/appStoreVersionReleaseRequests", {
        "data": {"type": "appStoreVersionReleaseRequests",
                 "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VID}}}}
    })
    print("[3] 手動リリース要求を送信（PENDING_DEVELOPER_RELEASE → リリース処理へ）")

    # 4) LP deploy 手順（別 repo）
    print("\n[4] LP deploy（app-support・別 repo・手動確認して実行）:")
    print("    cd ~/claude/app-support")
    print("    git checkout main && git merge v4-freemium-lp-draft && git push")
    print("    vercel --prod   # デプロイ後シークレットモードで /apps/adblock-keshi を目視")
    print("\n✅ ASC 側 go-live 完了。次: 実機ストア¥0確認・4点監査・実機Pro判定・レビュー監視。")


if __name__ == "__main__":
    main()
