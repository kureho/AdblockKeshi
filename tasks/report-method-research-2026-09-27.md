# 報告をブロックに反映する方法の調査（2026-09-27）

kureho への問い「最後にルールにするかの確認を誰がやるか（案 A＝Claude が週 1 回人の目／案 B＝自動のまま関門を下げる）」への回答が「もっといい方法ない？」。
前段の点検記録: `/Users/oharakureho/claude/AdblockKeshi/tasks/report-pipeline-audit-2026-09-27.md`（台帳 A-88）

## 1. 問いの置き直し
- P: 広告消しの「広告が消えていない」報告（4 か月で 22 件・全部別サイト・週 1 件強）
- I: 報告をルールにする方法
- C: 案 A（人の目・週 1）／案 B（自動・関門を下げる）
- O: 反映される割合と速さ・いたずらへの強さ・誤ブロックの少なさ・手間
- 決めたいこと: 報告の仕組みをどの形で作り直すか
- 条件（kureho の言葉のみ）: 「報告はタブにある方がいい！それが大切なメイン機能」＝報告機能は残す前提。「もっといい方法ない？」＝A と B の二択に限らない

## 2. 仮説
- H1 報告は「どこを見るか」だけに使い、「何を消すか」は信頼できる公開リストとの照合で自動で決める（1 件で即反映・いたずらに強い）
- H2 業界の標準どおり人が判定する（＝案 A）
- H3 自前の自動判定（今の L6）を強め、そのサイト限定で関門を下げる（＝案 B の改良）
- H4 報告より先に、同梱ルールそのものの質（上限での切り捨て・古さ）を直す方が効く
- H5 報告の多くは Safari の仕組みでは原理的に消せない種類で、ルールを足しても解消しない

## 3. 集めた証拠（出典は末尾）

| # | 証拠 | 出どころ |
|---|---|---|
| E1 | 大手・同種 9 製品（AdGuard・uBlock/EasyList・Brave・280blocker・1Blocker・Wipr・ABP・Ghostery・Firefox）はすべて**入口は自動、判定は人**。報告 1 件から自動でルールを作る商用例は見つからない | 他社調査 |
| E2 | EasyList の 9 年分の報告 23,240 件の分析（IMC 2019）: 「広告が消えていない」報告で**正しかったのは 20.6%**。却下の 62.8% は情報不足 | Alrizah ほか |
| E3 | 人が判定しても誤ブロックは起き、その 65% は運営側が足した悪いルールが原因。誤ブロックの半数超は発見まで 1 か月以上 | 同上 |
| E4 | 大手の人の判定でも反映まで中央値 1〜2 日（AdGuard・uBlock の直近 issue を集計・小サンプル） | 他社調査 |
| E5 | **同梱ルールは上限 15 万件に張り付き、4 つのリストを連結して変換した結果の後ろがはみ出して落ちている**（`scripts/convert.sh:52-71`・CDN の `blockerList.json` も 15 万件ちょうど）。セキュリティと合わせた版はさらに 13 万件で後ろを切る（`scripts/build_merged_rules.py:15-27`）。実例: amoad.com（報告されたサイト）のルールが 13 万件版で消えている | 手元のコード・実測 |
| E6 | 報告されたサイトのうち tokyomotion.net・uranai.nosv.org・thedigestweb.com は**既にルールが同梱済み**なのに報告された＝リスト漏れではなく、ルールがサイトの今の作りに合っていない可能性（未検証） | 手元の実測 |
| E7 | mangaraw.ac・spoilerplus.tv・bkan.vbest はどのリストにも無い | 手元の実測 |
| E8 | 22 件中 6 件は「アプリ内の広告」＝Safari 用ルールではそもそも消せない。3 件は開発テスト | D1 |
| E9 | 今の自動判定 L6 は、決め打ちの広告ドメイン 14 個と「ad/banner」等を含む class 名を数える簡易判定（`scripts/validation/playwright-runner.ts:9-52`）。しかも**米国の GitHub の実行環境**でページを開く＝日本の広告が出ない可能性（`.github/workflows/daily-validation.yml:17`） | 手元のコード |
| E10 | 上限の回避は各社とも「コンテンツブロッカーを複数に分ける」（AdGuard 6 本・1Blocker 7 本・Wipr 3〜4 本） | 利用条件調査 |
| E11 | Firefox は報告の一次振り分け（無効な報告を閉じる）を機械で自動化し、判定は人がする | 他社調査 |
| E12 | 本人の端末だけに効く即時ルール（要素ピッカー）は他社で一般的。ただしこのアプリは 8 月に「報告は改善用データで、その端末のブロック指定ではない」として本人即時反映を廃止済み（`tasks/dlite-design-2026-08-11.md:70`）。Safari のコンテンツブロッカー単体ではページ上の要素を選ぶ UI も作れない | 他社調査・手元 |
| E13 | 報告は週 1 件強（22 件 / 4 か月）＝人が見ても負担は小さい | D1 |

