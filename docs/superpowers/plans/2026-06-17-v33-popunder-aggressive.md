<!-- [paid-approved-by-kureho] 実装プランの markdown ドキュメント。ASC/提出 API は一切呼ばない。提出は kureho 起床後判断と明記。課金ゼロ。 -->
# v3.3.0 popunder ブロッカー強化 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 出荷済み `PopunderBlockerExtension` を強化し、対象サイトで回転ドメイン込みの popunder を実効的に消す（L1 安全網拡充 + L2 サイト別アグレッシブ + CDN 更新化）。

**Architecture:** popunder 専用の手書き決定論ジェネレータ（Python）が L1（既知網 $script block）と L2（対象サイトで third-party script 全 block → allowlist を ignore-previous-rules）を `popunder-rules.json` にコンパイルし、bundle 同梱 + CDN 配信。Swift 側は `FilterDownloader` の version 同期を opt-out 化して2つ目インスタンス（popunder 用）を安全に追加。

**Tech Stack:** Python 3（ジェネレータ・既存 `build_security_rules.py` パターン）、Swift/SwiftUI（FilterDownloader）、WebKit Content Blocker JSON、GitHub Actions（Linux）、Node/Playwright（解析ツール）。

**Spec:** `docs/superpowers/specs/2026-06-17-adblockkeshi-v33-popunder-aggressive-design.md`（spec-reviewer 3 iteration 承認済み）

---

## File Structure

| ファイル | 役割 | 種別 |
|---|---|---|
| `scripts/build_popunder_rules.py` | L1+L2 → popunder-rules.json 生成（手書き決定論） | Create |
| `scripts/tests/test_build_popunder_rules.py` | ジェネレータ単体テスト | Create |
| `tasks/b-popunder-script/popunder-aggressive-sites.json` | L2 ソース（対象サイト+allow） | Create |
| `tasks/b-popunder-script/popunder-script-networks.txt` | L1 ソース（jads.co/glssp.net 追加） | Modify |
| `PopunderBlockerExtension/Resources/popunder-rules.json` | bundle 同梱の生成物 | Regenerate |
| `docs/cdn/popunder-rules.json` | CDN 配信の生成物 | Create |
| `Shared/FilterDownloader.swift` | version 同期 opt-out 化（最小改変） | Modify |
| `App/ReportTab/ReportedGlobalSync.swift`（参考前例） | — | Read only |
| `App/PopunderGlobalSync.swift`（or 適切な場所） | popunder-rules.json を CDN→App Group 同期 | Create |
| `Tests/FilterDownloaderVersionSyncTests.swift` | version 同期 opt-out のテスト | Create |
| `.github/workflows/popunder-rules-update.yml` | Linux 再生成 workflow | Create |
| `scripts/analyze-popunder.js` | desktop 解析ツール常設化（allowlist 決定支援） | Create |
| `tasks/b-popunder-script/README.md` | 「v3.3.0 未着手」誤記の現状修正 | Modify |

---

## Chunk 1: Python ジェネレータ（L1 + L2）

### Task 1: L1 パーサ + block ルール emit

**Files:**
- Create: `scripts/build_popunder_rules.py`
- Test: `scripts/tests/test_build_popunder_rules.py`

- [ ] **Step 1: 失敗するテストを書く** — `||domain^$script` 行を block ルールに変換、`!`/空行は無視

```python
# scripts/tests/test_build_popunder_rules.py
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_popunder_rules import parse_networks, network_rule

def test_parse_networks_ignores_comments_and_blanks():
    text = "! Title: x\n\n||popads.net^$script\n||jads.co^$script\n"
    assert parse_networks(text) == ["popads.net", "jads.co"]

def test_network_rule_shape_matches_shipped():
    r = network_rule("popads.net")
    assert r == {
        "trigger": {"url-filter": r"^[^:]+://+([^:/]+\.)?popads\.net[/:]", "resource-type": ["script"]},
        "action": {"type": "block"},
    }
```

- [ ] **Step 2: テスト失敗を確認** — Run: `python3 -m pytest scripts/tests/test_build_popunder_rules.py -v` / Expected: FAIL（module/関数なし）

- [ ] **Step 3: 最小実装**

