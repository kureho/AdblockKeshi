# ADR: 報告駆動の保護スイート（基本保護 / 報告反映 / 遷移保護）

- 状態: **Accepted（A 案＝現3拡張を正式アーキテクチャとして採用）**
- 日付: 2026-06-23
- 関連: PR #29（reported-rule 安全化）, PR #30（4→3 統合・origin/main `52614a7`）
- 文脈: AdblockKeshi は固定フィルタ配布ではなく、**ユーザー広告報告を起点に改善を回すプロダクト**。3拡張は技術都合ではなく「報告由来の変更を安全に運用するための責務分離」として位置づける。

---

## 決定（Phase 1）: A 案を採用

| 案 | 構成 | 判定 |
|---|---|---|
| **A** | 3拡張（基本保護 / 報告反映 / 遷移保護） | **採用** |
| B | 2拡張（popunder を基本保護へ統合・遷移保護を残す） | 却下（実機事実で不成立） |
| C | 1拡張相当 | 却下 |

### 実機事実（推測でなく実測・kureho 目視）
- **PopunderBlocker OFF では広告抑止が不十分**（3→2 受入条件を満たさない・2026-06-23 kureho 判断）。
- **PopupShield 単独では現時点で静的対策を完全代替できない**（L2 の site-specific 抑止を JS のみで置換できていない）。
- → B（popunder を畳む）/C は不成立。**3拡張が現時点の最適**。

### 評価軸ごとの A 採用根拠
| 軸 | A（3拡張）の評価 |
|---|---|
| ユーザー報告との相性 | 報告→ローカル即時（基本保護 combined）→global 昇格→検証→配信 の各段を別責務に分離できる |
| ローカル即時反映 | PR #30 の自己報告ファストレーンが基本保護 combined に即反映（維持） |
| global 昇格 | 別工程（管理者検証）として分離可能 |
| 誤報の影響範囲 | 層別に隔離・quarantine しやすい |
| false positive / rollback / kill switch | 層別 rollback・combined の last-known-good・runtime トグルで層単位 OFF |
| **`ignore-previous-rules` の隔離** | **L2 の ipr を基本保護と別拡張（報告反映）に置くことで、標準ルールを ipr が解除する事故を構造的に防ぐ**（PR #30 監査で確認した最重要不変条件） |
| rule budget / WebKit 制約 | 150,000/拡張を層で分けて消費（基本保護 combined ≤149,000・popunder は別枠） |
| popup 抑止性能 | L1+L2（報告反映）+ JS 介入（遷移保護）の多層が現状の実効解 |
| サイト破壊リスク | 層分離で document 非遮断・ipr 隔離を担保 |
| 運用 / テスト容易性 | 層ごとに fixture・compile 検証・回帰を切り分け |
| Safari 設定の分かりやすさ | 3つの「保護」として説明（後述 UX） |
| 将来統合可能性 | Phase 11 の条件達成時に再検討（永久固定にしない） |

---

## 各保護の正式責務（Phase 1）

### 1. 基本保護 — `ContentBlockerExtension`（`com.kureho.adblockkeshi.blocker`）
- 安定した標準広告ルール / tracker / cosmetic / WebKit 基本リスト。
- **現状（PR #30）**: 安全条件を満たすローカル自己報告ルール + global reported ルールも、標準 Content Blocker の `combined-<state>.json` に統合済み。
- ユーザー向け説明: 「一般的な広告やトラッカーを、安定したルールでブロックします。」

### 2. 報告反映 — `PopunderBlockerExtension`（`com.kureho.adblockkeshi.popunderblocker`）
- 報告から発見・検証された追加対策 / 複数報告から昇格した静的ルール / サイト固有対策 / 静的 popunder L1 / サイト別 L2 / PopupShield だけでは止まらないケース。
- **`ignore-previous-rules`（L2）を基本保護と別拡張に隔離**するのが本層の構造的役割。
- ユーザー向け説明: 「利用者から届いた広告報告をもとに、安全性を確認した追加対策を反映します。」
- 「管理者提案保護」等の語はユーザーに出さない（管理者検証は運用工程）。

