# ASO / 評価ベースライン スナップショット — 2026-06-17（v3.2.0 承認・配信開始時点）

> v3.2.0 build 22（報告→反映ファストレーン＋ポップアップ広告対策）承認・READY_FOR_SALE 確認直後に記録。
> 30日後（2026-07-17 目安）に同条件で再取得し、レビュー施策v2＋Phase3 の効果を測定する起点。
> 取得方法: iTunes 公開 API（lookup / search・認証不要・JP）。**実 App Store 検索ランクではなく Search API 近似**である点に注意。

## 評価ベースライン（JP）
- trackName: 学習する広告消し - 消えない広告もブロック
- version: 3.2.0
- price: ¥500 / Utilities
- **averageUserRating: 5.0 / userRatingCount: 1**
- averageUserRatingForCurrentVersion: 5.0 / userRatingCountForCurrentVersion: 1

→ レビュー母数がほぼゼロ（★5×1件）。レビュー依頼施策v2の効果はここからの件数増で測る。

## 検索 rank 近似（iTunes Search API・JP・top100 内順位）
| キーワード | 順位 |
|---|---|
| 広告消し | **#24** |
| 広告ブロック | 圏外（top100外） |
| adblock | 圏外 |
| コンテンツブロッカー | 圏外 |
| 広告 ブロック | 圏外 |
| アドブロック | 圏外 |
| 広告 非表示 | 圏外 |

→ 自社名「広告消し」でしか引っかからない＝**流通/認知が律速**（memory の診断を数値で裏付け）。keywords 改善（広告ブロック/adblock/コンテンツブロッカー の未カバー解消）は次版同梱予定。

## 配信監査（4点・2026-06-17 ALL PASS）
- ① reviewSubmission `9e013833` = COMPLETE / v3.2.0 = READY_FOR_SALE・READY_FOR_DISTRIBUTION
- ② availableInNewTerritories = True
- ③ price points 200件
- ④ IAP 無し → 対象外