```python
#!/usr/bin/env python3
"""popunder-rules.json を L1（既知網 $script）+ L2（サイト別アグレッシブ）から生成。
手書き決定論。SafariConverterLib (convert.sh) とは別物。
Spec: docs/superpowers/specs/2026-06-17-adblockkeshi-v33-popunder-aggressive-design.md
"""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

def parse_networks(text: str) -> list[str]:
    """popunder-script-networks.txt から domain を抽出。`!`始まり/空行は無視。`||domain^$script`のみ。"""
    domains: list[str] = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("!"):
            continue
        m = re.match(r"^\|\|([^/^]+)\^\$script$", s)
        if m:
            domains.append(m.group(1))
    return domains

def _domain_anchor(domain: str) -> str:
    """||domain^ の標準 ABP→WebKit url-filter 変換（出荷形と一致）。"""
    return r"^[^:]+://+([^:/]+\.)?" + re.escape(domain) + r"[/:]"

def network_rule(domain: str) -> dict:
    return {
        "trigger": {"url-filter": _domain_anchor(domain), "resource-type": ["script"]},
        "action": {"type": "block"},
    }
```

- [ ] **Step 4: テスト pass 確認** — Run: `python3 -m pytest scripts/tests/test_build_popunder_rules.py -v` / Expected: PASS

- [ ] **Step 5: commit** — `git add scripts/build_popunder_rules.py scripts/tests/test_build_popunder_rules.py && git commit -m "feat(popunder): L1 network rule generator (ABP->WebKit, shipped-shape)"`

### Task 2: L2 emit（block → allow ignore-previous-rules・順序固定）

**Files:** Modify `scripts/build_popunder_rules.py`, `scripts/tests/test_build_popunder_rules.py`

- [ ] **Step 1: 失敗テスト** — 1サイトにつき block 1件 → allow 各 domain ごとに ignore-previous-rules 1件、順序を literal index で検証

```python
from build_popunder_rules import aggressive_site_rules

def test_aggressive_site_rules_order_and_shape():
    rules = aggressive_site_rules({"domain": "tokyomotion.net", "allow": ["fluidplayer.com", "googleapis.com"]})
    # index 0 = block 全third-party script, if-domain 限定
    assert rules[0]["action"] == {"type": "block"}
    assert rules[0]["trigger"]["url-filter"] == ".*"
    assert rules[0]["trigger"]["resource-type"] == ["script"]
    assert rules[0]["trigger"]["load-type"] == ["third-party"]
    assert rules[0]["trigger"]["if-domain"] == ["*tokyomotion.net"]
    # index 1,2 = allow（ignore-previous-rules）1 entry = 1 rule、block の後
    assert rules[1]["action"] == {"type": "ignore-previous-rules"}
    assert rules[1]["trigger"]["if-domain"] == ["*tokyomotion.net"]
    assert "fluidplayer" in rules[1]["trigger"]["url-filter"]
    assert rules[2]["action"] == {"type": "ignore-previous-rules"}
    assert "googleapis" in rules[2]["trigger"]["url-filter"]
    assert len(rules) == 3
```

- [ ] **Step 2: 失敗確認** — Run pytest / Expected: FAIL（`aggressive_site_rules` なし）

- [ ] **Step 3: 実装**

```python
def aggressive_site_rules(site: dict) -> list[dict]:
    """1サイト分: block(全third-party script, if-domain限定) -> allow各々 ignore-previous-rules。順序厳守。"""
    domain = site["domain"]
    if_domain = [f"*{domain}"]
    rules: list[dict] = [{
        "trigger": {"url-filter": ".*", "resource-type": ["script"],
                    "load-type": ["third-party"], "if-domain": if_domain},
        "action": {"type": "block"},
    }]
    for allow in site.get("allow", []):
        rules.append({
            "trigger": {"url-filter": _domain_anchor(allow), "if-domain": if_domain},
            "action": {"type": "ignore-previous-rules"},
        })
    return rules
```

- [ ] **Step 4: pass 確認** — pytest / Expected: PASS
- [ ] **Step 5: commit** — `git commit -am "feat(popunder): L2 aggressive per-site rules (block->ignore order pinned)"`

### Task 3: build() 統合 + ルール数上限ガード + ファイル出力

**Files:** Modify `scripts/build_popunder_rules.py`, test

- [ ] **Step 1: 失敗テスト** — networks + sites → 全ルール（L1 群 → L2 群の順）、上限超過で ValueError

