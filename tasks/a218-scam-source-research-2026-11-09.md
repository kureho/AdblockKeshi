# A-218 詐欺サイトの元データの代わり — 調査（2026-11-09 開始）

- 依頼: kureho 2026-11-09 選ぶ窓「先に元データの代わりを調べる」＝「無料で営利のアプリに使えて加工した一覧も配ってよい元データを調べ、候補と根拠を見せる（新しい有料サービスは使わない。問い合わせなど外へ出す物は先に見せる）。看板はその結果を見てから」
- 前提（確認済み）: 今の元データ Phishing.Database（MIT）は 2026-10-02T15:30Z の「Update Feeds」が最後（`Phishing-Database/Phishing.Database`・archived ではない・誤登録の報告は 11/8 まで届き続けている・2026-11-09 に GitHub API で確認）。URLhaus は配布先が 410・営利は有料の場合あり・派生物に同意が要る（`tasks/a218-g0-measurement-2026-11-09.md`）
- 日本向けの見本: JPCERT/CC phishurl-list 2026 年 8〜9 月のホスト 5,909 件（手元のみ・許諾の記載なし）。今の元データで止められる形にあるのは 1 件

## 1. 問いの立て直し（PICO）

- P: 広告消し（iOS の Safari コンテンツブロッカー・無料＋買い切りの営利アプリ）の利用者。日本の利用者が多い
- I: 詐欺サイト（フィッシング）のホスト名の一覧の元データを、続いて更新される物に替える・足す
- C: 今の Phishing.Database（10/2 で停止）だけ
- O: ①続いて更新される ②無料 ③営利のアプリで使える ④加工した一覧（ホスト名の規則）を配ってよい ⑤日本向けの詐欺サイトを含む
- この調査で決めること: 看板（G1）の前に、どの元データを使うか（または問い合わせが要るか）を kureho が選べるようにする

### 条件の台帳

| 条件 | 出どころ |
|---|---|
| 無料 | kureho が選んだ選択肢の文「無料で」 |
| 営利のアプリで使える | 同「営利のアプリに使えて」 |
| 加工した一覧を配ってよい | 同「加工した一覧も配ってよい」 |
| 新しい有料サービスは使わない | 同。設計 §4 非目標「Google Web Risk API など新しい有料サービス（使うなら kureho の事前承認）」 |
| 日本向けを含む | 問いの文（「日本向けの詐欺サイトの見本は 5,909 件中 1 件」）から。**除外には使わず順位だけに使う**（日本向けが少なくても、続いて更新される物には価値がある） |
| 続いて更新される | 問いの文（「元データは 10/2 から更新が無く」）から |
| 問い合わせなど外へ出す物は先に見せる | 同選択肢の文 |
| Claude の判断（除外には使わない・未確認として扱う） | 件数の多さ・更新の間隔の短さ・GitHub で取れるか（ワークフローで取りやすいか） |

- 許諾が「非営利だけ」「派生物は不可」の物は、条件 ③④ に合わないので「そのままでは使えない」に分ける。ただし**許可を問い合わせれば使える道**として残す（候補から消さない）

## 2. 仮説（互いに排他）

- **H1**: 無料・営利可・再配布可で更新が続く元データがあり、日本向けも含む（そのまま替えられる）
- **H2**: 無料・営利可・再配布可で更新が続く物はあるが、日本向けはほとんど含まない。日本向けは JPCERT/CC など日本の機関の一覧で、許可の問い合わせが要る
- **H3**: 無料で営利に使えて再配布もできる物は、更新が続いている物の中には無い（使える物は止まっているか、非営利だけか、有料）
- **H4**: Phishing.Database は止まっていない／別の場所で続いている（「止まった」という見立てが誤り）→ 2026-11-09 に GitHub API で確認: 本体も旧名も 10/2 が最後・枝は master だけ。**別の配布先で続いていないか**は未確認（調べ役 Q1 に入れる）

## 3. 計画

調べ役（`/Users/oharakureho/claude/api-research/bin/research`）に、重ならない狭い問いを順に頼む。返った「未確認」は別の担当（サブエージェント）で埋める。候補が見つかったら、**自由に取れる物は手元に取り、JPCERT/CC の見本との重なりと件数・形を実測する**（いちばん強い根拠）。

| 問い | 範囲 |
|---|---|
| Q1 世界の無料の詐欺サイト一覧の許諾と更新 | OpenPhish（community feed）・PhishTank・PhishStats・Phishing Army・phishunt・PhishDestroy（destroylist）・The Block List Project（phishing）・HaGeZi（Threat Intelligence Feeds）・malware-filter（phishing-filter）・Phishing.Database の後継の有無。各: 許諾の原文（営利・再配布・派生物）・最後の更新日・件数・取り方 |
| Q2 日本向けの詐欺サイトの一覧 | JPCERT/CC phishurl-list（許諾・更新の間隔・問い合わせ先）・フィッシング対策協議会・JC3・迷惑メール相談センター・日本の会社の無料の一覧。各: 許諾・更新・取り方 |
| Q3 他の広告ブロック・DNS の製品がどこから詐欺サイトの一覧を得ているか | AdGuard・NextDNS・1Blocker・DuckDuckGo・Lockdown・Cloudflare 1.1.1.1 for Families など。公表している元データと、その許諾の扱い（営利で無料の一覧を使う前例） |

