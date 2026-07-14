# クラウドソース/コミュニティ報告で育つフィルタ — 事実ベース調査

調査日: 2026-06-16 / 対象: iOS Safari Content Blocker（WKContentRuleList = 宣言的JSON・DNS解決なし・URLパターン照合のみ・JS/scriptlet注入不可・実行時DOM不可・1ブロッカーあたり上限150,000ルール）

CB タグ凡例:
- **[CB-addressable]** = Safari CB のルールリスト更新（trigger/action JSON）で塞げる
- **[CB-NOT-addressable]** = DNS解決・実行時ロジック・JS実行が必要で原理的に塞げない
- **[CB-partial]** = 条件付き/一部のみ塞げる（per-report で塞げるが汎用的には不可、等）

---

## 結論サマリ（PICO の決定に直結）

1. 「クラウドソース」と言っても実態は **1〜5人のメンテナ依存**（直近90日 EasyList の 92.7% を ryanbr 1人がコミット / hagezi は実質1人）。個人開発者が公開リスト並みの「報告→反映」スループットを自前で再現するのは非現実的 → **既存リストを取り込む（consume）べきで、独自リストを再構築すべきではない**。
2. 固定リストが構造的に取りこぼす durable な穴（CNAME 汎用検出・first-party 化・SSAI）は **大半が CB-NOT-addressable**。報告機能をどれだけ磨いても Safari CB では原理的に塞げない。
3. 報告で育つ機能の現実的な価値ポケットは **CB-addressable な遅延ケース**（新興ドメイン・地域広告・per-report で報告された CNAME クローク済みホスト）。ここは確かに価値があるが「集合知で全広告を倒す」訴求は誇大。

---

## Q1: 報告で育つ仕組みの実態と威力（一次ソース）

全て `gh api`（認証済み）で取得した一次データ。取得日 2026-06-16。

### コミット速度（過去52週・stats/commit_activity）
| リスト | 平均コミット/週 | 中央値/週 | 52週合計 | 確信度 |
|---|---|---|---|---|
| EasyList (easylist/easylist) | 1,859.5 | 2,246 | 96,695 | High |
| AdGuard (AdguardTeam/AdguardFilters) | 444.4 | 434.5 | 23,111 | High |
| uBO (uBlockOrigin/uAssets) | 392.8 | 392 | 20,425 | High |

EasyList の見かけのコミット量は圧倒的だが、これは「行単位の機械的コミット」を多く含む（後述の集中度参照）。

### 報告→クローズ latency（直近100件の closed issue・create→close）
| リスト | 中央値 | 平均 | 24h以内 | 48h以内 | 確信度 |
|---|---|---|---|---|---|
| uBO/uAssets | **8.1h** | 240.6h(外れ値あり) | 68% | **93%** | High |
| AdGuard | **23.4h(~1日)** | 88.0h | 51% | 65% | High |

**重要な caveat（survivorship bias）**: これは「最終的に close された report のみ」の latency。難しい/新規性の高いケースは open backlog に滞留してこのサンプルに入らない。EasyList は **open issue 1,340件** を抱える（uAssets は open 15件＝積極トリアージ）。「中央値≈1日」を「報告は1日で直る」と読んではいけない。あくまで「解決された報告の解決時間」。

### 配信 cadence（merged fix → ユーザー到達・フィルタファイルヘッダ一次確認）
- EasyList: `easylist.txt` は継続的に再生成（Version タイムスタンプ）、クライアント再取得上限 `Expires: 4 days`。確信度 High。
- AdGuard Base: `TimeUpdated` は同日更新、再取得上限 `Expires: 10 days`。full + optimized の2版をコンパイル。クライアントの正確なチェック間隔は KB 非開示（Low/lead）。
- uAssets: コア filter list は各リストの `Expires` に従う（EasyList=4日）、hosts系は `updateAfter:13`日。確信度 High。

### メンテナ集中度（H4 = 個人開発可否の核心）
- EasyList 学術測定（Who Filters the Filters, SIGMETRICS 2020）: 上位5人が **93,858 コミットの76.87%**、寄稿者の65.3%が100コミット未満。
- EasyList 実測（gh api 直近90日）: 13,248コミット中 **ryanbr 単独 92.7%**。
- hagezi: 実質1人プロジェクト（contributor 1名）。
- AdGuard: 「dedicated team of filter engineers（専任フィルタエンジニアチーム）」＋コミュニティ。AdGuard は有料製品で専任スタッフを抱えており、純粋クラウドソースとは別物。寄稿者は EasyList より分散（Alex-302=58k, AdamWr=45k, zloyden=25k…）。
- 出典: https://arxiv.org/pdf/1810.09160v3 / `gh api`（取得 2026-06-16）/ https://adguard.com/kb/general/ad-filtering/filter-policy/

