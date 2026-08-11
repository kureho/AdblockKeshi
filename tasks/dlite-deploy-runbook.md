# D-lite 本番デプロイ手順書（Workers + D1）

対象ブランチ: `dlite`。**反映が終わったら本ファイルを削除する。**

## 前提ブロッカー

1. **wrangler 未ログイン** — `npx wrangler whoami` が `Not logged in.` を返す。
   kureho がセッションで `! npx wrangler login` を実行する必要がある（ブラウザの OAuth 承認）。
   Claude は認証情報の入力・OAuth 承認を行わない。
2. CI 経由の代替は無い — `.github/workflows/` に Workers deploy を行う workflow は 0 件。
   `CF_API_TOKEN` secret は D1 REST API 専用で、Workers deploy 権限を持つかは未確認。
3. **4.0.3 が WAITING_FOR_REVIEW**（live は 4.0.2）。iOS の D-lite 提出は 4.0.3 が審査を抜けるまで開始できない。

## 実行順序の判断（2026-08-11）

**4.0.3 配信 → Workers deploy → iOS D-lite 提出**の順にする。

kureho の当初手順は Workers deploy を先頭に置いていたが、それは 4.0.3 が審査中である状況を織り込んでいない。
iOS 提出が 4.0.3 待ちで動かせない以上、**先に deploy しても短縮できる日程は無い**。一方で先行 deploy には:

- 審査官が 4.0.3 の報告フローを触った時、サーバ挙動が旧仕様（critical → 400）から
  新仕様（200 + `observation_legacy`）へ変わっている
- 4.0.3 が却下されて pre-D-lite ベースで 4.0.4 を出す展開になった場合、サーバだけ D-lite 世代という
  状態が切り分けを難しくする

というリスクがある。待つコストは「legacy 報告が数日多く `pending` に積まれる」だけで、
それは手順1 の sweep が回収する。相対順序（Workers が iOS より先）は当初手順のまま。

## 実行タイミングの制約（Codex High 指摘の緩和策）

D1 を触る schedule job は全て `main` のコードで動く（default branch = `main` を `gh repo view` で実測、
workflow 側に `ref:` 指定なし）。`main` の集約 SQL は
`WHERE status='pending'` のみで `seen_in` / `blocker_enabled` を見ない。
migrate 完了〜deploy 完了の窓で旧 Worker が書いた `pending / seen_in IS NULL` が
その窓中の集約に拾われ得るため、**手順1〜3 の間に hourly-aggregation の tick を挟まないこと**が必須要件。
毎時 :00 / :15 / :30 を外して実行すればこれを満たす。

| workflow | cron (UTC) | 分 |
|---|---|---|
| hourly-aggregation | `0 * * * *` | :00 |
| complaint-monitor | `15 * * * *` | :15 |
| hourly-deletion-processor | `30 * * * *` | :30 |
| daily-validation | `3 * * *` | 03:00 UTC = 12:00 JST |
| weekly-tranco-sync / build-security-rules | 日 02:00 / 00:00 UTC | — |
| weekly-stable-promotion | 月 04:00 UTC | — |
| weekly-cdn-sync | 火 05:00 UTC | — |

**推奨実行窓: 毎時 :35〜:55（分は UTC と JST で同一）。日曜 00:00-02:30 / 月 04:00 / 火 05:00 / 毎日 03:00 UTC を避ける。**

実行中は信頼レポーター端末（kureho 自身の端末）から報告を送らない。
`TRUSTED_UUID_HASHES` に載る uuid_hash からの報告は L2 閾値（unique uuid≥3 / unique ip≥2）を
バイパスして即候補化するため、窓中の 1 件が rule_candidate になり得る唯一の経路。

## 手順

すべて `cd /Users/oharakureho/claude/AdblockKeshi/workers` から実行する
（`npm run` の scripts は `workers/package.json` にあり、リポジトリ直下に `package.json` は無い）。

### 0. rollback 用スナップショット + ベースライン取得

migration の UPDATE は元の status を残さないため rollback 記録が必須。
併せて、窓中に候補が増えていないことを後で照合するためのベースラインも取る。

```bash
cd /Users/oharakureho/claude/AdblockKeshi/workers

# 0-a. rollback 用の pending id 一覧
npx wrangler d1 execute adblockkeshi-reports --remote \
  --command "SELECT id FROM reports WHERE status='pending'" --json \
  > ../tasks/dlite-rollback-pending-ids.json

# 0-b. ベースライン: 旧クライアント報告の件数
npx wrangler d1 execute adblockkeshi-reports --remote --command \
  "SELECT COUNT(*) AS legacy_pending FROM reports WHERE status='pending' AND seen_in IS NULL"

# 0-c. ベースライン: rule_candidates の status 分布（手順4 ④ の比較対象）
npx wrangler d1 execute adblockkeshi-reports --remote --command \
  "SELECT status, COUNT(*) AS n FROM rule_candidates GROUP BY status ORDER BY status"

# 0-d. ベースライン: reports 総数
npx wrangler d1 execute adblockkeshi-reports --remote --command \
  "SELECT COUNT(*) AS total FROM reports"
```

0-b は `seen_in` 列がまだ無いのでエラーになる。**手順1の後に流す**（migration 後の残存確認として使う）。
0-a / 0-c / 0-d は手順1より前に取る。**取得できるまで手順1へ進まない。**

