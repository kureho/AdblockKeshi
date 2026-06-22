# 広告消し (AdblockKeshi)

iOS Safari Content Blocker。「アドブロック」を知らない層向けのシンプル極限プロダクト。

- spec: `~/claude/docs/superpowers/specs/2026-05-30-adblock-design.md`
- plan: `~/claude/docs/superpowers/plans/2026-05-30-adblock-keshi-plan-a-mvp.md`

## ビルド

```bash
xcodegen generate
open AdblockKeshi.xcodeproj
```

## テスト

```bash
# Swift（ユニット + WebKit Content Rule List コンパイル）
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# ルール生成（Python）
python3 -m pytest scripts/tests/test_build_popunder_rules.py -q

# 強力モード判定エンジン / 登録計画（Node）
node --test PopupShieldExtension/Tests/*.test.js

# 強力モードの決定論 fixture（headless Chrome・iOS17 を忠実モデル化）
NODE_PATH="$HOME/.npm/_npx/<hash>/node_modules" \
  node PopupShieldExtension/Tests/fixtures/run-fixture.js
```

## ポップアップ広告対策（2 層）

動画/ファイルホスト系サイトの「タップ乗っ取り（tab-under）」に 2 層で対応する。

1. **ポップアップ広告対策（Content Blocker・`PopunderBlockerExtension`）** — 既知広告網の $script ブロック（L1）と
   対象サイトの third-party script 全ブロック（L2）。`scripts/build_popunder_rules.py` で
   `popunder-rules.json`（bundle + CDN）を生成。第三者 script 由来の広告に有効。
2. **強力ポップアップ対策（Safari Web Extension・`PopupShieldExtension`・任意/既定オフ）** — 静的ルールでは
   止められない「サイト本体の first-party `window.open` によるタブ乗っ取り」を、MAIN-world content script で
   cross-site のプログラム的遷移だけを止めて抑止する。詳細は `tasks/streamtape-hardening/`（再現調査・設計・実測検証）。

ルール再生成:

```bash
python3 scripts/build_popunder_rules.py \
  --networks tasks/b-popunder-script/popunder-script-networks.txt \
  --sites tasks/b-popunder-script/popunder-aggressive-sites.json \
  --out PopunderBlockerExtension/Resources/popunder-rules.json \
  --out docs/cdn/popunder-rules.json
```