- 止める条件: 3 つの問いが返り、候補ごとに許諾の原文と最後の更新日が揃い、取れる候補の重なりを実測し、各仮説に賛否の両方の証拠を当てた時
- 出す物: この文書の後半（ACH の表・反論の段落・採用／除外・未確認・次の問い・出典）と、kureho に見せる候補の表

## 4. 結果

### 4-1. 世界の無料の一覧（調べ役 Q1＋手元の確認・2026-11-09）

調べ役の報告: `/Users/oharakureho/claude/api-research/work/20261109T072346Z-r-20261109T072346Z-4e13c2/report.md`（回数切れで途中・$0.89）。更新日と許諾の SPDX は GitHub API で手元で確かめた。

| 候補 | 許諾（確認の仕方） | 最後の更新（GitHub API） | 中身 |
|---|---|---|---|
| PhishDestroy destroylist | MIT（LICENSE・README「MIT — Free, open, yours to use!」） | 2026-11-09T06:40Z（今日） | 主な一覧＝自分たちで選んだ物（README「Curated phishing domains」・Real-time）。別に「Community」＝13 以上の一覧を集めた物（2h ごと） |
| HaGeZi Threat Intelligence Feeds | GPL-3.0（README「You may redistribute, modify, and adapt the Lists」・調べ役） | 2026-11-08T09:52Z | 20 を超える一覧を集めた物（`sources.md`: PhishDestroy・CERT Polska・MetaMask・ut1・uBlock badware・Phishing-Database/phishing の追加分など）。元の一覧ごとの許諾はまちまち |
| OpenPhish Community Feed | **営利は不可**（Terms「not to use any part of the Services for any commercial purposes」・調べ役） | 2026-11-09T00:00Z | 自分で集めた物 |
| PhishTank | 古い規約は「データは無料で営利に使える」。今の規約は Cisco の EULA を見よとあり未読（調べ役） | 未確認 | 報告と確認の仕組み・Cisco Talos |
| Phishing Army | 一次資料は未取得。第三者は「free for personal use・再配布不可」（調べ役） | 生成のコードは 2026-10-26 | 他の一覧を集めた物 |
| malware-filter phishing-filter | 一覧は CC BY-SA 4.0。ただし元が OpenPhish（営利不可）・phishunt（All rights reserved）（調べ役・写しの README） | 未確認 | 他の一覧を集めた物 |
| The Block List Project | Unlicense | **保管扱い（archived）**・最後のコミット 2026-07-20 | ― |
| Phishing-Database/phishing（今の元データの追加の受け口） | **許諾の記載なし** | 2026-11-08T08:40Z（追加は続いている） | 追加の報告 4,142 件。本体の一覧（ACTIVE）への反映は 10/2 から止まっている |
| JPCERT/CC phishurl-list | **許諾の記載なし** | 2026-10-16（2026 年 9 月分まで） | 日本の機関が確認した詐欺の URL |

### 4-2. 実測: 今の除外を通した後の件数と、日本向けの見本との重なり（2026-11-09 取得）

手元の道具: `/private/tmp/claude-501/-Users-oharakureho-claude/eddaec7d-1a5b-4b0a-9971-ec4ad874e84e/scratchpad/a218-src/tools/coverage.py`（除外は配信中の選び方と同じ関数）。見本は JPCERT/CC の 2026 年 8〜9 月（重複を除いて 5,909 ホスト。最初の計測は見本のファイルの説明の行の語も数えて 5,929 としていたので、道具を直して数え直した。止められる数が変わったのは HaGeZi 全部の 360 → 353 だけ）。

| 一覧 | 元の件数 | 除外を通る件数 | うち日本向けの段 | 日本向けの見本を止められる数 | 今の元データに無い物 |
|---|---:|---:|---:|---:|---:|
| 今の元データ Phishing.Database（10/2 で停止） | ― | 372,573 | 4,024 | 1 | ― |
| PhishDestroy 主な一覧 | 237,026 | 234,076 | 444 | 9 | 226,051 |
| PhishDestroy 主な一覧（名前が引ける物だけ） | 143,277 | 140,436 | 266 | 9 | 134,877 |
| PhishDestroy Community | 1,173,353 | 1,161,765 | 1,744 | 17 | 1,142,368 |
| HaGeZi TIF Medium | 363,724 | 361,154 | 931 | 17 | 358,337 |
| HaGeZi TIF 全部 | 1,441,295 | 1,435,305 | 2,326 | 353 | 1,419,341 |
| Phishing-Database/phishing の追加分 | 4,142 | 4,044 | 2 | 0 | 1,155 |

- HaGeZi 全部の 353 件のうち 281 件は `drawboardhq.com` 1 つの下の住所（そのドメインごと載っている）。それを除くと 72 件
- 見本は 8〜9 月の物で、一覧は今生きている物が中心なので、時期のずれで重なりは小さく出る（どの一覧にも同じ条件）

### 4-3. 日本向けの一覧（調べ役 Q2＋手元の確認・2026-11-09）

調べ役の報告: `/Users/oharakureho/claude/api-research/work/20261109T072639Z-r-20261109T072639Z-4b2888/report.md`（回数切れで途中・$1.29）。JPCERT/CC の更新の間隔は GitHub API のコミットで手元で確かめた。