### 3. 遷移保護 — `PopupShieldExtension`（`com.kureho.adblockkeshi.popupshield`）
- `window.open` / 新規タブ popup / about:blank helper / script-driven navigation / current-tab takeover / JS redirect / 動的・ローテーション型遷移 / 静的では対応不能な挙動。
- ユーザー向け説明: 「勝手に開くタブや、広告ページへの意図しない移動を防ぎます。」
- 「強力保護」は使わない（守る対象で表現）。

---

## 現状実装と理想構成の差（重要・正直に記載）

**名称と現実装の乖離**: ユーザー向け名称では「報告反映」を **PopunderBlockerExtension** に与えるが、**実際にユーザー報告由来のルール（self/global reported）は PR #30 により基本保護（標準 ContentBlocker）の combined に入っている**。一方 PopunderBlocker の現ルールは下記のとおり **user-report 由来ゼロ**。

### PopunderBlocker 内ルールの出所分類（Phase 2 要求・実ソース確認済み）
| ルール群 | 件数 | 出所 | user-report 由来か |
|---|---|---|---|
| L1（広告NW host script block） | 31 | `popunder-script-networks.txt`（research-rigor 2026-06-16 調査 + 公開広告網ドキュメント・curated） | **いいえ**（admin調査 + upstream） |
| L2（サイト別 block + ipr） | 9 | `popunder-aggressive-sites.json`（admin の desktop/headless 実測 2026-06-17/06-23） | **いいえ**（admin調査由来） |
| 出所不明 | 0 | — | — |

→ **出所不明ルールを「ユーザー報告から反映」と断定しない**。現 PopunderBlocker は admin/upstream curated。「報告反映」名称は**本層が報告由来の検証済み追加対策を載せる"器"である**という前向きな責務定義であり、現時点の中身が全て報告由来という意味ではない（UX 文言もこの事実に整合させる＝Phase 9）。

### 将来必要な責務再配置（**別 PR 提案・本ブランディング PR には混ぜない**）
1. **報告由来ルールの再分離**: PR #30 で基本保護 combined に入れた self/global reported ルールを、名称と責務を一致させるため将来「報告反映」拡張側へ移す検討。ただし実行 target の移動は blocking 挙動・budget・保存先の変更を伴うため**別 PR**。
2. **ルール registry で source 明示**: 各ルールに `source`（user_report / admin_investigation / upstream_list / manual / legacy / unknown）を持たせる registry（Phase 3 metadata）。
3. これらは設計として本 ADR に記録し、実装は今回スコープ外。

---

## Phase 2: 報告→保護への routing

### 報告カテゴリ
通常広告 / cosmetic広告 / third-party広告host / 新規タブpopup / current-tab redirect / 偽再生ボタン / オーバーレイ / 表示崩れ / false positive / 報告済みだが消えない / 報告後にサイトが開けない。

### routing（現状コードと整合・理想は別記）
| 報告内容 | 即時ローカル | 管理者確認後 | 反映先 | rollback 単位 | fixture |
|---|---|---|---|---|---|
| 安全な third-party 広告 host | 可（safe block のみ） | global 候補 | 基本保護 combined（現状）/ 将来は報告反映 | combined 層 | reported safe rule round-trip |
| cosmetic 広告 | 条件付き | 可 | 基本保護 | combined 層 | cosmetic round-trip |
| popup network | 原則不可 | 必須 | 報告反映（L1） | popunder 層 | popunder build + compile |
| サイト固有 popunder | 不可 | 必須 | 報告反映（L2・ipr 隔離） | popunder 層 | L2 site fixture |
| JS 新規タブ | 不可 | 必須 | 遷移保護 | PopupShield 層 | run-fixture（MAIN/ISOLATED） |
| current-tab redirect | 不可 | 必須 | 遷移保護 | PopupShield 層 | run-fixture |
| false positive | 即時停止候補 | 必須 | 該当層を quarantine | 該当層 | regression |

