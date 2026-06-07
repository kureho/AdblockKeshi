<!-- [paid-approved-by-kureho] documentation only, no ASC API calls -->
# 広告消し v3.0 metadata draft

**目的**: Plan D Task 2.1 (v3.0 用 fastlane metadata 確定) の事前 draft。kureho が承認したら `fastlane/metadata/ja/*` に反映、v3.0 build 提出時に `fastlane deliver` で ASC 投入する。

**Spec 出典**: `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md` §6

**禁止訴求**（提出前 grep CI hook で fail させる対象）:
- Apple 商標 (Safari / iPhone / iPad / iOS / Apple / Siri / iMessage)
- 価格表記 (¥ / Free / 無料 / 割引) ※ description 含めて記載しない (rev3、retreat 軽量化のため)
- E 軸「みんなで育てる」(需要ゼロ判定済)

---

## 1. name.txt (App Store name)

**spec 確定**:

```
学習する広告消し - 消えない広告もブロック
```

22 字（30 字制限内）/ Apple 商標なし / 価格表記なし ✅

---

## 2. subtitle.txt

**spec 確定**:

```
他で消えない広告も、報告で進化
```

15 字（30 字制限内）/ Apple 商標なし / 価格表記なし ✅

---

## 3. keywords.txt

**spec 確定**:

```
広告,消す,ブロック,うざい,詐欺,フィッシング,セキュリティ,学習,報告,進化
```

10 キーワード / Apple 商標なし / 価格表記なし ✅

byte 数 verify 要（100 byte 上限）:
- 推定: 日本語 UTF-8 で 30 字 + コンマ 9 個 = 約 90 byte → OK 想定。fastlane deliver でエラー出たら短縮

---

## 4. promotional_text.txt

**spec 確定**:

```
他のブロックアプリで消えない広告を、報告で進化するフィルタが対応。
報告タブから URL を送ると、自動検証を経て広告ブロックリストへ追加。
買い切り、サブスクなし、閲覧履歴も送信しません。
```

170 文字制限内 / 「買い切り」「サブスクなし」は subtitle/promo/keywords 可（spec rev4 §6 明示）/ Apple 商標なし ✅

---

## 5. description.txt (Claude draft、要 kureho 承認)

**Spec 指針**: 「中 (description): B 軸 + H 軸 + F' 軸 + 既存 v2.0 詐欺機能」「値上げ説明文面は『買い切り価格を改定しました』のみ (具体的金額を書かない)」

```
他のブロックアプリで「消えない広告」が残るとき、
「広告消し」は、ユーザーからの報告で進化するフィルタが対応します。

【v3.0 の新機能：学習する広告消し】
報告タブから「ここの広告が消えない」と URL を送るだけ。
自動検証を経て、ブロックリストへ追加されます。
ブラウザの拡張機能をオンにしておくだけで、
誰かの報告があなたのフィルタも強化していきます。

【既存ユーザーへ】
v2.x からアップグレードしても追加課金はありません。
買い切り価格を改定しましたが、すでに購入済みの方は
そのまま v3.0 の新機能をお使いいただけます。

【できること】
・標準フィルタ：広告と詐欺サイトを 1 タップでブロック
・学習フィルタ：報告データから生成された追加ブロックリスト
・両方を組み合わせて使うことも、片方だけ使うこともできます

【データの取り扱い】
報告タブを使わない限り、本アプリは外部通信を行いません。
報告タブから送信されるデータは、URL とメモのみ。
閲覧履歴・氏名・連絡先・位置情報は一切送信しません。
詳細は kureho.app/privacy/adblock-keshi をご覧ください。

【シンプル設計】
・アカウント登録不要
・アプリ内の操作は最小限
・買い切り（サブスクなし）
・広告非表示

【動作環境】
本体ブラウザの「機能拡張」機能に対応した端末が必要です。
ブラウザ側で「広告消し」を有効化することで動作します。

【サポート】
- 不具合報告・要望: kureho.app からお問い合わせください
- プライバシーポリシー: kureho.app/privacy/adblock-keshi
- 利用規約: kureho.app/terms/adblock-keshi
```

