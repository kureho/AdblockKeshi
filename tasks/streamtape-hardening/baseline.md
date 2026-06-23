# Streamtape ポップアンダー再現調査（修正前 baseline）

- 対象: `streamtape.com` の動画埋め込みページ（`/v/<REDACTED>` ※検証用 URL のパス/ファイル名は規約により非記載）
- 計測日: 2026-06-23
- 計測環境: headless Chrome（system Chrome・channel:chrome）+ iPhone Safari 17.5 相当 UA + viewport 390x844 / isMobile / hasTouch
- ハーネス: `tasks/streamtape-hardening/harness/measure.js`（baseline モード）, `diagnose.js`（フレーム単位特定）
- コンテンツ保護: image / media / font リクエストは route で abort（動画本体・サムネを一切 DL しない）。
  cross-site の top-frame ナビは記録後 abort（広告ページを現在タブに読み込まない）。スクショ無し。
- 操作シナリオ: 1 ロードにつきプレーヤー領域中心の固定 10 タップ（中央=偽 play overlay 多め）。
- 反復: コールドロード × 3（ブラウザ毎回新規起動）。

## 修正前 実測値（measure.js baseline・全フレーム集計・3 ロード合計）

| 指標 | 値 | 備考 |
|---|---|---|
| 実 popup（新規タブ/ウィンドウ）総数 | **22**（7 / 7 / 8） | context.on('page') で実発火を計数 |
| うち cross-site（別 eTLD+1） | **19** | 広告サイトへの新規タブ |
| current-tab リダイレクト | **0** | 現在タブの外部遷移は無し |
| 捕捉した window.open | 4（全て cross-site・全て first-party stack） | 下記参照（過小：about:blank 由来は読み出し不可） |
| anchor.click()（合成クリック） | 0 | プログラム的 .click() 経由ではない |
| 既知広告網 script ロード（curated 30 網） | **0** | 安定網は使われない＝静的 $script で追えない |
| プレーヤー生存ロード | **3 / 3** | video/player DOM 検出・media リクエスト発火 |
| media リクエスト発火ロード | 3 / 3 | プレーヤーが正規 media を要求＝生存証跡 |

## フレーム単位の機構特定（diagnose.js）

`measure.js` の「実 popup 多数 / top-frame window.open=0」矛盾を `diagnose.js` で解明。各フレーム
（main + cross-origin iframe + 同一オリジン about:blank ヘルパー）に計装を入れ、クリック後に
全フレームの記録を回収した。決定的所見:

- **window.open は streamtape 自身の first-party 難読化インラインスクリプトから発火**。
  スタックトレース（抜粋・URL のクエリ/パスは伏せる）:
  ```
  at #O (streamtape.com/v/<REDACTED> :143:...)
  at HTMLDocument._0x35cf68 (streamtape.com/...)     ← 難読化された document クリックハンドラ
  ```
  → サイト本体（streamtape のページ）に同梱された難読化スクリプトが、document への
    クリックを契機に `window.open()` を呼ぶ。ロード元は streamtape 第一者なので、
    広告網ドメインの script-block では止められない。
- **window.open のターゲットは回転（gibberish）広告ドメイン**:
  `my.zoruftuiov.com` / `my.toruftuiov.com` / `zomayvin.cfd`（ロード毎・クリック毎に変化）。
  popup URL に付く base64 パラメータ（`ck9=`）をデコードすると `"pt":"tabup"`（タブアンダー）と
  `"q":"https://streamtape.com/v/<REDACTED>"`（参照元）が含まれ、タブアンダー広告であることが確定。
- **発火フレーム**: 同一オリジンの about:blank ヘルパーフレーム（streamtape 由来スクリプトが実行）。
  → MAIN-world オーバーライドの注入先として「同一オリジン子フレームへの伝播」が必要。
- gesture listener 登録元（回転ドメイン例）: `ij.cobolgammed.com` / `wo.nableroberto.com`（毎回変化）。
  安定網（realsrv/pemsrv 等）由来ではない＝列挙不能。
- cross-origin iframe: `www.google.com`（recaptcha/解析系。広告 popup 主因ではない）。

## 広告発生経路の分類（A–F）

- **主因 = C（first-party / inline window.open）**: streamtape 自身の難読化スクリプトが
  クリック契機で `window.open` を呼ぶ。宣言型 Content Blocker では原理的に止められない
  （サイト本体スクリプトを止めるとページが壊れる）。
- **+ B（回転ドメイン）**: ターゲット広告ドメインが毎回変化（`zoruftuiov.com`/`zomayvin.cfd`/…）。
  ドメイン列挙型のブロックは追従不能。既知広告網 script ロードは 0 件。
- **+ E（about:blank ヘルパーフレーム経由）**: window.open は同一オリジン about:blank
  フレームから発火する遅延型。
- **総合 = F（複合）**。ただし支配的・決定的なのは **C（first-party inline window.open）→ B（回転先）**。
- **該当しなかった経路**:
  - A（安定第三者広告ドメインの script）= 観測されず（known網ロード 0）。
  - D（透明 anchor / overlay クリック乗っ取り）= top-frame では overlay 検出 0 / anchor.click 0。
    （native `<a target=_blank>` は streamtape 自身の play ボタンの self ナビ `#` のみ＝良性）。

## 含意（対策の方向づけ）

1. **静的 Content Blocker（$script ドメインブロック）は無効**: 主因がサイト本体の first-party
   inline window.open であり、ターゲットが回転ドメインのため、`popunder-script-networks.txt`
   の拡充では止められない（known網ロード 0 が実証）。host-block（黒画面）は streamtape 本体を
   壊すため不可（プレーヤー破壊＝受入条件違反）。
2. **唯一実効的なのは MAIN-world での `window.open` 介入**（= Safari Web Extension 強力モード）。
   diagnose.js の MAIN-world オーバーライドが実際に first-party window.open を捕捉できた＝方式が効く実証。
3. **プレーヤー生存**: 正規 media リクエストは streamtape 自身のオリジンに出る。ブロック判定は
   「cross-site のプログラム的 window.open / 合成クリック」に限定すれば、プレーヤーの同一オリジン
   media / API は無傷（baseline で media 発火 3/3・別オリジンの fluidplayer 等は streamtape では不使用）。

修正後の実測（protection モード）は `verification.md` に記録する。
