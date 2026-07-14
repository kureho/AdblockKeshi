#!/usr/bin/env python3
"""広告消し v4.0（Chunk 3 tunnel）向け bundle ID capability 有効化。

com.kureho.adblockkeshi に Network Extension と iCloud(Key-Value storage) を追加する。
既に有効なものはスキップ（idempotent）。各ステップの結果を表示する。

★実行は kureho 権限が必要（Claude の auto-mode 分類器が本番 Apple 設定の書込をブロックするため）:
    ! python3 scripts/enable_bundle_capabilities.py

注意: capability 追加で既存プロビジョニングは無効化 → 次ビルド時に自動署名で再生成される。
配信中 v3.6 は出荷済みで影響なし。元に戻す場合は ASC の Identifiers から該当 capability を外す。
"""
import os, sys, json, urllib.request, urllib.error

os.environ.setdefault("ASC_KEY_ID", "8AQ38HX67R")  # Admin ロール
sys.path.insert(0, os.path.expanduser("~/claude/MannerCamera4K/scripts"))
from asc_api import make_token  # noqa: E402

BID = "65YY9ZYP8A"  # com.kureho.adblockkeshi


def _req(method, path, body=None):
    tok = make_token()
    headers = {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path, headers=headers, data=data, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, json.loads(resp.read() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:600]


def current_capabilities():
    code, resp = _req("GET", f"/v1/bundleIds/{BID}?include=bundleIdCapabilities")
    if code != 200:
        print(f"現在 capability の取得に失敗: HTTP {code}: {resp}")
        return None
    return sorted(c["attributes"]["capabilityType"]
                  for c in resp.get("included", []) if c.get("type") == "bundleIdCapabilities")


def enable(cap, settings=None):
    attrs = {"capabilityType": cap}
    if settings is not None:
        attrs["settings"] = settings
    body = {"data": {"type": "bundleIdCapabilities", "attributes": attrs,
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": BID}}}}}
    code, resp = _req("POST", "/v1/bundleIdCapabilities", body)
    if code in (200, 201):
        print(f"  ✅ {cap} を有効化しました")
        return True
    print(f"  ❌ {cap} HTTP {code}: {resp if isinstance(resp, str) else json.dumps(resp)[:400]}")
    return False


def main():
    caps = current_capabilities()
    if caps is None:
        sys.exit(1)
    print("現在の capabilities:", caps)

    if "NETWORK_EXTENSIONS" in caps:
        print("  ⏭ NETWORK_EXTENSIONS は既に有効")
    else:
        enable("NETWORK_EXTENSIONS")

    if "ICLOUD" in caps:
        print("  ⏭ ICLOUD は既に有効")
    else:
        # KVS 目的。settings 無しで通らなければ ASC の Identifiers 画面で iCloud を手動 ON。
        if not enable("ICLOUD"):
            print("     → iCloud は API 拒否の可能性。ASC の Identifiers → com.kureho.adblockkeshi →")
            print("        『iCloud』にチェック（Key-value storage）→ 保存 で手動有効化してください。")

    print("\n最終 capabilities:", current_capabilities())
    print("※ 次の実機ビルドで自動署名がプロビジョニングを再生成します。")


if __name__ == "__main__":
    main()