**現状コードとの差**: 「安全な third-party 広告 host」の最終反映先は現状 basic（PR #30）。理想は名称に合わせ「報告反映」。差は上表＋前節の再配置提案で明示。

---

## Phase 3: ルールのライフサイクル（registry 設計・未実装）
状態: `local` → `candidate` → `reviewing` → `canary` → `stable`（／ `quarantined` / `rolled_back` / `retired`）。
metadata（WebKit ルール JSON に入らないので**別 registry**で管理）: rule ID / source / report category / target protection / createdAt / updatedAt / report count / distinct reporter count / affected site / destination domain / confidence / false-positive count / last verified / rollout state / rollback reason / generator version。
※ 本 ADR は設計のみ。registry の実装は別 PR。

## Phase 4: ローカル即時反映（条件・現状維持）
即時反映は安全要件を満たすもののみ（PR #29/#30 で実装済みを維持）:
`load-type:["third-party"]` / document・main-frame 除外 / `ReportedRuleSafety.isDocumentBlockingRisk` / 報告ページ自身の registrable domain を host block しない / URL 全文を無条件 host block 化しない / compile verification / deterministic selection / maximum count（reportedReserve）/ last-known-good / reload rollback / 起動時 migration / 個別削除（quarantine 余地）。
**popup / redirect 報告を通常 host block として即時追加しない**（routing で遷移保護へ）。

## Phase 5: グローバル昇格と管理者確認（条件・未実装の運用設計）
distinct reporter 数 / 同一端末連投除外 / 一定期間の再現性 / confidence threshold / false positive 率 / fixture 再現 / WebKit compile / page 生存 / player・media 生存 / popup・redirect 抑止 / 一般サイト回帰 / canary / 自動 rollback / 手動 kill switch。
**L2・`ignore-previous-rules`・PopupShield 挙動は報告数だけで自動 stable 化しない。必ず管理者検証を通す。**

## Phase 6: プライバシー（監査方針・実装は別 PR）
- URL 全文を不要に保存しない。path/query/token を削除し **eTLD+1（registrable domain）** と destination domain・popup種別（new-tab/current-tab）・frame 種別のみを扱う方針。
- device 識別子・IP の保持方針、ログ保持期間、削除要求対応、Privacy Policy / App Privacy 回答を別 PR で精査。
- **成人向けページタイトル・動画名・検索語・token 付き URL を保存しない**。
- 現状コードの報告経路（workers）に対する具体監査・PII redaction の強化は別 PR（本ブランディング PR ではロジック非変更）。

## Phase 10: 運用設計（指標・運用サイクル）
指標: 日次報告数 / distinct reporter / カテゴリ別 / 対象サイト別 / ローカル適用成功率 / global 昇格数 / 確認待ち / canary 数 / stable 昇格 / quarantine / rollback / false positive 率 / compile failure / reload failure / 拡張別エラー率 / 遷移保護 active 率。
運用: 日次 triage → 週次 candidate review → 管理者再現 → canary → stable → emergency kill switch → rollback → postmortem → stale rule の retire。
**有料インフラを無断導入しない**（既存 Cloudflare Workers/GitHub Actions の範囲）。

## Phase 11: 将来の2拡張化（再検討条件・永久固定にしない）
全条件達成で再検討: PopunderBlocker OFF で主要サイト popup 0 / current-tab redirect 0 / player・media 生存 / 一般サイト回帰なし / L2 依存サイト 0 / `ignore-previous-rules` 不要 / 遷移保護 active 率十分 / 最低対応 OS（iOS 17）で実機確認 / 30日以上 canary / rollback 可能。**条件未達では統合しない**（今回 B 案不成立がその実例）。

---

## 本 ADR に基づく今回 PR のスコープ（厳守）
**名称・アイコン・説明・UX のみ**変更。以下は**変更しない**: 広告 blocking ロジック / rule budget / reported rule 保存先 / L1/L2 内容 / `ignore-previous-rules` / PopupShield 介入ロジック / 拡張数 / Bundle ID / version・build。責務再配置・registry・privacy 強化は**別 PR 提案**として本 ADR に記録済み。
