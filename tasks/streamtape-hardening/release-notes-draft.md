# リリースノート草案 — v3.4.0（強力ポップアップ対策）

> ⚠️ 草案。提出は kureho 判断。価格表記 NG 語（¥/円/無料/Free/iPhone/iPad/iOS/Safari/Siri）を含めない。

## whatsNew（App Store・ユーザー向け）

```
動画・まとめサイトで「タップすると別の広告サイトに飛ばされる」しつこいタブ乗っ取りに、新しい対策を追加しました。

・新機能「強力ポップアップ対策」（任意・初期はオフ）
  対象サイトに限り、サイト自身のスクリプトが開くタブ乗っ取りを止めます。機能拡張としてご自身でオンにしたときだけ動作し、サイトごとに一時停止もできます。閲覧履歴やページの内容を外部に送ることはありません。

・ポップアップ広告対策のルールを更新しました。
```

## reviewNotes（審査向け・提出版の機能を反映）

```
本バージョンの主な変更:

1) 新規 App Extension「PopupShieldExtension」（Safari Web Extension）を追加。
   - 目的: 一部の動画/ファイルホスト系サイトで、サイト自身の first-party スクリプトが
     ユーザーのタップ契機に window.open でタブ乗っ取り広告（tab-under）を開く挙動を抑止する。
     宣言型 Content Blocker では介入できないため Web Extension 方式を採用。
   - 既定は無効。ユーザーが機能拡張を有効化し、ポップアップ内のトグルを明示的にオンにしたときのみ動作。
   - 権限は scripting / storage と、限定した host_permissions（実測済みの高リスクサイトのみ。<all_urls> 不要）。
   - プライバシー: ネットワーク送信なし。端末内でブロック件数のみを集計し、URL・ページ内容・閲覧履歴は
     保存も送信もしない。サイトごとに一時停止可能。
2) ポップアップ広告対策（Content Blocker）の宣言型ルールを更新（対象サイトの third-party 広告 script 抑止）。

動作確認: シミュレータでアプリ/全拡張のビルド・ユニットテスト・WebKit Content Rule List コンパイルを通過。
強力モードの判定ロジックは決定論テストおよび実サイト計測（修正前後比較）で検証済み。
```

## App Privacy（変更なし想定）

強力モードはデータを外部送信しないため、App Privacy の宣言に追加項目は生じない見込み。
（提出時に Web UI で再確認すること。）

## 提出前 kureho 確認事項（必須）

1. iOS 17 実機 Safari で `scripting.registerContentScripts({world:"MAIN"})` が override を実際に実行するか目視
   （Apple は 16.4+ サポート言明だが実機確認必須）。
2. 強力モードをオンにして実機 streamtape で 3 回×操作の目視（タブ乗っ取り 0・プレーヤー再生 OK）。
3. PopupShieldExtension のアイコン未設定 → 提出前に追加（manifest からは省略済み・現状はシステム既定）。
4. App Privacy 再確認・価格表記 NG 語チェック・4 点監査。
