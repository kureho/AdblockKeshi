# 広告消し v4.0: フリーミアム転換 + DNS 型アプリ内広告ブロック 設計書

作成: 2026-07-14（kureho 承認済みの方針: プランB=ローカル VPN 型・運用費ゼロ・本体無料+Pro ¥800）
根拠調査: `AdblockKeshi/tasks/v4-freemium-dns-plan.md`（市場・審査・技術・転換実務の4系統・一次ソース約90件）

## 1. 目的

広告消しの収益を月¥0〜740 から月¥7,000+ へ（kureho 目標「10倍」）。手段は (a) 有料の蓋を外して発見の複利（DL→評価→検索順位）を回し、(b) 競合の無料版に無い「アプリ内広告ブロック」を買い切り Pro の対価にする。

## 2. スコープ

**v4.0 に入るもの**
1. 価格転換: 本体 ¥500 → 無料 + 非消耗型 IAP「Pro」¥800
2. DNS 型アプリ内広告ブロック（Pro・ローカル VPN 方式・端末内処理）
3. grandfather: 既存購入者（¥500/¥700 世代）へ恒久 Pro 自動付与
4. 基本保護フィルタの凍結修理（CDN 実行時更新の配線 = 無料層の「生きたフィルタ」化）
5. 機能ゲート再編: 無料 = 基本保護（Safari CB）/ Pro = DNS ブロック + 報告反映 + 遷移保護
6. metadata 刷新（無人キーワード「アプリ 広告」系の刈り取り・訴求規律遵守）

**入らないもの（YAGNI）**
- サブスク（「ずっと買い切り」宣言と矛盾するため封印）
- 報告→DNS リストの自動反映（v4.x。v4.0 の DNS リストは curated）
- iOS 26 URL Filter 方式・DoH サーバー方式（調査済み・不採用）
- 詐欺特化の再ポジショニング（調査で非推奨と判定済み）

## 3. アーキテクチャ

```
┌─ 本体アプリ ──────────────────────────────┐
│ ProStore（新設）                            │
│  ├ grandfather 判定（AppTransaction）       │
│  ├ IAP 購入/復元（StoreKit 2・非消耗型）    │
│  └ Pro 状態の単一真実源（App Group 共有）   │
│ DNS 設定 UI（新設・Pro ゲート）             │
│  ├ ワンタップ有効化（NETunnelProviderManager）│
│  └ 限界明記・VPN 表示の説明画面             │
│ 既存: Safari CB 3拡張の管理 UI・報告 UI     │
└──────────┬───────────────────────┘
           │ App Group（Pro 状態・ブロックリスト・設定）
┌──────────┴───────────────────────┐
│ PacketTunnelExtension（新設・NEPacketTunnelProvider）│
│  ├ TunnelController: DNS のみ claim する狭い tunnel │
│  ├ DNSEngine（純関数・TDD 対象の中核）              │
│  │   parse → domain 抽出 → Blocklist 照合           │
│  │   → ブロック時 0.0.0.0/NXDOMAIN 応答を合成       │
│  │   → 非ブロック時 上流 DNS へ転送                 │
│  └ BlocklistStore: App Group から読込（mmap/Set）   │
└──────────────────────────────────┘
外部（すべて既存インフラ・無料）:
- GitHub Pages CDN: DNS ブロックリスト配信（新ファイル dns-rules.txt を既存 cdn/ に追加）
- 既存 FilterDownloader 系: 基本保護の実行時更新（凍結修理）+ DNS リスト取得に流用
```

### 設計判断（固定）

