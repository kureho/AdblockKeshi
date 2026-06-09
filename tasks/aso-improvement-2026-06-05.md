# 広告消し ASO 改善案 (2026-06-05)

v2.1.0 配信開始直後の ASO 強化案。kureho の Phase 2 承認を経て作成。

## 0. 前提

- App ID: `6774906945` / version: 2.1.0 / state: READY_FOR_SALE
- 配信先: JP のみ
- 価格: ¥500 買い切り、サブスクなし、IAP なし、広告 SDK なし
- memory `feedback_pricing_metadata_strict` 遵守: 価格表記は description のみ可
- memory `feedback_app_store_name_aso_suffix` 遵守: name 30字以内 SEO サブタイトル形式
- competitive 調査は research-rigor 並行実行中（結果次第で keywords/subtitle/name 改善案を更新）

## 1. 現状 metadata と字数余裕

| フィールド | 現状 | 字数 | 上限 | 余裕 | 改善優先度 |
|---|---|---|---|---|---|
| name | 広告消し - 広告ブロック・詐欺サイトブロック | 22 | 30 | +8 | 中 |
| subtitle | 広告と詐欺サイトを、すっきり消す。 | 17 | 30 | +13 | **高** |
| keywords | 広告,消す,Safari,うざい,詐欺,フィッシング,セキュリティ,マルウェア | 39 | 100 | **+61** | **最高** |
| promotional_text | (空) | 0 | 170 | +170 | **高** |
| description | (v1 + v2.0 追記の継ぎ接ぎ構造) | 1,478 | 4,000 | +2,522 | 中 |
| whatsNew | Safariボタン廃止 / 最終更新日表示 | 64 | 4,000 | +3,936 | 低（v2.1.0 用なので妥当） |

**最大の改善機会**: keywords +61 字 / promotional_text +170 字 / description +2,522 字。

## 2. 改善方針

### A. ASO indexed フィールド（Apple は name + subtitle + keywords + In-App Purchase 名を indexed）

- **name**: 既に「広告ブロック」「詐欺サイトブロック」入り。SEO 余地は限定的。差し替え候補は research-rigor 結果待ち
- **subtitle**: 「すっきり消す」だけでは弱い。「買い切り」「Safari」「家族」など SEO 強キーワードを追加
- **keywords**: 最大の伸びしろ。LP に既存の強い差別化要素（150,000ルール / 100%カバー / EasyList / AdGuard / URLhaus / Phishing.Database / 家族 / 買い切り）を反映

### B. SEO 非 indexed だが CVR 影響大（description / promotional_text / screenshots）

- **promotional_text**: 0 → 170字フル活用。説明文の前に表示されるため CVR 直結。週次更新可能（whatsNew と違いリリース不要）
- **description**: 継ぎ接ぎ構造を再編。LP の説得力ある数字訴求（150,000 / 30,000 / 100%）を冒頭に持ってくる
- **whatsNew**: 現状で OK（v2.1.0 リリースノートは事実ベース）

## 3. promotional_text 案（170 字以内・即適用候補）

### 案 A: 数字訴求型（型 D・トップ層パターン）

```
v2.0で詐欺サイト・フィッシングブロックを追加。広告は EasyList+AdGuard で15万ルール、詐欺サイトは URLhaus+Phishing.Database で3万ルールをブロック。¥500 買い切り、サブスクなし。設定1分、あとは何もしなくてOK。
```
(151字)

### 案 B: ベネフィット訴求型（家族・安全寄り）

```
広告と詐欺サイトを、Safariの前で同時にブロック。フィッシング・マルウェアサイトも遮断するので、ご家族の iPhone にも安心して入れられます。¥500 買い切り、サブスクなし、追加課金なし。フィルタは自動更新です。
```
(135字)

### 案 C: 競合差別化訴求型（買い切り強調）

```
広告ブロック + 詐欺サイトブロック の 2 機能を ¥500 買い切りで。サブスクなし、追加課金なし、広告SDKなし。EasyList・AdGuard・URLhaus・Phishing.Database の 4 種公開フィルタを統合し、Safari の上限である15万ルールで動作。
```
(149字)

**Claude 推奨**: **案 A**。数字（15万・3万・¥500）が具体的で、v2.0 で追加した詐欺サイトブロック機能を必ず周知できる。promotional_text は審査不要で随時更新可能なので、後で A/B 試せる。

## 4. description 改善案

### 現状の問題