### DNS/コミュニティブロックリスト界（Pi-hole 系）と自動検証
- hagezi/dns-blocklists: 実質1人＋重い CI 自動化（`deaddomain.yml`=NXDOMAIN自動close, `release.yml`=リリース自動生成+CDN purge）。エントリ数: Ultimate 582,692 / Pro 499,365 / **Light 94,276** / Ultimate.mini 115,014。出典 README（取得 2026-06-16）。確信度 High。
- oisd: 完全自動集約。「リストを結合→非解決ドメイン削除→FP削除→残りがリスト」。更新 ≥24h（実測は1時間前等もっと高頻度）、dead domain 5日ごと剪定。総数は非開示（未確認）。出典 oisd.nl/faq。
- StevenBlack/hosts: 集約型・~172 contributors・Python テストスイート（testUpdateHostsFile.py）+ CI。unified base 84,972件。
- **自動検証の到達点**: easylist/AdGuard/hagezi/StevenBlack の4つとも **構文 lint・dead domain・ビルドの自動 CI を保有**（easylist: `domain-checker.yml`/`lint.yml`、AdGuard: `aglint.yml`/`rotating-domains-checker.yml`）。ただし「このルールが実際に広告を塞ぐか/FP か」の判定は依然 **人間（issue/forum 報告）依存**。三角測量済み（4 repo の workflow を直接確認）。

→ **個人開発者が "自己検証パイプライン"（CI で構文・dead domain・ビルドを自動検証）を回すことは技術的に可能**。ただし「ルールが実際に広告を塞ぐかの judgment」は自動化されておらず人手依存である点が H4 の核心。

---

## Q2: 固定リストが取りこぼす穴の類型（CB タグ付きは私が WKContentRuleList モデルに照合して付与）

### 2a. 新興ドメイン / フィルタ更新遅延 — [CB-addressable]
報告されさえすれば単純な `url-filter`（ドメイン照合）で塞げる。穴の本質は「報告→反映の遅延」であって表現力ではない。
- 合成遅延（Alrizah, IMC 2019, single-source/High）: 「エラーの半数以上が報告されるまで1ヶ月超持続。報告後の反映は平均 **2.09日**」。支配項は報告前の>1ヶ月。属性変更追従は平均10.3日。
- → CB でも同じ遅延を負う（報告ベースである限り原理的に同じ）。出典 https://gangw.cs.illinois.edu/imc2019-adblock.pdf

### 2b. ドメインローテーション / ランダム化サブドメイン — [CB-partial]
- 既知パターンのローテは `url-filter` 正規表現で一部捕捉可（CB-addressable な部分）。
- DGA 的に完全ランダム生成・高速循環する部分は、宣言的リストが追従しきれず実行時ロジックが要る → 一部 CB-NOT-addressable。
- Alrizah: ad-server ドメインは 505(2009)→15,500(2019)、月+146/-72。「ドメイン追加3日後に 52% のトラフィックが消失」だが長期では「61% のad serverのみ有意に影響」。Who Filters: ドメイン変更を **1,612回**観測も「EasyList 回避の population-wide トレンドは検出されず」＝ローテは起きるが測定窓では net カバレッジ損失は出ていない。確信度 High（single-source 各々）。

### 2c. first-party 化トラッカー（publisher 自身のドメイン/パスで配信）— [CB-partial]
- per-report で「特定 publisher の特定パス」を `url-filter` + `if-domain` で塞ぐのは可能（CB-addressable な部分）。だが publisher ごとの whack-a-mole でスケールしない。
- inline script で first-party からホストされる動的生成は宣言的リストでは捕捉困難 → 一部 CB-NOT-addressable（EasyList は CSP フィルタで対抗したが、CSP injection は Safari CB action に無い）。
- Who Filters: 「first party へリソース移動 **84回**（うち23回は自サブドメイン）」。例 cnn.com が `ssl.cdn.turner.com`(塞)→`cdn.cnn.com`(未照合)。出典 https://arxiv.org/pdf/1810.09160v3

### 2d. CNAME クローキング — [CB-NOT-addressable（汎用）/ CB-partial（per-report 単一ホスト）]
これが「DNS が要る」最重要例。
- 機構: publisher サブドメイン（例 `analytics.example.com`）の CNAME がトラッカーを指し、**same-site 扱い**で読み込まれる。汎用検出には DNS 解決が必須 → **汎用的には CB-NOT-addressable**。
- ただし **既に報告された特定ホスト名** は DNS 不要で `{"url-filter":"analytics\\.example\\.com"}` の文字列照合で塞げる（breakage しやすく per-publisher で whack-a-mole・非スケーラブル）→ **per-report では CB-partial**。ここがコミュニティ報告機能の数少ない真のニッチ。
- 一次数値（Dimova et al., PoPETs 2021, https://arxiv.org/pdf/2102.09301、single-source/High）:
  - top 10,000 サイトの **9.98%** が CNAME トラッカー使用（下限値）。22ヶ月で **+21%** 成長（通常トラッカーは -3〜-8%）。
  - URL パターン照合（uBlock Chrome 列= Safari CB と同条件）では 13 トラッカー中 **~9/13(~69%) が未ブロック**（表1のカウント。論文の見出し数値ではない=Med）。partial ブロックも「パスをランダム化すれば容易に回避」と論文が明記。
  - 副作用: CNAME トラッカー検出 7,797 サイトの **95%（7,377サイト）で cookie leak**、認証 cookie leak 10サイト。