| 対象 | 取り方・形 | 更新 | 利用の条件（原文） | 許可の窓口 |
|---|---|---|---|---|
| JPCERT/CC phishurl-list | GitHub・登録なし。月ごとの CSV（確認日・**完全な URL**・かたられたブランド） | **2〜4 か月ごとにまとめて追加**（コミット: 2025-11-18 → 2026-03-04 → 06-29 → 10-16。最後は 2026 年 6〜9 月分）。今月の詐欺サイトは、早くて 2 か月後に載る | **一覧には許諾の記載なし**（README は列の説明だけ）。JPCERT/CC のサイトの規約は「転載、再配布に当たっては…広報…までメールにてご連絡ください」（`https://www.jpcert.or.jp/guide.html`・2026-11-09 取得）。この規約が GitHub の一覧に当たるかは書かれていない | 広報（「公開文書の転載・引用など」・`https://www.jpcert.or.jp/reference.html`） |
| フィッシング対策協議会 URL 提供 | 一般向けの一覧は無い。正会員向けに OpenTAXII/STIX | 2010 年から | 対象は遮断ソフトなどを出す法人で、JPCERT/CC が認めた所。「※個人の方および上記に該当しない場合は対象外です。」（`https://www.antiphishing.jp/enterprise/url.html`・2026-11-09 取得） | 同じ頁の「お問い合わせ」 |
| JC3 | 公開の一覧は見つからなかった。携帯会社（ドコモ）へ提供 | ― | ― | 未確認 |
| 迷惑メール相談センター | メールの事例の頁だけ。URL・ドメインの一覧は見つからなかった | ― | 「引用・転載を行う際は、出典を…明示」（抜粋）。規約の頁は取得時に保守中 | 未確認 |
| 警察庁・都道府県警察 | 公開の一覧は見つからなかった（通報はフィッシング110番へ） | ― | ― | ― |

- 協議会に 2026 年 9 月に報告された URL は 49,032 件（重複なし・月次報告の抜粋）。提供先は 51 組織で、トレンドマイクロ・LINEヤフー・Cloudflare Japan・ソースネクスト・キングソフトなど。**日本の製品の多くは、この協議会の提供を受けて日本向けの詐欺サイトを止めている**と読める（提供先の一覧より）
- phishurl-list は完全な URL なので、ホスト名だけを取ると、乗っ取られた普通のサイトや共有のサービスまで止める恐れがある。今の除外（人気サイト・共有ホスト・守る一覧）を通すのが前提
- 結論: **登録なしで取れる日本向けの一覧は phishurl-list だけで、営利で使ってよいと書かれた物は無い**。使うなら JPCERT/CC 広報への問い合わせ（外へ出す文面＝先に kureho に見せる）

### 4-4. 他の製品の元データ（調べ役 Q3・2026-11-09）

調べ役の報告: `/Users/oharakureho/claude/api-research/work/20261109T073150Z-r-20261109T073150Z-72e8bd/report.md`（自動の続き 1 回を含めて回数切れで途中・$0.90）

| 製品 | 一覧の元 | 形 | 確からしさ |
|---|---|---|---|
| DuckDuckGo（ブラウザの詐欺よけ） | Netcraft（1 社）。"We get a feed of malicious site URLs from Netcraft"・20 分ごと | 企業から受け取る（契約の条件は未確認） | 高い |
| Quad9（非営利の DNS） | 多くの提携先からの寄付（OpenPhish・URLhaus・CERT.pl・IBM X-Force など）。"donated information from partners" | 寄付を受け、見返りに統計を返す。日本の提携先は見当たらない | 高い |
| ControlD（営利の DNS） | "many threat intelligence feeds"（名前なし） | 未確認 | 高い（名前は不明） |
| AdGuard DNS・ControlD の選べる一覧 | HaGeZi の一覧が「Online DNS Services」として挙がっている（README の目次だけ） | 公開の無料の一覧を利用者が選ぶ | 中くらい |
| AdGuard の Phishing URL Blocklist | malware-filter の一覧という根拠は第三者の名簿だけ | 公開の一覧 | 低い |
| NextDNS | "a mix of the most reputable feeds"（フォーラムの引用）。名簿の GitHub（nextdns/metadata）は 2026-11-09 に API で 404 | 未確認 | 低い |
| 1Blocker・Lockdown Privacy・Cloudflare for Families | 公式の頁が見つからず未確認 | ― | ― |

- 前例は 3 つの型: ①企業と組んで受け取る（DuckDuckGo × Netcraft）②提携先から寄付を受ける（Quad9）③公開の無料の一覧を使う（HaGeZi を使う DNS サービス）
- **日本向けの詐欺サイトへの対応を書いた製品は、確かめた中には無かった**。日本の製品（トレンドマイクロ・LINEヤフー・ソースネクストなど）は協議会の提供先（4-3）
- 公開の無料の一覧を営利の製品で使う時の条件を、製品の側がはっきり書いた一次資料は見つからなかった

### 4-5. 手元の確認: このアプリの今の許諾の扱いと、一覧の誤りの多さ（2026-11-09）