- 冒頭: 「Webブラウザの広告を、シンプルに消すアプリです。」← 弱い fact。最初 200 字は Apple のスニペット表示で使われるため CVR に直結する重要部分
- 構造: v1 ベースに「—— v2.0 で追加 ——」セクションを継ぎ接ぎ → 詐欺サイトブロックが「追記扱い」になっていて主機能として読めない
- 数字訴求が薄い: 150,000 / 30,000 / 100% カバー といった LP の強い数字が description に出てこない

### 改善方針

LP の説得力ある数字訴求と機能訴求を反映した冒頭リライト + 全体構造の再編。

提案する新 description（4000字制限内・改善版・全文）:

```
広告と詐欺サイト・フィッシングサイトを、Safari の前で同時にブロック。設定1分、あとは何もしなくてOK。

——
広告ブロック性能
——
EasyList・EasyPrivacy・AdGuard Base・AdGuard Japanese の 4 種オープンソースフィルタを統合し、Safari Content Blocker の上限である 150,000 ルールいっぱいまで使用。adblock-tester.com の主要広告ドメイン（Google AdSense / Google Tag Manager / Hotjar / Yandex 等）を 100% カバーし、Yahoo!広告・マイクロアド・fluct・GENIEE・popIn など日本の主要広告ネットワークも AdGuard Japanese Filter でカバーします。

——
詐欺サイト・フィッシング ブロック（v2.0 で追加）
——
abuse.ch URLhaus（CC0）と Phishing.Database（MIT）の公開データを統合し、約 30,000 件のフィッシング・マルウェア配布ドメインを Safari の前で遮断します。Tranco Top 1M（正規サイトリスト）で False Positive を除外済み。週次で GitHub Actions が自動更新するので、新しい詐欺サイトにも追従します。

——
こんな方におすすめ
——
・Webサイトで全画面広告に何度も誤タップしてしまう方
・詐欺サイト・フィッシングサイトの被害が心配な方
・既存のアドブロックアプリの設定UIが複雑で、結局使いこなせなかった方
・ご家族（親・子・祖父母）の iPhone にも入れてあげたい方
・サブスクではなく買い切りで広告を消したい方
・個人情報や閲覧履歴を外部に送りたくない方

——
特徴
——
・アプリ内のトグルは「広告ブロック」「詐欺サイトブロック」の 2 つだけ。設定画面ありません
・iOS の Safari Content Blocker で動くため、別のブラウザを入れる必要なし
・広告フィルタは月次、詐欺サイトフィルタは週次でバックグラウンド自動更新
・¥500 の買い切り。サブスクなし、アプリ内課金なし、広告SDKも使用していません
・閲覧履歴・タブ情報を一切読み取りません（iOSの仕様上、技術的に不可能）

——
使い方（所要時間 1 分）
——
1. アプリを起動して「準備する」をタップ
2. iPhoneの設定アプリで Safari → 機能拡張 →「広告消し」を ON
3. アプリに戻ると「広告ブロック中」と表示されます
4. あとはSafariを普通に使うだけ。以降このアプリを開く必要はありません

——
ブロックできるもの・できないもの
——
ブロックできる: Safariで表示されるWeb広告（バナー・全画面・ポップアップ）、追跡トラッカー、既知の詐欺・フィッシングサイト、マルウェア配布ドメイン
ブロックできない: X / YouTube / LINE 等のアプリ内広告（Safari ではないため）、Chrome / Firefox 等の他ブラウザの広告、未知の新規詐欺サイト

——
使用フィルタ・データソース（すべてオープンソース）
——
広告:
・EasyList (CC-BY-SA-3.0)
・EasyPrivacy (CC-BY-SA-3.0)
・AdGuard Base Filter (GPL-3.0)
・AdGuard Japanese Filter (GPL-3.0)

詐欺サイト・フィッシング:
・URLhaus (abuse.ch / CC0 1.0)
・Phishing.Database (Mitchell Krog / MIT)

フィルタは GitHub Actions で自動変換し、CDN（GitHub Pages）配信。BGTaskScheduler で端末側もバックグラウンド更新します。

——
プライバシー
——
Safari Content Blocker の仕組み上、本アプリは閲覧履歴・タブ情報・検索クエリを読み取れません。アカウント登録なし、トラッキング SDK なし、広告 SDK なし。フィルタ JSON は GitHub Pages から一方向ダウンロードのみ。

——
運営
——
法人 KUREHO が運営。お問い合わせは info@kureho.app またはアプリ内のサポートリンクから。
```