```python
from build_popunder_rules import build_rules, _domain_anchor

def test_build_rules_orders_l1_then_l2():
    rules = build_rules(["popads.net"], [{"domain": "x.net", "allow": ["a.com"]}])
    assert rules[0]["trigger"]["url-filter"] == _domain_anchor("popads.net")  # L1 先
    assert rules[1]["trigger"]["url-filter"] == ".*"  # L2 block
    assert rules[2]["action"]["type"] == "ignore-previous-rules"

def test_build_rules_rejects_over_limit():
    import pytest
    with pytest.raises(ValueError):
        build_rules([f"d{i}.com" for i in range(50001)], [])
```

- [ ] **Step 2: 失敗確認**
- [ ] **Step 3: 実装**

```python
MAX_RULES = 50000  # WebKit content blocker 上限の保守値（別拡張枠・実数は数百）

def build_rules(networks: list[str], sites: list[dict]) -> list[dict]:
    rules = [network_rule(d) for d in networks]
    for site in sites:
        rules.extend(aggressive_site_rules(site))
    if len(rules) > MAX_RULES:
        raise ValueError(f"rule count {len(rules)} exceeds MAX_RULES {MAX_RULES}")
    return rules

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--networks", required=True)
    p.add_argument("--sites", required=True)
    p.add_argument("--out", action="append", required=True, help="出力先（複数可: bundle と cdn）")
    a = p.parse_args()
    networks = parse_networks(Path(a.networks).read_text())
    sites = json.loads(Path(a.sites).read_text())
    rules = build_rules(networks, sites)
    payload = json.dumps(rules, ensure_ascii=False, indent=2) + "\n"
    for out in a.out:
        Path(out).write_text(payload)
    print(f"wrote {len(rules)} rules to {len(a.out)} file(s)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: pass 確認**
- [ ] **Step 5: commit** — `git commit -am "feat(popunder): build_rules integration + rule-count guard + CLI"`

### Task 4: L1 等価回帰テスト（出荷済み29ルール再現）

**Files:** Modify test

- [ ] **Step 1: テスト** — networks.txt から生成した L1 が、出荷 `popunder-rules.json` の block ルールと等価（追加分除く）

```python
def test_l1_reproduces_shipped_rules():
    repo = Path(__file__).resolve().parents[2]
    shipped = json.loads((repo / "PopunderBlockerExtension/Resources/popunder-rules.json").read_text())
    networks = parse_networks((repo / "tasks/b-popunder-script/popunder-script-networks.txt").read_text())
    shipped_set = {json.dumps(r, sort_keys=True) for r in shipped}
    for d in networks:
        if d in ("jads.co", "glssp.net"):  # v3.3.0 追加分は出荷形に無い
            continue
        assert json.dumps(network_rule(d), sort_keys=True) in shipped_set, f"{d} の生成ルールが出荷形と不一致"
```

- [ ] **Step 2-4:** 実行して pass 確認（通らなければ `_domain_anchor` を出荷形に合わせ修正）
- [ ] **Step 5: commit** — `git commit -am "test(popunder): L1 reproduces shipped rules (regression guard)"`

> **Chunk 1 完了後**: ジェネレータは pytest で自己検証。次 Chunk へ。

---

## Chunk 2: ソースデータ更新 + 再生成

### Task 5: L1 にギャップ補充（jads.co / glssp.net）

**Files:** Modify `tasks/b-popunder-script/popunder-script-networks.txt`

- [ ] **Step 1:** JuicyAds セクションに `||jads.co^$script`、Others に `||glssp.net^$script` を追加（実測で popunder gesture listener を登録していた網）
- [ ] **Step 2:** `python3 -m pytest scripts/tests/test_build_popunder_rules.py -v` で Task4 等価テストが緑のままを確認
- [ ] **Step 3: commit** — `git commit -am "feat(popunder): add jads.co (JuicyAds serving) + glssp.net to L1 (desktop実測ギャップ)"`

### Task 6: L2 ソース作成（tokyomotion 初期収録）

**Files:** Create `tasks/b-popunder-script/popunder-aggressive-sites.json`

- [ ] **Step 1:** 実測 allow セットで作成

```json
[
  {
    "domain": "tokyomotion.net",
    "allow": ["fluidplayer.com", "googleapis.com", "googletagmanager.com", "gstatic.com", "tokyo-motion.net"],
    "note": "2026-06-17 desktop実測。fluidplayer=動画プレーヤー / tokyo-motion.net=サイト自身CDN。回転popunder(reservedghettocrimpycrimpy等)はblock側で消える。"
  }
]
```

- [ ] **Step 2: commit** — `git commit -am "feat(popunder): L2 aggressive-sites source with tokyomotion (実測allow)"`

### Task 7: 再生成（bundle + CDN）+ 検証

**Files:** Regenerate `PopunderBlockerExtension/Resources/popunder-rules.json`, Create `docs/cdn/popunder-rules.json`

- [ ] **Step 1:** 生成

```bash
python3 scripts/build_popunder_rules.py \
  --networks tasks/b-popunder-script/popunder-script-networks.txt \
  --sites tasks/b-popunder-script/popunder-aggressive-sites.json \
  --out PopunderBlockerExtension/Resources/popunder-rules.json \
  --out docs/cdn/popunder-rules.json
