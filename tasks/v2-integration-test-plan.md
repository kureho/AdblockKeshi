# v2.0 手動 integration test plan

実機 iPhone or Simulator で実施。所要約 1 時間（縮小版で 30 分）。

## 準備
- v2.0 build を端末にインストール
- Safari → 設定 → 機能拡張 で「広告消し」を ON にする

---

## テスト 1: 4 通り toggle 組合せ × 動作確認

アプリで以下 4 通りを試し、それぞれ Safari でテスト URL を踏む。

| Combo | アプリ操作 | 期待挙動 |
|---|---|---|
| 広告 ON + sec ON | 両トグル ON | merged-rules.json → 広告 + 詐欺サイト両方ブロック |
| 広告 ON + sec OFF | 広告 ON、詐欺サイト OFF | ad-rules.json → 広告のみブロック・詐欺サイト素通り |
| 広告 OFF + sec ON | 広告 OFF、詐欺サイト ON | security-rules.json → 広告素通り・詐欺サイトのみブロック |
| 広告 OFF + sec OFF | 両トグル OFF | empty-rules.json → 全部素通り |

各組合せで:
1. アプリでトグル操作（即座に反映待ち 1 秒程度）
2. アプリを background へ
3. Safari を開きテスト URL リスト（下記）を踏む

---

## テスト 2: テスト URL リスト

### 広告ヘビーな JP サイト（広告ブロック確認用）
- https://news.livedoor.com/
- https://www.gizmodo.jp/
- https://ameblo.jp/

### 詐欺/マルウェアサイト（セキュリティブロック確認用）
- Phishing.Database の最新 active URL から 1 件
  - https://github.com/mitchellkrogza/Phishing.Database/blob/master/phishing-domains-ACTIVE.txt から最新分から選ぶ
- URLhaus の最新 active URL から 1 件
  - https://urlhaus.abuse.ch/browse.php から選ぶ

### 通常サイト（誤検知が無いことを確認）
- https://www.google.com/
- https://www.apple.com/
- https://www.nhk.or.jp/

---

## テスト 3: 誤検知チェック（Tranco top 50）

`tests/fixtures/tranco-top-50.txt` の全 50 サイトを、**広告 ON + sec ON** の状態で順に踏む。

```bash
# fixture ファイル内容を確認
cat tests/fixtures/tranco-top-50.txt
```

**判定**: 1 件でもブロックされたら build pipeline の Tranco 除外ロジックを見直す（`scripts/build_security_rules.py` の `load_tranco_set` / `build_security_rules`）。

---

## テスト 4: BG 更新

```bash
# Simulator で BG fetch trigger
xcrun simctl spawn booted /usr/bin/log stream --predicate 'subsystem == "com.kureho.adblockkeshi"' &
xcrun simctl io booted "background-fetch" com.kureho.adblockkeshi
```

ログで FilterDownloader が 4 ファイル fetch していることを確認。

---

## テスト 5: state 永続化

1. アプリで両トグルを OFF
2. アプリを完全に kill（スワイプアップで終了）
3. 1 分待つ
4. アプリ再起動
5. **判定**: 両トグルが OFF のままであること

---

## テスト 6: Safari Extension 無効化シナリオ

1. アプリ起動して CompletedView 表示
2. Safari 設定 → 機能拡張 → 広告消し を OFF
3. アプリに戻る → OnboardingView に遷移すること
4. Safari 設定で再度 ON にする
5. アプリに戻る → CompletedView + 前回の toggle state が復元されること

---

## テスト 7: 連打 debounce

1. アプリで広告トグルを 1 秒間に 5 回タップ
2. 操作完了後、500ms 以内に最終 state が反映されること
3. console ログで `reloadContentBlocker` の呼び出しが 1 回だけであることを確認

---

## 完了条件

- テスト 1〜7 全項目 OK
- Tranco top 50 で誤検知 0 件
- v1.0.1 比較で広告ブロック率劣化なし

完了したら結果を `tasks/v2-integration-results-YYYY-MM-DD.md` に残す。