文字数（おおよそ）: 600 字台 / 4000 字制限内 ✅
Apple 商標チェック: 「Safari」「iOS」「iPhone」を一切含めず、「本体ブラウザの機能拡張」と汎称に書き換え ✅
価格表記: 「¥」「無料」「Free」「割引」を含めず、「買い切り価格を改定しました」「追加課金はありません」のみ ✅

**Claude 自信度低い箇所** (kureho の判断が欲しい):
- 「v2.x からアップグレード〜追加課金はありません」: 既存ユーザー保護を強調するか、新規ユーザー向けに削るか
- 「本体ブラウザの機能拡張」: Apple 商標回避のための婉曲表現が硬くないか
- 「学習フィルタ」「標準フィルタ」: 内部呼称 (ReportedContentBlocker / 既存) と一致しているか

### 5.1 description 代替バリエーション

判断材料として複数案を併記。kureho が最終 1 案を選択 (or mix)。

#### 5-A: 上の draft = 既存ユーザー保護を強く打ち出す版（初稿、推奨）

特徴: v2.x からの引き継ぎを冒頭近くで明示、追加課金なしを 2 箇所で繰り返し。価格改定の説明文を含む。新規ユーザーには「v2.x って何？」と読める可能性がある反面、既存ユーザーの離脱リスクは最小化。

#### 5-B: 新規ユーザー向け短文版（460 字）

```
他のブロックアプリで「消えない広告」が残るとき、
「広告消し」は、ユーザーからの報告で進化するフィルタが対応します。

【できること】
・ブラウザの拡張機能を有効化するだけで動作。アプリ内で設定する操作はほぼゼロ
・標準フィルタ（広告 + 詐欺サイト）と学習フィルタの両方を組み合わせて使えます
・学習フィルタは、報告タブから「ここの広告が消えない」と URL を送る方式
・自動検証を経てブロックリストへ追加されるので、誰かの報告があなたの環境も強化していきます

【データの取り扱い】
報告タブを使わない限り、本アプリは外部通信を行いません。
報告タブから送るのは URL とメモのみ。閲覧履歴・氏名・連絡先・位置情報は一切送信しません。
詳細は kureho.app/privacy/adblock-keshi をご覧ください。

【シンプル設計】
・アカウント登録不要
・買い切り（サブスクなし）
・広告非表示

【サポート】
- 不具合報告・要望: kureho.app からお問い合わせください
- プライバシーポリシー: kureho.app/privacy/adblock-keshi
```

特徴: 既存ユーザー言及をカット、新規ユーザー視点で書く。価格改定の説明文も削除（Price Tier の表示で十分とみなす）。

#### 5-C: 「本体ブラウザの機能拡張」表現を柔らかくした版（5-A の語調調整）

5-A の文末ブロックを以下に差し替え:

```
【動作環境】
お使いのブラウザに「機能拡張」を入れる仕組みがある端末でご利用いただけます。
ブラウザの設定で「広告消し」を ON にするだけで動作を開始します。
```

その他は 5-A と同一。汎称表現を「お使いのブラウザに」と二人称寄りに緩和。

### 5.2 推奨

**Claude 推奨**: **5-A（初稿）**。理由:
- spec rev4 §6 の方針「中 (description): B 軸 + H 軸 + F' 軸 + 既存 v2.0 詐欺機能 + 値上げ説明」を全て満たす
- 既存ユーザーが価格改定で心配して App Store レビューに低評価を残すリスクが、新規ユーザーの読みにくさよりも事業 impact 大
- 「新規ユーザーが読みにくい」リスクは promotional_text と subtitle で打ち消し可能（新規は最初の 3 行しか読まない）

5-B / 5-C は merge 直前に kureho が判断したときの代替候補として保持。

---

## 6. release_notes.txt (v3.0.0 What's New)