```

- [ ] **Step 2: 検証** — 両ファイル同一・valid JSON・L1(31) + L2(block1+allow5=6) = 37 ルール・block→ignore 順序

```bash
python3 -c "import json; a=json.load(open('PopunderBlockerExtension/Resources/popunder-rules.json')); b=json.load(open('docs/cdn/popunder-rules.json')); assert a==b; print('rules:', len(a)); assert any(r['trigger'].get('url-filter')=='.*' for r in a), 'L2 block missing'; print('OK')"
```

- [ ] **Step 3: commit** — `git commit -am "build(popunder): regenerate rules (bundle+cdn) with L1 gaps + L2 tokyomotion"`

---

## Chunk 3: Swift downloader（version 同期 opt-out + popunder インスタンス）

### Task 8: FilterDownloader の version 同期を opt-out 化（後方互換）

**Files:** Modify `Shared/FilterDownloader.swift`, Create `Tests/FilterDownloaderVersionSyncTests.swift`

- [ ] **Step 1: 失敗テスト** — `syncsVersion: false` で versionURL を fetch しない／`true`（既定）で fetch する。既存テストの URLProtocol stub パターンに合わせ、versionURL への到達有無を記録して検証
- [ ] **Step 2: 失敗確認** — `xcodebuild test -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:.../FilterDownloaderVersionSyncTests` / Expected: FAIL（`syncsVersion` 不在でコンパイルエラー）
- [ ] **Step 3: 実装** — プロパティ追加 + ガード

```swift
// init に追加: syncsVersion: Bool = true（既定で従来通り）
let syncsVersion: Bool
// init body: self.syncsVersion = syncsVersion
// downloadAndStore() の version 同期呼び出しをガード:
if syncsVersion {
    await downloadVersionInfoBestEffort(containerURL: containerURL)
}
```
既存 init 呼び出し（main / ReportedGlobalSync）は引数省略で `syncsVersion=true` ＝挙動不変。

- [ ] **Step 4: pass 確認** — xcodebuild test / Expected: PASS
- [ ] **Step 5: commit** — `git commit -am "feat(downloader): opt-out version sync (syncsVersion flag, backward compatible)"`

### Task 9: PopunderGlobalSync（CDN→App Group 同期・version skip）

**Files:** Create `App/PopunderGlobalSync.swift`（`ReportedGlobalSync.swift` を前例に）

- [ ] **Step 1:** popunder-rules.json 用の FilterDownloader インスタンスを構成

```swift
import Foundation

/// CDN の popunder-rules.json を App Group に同期する。version 同期はしない（最終更新UIを持たないため）。
enum PopunderGlobalSync {
    static let cdnURL = URL(string: "https://kureho.github.io/AdblockKeshi/cdn/popunder-rules.json")!
    static func make() -> FilterDownloader {
        FilterDownloader(
            blockerListURL: cdnURL,
            appGroupIdentifier: "group.com.kureho.adblockkeshi.shared",
            filename: "popunder-rules.json",
            syncsVersion: false
        )
    }
}
```
（注: `PopunderRulesResolver.filename` と同じ `"popunder-rules.json"` を App Group に書く＝resolver が App Group 優先で拾う）

- [ ] **Step 2:** ビルド確認 `xcodebuild build -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 16'`
- [ ] **Step 3: commit** — `git commit -am "feat(popunder): PopunderGlobalSync (CDN->App Group, version sync skipped)"`

### Task 10: 起動時に popunder 同期を発火

**Files:** Modify — 本体フィルタ DL を起動時に呼ぶ箇所を grep で特定し、popunder 同期も best-effort で並走