- **このアプリはすでに GPL-3.0 の一覧を同梱している**: `scripts/filters.yml` で AdGuard の日本語・基本フィルタ（`license: GPL-3.0`）と EasyList・EasyPrivacy（`CC-BY-SA-3.0`）を使い、`App/AboutView.swift` に「使用フィルタ」とライセンス全文（`AdGuard-GPL-3.0` など）を出している。HaGeZi（GPL-3.0）を足すのは、今と同じ扱いの追加になる
- 同じ画面の「セキュリティルール提供」に URLhaus と Phishing.Database が載っている。元データを替える時は、この表示と同梱のライセンス文も合わせて替える（アプリの更新が要る。配信だけでは変わらない）
- 一覧に人気サイトそのものがどれだけ混じっているか（誤って止める恐れの目安。道具 `/private/tmp/claude-501/-Users-oharakureho-claude/eddaec7d-1a5b-4b0a-9971-ec4ad874e84e/scratchpad/a218-src/tools/reasons.py`）:

| 一覧 | 件数 | 人気サイト・その下で外れる数（tranco＋popular-parent） | Tranco 上位 1 万の名前そのもの |
|---|---:|---:|---|
| PhishDestroy 主な一覧 | 237,026 | 2,902 | 13 件（**`line.me`**・`dribbble.com`・`mail.com`・`libero.it`・`tiscali.it` など） |
| PhishDestroy Community | 1,173,353 | 11,167 | 126 件（`appspot.com`・`azurefd.net`・`amazon.pl` など共有の入口や大手） |
| HaGeZi TIF Medium | 363,724 | 2,568 | 16 件（広告の配信元 `clickadu.net` など。詐欺より広い「脅威」の一覧） |
| HaGeZi TIF 全部 | 1,441,295 | 5,481 | 29 件（`mybluehost.me`・`plesk.page` などの共有の場を含む） |

- どれも今の除外（人気サイト 10 万位・共有ホスト・守る一覧）で外れるので、配信には入らない。ただし **PhishDestroy の主な一覧に `line.me` そのものが載っている**のは、「選び抜いた」一覧でも誤りがあるという証拠で、除外を外さずに使うのが前提
- どの一覧も、詐欺サイトに使える枠（3 万件）を大きく超える。**件数の多さは決め手にならず**、決め手は許諾・新しさ・誤りの少なさ・日本向けの多さ

### 付録 A. JPCERT/CC 広報への問い合わせの案（未送信・送るかは kureho が決める）

宛先: JPCERT/CC 広報（窓口の案内 `https://www.jpcert.or.jp/reference.html`「公開文書の転載・引用など」）。送るのは kureho 本人。下は案で、送る前に kureho が全文を確かめる。

> 件名: phishurl-list の利用についてのご相談（iOS アプリでの利用）
>
> JPCERT/CC 広報ご担当者様
>
> 突然のご連絡失礼いたします。KUREHO と申します。iOS 向けの広告ブロックのアプリ「広告消し」を個人で開発・配信しております（App Store・基本無料、アプリ内課金あり）。
>
> このアプリには、Safari で詐欺サイト（フィッシングサイト）を開かないようにする機能があります。GitHub で公開されている phishurl-list を、この機能の元データの一つとして使わせていただけないかと考え、ご相談いたしました。
>
> 使い方は次のとおりです。
> 1. phishurl-list の CSV から、URL のホスト名だけを取り出します。
> 2. よく使われているサイトや、共有のホスティング（多くの人が同じドメインを使う場）などは、誤って止めないよう取り除きます。
> 3. 残ったホスト名を Safari の遮断の規則（JSON）に変換し、週に一度、GitHub Pages から配信します。アプリはこれを読み込みます。配信される規則はどなたでも取得できる状態になります。
> 4. アプリ内の「ライセンス情報」の画面に、出典として JPCERT/CC の名前と phishurl-list の URL を表示します。
>
> 次の点を教えていただけますでしょうか。
> - 上の使い方（営利のアプリでの利用、加工した規則の配信）をお認めいただけるか
> - お認めいただける場合、出典の書き方などの条件
> - 利用をお控えすべき場合は、その旨
>
> お忙しいところ恐れ入りますが、ご確認いただけますと幸いです。
>
> KUREHO（「広告消し」開発者）

- 書いたこと・根拠: 規約は「転載、再配布に当たっては…広報…までメールにてご連絡ください」（`https://www.jpcert.or.jp/guide.html`・2026-11-09）なので、使い方（取り出す・取り除く・配る・出典）を具体的に書き、可否と条件だけを聞く。配信物が誰でも取れることは、隠さずに書く
- 決めていないこと: 送り元のメールアドレス・署名の名前（kureho が決める）。「個人で」の書き方は、kureho が法人で配信しているなら直す

### 4-6. 未確認だった許諾の確認（担当 A＋手元の確認・2026-11-09）

担当の報告を受け、★印は手元でも頁・GitHub API を取って原文を確かめた。

