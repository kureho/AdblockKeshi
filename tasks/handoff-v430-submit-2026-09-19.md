# 引き継ぎ: 学習する広告消し v4.3.0 / build 10302 の提出

- 作成: 2026-09-19（前セッションから引き継ぐための正典。チャットの文脈は無くてよい）
- 状態: **ASC 側の準備は完了。残るのは kureho の submit 承認 → 承認ログ → submit API の 3 手だけ**
- 台帳: `/Users/oharakureho/claude/tasks/remaining-tasks.md` の **A-74**（同内容が Artifact 版にも反映済み）

## 1. 何を出そうとしているか

| 項目 | 値 |
|---|---|
| アプリ名 | 学習する広告消し - 消えない広告もブロック |
| APP_ID | `6774906945` |
| bundle id | `com.kureho.adblockkeshi` |
| バージョン | `4.3.0` |
| appStoreVersion id | `9c3a77c6-a478-4ff9-830a-cc7eccbb7c63` |
| state | `PREPARE_FOR_SUBMISSION` |
| build | `10302`（id `adcdea13-d669-466c-9ba9-66ada3e8382d`・processingState VALID・attach 済み） |
| 課金商品 | `com.kureho.adblockkeshi.pro`（NON_CONSUMABLE・**APPROVED 済み**＝版との同梱は不要） |

★ build 10300 / 10301 は**使わない**（10300 は設定カードの CTA 修正前、10301 は購入画面の是正前）。

## 2. この版で直したもの（5 点）

1. **起動直後にアプリが終了する不具合の根治** — ブロックを一時オフにしているサイトがあると、起動時のルール再生成がバックグラウンドで WebKit を初期化して `SIGTRAP` で落ちていた。**配信中の 4.2.1 に入っている**。メインスレッドへ寄せて解消し、回帰テスト 2 本を追加。
2. **「設定」タブを新設** — 他 21 本と同じ形（課金カード / ブロックを止めているサイト / お問い合わせ / このアプリについて / バージョン）。広告・セキュリティの 2 トグルはこのアプリの主役なのでホーム画面に残したまま。
3. **起動時に Apple Account のサインインを求める回帰の根治** — 所有判定を端末キャッシュ優先へ。
4. **購入画面を 22 本共通フォーマットへそろえた**（2026-09-18 kureho「デザイン全然他と揃ってなくない？」）。直した 4 点 = 囲みが三重 →**囲みは購入ボタンだけ** / 閉じるが左上 →**右上** / シートが全画面固定 → `fittingSheetHeight()` で中身ぴったり / 見出し 20 字が助詞の途中で折り返し → 14 字 1 行。あわせてプライバシーポリシーのリンクを画面内に追加。
5. **課金導線の入口をブロッカー設定前の画面にも掲出** — 従来は有効化後の画面にしか入口が無く、入れたばかりの端末から辿り着けなかった（`ProEntryCard` として切り出し）。

正典 = `/Users/oharakureho/claude/tasks/paywall-redesign-2026-09-18.md`（22 本共通フォーマットの規則）。

## 3. 済んでいる提出前監査（skill `submitting-ios-build` Phase 1〜3）

**2026-09-18〜19 に実測。番号は skill のチェックリストに対応。**

| # | 項目 | 結果 |
|---|---|---|
| ① | 権利のすり抜け | OK（`-FORCE_PRO` は `#if DEBUG` の中だけ・RELEASE では常に false） |
| ② | 既存購入者の救済ライン | OK（`conversionBuild=10000` に対し新規は 10302 ≥ 10000・補助判定の `cutoffDate` 2026-09-01 も過去） |
| ③ | 審査メモ | 4.3.0 用に書き直して PATCH 済み（`audit_review_notes_version.py` で版番号一致・NG 0） |
| ④⑤ | 審査担当の連絡先 | 法人情報のみ（Kureho Support / info@kureho.app / +81753133700）。`patch_review_contact_phone.py --apply` 実行済み |
| ⑥ | メタデータの価格表記 | 0 件。★途中で更新履歴に「無料で使える範囲」と書いてしまい、**自分で見つけて「購入前に使える範囲」へ訂正済み**。ASC に入った実物を再 grep して 0 件を確認 |
| ⑦ | 名前 / サブタイトル | 22 字 / 15 字（30 字以内） |
| ⑧ | Copyright | `© 2026 KUREHO` |
| ⑨ | ブロックルールの同梱 | OK（拡張の中に ad-rules 21MB / merged 19MB / security 3.5MB） |
| ⑩ | PreAd モーダル | N/A（広告 SDK なし） |
| ⑪⑰ | 課金商品 | `APPROVED` 済み・下書きの置き去りゼロ（`audit_pending_iap_names.py` exit 0） |
| ⑫ | プライバシー | 収集なし・トラッキングなし。今回の変更で増えていない |
| ⑬ | SKAdNetworkItems | N/A（`GoogleMobileAds` 参照 0 件） |
| ⑭ | 返金の扱い | `Transaction.updates` → `refreshEntitlements()` で `revocationDate == nil` を見ている。**ただし端末キャッシュは剥奪しない**（下の申し送り参照） |
| ⑮⑯ | CloudKit / CKShare | N/A（不使用） |
| ⑱ | 年齢制限アンケート | 回答済み。`--audit` で広告申告と AdMob 同梱のズレ 0 件 |
| ⑲ | 説明文のプライバシー主張 | 要対応なし |
| ⑳ | タップ領域 / 課金導線 | どちらも 0 件（`paywall_reach_sweep` の自己検証 3/3 も通過） |
| ㉑ | 説明文の価格ズレ | 0 件（exit 0） |
| — | URL 監査 | 全アプリ・全ロケール正規 URL 一致 |
| — | スクリーンショット | ja / iPhone 6.7 インチ 5 枚が COMPLETE で引き継がれている |

