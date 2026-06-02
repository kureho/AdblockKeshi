# AdblockKeshi プロジェクト指示

## プロダクト
- iOS Safari Content Blocker、買い切り **¥500**、シンプル極限訴求
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

## やらないこと（v2.0 で一部更新）
- カスタムフィルタ追加
- サイト別ホワイトリスト機能（v2.0 でも維持。誤検知時はトグル全体 OFF）
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