`0-a` があれば `UPDATE reports SET status='pending' WHERE id IN (...)` で戻せる。
ただし**窓中に書かれ cleanup が回収した行は 0-a に含まれない**（rollback しても
`observation_legacy` のまま残る）。実害は無いが把握しておく。

### 1. migration 適用

```bash
npm run db:migrate:prod
```

`0012_reports_dlite_diagnostics.sql` = 6 列 ADD COLUMN + `UPDATE ... observation_legacy`。

### 2. Workers デプロイ

```bash
npm run deploy
```

**手順1の直後に間を空けずに実行する**（旧 Worker が pending/seen_in NULL を書く窓を最小化）。

### 3. legacy cleanup

```bash
npm run db:cleanup-legacy:prod
```

窓中に旧 Worker が書いた行を回収する。冪等（ローカルリハーサルで 2 回実行して分布不変を実測済み）。

## 本番確認（手順4）

```bash
# ① 新しい診断列が存在する
npx wrangler d1 execute adblockkeshi-reports --remote --command \
  "SELECT name FROM pragma_table_info('reports') WHERE name IN ('seen_in','blocker_enabled','dns_enabled','app_version','app_build','filter_version') ORDER BY name"

# ② status 分布（旧 pending が observation_legacy へ隔離されたか）
npx wrangler d1 execute adblockkeshi-reports --remote --command \
  "SELECT status, COUNT(*) AS n FROM reports GROUP BY status ORDER BY status"

# ③ 既存データが消えていない（手順0 の件数と突き合わせる）
npx wrangler d1 execute adblockkeshi-reports --remote --command \
  "SELECT COUNT(*) AS total FROM reports"

# ④ 窓中に candidate が増えていないこと（実行前の件数と比較する）
npx wrangler d1 execute adblockkeshi-reports --remote --command \
  "SELECT status, COUNT(*) AS n FROM rule_candidates GROUP BY status ORDER BY status"
```

④ は手順0 の時点でも同じクエリを流して控えておく。差分が出たら窓中に集約が走った証拠。

## ローカルリハーサル結果（実測済み・2026-08-11）

`0012` を退避して 0001-0011 を適用 → 既存 5 行（pending×2 / aggregated / validating / stable）を投入 →
`0012` 適用、で以下を全て green で確認済み。

- 6 列すべて存在
- pending 2 件が `observation_legacy` へ、`aggregated` / `validating` / `stable` は不変
- 行数 5 → 5（削除なし）
- cleanup を 2 回流しても分布不変（冪等）
- `seen_in='safari'` の新規行は cleanup 後も `pending` のまま（条件が効いている）

## 残る既知の差分（対応不要と判断した根拠）

`main` の `l3-decision.ts` は critical を `rejected_critical` に落とし、`dlite` は `kureho_queue` に送る。
どちらも `l3_check:'fail'` で `stable` に到達しないため CDN 配信への差は無い。
kureho のレビュー待ち行列の可視性が落ちるだけで、iOS 版リリース後に `dlite` を `main` へ通常マージすれば解消する。

## Codex 反証 2 巡目の結果（2026-08-11）

Codex に「main を揃えないと deploy 不可」という自身の High 指摘への反論を壊させた。結果:

**採用（Codex が正しかった）**
- **「push トリガー workflow は 0 件」は私の誤り**。`popunder-rules-update.yml:7-13` に `push: branches: main` が実在する。
  ただし裏取りの結果、`paths:` が 3 ファイルに限定され `git diff --name-only main...dlite` でそのいずれも触っておらず、
  D1 参照も 0 件（CDN JSON 再生成のみ）。**deploy 手順の危険度もマージ可否の判断も変わらない。**
- `trustedUuidHashes` バイパスは実在（`aggregation-threshold.ts:92,99-101` / `scripts/aggregation/run.ts:15-30` /
  `hourly-aggregation.yml:34-36` の secret 注入）。**窓中の 1 件が即候補化し得る唯一の経路**なので、
  上の「実行中は kureho 端末から報告しない」は緩和策ではなく必須条件として扱う。
- 手順0 に `rule_candidates` のベースライン取得が無かった（手順4 ④ が比較対象を持てなかった）→ 追加済み。

**却下（根拠つき）**
- 「main を fast-track merge すべき」— Codex 自身が「可能なら」と条件付きで挙げている。
  :35〜:55 に実行すれば migrate〜cleanup の間に hourly-aggregation の tick が入らず、
  すり抜け行が集約される機会そのものが発生しない。マージは deploy の前提条件ではない。
- 「(C) post-deploy の等価性が崩れる」— Codex の反証内容は窓中の行の話であり、
  deploy 完了後の定常状態については `main` の旧 SQL が返す集合と D-lite の絞り込み後の集合は一致する
  （D-lite の `reportStatus()` が `pending` を safari かつ blocker_enabled=1 に限定するため）。定常状態の等価性は維持。

**未確認のまま残すもの**
- `wrangler d1 migrations apply` が 1 ファイル内を単一トランザクションで適用するかは repo からは確定できない。
  ただし ADD COLUMN 後・UPDATE 前の INSERT は UPDATE が拾い、UPDATE 後の INSERT は手順3 の cleanup が拾うため、
  どちらの順序でもカバーされている。手順を増やす理由にはならない。