| 対象 | 分かったこと（原文） | 判断 |
|---|---|---|
| PhishTank | ★新規登録の頁「New user registration temporarily disabled.」。今の規約は Cisco の EULA に差し替わり、データの営利利用・再配布を定める条項は見つからない（担当がキーワードで検索）。旧規約は「the "Data" … are available for commercial use without charge」だが、同じ節に「You shall not … distribute … any or the rights that you receive hereunder」。データは今も 1 時間ごとに更新（HEAD で 11/9 07:22 GMT）。自動で取るならキーが要る（キーなしは 1 日数回） | **今は使えない**（キーが取れない・今の規約で営利可否が書かれていない） |
| Phishing Army | ★「does not impose an additional restriction on access to or use of its generated feeds by individuals, organizations or commercial services. This applies only to the aggregation, normalization, formatting … It does not grant … any rights belonging to the independent upstream data providers.」★「… solely responsible for reviewing the terms of every upstream source and obtaining any authorization required for its own use case.」元は PhishTank・**OpenPhish（営利は不可・4-1）**・CERT.PL・Phishunt（All rights reserved とされる）・urlscan.io・PhishStats・StalkPhish・URLAbuse（CC BY 4.0）・AntiPhish.org | **そのままでは使えない**（元に営利不可の OpenPhish を含み、元の許諾は使う側の責任と明記） |
| PhishStats | 頁が 502 で利用条件を読めず。Phishing Army の元の説明では「最新 100 件だけ」 | 未確認（量も足りない） |
| Phishing.Database（今の元データ） | GitHub の一覧は 2026-10-02 が最後。公式の配信元 `phish.co.za` は 11/9 に 503。作者は 9 月からメールに返事が無いと管理者が Issue #2282 で報告。★Issue #2315（2026-09-26）で**別の営利の遮断アプリが「元の一覧に非営利の物は無いか」と聞き、10/11 にもう 1 社が同じ問いを足したが、作者の返答は無い**。Phishing Army は「recurring false positives and unreliable current coverage」を理由にこの一覧を外している | **今の元データにも同じ「元の許諾が分からない」問題がある**。MIT は作者の作業の許諾で、元の一覧の条件は書かれていない |

### 4-7. PhishDestroy と HaGeZi の中身の元・条件・前例（担当 B＋手元の確認・2026-11-09）

★印は手元でも原文を取って確かめた。

**PhishDestroy**
- ★他の一覧（OpenPhish を含む 13 以上）を取り込む処理 `scripts/smart_aggregator.py` の出力は `community/blocklist.json` だけ（`"""Aggregate external blocklist sources into community/blocklist.json."""`・`OUTPUT_FILE = COMMUNITY_DIR / "blocklist.json"`）。主な一覧 `list.json` はこの処理では入力として読むだけ。主な一覧は非公開の「30+ proprietary parsers」で作られ、**中身の元は確かめられない**
- Community の説明は「Source licenses remain applicable」（元の許諾が残る）。**Community は OpenPhish（営利不可）を含むので使えない**
- ★利用条件（`https://phishdestroy.io/termsmain`・2026-10-28 更新）:「Under the MIT License, you are free to use, copy, modify, merge, publish, distribute, sublicense, and/or **sell copies of our data and tools for any lawful purpose** — provided you do so under your own name and responsibility. Attribution … is appreciated but not legally required.」「Factual information — such as which domains we have flagged — is not owned by anyone and is free for all to use.」
- ★著作権の頁（`https://phishdestroy.io/copyright`・2026-02-26 更新）:「**Notwithstanding the MIT License, the use of PhishDestroy tools, code, or data is strictly prohibited for individuals, entities, or government agencies located in the Russian Federation** or any jurisdictions under comprehensive international sanctions.」
- ★**このアプリはロシアの App Store に出ている**（公開の検索の窓口 `itunes.apple.com/lookup?bundleId=com.kureho.adblockkeshi&country=ru` が 1 件・2026-11-09）。PhishDestroy の物を配ると、この条項とぶつかる恐れがある。配信の JSON は誰でも取れるので、アプリの配信地域を変えても完全には分けられない
- 再配布の時の出典: Acceptable Use は「Attribute PhishDestroy as the source when redistributing」、利用条件は「not legally required」で食い違う → 出すのが安全
- 誤掲載の窓口: 申し立てから 24 時間で運営が決めなければ自動で削除。ただし削除の遅れの報告（Issue #386・#403・#447）がある
- README の「non-commercial volunteer project」は、運営の性質（法人・収益が無い）を述べた文で、使う側の営利を止める文ではない（利用条件の「sell copies」と合わせて読む）

**HaGeZi**
- ★営利の非公開アプリでの利用に、作者が答えている（Issue #11938・2026-10-16。質問は Pop-Up Ads の一覧についてだが、答えは GPL の一覧一般の扱い）:「This is redistribution, so GPL-3.0 applies to the list itself: Include the GPL-3.0 license text … Keep the original file header, including the copyright notice. … If your build converts it …, add a short note saying it was modified, and when. The list is data that Shield reads at runtime. It isn't linked into your code. That doesn't make Shield a derivative work, so Shield can stay closed-source.」
- README:「GPL-3.0 covers the Lists as published here; it doesn't hand you any rights in the upstream data itself」（元の一覧の権利は渡さない）。sources.md:「None of them is copied over one to one. … Every source has its own license.」作り方は非公開（Issue #11215）
- **TIF の入力に PhishDestroy の主な一覧が入っている**（sources.md）。HaGeZi を使っても PhishDestroy の条件の問題からは完全には離れられない（どの物が PhishDestroy 由来かは分からない）
- 2023 年に MIT から GPL-3.0 に変えた理由は「元の一部が GPL だから」（Issue #7273）
- 営利の DNS サービス（AdGuard DNS・Control D）で TIF が選べると、HaGeZi の README・FAQ に書かれている

