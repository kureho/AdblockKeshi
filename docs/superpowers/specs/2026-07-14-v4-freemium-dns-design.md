# 広告消し v4.0: フリーミアム転換 + DNS 型アプリ内広告ブロック 設計書

作成: 2026-07-14 / 改訂 r2: 2026-07-15（spec レビュー C-1〜C-3・I-1〜I-7・M-1〜M-5 反映）
方針の確定経緯: kureho 承認（プランB=ローカル VPN 型・運用費ゼロ・本体無料+Pro ¥800）
根拠調査: `AdblockKeshi/tasks/v4-freemium-dns-plan.md`（市場・審査・技術・転換実務・一次ソース約90件）

## 1. 目的

広告消しの収益を月¥0〜740 から月¥7,000+ へ（kureho 目標「10倍」）。手段は (a) 有料の蓋を外して発見の複利（DL→評価→検索順位）を回し、(b) 競合の無料版に無い「アプリ内広告ブロック」を買い切り Pro の対価にする。

## 2. スコープ

**v4.0 に入るもの**
1. 価格転換: 本体 ¥500 → 無料 + 非消耗型 IAP「Pro」¥800
2. **Pro = DNS 型アプリ内広告ブロックのみ**（ローカル VPN 方式・端末内判定）
   - r2 変更: 報告反映・遷移保護は**無料のまま維持**（旧案の「Pro に含める」は撤回。理由: 既存2拡張のゲート改修は Safari 拡張のアーキテクチャ（storage.local 保持・native stub・popunder 基礎ルール同梱）と衝突し工数とリスクが大きい／Pro の対価の主柱は調査上 DNS／無料層が厚いほど DL・評価の複利が強い）
3. grandfather: 既存購入者（¥500/¥700 世代）へ恒久 Pro 自動付与
4. metadata 刷新（無人キーワード「アプリ 広告」系の刈り取り・訴求規律遵守・description に規約/ポリシーリンク追加・「買い切り（サブスクなし）」文言を「本体無料 + Pro 買い切り」へ再フレーミング）+ LP のプライバシーポリシーに DNS/VPN 処理の記述追加 + 「¥500 買い切り」表記の全更新（2.3.1 false price）

**前提（完了済み・v4.0 の作業対象外）**
- 基本保護/詐欺サイトブロックの CDN 実行時更新は **v3.5.0（commit 68ad6f9・RuleUpdater）で配線済み・現行 live v3.6.0 に同梱**。担い手は RuleUpdater（起動時 + 週次 BGTask・manifest sha256 差分・App Group 適用・reload）。FilterDownloader は ReportedGlobalSync/PopunderGlobalSync 専用のレガシー。v4.0 では **BGTask の実機発火確認（動作検証）のみ**行う

**入らないもの（YAGNI）**
- サブスク（「ずっと買い切り」宣言と矛盾・封印）
- 報告→DNS リストの自動反映（v4.x。v4.0 の DNS リストは curated）
- on-demand rules による再起動後の自動再接続（v4.x。v4.0 は手動 ON + 限界明記）
- iOS 26 URL Filter 方式・DoH サーバー方式・詐欺特化再ポジショニング（調査済み・不採用）

## 3. アーキテクチャ

