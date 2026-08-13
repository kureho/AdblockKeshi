# 広告消し v4.1.0 / build 10100 提出準備（2026-08-13）

D-lite（報告機能の再設計）のクライアント版。サーバ側は**同日 21:36 に本番反映済み**
（Workers Version `43541612` / migration `0012` / 経緯は memory `project_adblockkeshi`）。

## build

- `4.1.0` / `10100`。**番号の根拠** = `1` + minor(2桁) + patch(2桁)。4.0.0→10000 / 4.0.3→10003 の実測パターンに一致し、単調増加も満たす
- テスト **352 tests / 0 failures / 7 skipped**（`-only-testing:AdblockKeshiTests`・iPhone 17 Pro）。
  8/11 時点の 341 から増えているのは `44d87d0` / `f49fad9` / `adb0488` で追加された分
- Archive → 署名 → TestFlight アップロードまで完了。**deploy した Worker と同じ commit（`dlite` HEAD）から作った**ので
  `contracts/submit-request.json` の契約は両側で一致する

## 🔴 description の修正 2 箇所（4.1.0 で事実でなくなるので必須）

live（4.0.3）の ja description には、4.1.0 の挙動と食い違う記述が 2 つある。
**live 版は 409 で編集不可なので、4.1.0 の localization で直す**。

| 行 | 現行（4.0.3） | 4.1.0 で不正確になる理由 |
|---|---|---|
| L11 | 報告した広告ドメインは、**その端末で即ブロック対象に**。日本のアプリに強い、育つフィルタです。 | 自己報告ファストレーンを**完全廃止**した（`SelfReportApplier` / `ReportedRuleBuilder` / `appendSelfRule` を削除、起動時に `purgeSelfRules()`）。報告しても端末側では即ブロックされない |
| L23 | 報告タブから送信されるデータは、**URL とメモのみ**。 | 診断 5 項目（表示面 / ブロッカー有効 / DNS 有効 / アプリ版・build / フィルタ版）を best-effort で添付する |

### 修正案

```
L11: 報告は検証を経てフィルタに反映されます。日本のアプリに強い、育つフィルタです。

L23: 報告タブから送信されるデータは、URL とメモ、および改善に使う診断情報
     （どの画面で見たか・保護の有効状態・アプリとフィルタのバージョン）のみ。
```

L24「閲覧履歴・氏名・連絡先・位置情報は一切送信しません」は**そのまま維持できる**（診断 5 項目にどれも含まれない）。
L18「自動検証を経て、Safari のフィルタにもアプリ内広告ブロックにも反映されます」も維持（サーバ集約 → CDN 配信の経路は不変）。

## whatsNew 案（ja）

```
・報告の仕組みを見直しました。報告は「ブロック対象の指定」ではなく、フィルタを改善するためのデータとして扱います。報告したページがそのままブロックされることはなくなりました。
・報告時に、改善に使う診断情報（どの画面で見たか、保護の有効状態など）を添付するようにしました。
・保護が必要なドメインを報告したときの扱いを改善しました。
```

## reviewNotes 案

```
v4.1.0 の変更点は報告機能の再設計です。

1. 報告の位置づけを変更しました。従来は報告された URL のホスト名をその端末のブロック
   リストへ直接追記していましたが、この経路を完全に削除しました。報告はサーバ側で集約・
   検証したうえでフィルタへ反映されます。
2. 報告送信時に診断情報（どの画面で見たか / Safari 拡張の有効状態 / DNS 機能の有効状態 /
   アプリのバージョンとビルド / フィルタのバージョン）を任意添付します。個人を特定する
   情報、閲覧履歴、位置情報は送信しません。
3. サーバ側（Cloudflare Workers）は 2026-08-13 に対応版を配信済みで、旧バージョンの
   クライアントからの報告も引き続き受け付けます。

動作確認の手順:
- 「報告」タブを開き、任意の URL（例: https://example.com）を入力して送信すると、
  送信完了の表示が出ます。アカウント登録は不要です。
- 「アプリ内広告ブロック」は既存のアプリ内課金で、本バージョンでの変更はありません。
  未購入でも報告機能を含む他の機能はすべて利用できます。
```

## 提出前監査（skill `submitting-ios-build` Phase 2）