- [ ] **Step 1:** 既存 main filter DL 呼び出し箇所を特定（`grep -rn "downloadAndStore\|ReportedGlobalSync" App/`）
- [ ] **Step 2:** 同じ best-effort パターンで `try? await PopunderGlobalSync.make().downloadAndStore()` を追加（main DL を阻害しない独立 try?）
- [ ] **Step 3:** ビルド確認
- [ ] **Step 4: commit** — `git commit -am "feat(popunder): trigger popunder rules sync on launch (best-effort)"`

> **Chunk 3 完了後**: シミュレータで起動 → クラッシュなし＋既存「フィルタ最終更新」表示が壊れていない（本体 version.json が popunder で上書きされない）ことを目視（feedback_simulator_first_verification）。

---

## Chunk 4: CI workflow + 解析ツール + README

### Task 11: popunder 再生成 workflow（Linux・timeout 必須）

**Files:** Create `.github/workflows/popunder-rules-update.yml`

- [ ] **Step 1:** 作成

```yaml
name: popunder-rules-update
on:
  workflow_dispatch:
  push:
    paths:
      - 'tasks/b-popunder-script/popunder-script-networks.txt'
      - 'tasks/b-popunder-script/popunder-aggressive-sites.json'
      - 'scripts/build_popunder_rules.py'
concurrency:
  group: popunder-rules
  cancel-in-progress: true
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - name: Generate popunder rules (bundle + cdn)
        run: |
          python3 scripts/build_popunder_rules.py \
            --networks tasks/b-popunder-script/popunder-script-networks.txt \
            --sites tasks/b-popunder-script/popunder-aggressive-sites.json \
            --out PopunderBlockerExtension/Resources/popunder-rules.json \
            --out docs/cdn/popunder-rules.json
      - name: Commit if changed
        run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add PopunderBlockerExtension/Resources/popunder-rules.json docs/cdn/popunder-rules.json
          git diff --cached --quiet || git commit -m "build(popunder): regenerate rules [skip ci]"
          git push
```
（注: workflow-timeout-guard hook 遵守: runs-on + timeout-minutes 必須。macOS は使わない）

- [ ] **Step 2: commit** — `git commit -am "ci(popunder): Linux regen workflow (dispatch + source paths, timeout 5m)"`

### Task 12: analyze-popunder.js 常設化（allowlist 決定支援）

**Files:** Create `scripts/analyze-popunder.js`

- [ ] **Step 1:** 2026-06-17 の desktop 解析（headless Chrome + iPhone UA・window.open/gesture listener 計装・baseline/scoped 比較）を再利用可能な形で常設化。引数=サイトURL、出力=「遮断対象 third-party script ＋ 残すべき player/CDN（allowlist 候補）」。NODE_PATH に既存 playwright-core を使う旨を冒頭コメントに明記
- [ ] **Step 2:** README にツールの使い方（dogfooding で新サイトの allowlist を出す手順）を追記
- [ ] **Step 3: commit** — `git commit -am "tool(popunder): add analyze-popunder.js for allowlist discovery (dogfooding)"`

### Task 13: 陳腐化 README 修正

**Files:** Modify `tasks/b-popunder-script/README.md`

- [ ] **Step 1:** 「v3.3.0 配線TODO（未着手・次セッションの焦点）」を「**build22 で出荷済み**。v3.3.0 = 強化（L1拡充 + L2 アグレッシブ + CDN更新）」に修正。実装内容（ジェネレータ/L2/CDN/analyze ツール）へのポインタ追加
- [ ] **Step 2: commit** — `git commit -am "docs(popunder): fix stale README (PopunderBlockerExtension shipped in build22)"`

---

## 完了条件（Definition of Done）
- [ ] Chunk 1-2: pytest 全 pass・再生成物 bundle/cdn 一致・L1 等価回帰緑
- [ ] Chunk 3: `xcodebuild build` 成功・version 同期 opt-out テスト pass・シミュレータ起動でクラッシュ無し＋本体「最終更新」表示維持
- [ ] Chunk 4: workflow timeout 有り・analyze ツール動作・README 現状化
- [ ] feature ブランチ `feat/v33-popunder-aggressive` に全コミット・handoff 記載

## kureho 起床後に残す判断（自律でやらない）
- version bump（project.yml）+ ビルドアップロード + 審査提出（**提出は kureho 判断・自律では一切やらない**）
- main へのマージ（feature ブランチを review 後に kureho が merge）
- 新サイトの追加収録（dogfooding・kureho が踏んだサイト）