**Phase 2.5（実機でしか見えない道）**: 課金は `SKTestSession` で購入成功パスを実測（`Tests/ProStoreTests.swift`）。Content Blocker はルールセット同梱を確認。起動クラッシュは回帰テスト 2 本。ユニット 420 本 green（5 skip）。シミュレータ `29497B6D-8C83-4841-A22B-F9F2962B8F34` に build 10302 を入れて全画面を目視済み。

**Phase 3（今日の他アプリ棚卸し）**: **束ねる必要なし**。2026-09-18 に 22 本の購入画面を触っているが、台帳 **A-72** の方針が「購入画面だけで単独提出しない・各アプリの次のリリースに束ねる」。広告消しは起動クラッシュ修正という出す理由があるので単独で先に出す。

## 4. 残っている 3 手（これだけ）

### 手順 1: kureho の submit 承認をもらう

skill `submitting-ios-build` Phase 4 の様式で確認を出し、**「無ければ submit」の返事をもらってから**次へ進む。
★「デザインこれで ok」は**デザイン修正への承認**であって submit の承認ではない（2026-09-18 に一度この区別で止めている）。

### 手順 2: 承認ログを書く（これが無いと hook が submit を deny する）

```bash
mkdir -p ~/.claude/logs/submission-precheck
cat > ~/.claude/logs/submission-precheck/$(date +%Y-%m-%d)-adblockkeshi-build10302.json <<'JSON'
{
  "app_name": "学習する広告消し - 消えない広告もブロック",
  "app_slug": "adblockkeshi",
  "bundle_id": "com.kureho.adblockkeshi",
  "app_id": "6774906945",
  "version": "4.3.0",
  "build": "10302",
  "build_id": "adcdea13-d669-466c-9ba9-66ada3e8382d",
  "kureho_approved_at": "<承認をもらった時刻を date -Iseconds で>",
  "fixes_included": [
    "起動直後にアプリが終了する不具合の根治（SIGTRAP・WebKit をメインスレッドへ）",
    "設定タブを新設（課金カード / 止めているサイト / お問い合わせ / バージョン）",
    "起動時に Apple Account のサインインを求める回帰の根治",
    "購入画面を 22 本共通フォーマットへ統一（囲み・閉じる位置・シート高さ・見出し）",
    "課金導線の入口をブロッカー設定前の画面にも掲出"
  ],
  "other_apps_today": [],
  "audits_run": {
    "audit_pending_iap_names.py":  {"ran_at": "2026-09-19T00:00:00+09:00", "exit_code": 0},
    "audit_description_prices.py": {"ran_at": "2026-09-19T00:00:00+09:00", "exit_code": 0}
  }
}
JSON
```

★ `ran_at` は**実際に回した時刻**に直す。回し直すなら下の再確認コマンドで exit 0 を見てから書く。

### 手順 3: submit

```bash
python3 ~/claude/tasks/scripts/submit_app_version.py 6774906945 4.3.0
```
（スクリプトの引数は実行前に `head -30` で確認する。）

提出後は skill `auditing-apple-submission` の 4 点監査を回して「submitted ≠ distributed」を確認する。

## 5. 再確認したいとき回すもの（すべて読み取りのみ・期待値は全部 0 件 / exit 0）

```bash
python3 ~/claude/tasks/scripts/audit_pending_iap_names.py          # 置き去りゼロ（数分かかる）
python3 ~/claude/tasks/scripts/audit_description_prices.py         # ズレ 0 件（数分かかる）
python3 ~/claude/tasks/scripts/audit_review_notes_version.py       # 提出版 v4.3.0 / メモ内の版 4.3.0
python3 ~/claude/tasks/scripts/audit_asc_urls.py                   # 全ロケール一致
python3 ~/claude/tasks/scripts/patch_social_media_declaration.py --audit   # 広告申告のズレ 0 件
python3 ~/claude/tasks/scripts/audit_store_privacy_claims.py       # 要対応なし
python3 ~/claude/tasks/scripts/hitarea_sweep.py --app AdblockKeshi # 0 件
python3 ~/claude/tasks/scripts/paywall_reach_sweep.py AdblockKeshi # 0 件（自己検証 3/3 が先に出る）
```

ビルドし直す必要が出たら `cd /Users/oharakureho/claude/AdblockKeshi && fastlane beta`
（★ `bundle exec` は付けない＝このプロジェクトに Gemfile が無い。`fastlane/Fastfile` の `changelog:` は
lane にハードコードされているので**版を上げたら必ず書き換える**。build 番号は `project.yml` の
`CURRENT_PROJECT_VERSION` を上げて `xcodegen generate`）。

## 6. 申し送り（提出を止める話ではないが、把握しておくもの）

- **返金されても端末内の購入記録は消えない**。`Transaction.updates` は `revocationDate` を見ているが、
  `ProEntitlementCache` 側は剥奪しない設計。これは「起動時に Apple Account のサインインを求めない」
  （上の 3）とセットの意図的なトレードオフで、v4.0 からの既存挙動。
- **報告タブが 3 か月ゼロ稼働**（台帳 **A-75**）。`reports_aggregated: 0` が続き、報告由来のルールは
  2026-06-23 から増えていない。推奨は「報告タブを畳んでブロッカー画面の中の導線へ下ろす」だが、
  **4.3.0 には混ぜない**（出す理由はクラッシュ修正）。4.3.0 配信後の次版で判断する。
- 提出が終わったら台帳 A-74 を「提出済み・審査待ち」へ更新する（正典 md と Artifact の**両方を同じターンで**。
  Artifact は `url = https://claude.ai/code/artifact/ef95a31b-27f4-42b6-9925-6bcf46f68d24` を必ず渡す）。