### 2e. ポップアンダー/ポップアップ/タブアンダー — [CB-partial]
- Safari CB には `popup` リソースタイプの trigger があり、一部のポップアップ要求は `popup` load type で塞げる（CB-addressable な部分）。
- background redirect 型 tab-under は要求のブロックでは止まらず（ナビゲーション挙動）→ CB-NOT-addressable。
- Alrizah: tab-under は 2015年5月報告、2019年時点で「EasyList 未だ対処不能」。Chrome v68+ がブラウザ側で対処。prevalence 数値なし（未確認）。

### 2f. アンチアドブロック検出+回避 — [CB-partial]
- 要求ブロックは不可だが、Safari CB の **`css-display-none`（基本 CSS セレクタのみ・uBO の procedural/`:has-text` 等は不可）**で警告オーバーレイ要素を非表示にできる（CB-addressable な部分）。
- 検出 JS 自体の無効化・DOM 書き換えは JS 実行が要る → CB-NOT-addressable。
- prevalence は三角測量済（2出典・top-5K）: Nithyanand FOCI 2016「top-5K の **6.7%**」/ AdWars IMC 2017「Anti-Adblock Killer List が **8.7%** で発火」→ **~7-9%（2016-17）**。
- リスト側カバレッジの穴（Mughees PETS 2017, High）: top-100K に anti-adblock 686サイト、EasyList は **130/686=19%** しか捕捉。最良の Anti-Adblock Killer List は **2016年11月以降更新停止**なのに依然 EasyList を上回る＝最良リストが放棄状態。

### 2g. サーバーサイド広告挿入 SSAI/SGAI — [CB-NOT-addressable]
- 機構: サーバーが配信前に広告を動画ストリームに縫い込む。コンテンツと広告が同一 first-party CDN から区別不能な単一ストリームで届く → **別個の広告要求が存在しない**ため URL 照合でも css 非表示でも原理的に不可。クリーンに CB-NOT-addressable。
- 機構は業界ドキュメントで十分裏付け（Wurl/Bitmovin/broadpeak）。学術的 prevalence/効果数値は **未確認**（一次文献に存在せず）。

---

## ACH 表（hypotheses × evidence）

| 証拠 | H1: 報告は威力大・CB制約は限定的 | H2: 報告は有効だがCB制約で塞げる穴は単純URL型に限定 | H3: 報告の威力は誇張・固定リストと差小 | H4: 個人開発で同等運用不可・取り込み以上の価値出にくい |
|---|---|---|---|---|
| latency 中央値≈1日(closed のみ) | 整合 | 整合 | **不整合**（速い） | N/A |
| open backlog 1,340件・>1ヶ月報告遅延 | **不整合** | 整合 | 整合 | 整合 |
| CNAME 汎用=DNS必須・SSAI=要求なし | **不整合** | 整合 | N/A | 整合 |
| 150k ルール上限・大規模DNSリスト超過 | **不整合** | 整合 | N/A | 整合 |
| メンテナ集中(ryanbr 92.7%/hagezi 実質1人) | N/A | N/A | 整合(少数依存) | **整合（強）** |
| AdGuard は有料専任チーム | N/A | N/A | 一部不整合 | **整合（強）** |
| per-report で CNAME 単一ホストは塞げる | 一部整合 | 一部不整合 | N/A | N/A |
| 自己検証 CI は技術的に可能 | N/A | N/A | N/A | 一部不整合 |

**最少矛盾で生き残る仮説 = H2 + H4**。H1 は CB 制約・上限・backlog で複数不整合。H3 は latency と「報告で確かに塞げる CB-addressable 領域がある」事実で不整合（ただし「少数メンテナ依存」部分は正しい）。

---

## Devil's Advocate（生き残り仮説 H2+H4 への自己攻撃）

H2+H4 への最強の反証: **per-report での CNAME 単一ホスト・新興ドメイン・地域広告という CB-addressable なロングテールは、まさに大手公開リストが構造的に苦手とする領域**であり、ここに特化したコミュニティ報告機能なら「取り込みだけ」を超える独自価値が出せる余地がある。Dimova の CNAME は top-10K の9.98%だが、ロングテール（地域・ニッチサイト）では公開リストのカバレッジが薄く、能動的な報告ユーザーがいれば局所的に優位を作れる。さらに hagezi が実質1人で582k エントリの DNS リストを CI 自動化で回せている事実は、「個人開発でも自動検証パイプラインで規模を出せる」ことの実証であり、H4 の「個人開発不可」を部分的に否定する。