- **fail-open が最優先の不変条件**: DNSEngine はパース失敗・リスト未ロード・照合エラーのどの経路でも「素通し（上流転送）」に倒す。広告が見えるのは許容、**ユーザーの通信を壊すのは不許容**
- **tunnel は DNS（port 53）のみを claim**: 全トラフィックを通さない（バッテリー・複雑性・審査説明の全てで有利）。上流はシステム既定 DNS を維持
- **DNSEngine は NetworkExtension 非依存の純関数群**として切り出す（`DNSMessage` パース・`BlockDecision` 判定）。ユニットテストの主戦場
- **Pro 判定は ProStore の単一真実源**を App Group 経由で extension と共有（Pro でなければ tunnel 起動 UI 自体をゲート）
- Blocklist は起動時ロード + CDN 日次更新（既存 FilterDownloader パターン）。bundle 同梱の初期リストをフォールバックに（Content Blocker の bundle 同梱教訓と同型）
- Network Extension のメモリ上限（未確認・実測で確定）に備え、リストは Set<String>（ドメイン完全一致 + サフィックス一致）で保持し、上限超過時はリスト縮退

### grandfather（実装チェックリストは v4-freemium-dns-plan.md §grandfather を正とする）

要点: 閾値 = 転換ビルドの CFBundleVersion 未満・**Int 比較**・転換ビルド番号は 10000 へジャンプ / `environment == .production` 限定（審査環境で無効化 = 購入導線が審査員に見える）/ 一度付与したら恒久キャッシュ（剥奪しない）/ `refresh()` は復元ボタン起点のみ / originalPurchaseDate 補助判定の二段構え / **フェーズ0 で本番実機の削除→再インストール実測**（最大の残存不確実性の決着）

## 4. エラー処理

| 障害 | 挙動 |
|---|---|
| DNS パース失敗 / リスト未ロード | 素通し（fail-open） |
| 上流 DNS 無応答 | タイムアウト後そのまま無応答を返す（システムの再試行に委ねる・偽装しない） |
| tunnel 起動失敗 | UI にエラー + 再試行導線。Safari CB は独立して動作継続 |
| AppTransaction 取得失敗/ハング | タイムアウト → 黙って無料扱い（過少付与に倒す）+ 復元ボタン常設 |
| IAP 商品ロード失敗 | 明示 UI + リトライ（2026-01 reject 実例対策） |
| CDN 取得失敗 | 既存キャッシュ → bundle 同梱リストの順でフォールバック |

## 5. テスト戦略

- **TDD 対象（ユニット）**: DNSEngine（パース・照合・応答合成・fail-open 全経路）/ grandfather 判定（閾値・Int 比較・environment 分岐・キャッシュ恒久性）/ BlocklistStore（フォールバック順）
- **実機 E2E ゲート（提出前必須）**: ①本番購入済み実機で削除→再インストール→grandfather 実測（フェーズ0）②tunnel ON で実アプリ内広告のブロック目視 + 通常ブラウジング無破壊 ③VPN 排他・スリープ復帰・機内モード復帰
- **StoreKitTest**: 購入/復元/Pro 反映（iOS 18.3 sim の実 PASS 手法 = reference_storekittest_cli_workaround）
- **バナー UI テストは対象外**（広告消しは AdMob 非搭載）

## 6. 審査・リリース

- 提出は**手動リリース**・審査ノートに転換説明（実績文例 = v4-freemium-dns-plan.md §手順3）・初回 IAP はバージョン同時提出（公式必須）
- 承認後: **即時価格変更で無料化 → 実機で ¥0 確認 → 分単位でリリース**（窓は無害方向に限定）
- description に利用規約/プライバシーポリシーのリンク追加（reject 前例対策）・LP/外部の「¥500」表記の同時更新（2.3.1 false price）
- 訴求規律: 「他アプリの広告も**抑える**」・限界明記（YouTube 等不可）・metadata に価格/無料表記を書かない（2.3.7）
- 想定: 審査往復 1-2 回（却下でも live の Safari CB 版は無傷）

## 7. リスクと未確認事項（すべて kureho 提示済み）

①再インストール時の originalAppVersion 挙動（フェーズ0 実測で決着）②Network Extension メモリ上限の現行値（実測）③審査往復の可能性 ④無料化の実質不可逆性 ⑤「YouTube 消えない」失望レビュー（限界明記で緩和）⑥収益見立ては月¥1,600〜9,600 + 複利・撤退判定は転換後3ヶ月で月販 0-1 本なら追加投資停止