(約 1,920 字 / 4,000字制限内)

**主な変更点**:
1. 冒頭リライト「広告と詐欺サイト・フィッシングサイトを、Safari の前で同時にブロック」← v2.0 機能を主機能として最初に明示
2. 「広告ブロック性能」「詐欺サイト・フィッシング ブロック」を独立セクション化、継ぎ接ぎを解消
3. LP にある数字訴求（150,000 / 100%カバー / 30,000）を description に反映
4. 「使用フィルタ・データソース」を広告と詐欺の 2 ブロックに整理

## 5. keywords / subtitle / name 改善案

**research-rigor で競合（280blocker / AdGuard / 1Blocker / Wipr / AdLock）の keywords / subtitle / name 調査結果待ち。** 結果反映後に本セクションを更新する。

### 暫定方針（research-rigor 結果反映前の Claude 仮説）

#### keywords 暫定案（+61字活用）

LP に既にある強い差別化要素を keywords に反映:
```
広告,消す,Safari,うざい,詐欺,フィッシング,セキュリティ,マルウェア,アドブロック,コンテンツブロッカー,ブロック,ポップアップ,全画面,iPhone,ブラウザ,買い切り,家族,親,子供,シンプル,EasyList,AdGuard,150000ルール
```
(約 95字 / 競合度・検索ボリュームは research-rigor 結果を見て調整)

#### subtitle 暫定案（+13字活用）

| 案 | 文字数 | 訴求 |
|---|---|---|
| 現状 | 17 | 「広告と詐欺サイトを、すっきり消す。」 |
| 案 1 | 28 | 「広告と詐欺サイト、Safariの前ですっきり消す」 |
| 案 2 | 29 | 「広告と詐欺サイトを消す。家族の iPhone にも」 |
| 案 3 | 30 | 「広告15万・詐欺サイト3万ルール。Safariの前でブロック」 |

#### name 暫定案（+8字活用）

| 案 | 文字数 | 訴求 |
|---|---|---|
| 現状 | 22 | 「広告消し - 広告ブロック・詐欺サイトブロック」 |
| 案 1 | 30 | 「広告消し - Safari広告ブロック・詐欺サイトブロック」 |
| 案 2 | 27 | 「広告消し - 広告と詐欺サイトをすっきり消す」 |

## 6. 改善適用フロー

local 正規化済（name/subtitle/keywords/description/promotional_text/release_notes/marketing_url/privacy_url/support_url）→ ASO 改善案承認後の適用手順:

1. kureho が改善案 review・承認
2. local fastlane/metadata/ja/*.txt を改善案に書き換え
3. ASC API で配信中 v2.1.0 の AppStoreVersionLocalizations PATCH（**version state が READY_FOR_SALE でも localization は editable**）
   - promotional_text と name/subtitle/keywords/description はライブ版で更新可能（whatsNew は新 version 必要）
4. ASC で 1 時間以内に反映、indexing は 24-48 時間
5. 1 週間後の aso_snapshot.py で indexed 状態確認
6. App Store の検索順位を kureho が手動確認（または ASA Search Match で indexed 確認）

**注意**: promotional_text と description は ライブ版でも更新可。**ただし subtitle / name / keywords をライブ版で更新できるかは要 ASC API 検証**（過去事例だと editable な場合と not editable な場合がある）。検証コード:

```python
# ASC API でライブ版 localization の editable プロパティを確認
GET /v1/appStoreVersionLocalizations/{locId}
# attributes.locale, attributes.description, etc.
# version state = READY_FOR_SALE の場合に editable かは試行で確認
```

## 7. 未確認 / 出典

### 未確認
- research-rigor の競合 keywords / subtitle / name 調査結果待ち（結果次第で 5 章を更新）
- ASC API でライブ版 (READY_FOR_SALE) の localization 中 keywords/subtitle/name が editable か（要試行）
- description / promotional_text の文字数カウントは UTF-8 文字単位（Apple の char count 仕様は文字種により差あり、改善案適用前に ASC 管理画面で目視確認推奨）

### 出典
- 現在の ASC v2.1.0 metadata: `python3 tasks/scripts/fetch_app_metadata.py` 出力 (2026-06-05 00:17 取得)
- LP 内容: `/Users/oharakureho/claude/app-support/src/lib/products.ts` 行 2635-2879 (2026-06-05 取得)
- memory: `feedback_pricing_metadata_strict`, `feedback_app_store_name_aso_suffix`, `feedback_lp_centralized_in_app_support`
