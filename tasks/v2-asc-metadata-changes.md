# AdblockKeshi v2.0 ASC Metadata 改訂計画

提出時に App Store Connect で以下に置換する。
**pricing_metadata_strict 厳守**: ¥/Free/無料/割引は **description のみ** 許容、subtitle / keywords / promotional_text / screenshots には絶対に入れない。

---

## App Information

### name（30 字以内）
変更前: `広告消し - 広告ブロック・アドブロック`（18 字）
変更後: `広告消し - 広告ブロック・詐欺サイトブロック`（21 字）

### subtitle（30 字以内・¥/無料/割引 NG）
変更前: `広告をすっきり消す。設定1分。`
変更後: `広告と詐欺サイトを、すっきり消す。`

### keywords（100 bytes 以内・¥/無料/割引 NG）
変更前（推定）: `広告,消す,ブロック,Safari,うざい,ポップアップ,全画面,オフ,ストップ,シンプル,簡単,設定不要,ノー広告,広告なし`
変更後候補: `広告,消す,Safari,うざい,詐欺,フィッシング,セキュリティ,マルウェア`

**Byte count 確認手順**（提出前に必ず実行）:

```bash
python3 -c "
kw = '広告,消す,Safari,うざい,詐欺,フィッシング,セキュリティ,マルウェア'
print(f'bytes={len(kw.encode(\"utf-8\"))}, chars={len(kw)}')
"
```

→ 100 bytes 以下を確認してから ASC に登録。超過時は短い token から削減。

### promotional_text（170 字以内・¥/無料/割引 NG）
候補: `v2.0 で詐欺サイトブロックを追加。広告と詐欺サイトを、買い切りでまるごとブロック。設定は最初の 1 回だけ。`

---

## description（¥/無料/割引 OK 領域）

既存 description の末尾に以下を追加:

```
—— v2.0 で追加 ——
詐欺サイトブロック機能を、買い切り価格 ¥500 にそのまま同梱。
追加課金・サブスクリプションは一切ありません。

・既知の詐欺サイト・フィッシングサイトをブロック
・マルウェア配信サイトをブロック
・データは週次で自動更新
・誤検知時はアプリ内トグルで詐欺サイトブロックを OFF にできます

—— ブロックできるもの・できないもの（v2.0 更新） ——
ブロックできる: Webサイトに表示される広告、追跡トラッカー、既知の詐欺・フィッシングサイト、マルウェア配信ドメイン
ブロックできない: X / YouTube / LINE 等のアプリ内広告、他のWebブラウザ、未知/新規の詐欺サイト

—— 使用データ ——
・EasyList / EasyPrivacy（CC-BY-SA-3.0）
・AdGuard Base / Japanese / Annoyances（GPL-3.0）
・URLhaus（abuse.ch・CC0 1.0）— マルウェア配信ドメイン
・Phishing.Database（Mitchell Krog・MIT）— フィッシングサイトデータベース
```

---

## What's New（v2.0 release notes・170 字以内）

候補: `詐欺サイト・フィッシングサイトのブロック機能を追加しました。アプリのトグルで広告ブロックと詐欺サイトブロックを独立に ON/OFF できます。価格は ¥500 のまま、買い切りで両方ご利用いただけます。`

---

## Review notes（reviewNotes）

```
v2.0 changes:
- Added anti-phishing / malware site block as a built-in feature (no additional IAP).
- Single Content Blocker extension now serves 4 rule variants based on user toggles
  in the main app screen (ad ON/OFF × security ON/OFF).
- Filter data sources: URLhaus (CC0 1.0) + Phishing.Database (MIT).
  Attribution in Acknowledgements ("このアプリについて") screen.
- No new entitlements required, no new API or framework.
- No new permissions, no data collection, no IAP, no subscription.

To verify in review:
1. Install app, complete onboarding.
2. Open Safari → 設定 → 機能拡張 → 広告消し を ON.
3. Return to app, main screen shows 2 toggles: 広告ブロック / 詐欺サイトブロック.
4. Both toggles default ON.
5. Toggle changes persist across app restart and apply to Safari immediately.
```

---

## Screenshot 改訂

既存 5 枚は維持（v1.0.x スクショ）。
追加候補 1 枚: 「広告 + 詐欺サイト、2 つのブロック」アプリトップ画面（2 トグル UI が見えるスクショ）。
**注意**: スクショ内のテキストオーバーレイには ¥ / 無料 / 割引 / "セール" を絶対に入れない（pricing_metadata_strict）。

---

## 4 点監査チェック（submission 後）

memory `feedback_apple_submission_state_audit.md` 準拠で以下 4 点確認:

- [ ] `reviewSubmissions` → WAITING_FOR_REVIEW
- [ ] `appAvailabilityV2` → territories 非空（既存配信地域維持）
- [ ] `appPricePoints` → ¥500 設定済
- [ ] IAP availability → 該当なし（買い切り）