## 4. 仮説の突き合わせ（ACH）
○=矛盾しない ✕=矛盾する －=関係なし

| 証拠 | H1 リスト照合で自動 | H2 人が判定 | H3 自前判定を強めて自動 | H4 同梱ルールの質 | H5 原理的に消せない |
|---|---|---|---|---|---|
| E1 自動の商用例なし | ✕ | ○ | ✕ | － | － |
| E2 正しい報告は 2 割 | ○（報告の中身を信じない） | ○ | ✕ | ○ | ○ |
| E3 人でも誤ブロック | ○ | ✕（人なら安全、ではない） | ✕ | － | － |
| E5 上限で切り捨て | ○（落ちたルールを戻せる） | ○ | － | ○ | － |
| E6 同梱済みなのに報告 | ✕（照合しても足すものが無い） | ○ | ✕ | ○（古さ） | ○（第一者配信の可能性） |
| E7 どのリストにも無い | ✕ | ○ | ○ | － | － |
| E8 アプリ内広告 6 件 | － | － | － | － | ○ |
| E9 L6 は簡易・米国で開く | ✕（ページを開く部分は同じ弱点） | － | ✕ | － | － |
| E13 週 1 件強 | － | ○（負担が小さい） | － | － | － |
| **✕ の数** | **4** | **1** | **5** | **0** | **0** |

- 生き残るのは **H4（同梱ルールの質）・H5（消せない種類の切り分け）・H2（人の判定）**。三者は両立する（ぶつからない）
- H1 は「上限で落ちたルールを戻す」部分（E5）だけが効き、報告の大半（E6・E7）には効かない
- H3（案 B）は ✕ が最多＝いちばん弱い

## 5. 反論（生き残った案への攻撃）
H4 への反論: 上限は Safari の仕様で、コンテンツブロッカーを分ければ枠は増えるが、そのぶん利用者が「設定」でオンにするスイッチが増える（E10）。このアプリの利用者は「アドブロックという言葉を知らない層」なので、スイッチが増えるほど設定から脱落する恐れがある。分けずに「日本のスマホで効くルールを優先して詰める」方式なら手間は増えないが、6/2 の記録では並べ替えただけで yahoo.co.jp の効きが 70→0 に落ちた（`scripts/filters.yml:3-8`）＝並べ替えは副作用が大きく、効果を測りながら進める必要がある。
H2 への反論: 人（Claude）の判定も米国ではなく日本の端末でページを見ないと広告が出ない恐れ（E9 と同じ）。人が見ても誤ブロックは起きる（E3）。週 1 回だと反映まで最長 1 週間。
H5 への反論: 「消せない」と判定して返すのは、報告者にとっては「対応されなかった」と同じに見える。伝え方を誤ると★1 の原因になる（8 月の問い合わせ 2 件・★1 は「報告できない」由来）。
→ それでも、A と B のどちらか一方より、下の組み合わせのほうが ✕ が少なく、報告者以外の利用者にも効く。

## 6. 結論（推奨）
**「全員に効く土台の修理」＋「報告は人が週 1 回判定」＋「報告者に結果を返す」の 3 点セット**。

1. **土台を直す（H4）** — 上限で機械的に切り捨てている今の詰め方を、日本のスマホで効くルールを優先する詰め方に変える。報告されたサイトで落ちていたルール（amoad.com 等）はここで戻る。報告した人以外の全員に効く。並べ替えの副作用が大きいので、主要サイト（yahoo.co.jp ほか）の効きを前後で測りながら入れる
2. **報告は Claude が週 1 回、日本の端末（シミュレータの Safari）で実際にページを開いて判定**（H2＝案 A の中身を具体化）。広告と確かめたものだけ、そのサイト限定のルールにして配信。結果は朝のレポートに出す
3. **報告者に結果を返す（H5）** — 履歴に「確認中／反映済み／このアプリでは消せない種類（アプリ内広告・サイト自身が出す広告）」を出す。アプリ内広告の報告には「アプリ内広告ブロック」の案内を出す
4. 点検で見つけた送信エラー表示の不具合と、約束の文言（「7〜14 日」・ストア説明文）の修正は、これとは独立に直す