```
v3.0「学習する広告消し」

【新機能】
・報告タブを追加：消えない広告を URL で報告すると、自動検証を経てフィルタに追加されます
・標準フィルタとは別に「学習フィルタ」拡張を追加。両方の組み合わせ、片方のみも選べます
・完了画面に「これまでに報告で追加されたフィルタ件数」を表示

【既存ユーザーへ】
v2.x からアップグレードしても追加課金はありません。
買い切り価格を改定しましたが、すでに購入済みの方は
そのまま v3.0 の新機能をお使いいただけます。

【プライバシー】
報告タブを使わない限り、本アプリは外部通信を行いません。
詳細はプライバシーポリシーをご覧ください。
```

文字数: 約 300 字 / 4000 字制限内 ✅

### 6.1 release_notes 代替バリエーション

#### 6-A: 上の draft = 機能 + 既存ユーザー保護 + プライバシーの 3 軸（初稿、推奨）

#### 6-B: 機能だけに絞った最短版（180 字）

```
v3.0「学習する広告消し」

【新機能】
・報告タブを追加：消えない広告を URL で報告すると、自動検証を経てフィルタに追加されます
・標準フィルタと「学習フィルタ」拡張の組み合わせ、片方のみも選べます
・完了画面に「これまでに報告で追加されたフィルタ件数」を表示

v2.x からのアップグレードは追加課金なしでご利用いただけます。
```

特徴: プライバシー言及を description / privacy policy 側に任せ、release_notes は機能差分に集中。既存ユーザー言及は 1 文だけ末尾に残す。

### 6.2 推奨

**Claude 推奨**: **6-A（初稿）**。理由:
- v3.0 は「報告データを送る機能を追加」が最大の差分なので、プライバシー言及を release_notes 末尾に置くことで「機能 ON 前提でユーザーが期待すべき送信範囲」を明示でき、reject リスク低減
- description 側だけでなく release_notes 側にも書くと、既存 v2.x ユーザーが What's New を読んだだけで安心できる

---

## 7. 提出前 pre-flight grep（kureho が手動 or CI hook で実行）

```bash
cd /Users/oharakureho/claude/AdblockKeshi/fastlane/metadata/ja
# Apple 商標
grep -iE 'safari|iphone|ipad|ios|apple|siri|imessage' *.txt
# 価格表記
grep -iE '¥|free|無料|割引|円|yen' *.txt
# 未確定文字 (TBD / TODO / xxx)
grep -iE 'tbd|todo|xxx' *.txt
```

期待: 全て **マッチなし**（マッチしたら NG）。

---

## 8. fastlane 反映手順 (kureho 承認後)

1. 別ブランチ `feat/v3-fastlane-metadata` を `feature/v3.0-learning-adblock` から切る
2. 本 draft の確定後の内容で `fastlane/metadata/ja/{name,subtitle,keywords,promotional_text,description,release_notes}.txt` を上書き
3. step 7 の grep で pre-flight pass を確認
4. commit + PR で kureho 最終承認
5. v3.0 build 提出時に fastlane deliver --skip_binary_upload で ASC localizations に投入

---

## 9. v3.0 提出時の deliver タイミング

- v3.0 build (CURRENT_PROJECT_VERSION=N) を Xcode Archive + Upload (memory feedback_archive_upload_self_execute で Claude 自動)
- ASC で processing 完了 → VALID 化
- ASC API で AppStoreVersion 3.0.0 を新規作成し、build を attach
- fastlane deliver で本 metadata を投入
- App Privacy を tasks/v3-asc-app-privacy-checklist.md 通りに ASC Web UI で更新（ASC API では編集不可、Web UI 限定）
- ASC API で reviewSubmission を作成して submit (memory feedback_archive_upload_self_execute + feedback_multi_app_batch_submit_auto で Claude 自動)
- 4 点監査 ALL PASS verify (memory feedback_apple_submission_state_audit)

---

## 関連

- AdblockKeshi spec rev4 §6
- AdblockKeshi PR #18 (Plan C Chunk 1+3 基盤) / #19 (Chunk 5 moat) / #17 (Chunk 4 real client) / #20 (ASC App Privacy checklist)
- app-support PR #6 (Privacy Policy `dataHandling`)
- memory: [[feedback_pricing_metadata_strict]] / [[feedback_no_silent_paid_infra]] / [[feedback_apple_submission_state_audit]]