この反証への再反論（なぜ H2+H4 が依然生き残るか）: (1) ロングテール CNAME の per-report ブロックは breakage しやすく whack-a-mole で、ユーザー数が少ない個人アプリでは報告ボリュームが集まらず正のフィードバックループが回りにくい。(2) hagezi の規模は「ドメイン集約の自動化」であって「新規広告の発見」ではない — 発見は依然人手で、しかも DNS 粒度（CB の url-filter には変換できるが 150k 上限で Light/mini 版しか載らない）。(3) durable な穴の本体（SSAI・first-party 動的生成）は CB-addressable 領域の外にあり、報告をいくら集めても閉じない。よって「報告で育つ」は **CB-addressable な遅延ロングテールの補完機能としては有効だが、製品の中核差別化としては過大評価**という H2+H4 の結論は保持される。

---

## 採用 / 除外
- 採用: 主要主張 ~22件（gh api 一次数値・査読論文6本・公式 KB/フィルタヘッダ）。
- 除外/格下げ: 「CNAME の EasyList miss率の見出し数値」（論文に存在せず表1カウントに格下げ=Med）/ AdGuard クライアントチェック間隔（KB非開示=Low）/ SSAI prevalence（学術未確認）/ tab-under prevalence（未確認）/ 0.13%/日 decay（lead のみ）。
- 除外理由: 一次ソースで裏が取れない、または single-source の見出し化を避けた。

## 未確認（明示）
- oisd 総ドメイン数（非開示）。
- AdGuard の正確なフィルタ再コンパイル/クライアントチェック間隔（10日 Expires 上限のみ一次）。
- EasyList の現在の総ルール数（2018論文の「60,000+」を流用=Med）。
- SSAI/SGAI の対ブロッカー prevalence・効果の定量（学術文献に存在せず）。
- ポップアンダー/tab-under の prevalence%。
- latency 数値は「close された report のみ」（survivorship bias・open backlog の難ケースは未サンプル）。

## 次に見れば確度が上がる問い
- 実機 iOS Safari で per-report の CNAME ホスト名ルールが実際に same-site 要求を止められるか（WKContentRuleList の url-filter が CNAME 解決後の最終ホストでなく URL 文字列を見る点の挙動確認）。
- 自アプリ（AdblockKeshi/ReportedRulesExtension）の報告→反映パイプラインの現状 latency と、報告がどの CB タグ類型に落ちるかの分類。
- 150k 上限下で EasyList+EasyPrivacy+地域リスト+報告ルールが収まるか、複数 content blocker への分割設計（AdGuard の6分割=900k が参考）。
- 地域（日本語）サイトでの公開リストカバレッジ実測（ロングテール優位の検証）。

## 出典（取得日 2026-06-16）
- https://arxiv.org/pdf/2102.09301 — Dimova et al. "The CNAME of the Game" (PoPETs 2021)
- https://gangw.cs.illinois.edu/imc2019-adblock.pdf — Alrizah et al. (IMC 2019)
- https://arxiv.org/pdf/1810.09160v3 — Snyder/Vastel/Livshits "Who Filters the Filters" (SIGMETRICS 2020)
- https://conferences.sigcomm.org/imc/2017/papers/imc17-final113.pdf — Iqbal et al. "The Ad Wars" (IMC 2017)
- https://arxiv.org/pdf/1605.05077 — Nithyanand et al. (FOCI 2016)
- https://www.cs.ucr.edu/~zhiyunq/pub/pets17_anti_adblocker.pdf — Mughees et al. (PETS 2017)
- https://webkit.org/blog/3476/content-blockers-first-look/ — WebKit Content Blockers（action/trigger 型・宣言的=JS不可）
- https://adguard.com/kb/adguard-for-safari/solving-problems/rule-limit/ — Safari 150,000 ルール上限・6分割
- https://bugs.webkit.org/show_bug.cgi?id=205719 — WKContentRuleList 上限 300k 要望（履歴）
- https://adguard.com/kb/general/ad-filtering/filter-policy/ — AdGuard フィルタチーム/ポリシー
- https://github.com/hagezi/dns-blocklists, https://github.com/StevenBlack/hosts, https://oisd.nl/faq — DNS リスト一次（README/FAQ/workflow）
- `gh api` (easylist/easylist, AdguardTeam/AdguardFilters, uBlockOrigin/uAssets, hagezi/dns-blocklists, StevenBlack/hosts) — commit_activity / issues / contributors（取得 2026-06-16）