**GPL の一覧を App Store のアプリで使う前例**
- AdGuard for iOS（GPL-3.0）は App Store で配られているが、自社の一覧を自社のアプリで使う例で、他社の前例にはならない
- FSF の 2010 年の指摘（App Store の Usage Rules が GPL の「追加の制限の禁止」に反する・VLC が 2011 年に取り下げ）は**プログラム**についての物。データの一覧に直接言及した公式の文書は見つからなかった
- **このアプリは既に AdGuard の GPL-3.0 の一覧を同梱して配っている**（4-5）。HaGeZi を足しても、GPL の扱いの危うさは今と同じ種類で、新しく増える物ではない

### 4-8. 実測: JPCERT/CC の一覧を許可を得て配った場合に、どれだけ止められるか（2026-11-09）

JPCERT/CC の一覧は 2〜4 か月ごとにまとめて追加される（4-3）。8〜9 月の詐欺サイトの時点で手元にある一覧は、6/29 に出た 2〜5 月分まで。その古い月の一覧を今の除外に通して配っていたら、8〜9 月の見本（5,909 ホスト）をいくつ止められたかを数えた（道具 `/private/tmp/claude-501/-Users-oharakureho-claude/eddaec7d-1a5b-4b0a-9971-ec4ad874e84e/scratchpad/a218-src/tools/lag.py`・一覧は手元の計測だけに使いコミットしない）。

| 配っていた一覧 | ホスト（除外を通る） | 8〜9 月の見本を止められる数 |
|---|---:|---:|
| 2〜5 月分（6/29 公開・実際に手に入った物） | 7,761 | **0** |
| 4〜7 月分（もっと早く出ていたら・楽観） | 7,125 | 9（0.2%） |

- 詐欺サイトのホスト名は月ごとにほぼ入れ替わる。**JPCERT/CC の一覧をホスト名の遮断に使っても、公開の遅れのせいでほとんど止められない**
- 名前の登録単位（`example.co.jp` の形）で見ると 187〜209 件が重なるが、共有のサービスの下の住所が多いと見られ（未確認）、登録単位で止めるのは誤って止める恐れが大きい
- この一覧は、遮断の元データより、**日本向けの段を見分ける語（ブランド名など）を調整する手元の見本**として役に立つ（今もその使い方をしている）

### 4-9. 実測: 配信と同じ選び方（3 万件の枠）に通した後で、日本向けの見本をいくつ止められるか（2026-11-09）

4-2 の「止められる数」は一覧全体で数えた物で、Safari 用は 3 万件の枠（日本向けの段が先・残りは決まった順）に入った物しか配らない。配信と同じ関数 `select_hosts` に通して数え直した（道具 `/private/tmp/claude-501/-Users-oharakureho-claude/eddaec7d-1a5b-4b0a-9971-ec4ad874e84e/scratchpad/a218-src/tools/select_cover.py`）。

| 元データ | 3 万件のうち日本向けの段 | 8〜9 月の見本 5,909 件を止める数（3 万件の中） | 参考: 一覧全体なら（4-2） |
|---|---:|---:|---:|
| 今の元データ（10/2 で停止） | 4,024 | 0 | 1 |
| PhishDestroy 主な一覧 | 444 | 3 | 9 |
| HaGeZi TIF Medium | 931 | 2 | 17 |
| HaGeZi TIF 全部 | 2,326 | 1 | 353（うち 281 は `drawboardhq.com` の下） |
| HaGeZi Medium＋PhishDestroy | 1,341 | 4 | ― |

- **Safari 用の 3 万件では、どの元データに替えても見本を止める数は 0〜4 件**。見本の多くは「その他」の段にあり、枠の外になる
- 一覧全体の数（右の列）は、件数の上限を実測で決める G2（アプリ内広告ブロック・DNS 用）で効く
- `drawboardhq.com` は Tranco 100 万位の中に無い（`drawboard.com` は 105,628 位）。見本では 281 件がランダムな 8 文字の下の住所。Drawboard 社の正規の共有の場が悪用されているのか、詐欺の専用の場なのかは未確認。G2 で丸ごと止める前に確かめる

## 5. ACH の表（仮説 × 証拠）

○＝合う　×＝合わない　△＝一部だけ合う　―＝関係しない

| 証拠 | H1 そのまま替えられる（日本向けも） | H2 世界の一覧は使えるが日本向けは薄い | H3 使える物は無い | H4 今の元データは止まっていない |
|---|---|---|---|---|
| E1 PhishDestroy: MIT・「sell copies of our data」・11/9 更新（4-1・4-7） | ○ | ○ | × | ― |
| E2 PhishDestroy: ロシア所在の者の利用を禁じる・アプリはロシアでも配信（4-7） | × | △ | ○ | ― |
| E3 HaGeZi: GPL-3.0・作者が営利の非公開アプリでの利用を認める・11/8 更新（4-1・4-7） | ○ | ○ | × | ― |
| E4 HaGeZi: 元の一覧の権利は渡さない・入力に PhishDestroy（4-7） | △ | △ | ○ | ― |
| E5 日本向けの見本: 一覧全体で 9〜353 件・3 万件の中で 0〜4 件（4-2・4-9） | × | ○ | ― | ― |
| E6 JPCERT/CC: 許諾の記載なし・再配布は広報へ連絡・遅れのせいで止める数 0（4-3・4-8） | ― | △ | ― | ― |
| E7 協議会の提供は法人だけ（4-3） | ― | △ | ― | ― |
| E8 OpenPhish 営利不可・PhishTank 登録停止・Phishing Army と phishing-filter は元に営利不可（4-1・4-6） | ― | ○ | ○ | ― |
| E9 Phishing.Database: 10/2 が最後・公式の配信元 503・告知なし（4-6） | ― | ― | ― | × |
| E10 他の製品に日本向けを書いた物は無い・日本の製品は協議会の提供先（4-3・4-4） | × | ○ | ― | ― |

