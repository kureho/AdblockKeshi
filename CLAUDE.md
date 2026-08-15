# AdblockKeshi プロジェクト指示

## プロダクト
- iOS Safari Content Blocker、**無料 + 買い切り IAP『アプリ内広告ブロック』¥800**（v4.0 フリーミアム転換・2026-07-29 配信。〜v3 は買い切り ¥500）、シンプル極限訴求
- ターゲット: 「アドブロック」という言葉を知らない、Safari をもっと快適に使いたい層
- v1 spec: `~/claude/docs/superpowers/specs/2026-05-30-adblock-design.md`
- **v2.0 spec（セキュリティ機能追加）**: `~/claude/docs/superpowers/specs/2026-06-02-anti-phishing-design.md`

## 開発ルール
- Swift 5.10 / SwiftUI / iOS 17 SDK
- XcodeGen で project.yml 管理（.xcodeproj は git ignore）
- bundle id (app): com.kureho.adblockkeshi
- bundle id (extension): com.kureho.adblockkeshi.blocker
- App Group: group.com.kureho.adblockkeshi.shared
- Team ID: L455WPL8QZ

## やらないこと（v2.0 で一部更新・v4.2 で一部解除）
- カスタムフィルタ追加
- ~~サイト別ホワイトリスト機能~~ → **v4.2.0 で解除（2026-08-15 kureho 承認）**: 壊れ報告種別 +「このサイトで一時オフ」（Safari CB の per-site 例外・ignore-previous-rules のみ生成）を実装。設定画面型の常設ホワイトリスト UI は引き続き作らない（報告フロー起点 + 停止中リストの管理のみ）。設計 = `tasks/v42-design-2026-08-15.md`
- ブロック統計・履歴表示
- 通知・更新案内
- ~~設定画面なし~~ → **v2.0 でメイン画面に 2 トグル追加**（広告 / 詐欺サイト）。別「設定」画面は依然作らない

## v2.0 セキュリティ機能（参考）
- データソース: URLhaus (CC0 1.0) + Phishing.Database (MIT)
- 週次 GitHub Actions で生成: `.github/workflows/build-security-rules.yml`
- 4 通り組合せ動的選択: merged/ad-only/security-only/empty
- StateStore で App Group state.json 管理、500ms debounce で reload

## 関連メモリ
- `feedback_simulator_no_activate.md` — シミュレータ操作時 activate 禁止
- `feedback_pricing_metadata_strict.md` — App Store メタデータ価格表記禁止
- `reference_x_promo_stillcam_proven.md` — X¥1,500プロモ CPI¥3-4実証
- `feedback_content_blocker_must_bundle_full_ruleset.md` — v1.0.1 で確立、bundle 同梱必須