| # | 項目 | 判定 |
|---|---|---|
| ① | Entitlement bypass | PASS。`isPro = cache.isPro() OR hasPurchaseEntitlement`（`ProStore.swift:186`）。UserDefaults 直読みの抜け道ではなく grandfather 権利の永続化 |
| ② | Grandfather cutoff | PASS。`GrandfatherPolicy.swift` が `originalAppVersion` 欠落時の `originalPurchaseDate < cutoff` 救済まで持つ。4.0.x から不変 |
| ③ | reviewNotes | 上記案を投入する |
| ④ | App Review Information | 法人情報のみ（4.0.3 から継承。提出前に再確認） |
| ⑤ | contactPhone | 新 version 作成後に `patch_review_contact_phone.py --apply` を実行する（新 version は前版の値をコピーするため明示 PATCH が要る） |
| ⑥ | metadata 価格表記 | PASS。name / subtitle / keywords に価格表記なし。description の「ずっと買い切り。サブスク化しません」は価格の数値表記ではないので 4.0.x と同じ扱い |
| ⑦ | App Store name | PASS。`学習する広告消し - 消えない広告もブロック` = 22 字（30 字以内） |
| ⑧ | Copyright | 4.0.3 から継承（`© 2026 KUREHO`）。提出前に確認 |
| ⑨ | Content Blocker 同梱 | PASS。`Extension/Resources/ad-rules.json` 20MB / `merged-rules.json` 19MB / `security-rules.json` 3.4MB を**バンドル同梱**。`Extension/blockerList.json`（2 ルール・965B）は 4 通り動的選択の "empty" 用プレースホルダであってスタブ出荷ではない |
| ⑩ | PreAd モーダル | N/A。広告 SDK を積んでいない（`GoogleMobileAds` 参照 0 件） |
| ⑪ | IAP review screenshot | N/A。IAP は既存の Pro（APPROVED 済み）で本バージョンに変更なし |
| ⑫ | App Privacy | 診断 5 項目が増えるが、いずれも既存の申告区分（診断・製品の操作）の範囲。**提出前に ASC の App Privacy を実見して確認する** |
| ⑬ | SKAdNetworkItems | **N/A（別タスク・一次情報調査前）**。0 件だが、memory `project_adblockkeshi` が「❌ 確認前に一般的な ID 一覧を一括追加しない」と明示している。この build で触らない |
| ⑭ | revocationDate | PASS。`ProStore.swift:154` が `transaction.revocationDate == nil` を見ている |
| ⑮ | CKShare | N/A（CloudKit 共有なし） |
| ⑯ | CloudKit スキーマ | N/A |
| ⑰ | 初回 IAP 同梱 | N/A（Pro は既に APPROVED） |
| ⑱ | socialMedia 宣言 | 新 version 作成後に `patch_social_media_declaration.py 6774906945` を実行する |

### Phase 2.5（sim-blind path）

変更点はネットワーク経路（報告送信）。**契約ファイル `contracts/submit-request.json` を iOS
（`Tests/SubmitContractTests.swift`）と workers（`tests/handlers/submit-contract.test.ts`）の
両方が読む**設計で、片側だけキー名を変えると必ず落ちる。構造テストで担保済み＝実機不要。

⚠️ **ただし本番エンドポイントの実挙動は未検証**。deploy 後に確認したのは D1 側（スキーマ・件数・
status 分布）だけで、新 `submit.ts` が本番で正しく応答することは確かめていない。合成リクエストを
送ると prod D1 に書き込むうえ、kureho 端末からだと `TRUSTED_UUID_HASHES` バイパスに乗るため、
検証手段として選ばなかった。`npx wrangler tail adblockkeshi-reports` で実トラフィックを観測するのが
非侵襲な代替。

### Phase 3（今日ほかに同種対応が必要なアプリ）

なし。今日提出したちりつも 1.14.0 は無関係な変更（UIUX 監査 27 件）で、本件と束ねる対象ではなかった
（着手時点で広告消しは Workers deploy 待ちで動かせなかった）。

## 🔴 評価リセット（この版が最後のチャンス・不可逆）

memory `project_adblockkeshi` が 4.0.3 について「**評価リセットは設定しない（この版では見送り・
D-lite 版で実施）**」と記録している＝**4.1.0 が実施予定の版**。

**実測（2026-08-13）**:

- 全体 **3.67★ / 3 件**（現バージョンも同数）
- うち**本文付きは 1 件だけ**: ★5「報告で改善されるのが良い」(2026-06-11)
- 残り 2 件は**星だけ**（合計 6 = 平均 3.0）。これが 5.0 を 3.67 へ押し下げている

**判断材料**（memory `reference_app_store_rating_reset`）:

- リセットしても**文章レビューはカードとして残る**＝★5 のレビューは消えない。数値だけがゼロになる
- 「総評価数が少なく、価値ある評価が文章レビュー側にある → リセット推奨（代償ほぼゼロ）」に**該当する**
- 代償 = 評価数 3 → 0。Apple は「評価数が少ないと DL の妨げになる」と明記している
- **効くのは満足度ゲートとセットの場合のみ**。広告消しはレビュー依頼施策 v2 の対象 10 本に入っている＝条件は満たす
- **API 不可・Web UI のみ**（ASC → 対象バージョン → 「概要評価のリセット」→「このバージョンのリリース時に評価をリセット」→ 保存）
- **次バージョンのリリース時に発動**するので、**4.1.0 を提出する前に設定しないと 4.1.0 では発動しない**

→ **kureho の判断が要る**（不可逆・全地域同時）。

## 残手順

1. build 10100 の processing 完了を待つ
2. ASC に 4.1.0 の version を作成（`releaseType` は 4.0.1〜4.0.3 と同じ `AFTER_APPROVAL`）
3. build 10100 を attach
4. ja localization に **修正済み description** + whatsNew を投入
5. reviewNotes 投入 → `patch_review_contact_phone.py --apply` → `patch_social_media_declaration.py`
6. 🔴 **評価リセットの設定**（kureho 判断・Web UI）
7. URL 監査（`audit_asc_urls.py`）
8. Phase 4（kureho に確定確認）→ Phase 5（precheck ログ）→ submit → 4 点監査