- 合わない数: H1 3・H2 0・H3 2・H4 1 → **残るのは H2**
- ただし H2 は 2 か所を直して残る: ①「使える」は条件つき（E2・E4）②「日本向けは日本の機関の一覧で補える」は、遅れのせいで遮断には効かない（E6）

## 6. 反論（Devil's Advocate）

H2 の「HaGeZi（か PhishDestroy）に替えれば使える」をいちばん強く攻めると、こうなる。**厳しく言えば、きれいに使える元データは無い（H3）**。HaGeZi は元の一覧の権利を渡さないと明言し、作り方も非公開で、入力には「ロシア所在の者の利用を禁じる」PhishDestroy が入っている。広告消しはロシアの App Store にも出ている。さらに、**替えても Safari 用の 3 万件で日本向けの見本を止める数は 0 → 1〜4 件にしかならず**、「日本向けの段」は 4,024 → 931〜2,326 件に減る。「詐欺サイト対策が良くなった」と言える数字は、この測り方では出ない。

これに対して言えること:
- 元の許諾が分からないのは**今の元データも同じ**（Issue #2315 に作者が答えていない）。アプリは既に AdGuard の GPL-3.0 の一覧を同梱し、ライセンスの全文を出している。HaGeZi の作者は、営利の非公開アプリが変換して配る使い方を、条件つき（GPL の全文・元の見出し・改変の日付）で認めている。**増える危うさは「ロシアの条項」だけ**で、それは kureho が決めること
- 日本向けの段の件数は、10/2 で止まった一覧の語の一致で、見本を止めた数は 0。JPCERT/CC の月の一覧どうしでは、詐欺サイトのホスト名は月ごとにほぼ入れ替わる（2〜5 月分の 7,761 件は 8〜9 月に 1 件も出ない・4-8）。止まった一覧の 4,024 件の多くは、もう使われていない見込み（推測・名前が引けるかは未確認）。**件数より新しさが効く**
- 見本は 8〜9 月の物で、今の一覧は 11 月の物。時期のずれで、どの一覧も小さく出る（条件は同じ）。替えた後の効きは、JPCERT/CC の 10〜11 月分が出たら測り直せる

残る弱み: 替えることで「日本向けの詐欺サイトを止める力」が上がるという証拠は、今の手元には無い。替える理由は「止まった・許諾が分からない・誤検知で他から外された元データから、更新の続く・作者が営利の利用を認めた元データへ移る」ことで、日本向けの力ではない。**日本向けを強くするのは元データの問題ではなく、3 万件の選び方（新しい物を先に）と G2 の件数の問題**。

## 7. 結論と、kureho に見せる候補

| 順 | 候補 | 良い所 | 気をつける所 | Claude の判断 |
|---|---|---|---|---|
| 1 | **HaGeZi TIF（全部）に替え、今の元データは外す** | 作者が営利の非公開アプリでの利用を認めた（10/16）。今の AdGuard と同じ GPL の扱い。毎日更新。日本向けの段 2,326 件。一覧全体では見本を 353 件止める（G2 で効く） | 中に PhishDestroy（ロシアの条項）が混ざる。中身は詐欺より広い（マルウェア・暗号の採掘・広告の配信元も）。配る規則に GPL の全文・元の見出し・改変の日付を付け、アプリの「ライセンス情報」を替える（アプリの更新） | **推奨**。Medium でなく全部にするのは、日本向けの段が 2.5 倍で、誤って止める物は今の除外で外れるため。実装の時に G0 と同じ関門（読めない規則 0・トップが止まる 0・人気サイトの中の住所 0・公的機関の .jp 0）を通らなければ Medium に下げる |
| 2 | PhishDestroy 主な一覧に替える | 許諾がいちばんゆるい（MIT・「sell copies」）。誤掲載の窓口が速い | ロシアの条項が**直接**かかる。日本向けの段 444 件で HaGeZi より少ない。`line.me` そのものが載っていた。中身の元は非公開 | 次点。GPL の手間が無いという利点は、既に AdGuard の GPL を扱っているので小さい |
| 3 | 両方を使う | 3 万件の中の日本向けの段 1,341 件 | HaGeZi の中に PhishDestroy が既に入っていて重なる。ロシアの条項が直接かかる | 勧めない |
| 4 | 替えない | 手間が無い | 10/2 から更新が無い。公式の配信元が落ちている。元の許諾の問いに作者が答えない。Phishing Army が誤検知で外した | 勧めない |