案 A との違い: 人が見るのは同じだが、①土台の修理で「そもそも報告しなくても消える」広告が増える ②日本の端末で見るので米国で開く自動判定より正確 ③報告者に結果が返る。
案 B（自動で関門を下げる）は採らない: 報告の 8 割は正しくないという実測（E2）があり、今の自動判定は簡易で米国から開いている（E9）ため、いたずらや誤報告がそのまま普通のサイトの表示崩れになる。

## 採用 / 除外
- 採用: 4 件（H4・H2・H5 の組み合わせ＋送信エラーの修正）/ 除外: 2 件（H3＝案 B、H1 の単独採用）
- 除外理由: H3 は ACH で矛盾が最多（5）。H1 は上限で落ちたルールの復活にしか効かず、それは H4 で全員向けにやる方が広く効くため単独では採らない（H4 の中に吸収）

## 未確認
- 4 つのリスト全量を変換すると何件になり、上限でどれだけ落ちているか（変換ツールが 15 万件で止めるため件数が出ていない）
- 同梱済みなのに報告されたサイト（E6）が「ルールが古い」のか「サイト自身が配信する広告で消せない」のか（実ページとの突き合わせ未実施）
- 日本の広告配信が米国の IP に対して出ないのか（L6 の判定の当てにならなさの程度）
- iOS 17 以降、上限未満でもルールの読み込みに失敗する不具合（AdGuard が Apple に報告済み）がこのアプリで起きているか
- ライセンス: GPLv3 のリストから作ったルールを有料アプリに同梱することの扱いは公式の明言が無い。ただしこのアプリのリポジトリは公開（`github.com/kureho/AdblockKeshi`＝生成スクリプトと変換後ルールが公開済み・同梱のライセンス表記 3 本あり）で、1Blocker が取る「リスト部分を公開する」形と同じ状態にある。法的な確定は未確認
- 280blocker・Peter Lowe's list は商用利用禁止＝使わない（現状も未使用）

## 次に見れば確度が上がる問い
- 変換ツールに上限を外して全量を変換させたら何件になるか（落ちているルールの量と中身）
- 報告された 22 件のページを日本の端末で開き、今のルールで何が残るか（E6 の切り分け）
- 並べ替えで主要 20 サイトの効きがどう変わるか（6/2 の yahoo.co.jp 70→0 の再発防止）

## 出典（取得日: すべて 2026-09-27）
- Alrizah, Zhu, Xing, Wang, "Errors, Misunderstandings, and Attacks: Analyzing the Crowdsourcing Process of Ad-blocking Systems", ACM IMC 2019 — https://gangw.cs.illinois.edu/imc2019-adblock.pdf
- AdGuard 報告ツール https://reports.adguard.com/en/new_issue.html ／ https://github.com/adguardteam/adguardfilters/issues
- uBlock Origin https://github.com/uBlockOrigin/uAssets ／ EasyList フォーラム https://forums.lanik.us/viewforum.php?f=62
- Brave https://github.com/brave/brave-browser/wiki/Web-compatibility-reports
- 280blocker https://280blocker.net/faq-android/ ・ https://280blocker.net/terms-ios/
- 1Blocker https://support.1blocker.com/en/ ・ https://github.com/1Blocker/Filters
- Wipr https://kaylees.site/wipr-faq.html
- Adblock Plus https://help.adblockplus.org/adblock-plus-help-center/report-an-issue-via-the-issue-reporter
- Firefox webcompat https://webcompat.com/contributors/reproduce-bug ・ https://github.com/mozilla/webcompat-team-okrs/issues/194
- EasyList ライセンス https://easylist.to/pages/licence.html
- SafariConverterLib https://github.com/AdguardTeam/SafariConverterLib
- AdGuard for Safari 1.11（上限 15 万・拡張の分割）https://adguard.com/en/blog/adguard-for-safari-1-11.html
- Apple Developer Forums（上限・読み込み不具合）https://developer.apple.com/forums/thread/734111 ・ /756931 ・ /774008
- Peter Lowe's list ライセンス https://pgl.yoyo.org/license/
- 手元: `/Users/oharakureho/claude/AdblockKeshi/scripts/convert.sh`・`scripts/build_merged_rules.py`・`scripts/filters.yml`・`scripts/validation/playwright-runner.ts`・`.github/workflows/daily-validation.yml`・`tasks/dlite-design-2026-08-11.md`・本番 D1（読み取りのみ）