```
┌─ 本体アプリ ──────────────────────────────────┐
│ ProStore（新設）                                 │
│  ├ grandfather 判定（AppTransaction）            │
│  ├ IAP 購入/復元（StoreKit 2・非消耗型）         │
│  └ Pro 状態の単一真実源 → App Group へ atomic 書出│
│ DNS 設定 UI（新設・Pro ゲート）                  │
│  ├ ワンタップ有効化（NETunnelProviderManager）   │
│  ├ NEVPNStatusDidChange 監視（設定アプリ側 OFF   │
│  │   や再起動後の未接続を UI に正直に反映）      │
│  └ 説明画面: VPN 表示の理由・他 VPN 排他・        │
│     再起動後は手動 ON・YouTube 等は不可          │
│ 既存: Safari CB 3拡張の管理 UI・報告 UI（不変）  │
└──────────┬─────────────────────────────┘
           │ App Group（Pro 状態・DNS ブロックリスト・設定）
┌──────────┴─────────────────────────────┐
│ PacketTunnelExtension（新設・NEPacketTunnelProvider）│
│  ├ TunnelController: sentinel IP 方式                │
│  │   dnsSettings.servers=[sentinel]・matchDomains=[""]│
│  │   includedRoutes = sentinel /32 + IPv6 sentinel のみ│
│  │   （DNS 以外のトラフィックは tunnel を通らない）  │
│  ├ PacketCodec（純関数）: IPv4/IPv6 + UDP ヘッダの   │
│  │   decode/encode（checksum 含む）                  │
│  ├ DNSEngine（純関数・TDD の中核）:                  │
│  │   DNSMessage parse → domain 抽出 → 照合 →         │
│  │   block 時 qtype 別応答合成 / 非 block 時 上流転送 │
│  ├ 上流 = 固定 public DNS（Cloudflare 1.1.1.1/1.0.0.1 │
│  │   + IPv6）へ plain UDP 転送。TCP:53 は上流へ最小  │
│  │   フォワード（自前でハングさせない）              │
│  └ BlocklistStore: App Group 読込 + tunnel 内         │
│     日次 self-fetch + sendProviderMessage reload      │
└────────────────────────────────────┘
外部（すべて既存インフラ・無料）:
- GitHub Pages CDN: DNS リスト配信（RuleUpdater の manifest + sha256 パターンを流用した
  新 variant として配信。FilterDownloader は使わない = JSON validity check が txt を弾くため）
```

### 設計判断（固定）

- **fail-open が最優先の不変条件（3層で保証）**:
  1. エンジン層: パース失敗・リスト未ロード・照合エラーは素通し（上流転送）
  2. transport 層: TCP:53 は上流へ最小フォワード（truncation retry をハングさせない）。UDP 上流タイムアウト時は応答なしを維持（偽装しない）
  3. リスト層: **CriticalDomainGuard を DNS 側にも移植**（push.apple.com 等の Apple インフラ・決済・主要 CDN ドメインはリストに何が来ても絶対にブロックしない）
- **応答合成は qtype 別**: A → 0.0.0.0 / AAAA → `::` / HTTPS・SVCB(type 65) → NODATA / その他 → NODATA。TTL は短め固定（実装時に定数化）
- **上流 = 固定 public DNS（Cloudflare 1.1.1.1）**: 「システム既定へ転送」は tunnel 確立後に自分自身を指すループになるため不採用。訴求整合: **ブロック判定とクエリログは端末内**（280blocker との差別化はここ）、名前解決先が ISP → Cloudflare に変わることはプライバシーポリシーと説明画面に明記
- **DNSEngine / PacketCodec は NetworkExtension 非依存の純関数群**（ユニットテストの主戦場）
- Pro 判定は ProStore 単一真実源 → App Group へ atomic 書出（既存 StateStore パターン踏襲）。tunnel は起動時に Pro を検証し、非 Pro なら起動拒否。**返金 edge**: tunnel 起動時再検証のみ（v4.0）— 走行中の失効は次回起動で反映
- リストはドメイン完全一致 + サフィックス一致の Set 構造。Network Extension のメモリ上限（既知の目安 ≈50MB・一次未確認 → 実装時に実測）内に収まるようリスト上限を設けて縮退
- **DNS リストの供給源**: 独自 curated（既存 popunder 研究の広告配信網ドメイン + 主要広告 SDK ドメインの自前調査）。外部リスト取り込み時は `docs/license-audit` の運用に従いライセンス確認（AdGuard 由来 GPL は不可）

### grandfather（実装チェックリストは v4-freemium-dns-plan.md §grandfather を正とする — 転記しない）

要点のみ: 閾値 = 転換ビルドの CFBundleVersion 未満・Int 比較・ビルド番号 10000 へジャンプ / `environment == .production` 限定 / 恒久キャッシュ / `refresh()` は復元ボタン起点のみ / originalPurchaseDate 補助判定 / Pro 状態でも購入・復元 UI に到達可能 / 商品ロード失敗の明示 UI

### フェーズ0（実装前の実測・スケジュール前提）