- **JPCERT/CC への問い合わせは勧めない**: 許可が出ても、公開の遅れのせいで遮断の力はほぼ増えない（4-8）。手元の見本として使うだけなら配らないので問い合わせは要らない。送る場合の案は付録 A
- フィッシング対策協議会の提供は法人だけで、会員の費用などは未確認（有料なら新しい有料サービスにあたり、事前の承認が要る）
- 看板（G1）への影響: どの元データでも、Safari 用の 3 万件で日本向けの見本を止める数は小さい。看板の文面と、3 万件の選び方（新しい物を先に）・G2 の件数は、元データを決めた後に G1 の前で決める

## 採用 / 除外

- 採用（推奨 1・次点 1）: HaGeZi TIF（推奨）・PhishDestroy 主な一覧（次点）
- 除外（今の条件ではそのままでは使えない）7 件:
  - OpenPhish（営利は不可）
  - PhishTank（新規登録の停止・今の規約で営利の可否が書かれていない）
  - Phishing Army（元に営利不可の一覧を含み、元の許諾は使う側の責任）
  - malware-filter phishing-filter（元に営利不可・All rights reserved を含む）
  - PhishDestroy Community（元に OpenPhish を含む）
  - The Block List Project（保管扱い）
  - Phishing-Database/phishing の追加分（許諾の記載なし・4,142 件だけ）
- 保留 3 件:
  - JPCERT/CC phishurl-list（問い合わせれば使える道は残る。遅れのせいで遮断の効果は小さい）
  - フィッシング対策協議会（法人だけ）
  - PhishStats（頁が 502 で条件を読めない）
- 今の元データ Phishing.Database: 外すのを推奨（更新が止まっている・元の許諾が分からない・誤検知で他から外された）

## 未確認

- PhishDestroy の主な一覧の 1 件ずつの元（非公開の作り方）。OpenPhish などの営利不可の一覧から来た物が混ざっていないか
- HaGeZi TIF の 1 件ずつの元（作り方は非公開）
- PhishDestroy のロシアの条項を、世界で配信するアプリがどう扱えばよいか（法の判断）
- PhishTank のデータについて、Cisco の EULA に条項があるか（キーワードの検索だけ）
- PhishStats の利用条件
- `drawboardhq.com` が正規の共有の場か、詐欺の専用の場か
- 今の元データの日本向けの段 4,024 件のうち、今も名前が引ける割合
- 1Blocker・Lockdown・NextDNS・Cloudflare for Families の元データ
- データの一覧を App Store のアプリで配ることについての FSF や専門家の見解
- kureho が法人として配信しているか（協議会の提供の対象かどうか）

## 次に見れば確度が上がる問い

- 替えた後の 3 万件で、10〜11 月の日本向けの詐欺サイトをいくつ止められるか（JPCERT/CC の 10 月分以降が出たら測る）
- 今の日本向けの段と HaGeZi の日本向けの段で、今も名前が引ける割合はどれだけ違うか
- 3 万件を「新しい物から」選べるか（HaGeZi の一覧に日付は無い。PhishDestroy の `list.json` に日付があるか）
- G2 の DNS 用で何件まで持てるか（計画の Task C6 の実測）

## 出典（日付つき）

- https://github.com/hagezi/dns-blocklists （README・FAQ・sources.md）— 取得日: 2026-11-09
- https://github.com/hagezi/dns-blocklists/issues/11938 （作者の回答 2026-10-16）— 取得日: 2026-11-09（手元で原文を確認）
- https://github.com/hagezi/dns-blocklists/issues/7273 ・/11215 — 取得日: 2026-11-09
- https://github.com/phishdestroy/destroylist （README・LICENSE・scripts/smart_aggregator.py・community/README.md）— 取得日: 2026-11-09（smart_aggregator は手元で確認）
- https://phishdestroy.io/termsmain （2026-10-28 更新）・https://phishdestroy.io/copyright （2026-02-26 更新）— 取得日: 2026-11-09（手元で原文を確認）
- https://phishdestroy.io/acceptable-use ・https://phishdestroy.io/appeals/ — 取得日: 2026-11-09
- https://openphish.com/terms.html ・https://github.com/openphish/public_feed — 取得日: 2026-11-09
- https://phishtank.org/terms.php ・https://phishtank.org/register.php （手元で確認）・https://phishtank.org/developer_info.php — 取得日: 2026-11-09
- https://phishing.army/license/ （手元で確認）・https://github.com/drego85/PhishingArmyCore/blob/master/SOURCES.md — 取得日: 2026-11-09
- https://github.com/Phishing-Database/Phishing.Database/issues/2282 ・/2297 ・/2315 （2315 は手元で確認）— 取得日: 2026-11-09
- https://github.com/JPCERTCC/phishurl-list （コミットの日付・2026 年 2〜9 月の CSV）— 取得日: 2026-11-09
- https://www.jpcert.or.jp/guide.html ・https://www.jpcert.or.jp/reference.html — 取得日: 2026-11-09
- https://www.antiphishing.jp/enterprise/url.html — 取得日: 2026-11-09
- https://spreadprivacy.com/scam-blocker/ ・https://quad9.net/about/partners/ — 取得日: 2026-11-09
- https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement — 取得日: 2026-11-09（担当の要約）
- https://itunes.apple.com/lookup?bundleId=com.kureho.adblockkeshi&country=ru （ロシアの App Store に出ていること）— 取得日: 2026-11-09
- 手元の計測: Tranco 上位 100 万（G0 と同じ物）・候補の一覧（2026-11-09 取得）・JPCERT/CC 2026 年 2〜9 月（コミットしない）
