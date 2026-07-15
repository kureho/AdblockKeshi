# 広告消し v4.0 転換リリース 提出ランブック（kureho 最小手順）

**目的**: ¥500 買い切り → 本体無料 + Pro IAP ¥800（アプリ内広告ブロック）への転換提出。
**不可逆**（無料化は実質戻せない）+ Apple 審査あり。準備は全部済（採番 build 10000/4.0.0・metadata・LP 下書き・E2E 合格）。

**分担**: ASC への書き込み（IAP作成・アップロード・提出）は Claude の安全ガードでブロックされるため kureho が実行（`!` or Web UI）。Claude は準備・スクリプト・確認を担当。

---

## ✅ ① IAP 作成 = Claude が API で完了済み（2026-07-15）
`com.kureho.adblockkeshi.pro`（id=6791059609）・NON_CONSUMABLE・**¥800**・ja/en 説明・
175地域配信・審査スクショ（1242x2208・COMPLETE）→ **state=READY_TO_SUBMIT**。
※ 初回IAPは版と同時に審査へ回るため、下記④の提出で version と一緒に submission items に含める。
※ kureho の Web UI 作業は不要だった（全て API で完結）。

## kureho がやること（残り）

### ③ ビルドのアップロード（`!` 一発）
Claude が Archive を作成 → kureho が以下を実行:
```
! <Claude が渡す upload コマンド>
```

### ④ 提出（`!` 一発・Claude の最終確認後）
Claude が submitting-ios-build の Phase1-5 監査 + precheck ログを済ませ、Phase4 で「これで提出します」確認 → kureho が:
```
! <Claude が渡す submit コマンド>
```
※ **手動リリース（Pending Developer Release）** 選択・**Phased Release オフ**・**評価リセット絶対に選ばない**

### ⑤ 承認後（Apple から approved 通知が来たら）
Claude が誘導:
1. **即時価格変更で ¥0（無料）に** → 実機ストアで ¥0 確認 → 分単位で「このバージョンをリリース」（深夜帯）
2. app-support LP を deploy（`v4-freemium-lp-draft` を main へ → `vercel --prod`）
3. 4点監査 + 新規/既存購入者の Pro 判定を実機確認 + 数日レビュー監視

---

## 審査ノート（英語・reviewNotes に貼る・Claude 下書き）

```
This update transitions the app from a paid download to a free download with a
one-time (non-consumable) in-app purchase.

- Free: the existing Safari Content Blocker features (ad blocking + anti-phishing).
- Non-consumable IAP "In-App Ad Blocking" (com.kureho.adblockkeshi.pro): a local
  on-device DNS content filter (NEPacketTunnelProvider) that reduces ads in other
  apps and Safari. All DNS filtering happens on-device; no browsing data is sent to
  our servers. Upstream DNS is Cloudflare (1.1.1.1). No account is required.

- The app's price will be changed to Free before this version is publicly released.
- Existing paid customers are automatically granted the Pro entitlement permanently
  ("grandfathering"). This legacy grant is intentionally DISABLED in the review /
  sandbox environment so that the full purchase and restore flow is visible to the
  reviewer.

To test the IAP:
1. Open the app, tap "アプリ内広告ブロック" (In-App Ad Blocking).
2. On the paywall, tap the purchase button. (Restore is always available.)
3. After purchase, toggle it on. iOS will ask to allow a VPN configuration
   (this is the local on-device DNS tunnel — no external VPN server). Allow it.
4. Browse in another app or Safari; common ad domains are blocked.

Note: YouTube / X / Instagram / some games' in-app ads cannot be blocked by design
(disclosed in the UI and description).
```

---

## Claude 側の残タスク（提出前）
- [ ] Paywall 審査スクショ生成 → kureho へ
- [ ] 4.0.0 Archive 作成（ローカル）
- [ ] upload / submit の `!` スクリプト用意
- [ ] submitting-ios-build Phase1-5 監査 + precheck ログ
- [ ] App Privacy 確認（DNS/VPN は端末内処理で新規データ収集なし・NE 追加の申告要否を確認）