再インストール時の `originalAppVersion` 挙動は本番 receipt でしか観測できない（TestFlight/開発署名は sandbox）。**先行diagnostics リリース（v3.6.1・設定画面のバージョン行 連打で AppTransaction 診断値を表示する隠し画面）を1回挟む** → kureho の購入済み実機で「削除 → 再インストール → 診断値確認」。これによりリリースサイクルが1回増えることを計画に織り込む。

## 4. エラー処理

| 障害 | 挙動 |
|---|---|
| DNS パース失敗 / リスト未ロード / 照合エラー | 素通し（fail-open 層1） |
| TCP:53（truncation retry） | 上流へ最小フォワード（fail-open 層2） |
| 上流 DNS 無応答 | タイムアウト後そのまま無応答（偽装しない） |
| リストに critical ドメイン混入 | CriticalDomainGuard が遮断を拒否（fail-open 層3） |
| tunnel 起動失敗 / 設定アプリ側 OFF / 再起動後未接続 | NEVPNStatusDidChange で UI に正直反映 + 再試行導線。Safari CB は独立動作継続 |
| AppTransaction 取得失敗/ハング | タイムアウト → 黙って無料扱い（過少付与に倒す）+ 復元ボタン常設 |
| IAP 商品ロード失敗 | 明示 UI + リトライ（2026-01 reject 実例対策） |
| CDN 取得失敗 | 既存キャッシュ → bundle 同梱初期リストの順でフォールバック |

## 5. テスト戦略

- **TDD 対象（ユニット）**: PacketCodec（IPv4/IPv6+UDP decode/encode・checksum）/ DNSEngine（parse・照合・qtype 別応答合成・fail-open 全経路）/ CriticalDomainGuard（DNS 版）/ grandfather 判定（閾値 Int 比較・environment 分岐・キャッシュ恒久性・purchaseDate 補助）/ BlocklistStore（フォールバック順・上限縮退）
- **StoreKitTest**: 購入/復元/Pro 反映（iOS 18.3 sim 実 PASS 手法）
- **実機 E2E ゲート（提出前必須・具体手順）**:
  1. フェーズ0: 本番購入済み実機で削除→再インストール→診断値確認（v3.6.1 経由）
  2. アプリ内広告ブロック目視: 対象3アプリ固定（自作 AdMob 搭載アプリ + 無料ニュース系 + カジュアルゲーム1本）で tunnel OFF→ON のバナー領域スクショ比較
  3. ネガティブコントロール: YouTube 広告が**消えない**こと（限界明記文言との整合確認）
  4. DEBUG 限定クエリログで block 判定経路を確認
  5. 無破壊確認: 主要サイト20件巡回 + 決済/ログイン系1件 + スリープ復帰・機内モード復帰・他 VPN との排他挙動

## 6. 審査・リリース

**転換リリースの全手順は v4-freemium-dns-plan.md §転換リリース手順を正とする**（転記しない。要点: 手動リリース・Phased Release オフ・評価リセット絶対禁止・CFBundleVersion 履歴一覧化・初回 IAP はバージョン同時提出・審査ノート実績文例・承認後は即時無料化 → ¥0 確認 → 分単位でリリース・LP/外部の価格表記同時更新）。
- 訴求規律: 「他アプリの広告も**抑える**」・限界明記・metadata に価格/無料表記なし（2.3.7）
- project.yml/entitlements の作業項目: app + extension 両方に `packet-tunnel-provider`、extension に App Group（+ 必要なら keychain-access-groups）追加
- 想定: 審査往復 1-2 回（却下でも live の Safari CB 版は無傷）

## 7. リスクと未確認事項（すべて kureho 提示済み）

①再インストール時の originalAppVersion 挙動（フェーズ0 実測で決着）②Network Extension メモリ上限の現行値（実測）③審査往復の可能性 ④無料化の実質不可逆性 ⑤「YouTube 消えない」失望レビュー（限界明記で緩和）⑥上流 1.1.1.1 化のプライバシー説明責任（ポリシー明記で対処）⑦収益見立ては月¥1,600〜9,600 + 複利・撤退判定は転換後3ヶ月で月販 0-1 本なら追加投資停止
