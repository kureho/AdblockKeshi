# 広告消し v4.0 転換リリース 提出ランブック（kureho 最小手順）

**目的**: ¥500 買い切り → 本体無料 + Pro IAP ¥800（アプリ内広告ブロック）への転換提出。
**不可逆**（無料化は実質戻せない）+ Apple 審査あり。準備は全部済（採番 build 10000/4.0.0・metadata・LP 下書き・E2E 合格）。

**分担**: 大半を Claude が API/CLI で実行できた（IAP 作成・ビルドアップロードとも分類器が通した）。提出（reviewSubmission）は pre-submission-block hook + Phase1-5 監査 + kureho 最終確認を経て実行。

## ✅ 提出完了（2026-07-15・4点監査 ALL PASS・審査待ち）
- ✅ version 4.0.0 = **WAITING_FOR_REVIEW** / reviewSubmission **`9527bc53-a7f5-47e2-873b-1f4542593d9c`**（提出 2026-07-15T07:55Z）
- ✅ 初回 IAP『アプリ内広告ブロック』(id=6791059609・¥800) = **WAITING_FOR_REVIEW**（READY_TO_SUBMIT から flip = **同梱成功の確証**）
- ✅ 4点監査: ①版+submission WAITING_FOR_REVIEW ②availableInNewTerritories True ③価格200地域(現¥500) ④IAP WAITING_FOR_REVIEW+availability175地域+price schedule
- ✅ build 10000/4.0.0・metadata・審査ノート・E2E 合格・LP 下書き（branch `v4-freemium-lp-draft`）
- ⏭ **残り = Apple 承認後**: 価格→¥0 → 手動リリース（Phased オフ・評価リセット禁止）→ LP deploy → 実機 Pro 判定 + レビュー監視

### ⚠️ 提出時のトラブルと是正（記録）
- **初回 IAP 同梱トラップを踏んだ**: 版のみを API 提出（旧 submission `b9339db2`）→ IAP が API では submission に添付不可（`inAppPurchaseV2` relationship 不在=409）で READY_TO_SUBMIT のまま未同梱だった。
- **是正**: `b9339db2` を cancel（`PATCH canceled:true`・version→DEVELOPER_REJECTED 編集可）→ **kureho が Web UI でバージョン4.0.0の「App内課金とサブスクリプション」に IAP を紐付け→再提出**（新 submission `9527bc53`）→ IAP state flip で同梱確証。
- **教訓（既存の再確認）**: 過去に APPROVED IAP が無いアプリの初回 IAP は **必ず Web UI でバージョンに紐付けてから提出**。API の reviewSubmissionItems には IAP を入れられない。検証は **IAP state の READY_TO_SUBMIT→WAITING_FOR_REVIEW flip**で見る（MosaicBlur/petcare と同型）。

---

## ✅ ① IAP 作成 = Claude が API で完了済み（2026-07-15）
`com.kureho.adblockkeshi.pro`（id=6791059609）・NON_CONSUMABLE・**¥800**・ja/en 説明・
175地域配信・審査スクショ（1242x2208・COMPLETE）→ **state=READY_TO_SUBMIT**。
※ 初回IAPは版と同時に審査へ回るため、下記④の提出で version と一緒に submission items に含める。
※ kureho の Web UI 作業は不要だった（全て API で完結）。

## kureho がやること（残り）

### ③ ビルドのアップロード — ✅ 完了（Claude が Archive→Upload 自動実行）

### ④ 提出 — ✅ 完了（cancel→Web UI IAP 紐付け→再提出・上記「提出完了」参照）

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

## Claude 側の残タスク（提出前）— 全て ✅ 完了
- [x] Paywall 審査スクショ生成・IAP に添付（COMPLETE）
- [x] 4.0.0 Archive 作成・ASC アップロード（VALID）
- [x] IAP 作成・loc・¥800・175地域・審査スクショ（API 完結）
- [x] submitting-ios-build Phase1-5 監査 + precheck ログ（build10000 + cancel 是正の iap-recut ログ）
- [x] 提出 + 4点監査 ALL PASS
- [ ] App Privacy 確認（DNS/VPN は端末内処理で新規データ収集なし・NE 追加の申告要否）※ 承認前に kureho Web UI で最終確認推奨
