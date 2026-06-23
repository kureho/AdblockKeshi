# Streamtape 広告ブロック強化 — 実装設計書

対象: `streamtape.com`（動画埋め込みページ）で残るタブ乗っ取りポップアップの根絶。
関連: `baseline.md`（再現調査）/ `verification.md`（修正前後の実測）。

## 1. 根本原因（実測で確定）

streamtape 自身の **first-party 難読化インラインスクリプト**（`HTMLDocument._0x35cf68` に束ねた
document クリックハンドラ）が、クリック契機で `window.open()` を呼び、**回転する広告ドメイン**
（`zoruftuiov.com` / `toruftuiov.com` / `zomayvin.cfd` 等・ロード毎に変化）へ新規タブ（tabunder）を開く。
発火元は同一オリジンの about:blank ヘルパーフレーム（ロード時点で既に存在）。

- 広告発生経路の分類（A–F）: **C（first-party/inline window.open）＋ B（回転ドメイン）＋ E（about:blank 経由）= F 複合**。
  支配的・決定的なのは **C → B**。A（安定第三者網 script）/ D（透明 overlay）は streamtape では主因ではない。
- 実測: 3 コールドロードで cross-site popup 19 件（7/7/8）、既知広告網 script ロード 0 件、プレーヤー生存 3/3。

## 2. 静的 Content Blocker では解決不可（Phase 2・実測で確定）

- 主因がサイト本体の first-party inline `window.open` であり、ターゲットが回転ドメインのため、
  `popunder-script-networks.txt`（ドメイン列挙の $script ブロック）では追えない。
- host-block（黒画面）は streamtape 本体スクリプトを壊す＝プレーヤー破壊で受入条件違反。
- **実証**: L1（既知網）+ L2（対象サイトの third-party script 全 block）を network 層で模擬しても、
  third-party script は止まる（22→7）が first-party popunder は残存（7 件・cross-site・プレーヤー生存）。

### 採用した静的対策（defense-in-depth・必要だが十分ではない）

`popunder-aggressive-sites.json` に streamtape の L2 エントリを追加（block 全 third-party script →
allow は実測 present かつ既知安全な `gstatic.com`/`google.com` のみ＝recaptcha 温存）。
これは third-party script 由来広告を 22→7 に減らす。**主因の first-party popunder は次節の強力モードが担う**。

## 3. 強力モード（Safari Web Extension）= 決定的対策

first-party inline `window.open` を止められるのは **ページの MAIN world で `window.open` を介入する**方法のみ。
宣言型 Content Blocker には不可能。よって独立の Safari Web Extension ターゲット `PopupShieldExtension` を追加。

### 構成

- `popup-shield-core.js` — 純関数の判定エンジン（`makeDecider(siteHost)`）。Node でユニットテスト可能。
  主信号 = **クロスサイトのプログラム的遷移**。タップ位置は使わない（プレーヤー保護）。
- `popup-shield.js` — MAIN-world content script。`window.open` / 合成 `anchor.click()` / native
  `target=_blank` / 同一オリジン子フレームの `window.open` を計装し、core の判定で cross-site の
  プログラム的遷移だけを止める。**同一オリジン子フレームへ override を伝播（traversal + MutationObserver）**
  し、iOS 17 が about:blank フレームへ content script を注入しない制約を補う。
- `background.js` — `storage.local` の {enabled, pausedHosts} に応じて
  `scripting.registerContentScripts({world:"MAIN", allFrames:true, runAt:"document_start"})` で登録/解除。
  **既定 OFF = 何も注入しない**。件数のみ集計（URL・内容は保存しない）。
- `popup.html`/`popup.js` — 強力モードの ON/OFF（明示・既定オフ）+ サイト別一時停止 + ブロック件数表示。
- `SafariWebExtensionHandler.swift` — ネイティブハンドラ（state は持たず空応答。将来のアプリ連携フック）。
- アプリ内 `StrongModePermissionNote`（SwiftUI）で権限理由・プライバシーを日本語説明。

### 判定ルール（core）

| 種別 | 条件 | 動作 |
|---|---|---|
| window.open / iframe.open | cross-site URL | **block**（null 返し） |
| window.open / iframe.open | same-site | allow（1 ジェスチャ複数遷移は抑止） |
| window.open / iframe.open | about:blank / 空 | **stub**（非 throw な安全スタブ・遅延 popunder=E 無害化） |
| window.open | javascript: / 相対 | allow |
| anchor.click()（合成） | cross-site | **block** |
| native `<a target=_blank>` | cross-site かつ overlay（透明/全面/文字なし） | **block**（乗っ取り=D） |
| native `<a target=_blank>` | cross-site だが通常リンク（可視・テキスト/アイコンあり） | allow（正規リンクを壊さない） |

### 権限・プライバシー（最小）

- `permissions: ["scripting", "storage"]`、`host_permissions` は **実測済み高リスクサイトに限定**
  （`streamtape.com` / `tokyomotion.net`）。`<all_urls>` は要求しない。
- 既定 OFF。ユーザーが明示的にオンにしたときだけ、対象サイトに content script を登録。
- ネットワーク送信なし。ログは端末内の件数・分類（reason）のみ（URL・ページ内容・履歴は保存も送信もしない）。

## 4. 検証（詳細は verification.md）

- core: Node ユニットテスト 19 件（mutation で歯を確認）。
- hook: 決定論 fixture（`PopupShieldExtension/Tests/fixtures/`）を **top-frame のみ注入＋traversal** で実行し、
  全ベクタの block と正規操作の生存を確認（iOS 17 のフレーム制約を忠実モデル化・traversal も mutation で検証）。
