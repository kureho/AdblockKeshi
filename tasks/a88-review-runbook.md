# 広告消し 報告の週 1 回判定 — 手順（A-88 §2）

Claude が判定する。kureho に聞くのは「判定の方針そのものを変える」ときだけ。

## いつ

- 毎週月曜 06:30 に launchd `com.kureho.adblockkeshi-review-packet` が束を作る（Claude なし・D1 は読み取りのみ）
- 朝のレポートの「広告消しの報告（未判定）」に件数が出る。新しい束は次のセッション開始時に 1 回だけ知らせる
- 手で作り直すとき: `python3 -B scripts/review/build_review_packet.py`（約 5〜10 分・報告ページを開くため）

## 手順

1. `.review-packets/status.json` の `packet` を開く（束は手元専用・公開リポジトリに入れない）
2. 1 件ずつ結果を決める（`results-draft.json` の空欄を埋める）

   | 見えたもの | outcome |
   |---|---|
   | ほかのアプリの中の広告（下書き済み） | `in_app_ad` |
   | 画面に広告が残り、原因の通信先・要素が特定できた → 3 でルールを書いた | `applied` |
   | 広告がサイト自身のドメインから出ている（PR 記事・自社バナー等）＝止めると壊れる | `site_own_ad` |
   | 画面にも通信先にも広告が見当たらない | `not_reproduced` |
   | テスト送信（example.com 等）・広告と無関係 | `invalid` |

   - 「広告規則の全体に載っているドメインの通信先」は目印（下限）。載っていない広告網もある
   - 例: thedigestweb.com・uranai.nosv.org の html-load.com は、条件つきの規則しか無いので上限なしでも漏れる（`tasks/a88-design-2026-09-27.md` §1）
3. `applied` にするものは `review/rules/<日付>-<サイト>.json` にサイト限定のルールを書く（形と禁止事項は `review/rules/README.md`）。
   **入れる前に計測ツールでルールありとなしの画面を並べ、広告が消えてページが壊れないことを見る**
   （アンチ広告ブロック系の通信を止めると「広告ブロックを外して」の壁が出るサイトがある＝その場合は `site_own_ad` 扱いで見送る）
4. 止まっている候補（束の末尾）は判断して `candidates` に `closed` で閉じる（ルールが要るなら 3 と同じく review/rules に書く）
5. `results-draft.json` を `review/results/<日付>.json` にコピーし、`outcome` の空欄が無いことを確かめる。
   **URL・メモ・画面の中身は書かない**（`note` を書くなら理由の種類だけ）
6. `cd workers && npx tsx ../scripts/review/run-apply-review-results.ts --dry-run` で流す予定の UPDATE を確認
7. commit → push。`apply-review-results.yml`（D1 に結果を書く）と `weekly-cdn-sync.yml`（ルールを配信）が動く。
   両方の run が成功したことを `gh run list` で確かめる
8. 報告者のアプリは履歴を開いたときに結果を取りに行く（10 分に 1 回まで）

## 触らないもの

- 本番 D1 を手で書き換えない（書き込みは上の 2 本の workflow だけ）
- 候補の `rule_text` をそのまま stable にしない（サイト限定で書き直す）