- background: 登録計画 純関数のユニットテスト 5 件。
- 実 streamtape: protection モードで **cross-site popup 0**（baseline 19 → 0）・プレーヤー/メディア生存 3/3。

## 5. 研究結論（research-rigor）— Safari Web Extension の MAIN world 可否

### ACH

| 証拠 | H1: 宣言的 manifest world:MAIN（iOS17 可） | H2: iOS17 は MAIN 不可→CSP bridge | H3: scripting.registerContentScripts world:MAIN（iOS16.4+） |
|---|---|---|---|
| Apple エンジニア「Safari 16.4 は registerContentScripts で MAIN サポート」(2023) | 不一致（manifest は対象外と明言） | 不一致 | 一致 |
| forum: 宣言的 world:MAIN は未確認・OP は実地で動かないと報告 | 不一致 | 部分一致 | 中立 |
| Safari 18.4 で match_about_blank / match_origin_as_fallback 追加 | N/A（about:blank は別問題） | N/A | N/A（traversal で補う） |
| 「MAIN world は page CSP の影響を受ける／Safari は CSP bypass 不可」 | リスク | bridge は CSP 被弾 | override 自体は CSP 非対象操作=一致（caveat） |
| streamtape は CSP ヘッダ・meta 共に無し（実測） | — | 当該サイトでは無害化 | 当該サイトで完全に有効 |

→ 生存仮説 = **H3**（`scripting.registerContentScripts({world:"MAIN"})` で注入。override は関数再代入＝
CSP 非対象操作のため、ブラウザ注入の MAIN world コードは streamtape の CSP（そもそも無し）に左右されない）。

### Devil's Advocate

Apple の言明は 2023 年で「実地で動かない」報告も付く。iOS 17 実機で `registerContentScripts world:MAIN`
が override を実際に実行するかは device 確認しないと断定できない。また about:blank 子フレームへの注入は
iOS 18.4 以降のため、iOS 17 では親→子 traversal に依存する。**反証への応答**: streamtape のヘルパーフレームは
同一オリジン about:blank で、ロード時点で既に存在することを実測（traversal が click より先に override を仕込める）。
fixture を top-frame のみ注入＋traversal で実行し、この機構が機能することを実証済み（mutation で traversal を切ると漏れる＝テストに歯がある）。クロスオリジン広告 iframe 由来の popunder は届かない＝既知の限界として明記。

### 採用 / 除外
- 採用: H3（scripting.registerContentScripts world:MAIN）。
- 除外: H1（宣言的 world:MAIN・iOS17 で信頼できない）/ H2（bridge・CSP 被弾サイトで破綻）。
- 除外理由: 一次情報（Apple）+ 実測（streamtape は CSP 無し）で H3 の矛盾が最少。

### 未確認
- iOS 17 実機 Safari で `registerContentScripts({world:"MAIN"})` が override を実行するか（提出前 device 確認必須）。
- 強力モード ON 後の実機 streamtape 目視（3回×10操作）。
- CSP を持つ別サイトでの挙動（streamtape は CSP 無しのため当該検証は別途）。
- iOS の `tabs.onCreated`/`remove` 可用性（不確実なため安全ネットには非依存）。

### 次に見れば確度が上がる問い
- iOS 17 実機での registerContentScripts world:MAIN の動作ログ（device 必須）。
- host_permissions のミラードメイン（streamtape.to/.cc 等）カバレッジ（現状は streamtape.com のみ＝既知の限界）。

## 6. 既知の限界（正直な明記）

- **クロスオリジン広告 iframe 由来の popunder は対象外**: content script は host_permissions 対象フレームにしか
  入らないため、別オリジンの広告 iframe が自前の window.open で開く popunder には届かない（streamtape の主因は
  same-origin first-party のためカバー範囲内）。
- **子フレームへ伝播するのは window.open のみ**: 親→子 traversal は同一オリジン子フレームに window.open override を
  伝播するが、`anchor.click` prototype override と native overlay の capture 捕捉は親 realm のみ。同一オリジン
  子フレーム発の合成 anchor / overlay vector は捕捉しない（支配的な window.open はカバー）。
- **動的 iframe の同一タスク内 race**: クリックハンドラ内で iframe を生成し同期的に
  `contentWindow.open` する極端なケースは取りこぼし得る（ジェスチャ開始時の再走査で大半は緩和）。
- **same-site about:blank の正規利用**: vector E 無害化のため about:blank を一律スタブ化する。
  同一サイトの正規 about:blank 利用（印刷ビュー等）が壊れる可能性を受容（高リスクサイト限定スコープ）。
- **ミラードメイン非対応**: host_permissions は `streamtape.com` のみ。streamtape.to/.cc 等のミラーは未対象
  （実測したドメインに限定する方針。追加は実測してから）。
- **拡張アイコン未設定**: manifest に icons 未指定（システム既定）。提出前に追加すること。
- **iOS 17 実機での world:MAIN 実行は未確認**（§5 Devil's Advocate・提出前 device 確認必須）。

## 出典（取得日: 2026-06-23）
- Apple Developer Forums thread/728849「Support for world:MAIN in Safari content scripts」（Apple Frameworks Engineer: Safari 16.4 supports MAIN for registerContentScripts）
- WebKit Features in Safari 18.4（Expanded Subframe Injection: match_about_blank / match_origin_as_fallback）
- Apple「Assessing your Safari web extension's browser compatibility」（iOS は windows API 等一部非対応）
- 実測: streamtape /v/ ページの応答ヘッダ・HTML に CSP 無し（curl, 2026-06-23）
