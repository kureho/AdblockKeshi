import Foundation
import WebKit
import AppKit

// 配信中の規則ファイルを WebKit でコンパイルし、ページから各広告網のスクリプトを読ませて
// 「止まったか（onerror）」を数える。対照に、規則に無い CDN のスクリプトが読めることも見る。
// 規則なしの 25 秒時点の結果と並べ、「止まった」がネットワーク失敗ではなく規則によるものかを見分ける。
//
// 使い方（macOS・実機不要。iOS Safari のコンテンツブロッカーと同じ WebKit の規則エンジン）:
//   swiftc -O scripts/check-popunder-rules-webkit.swift -o /tmp/popcheck -framework WebKit -framework AppKit
//   /tmp/popcheck PopunderBlockerExtension/Resources/popunder-rules.json
// 2026-09-23 実測: 規則あり 33/33 件停止・対照 CDN 読み込み OK ／ 規則なし 25 秒時点で 2 件読み込み・17 件応答待ち（＝実通信が出ている）
let rulesPath = CommandLine.arguments[1]
let rulesJSON = try! String(contentsOfFile: rulesPath, encoding: .utf8)
let rules = try! JSONSerialization.jsonObject(with: Data(rulesJSON.utf8)) as! [[String: Any]]
var domains: [String] = []
for r in rules {
    let action = r["action"] as! [String: Any]
    guard action["type"] as! String == "block" else { continue }
    let filter = (r["trigger"] as! [String: Any])["url-filter"] as! String
    // "^[^:]+://+([^:/]+\\.)?popads\\.net[/:]" → popads.net
    let host = filter.replacingOccurrences(of: "^[^:]+://+([^:/]+\\.)?", with: "")
        .replacingOccurrences(of: "[/:]", with: "")
        .replacingOccurrences(of: "\\.", with: ".")
    domains.append(host)
}
let control = "https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js"
var tags = ""
for (i, d) in domains.enumerated() {
    tags += "<script src=\"https://\(d)/x.js\" onload=\"r('ok',\(i))\" onerror=\"r('blocked',\(i))\"></script>\n"
}
tags += "<script src=\"\(control)\" onload=\"r('ok',-1)\" onerror=\"r('blocked',-1)\"></script>\n"
let html = """
<html><head><script>window.res={};function r(s,i){window.res[i]=s}</script>
\(tags)
</head><body>t</body></html>
"""

final class Runner: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let label: String
    let done: ([String: String]) -> Void
    init(label: String, list: WKContentRuleList?, done: @escaping ([String: String]) -> Void) {
        let cfg = WKWebViewConfiguration()
        if let list { cfg.userContentController.add(list) }
        web = WKWebView(frame: .zero, configuration: cfg)
        self.label = label; self.done = done
        super.init()
        web.navigationDelegate = self
        web.loadHTMLString(html, baseURL: URL(string: "https://example.com/"))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("JSON.stringify(window.res)") { v, _ in
            let s = v as? String ?? "{}"
            let d = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: String] ?? [:]
            self.done(d)
        }
    }
}

var runners: [Runner] = []
func report(_ label: String, _ d: [String: String]) {
    let blocked = domains.indices.filter { d[String($0)] == "blocked" }.count
    let notBlocked = domains.indices.filter { d[String($0)] != "blocked" }.map { domains[$0] }
    print("[\(label)] 広告網 \(domains.count) 件中 止まった \(blocked) 件 / 対照 CDN: \(d["-1"] ?? "結果なし")")
    if !notBlocked.isEmpty { print("  止まらなかった: \(notBlocked.prefix(10).joined(separator: ", "))") }
}

WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "popcheck", encodedContentRuleList: rulesJSON) { list, err in
    guard let list else { print("コンパイル失敗: \(String(describing: err))"); exit(1) }
    runners.append(Runner(label: "規則あり", list: list) { d in
        report("規則あり", d)
        let base = Runner(label: "規則なし", list: nil) { _ in }
        runners.append(base)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            base.web.evaluateJavaScript("JSON.stringify(window.res)") { v, _ in
                let d2 = (try? JSONSerialization.jsonObject(with: Data((v as? String ?? "{}").utf8))) as? [String: String] ?? [:]
                let ok = domains.indices.filter { d2[String($0)] == "ok" }.map { domains[$0] }
                let err = domains.indices.filter { d2[String($0)] == "blocked" }.count
                let pending = domains.count - ok.count - err
                print("[規則なし・25秒時点] 読み込めた \(ok.count) 件 / エラー \(err) 件 / 応答待ち \(pending) 件 / 対照 CDN: \(d2["-1"] ?? "結果なし")")
                print("  読み込めた広告網: \(ok.joined(separator: ", "))")
                exit(0)
            }
        }
    })
}
DispatchQueue.main.asyncAfter(deadline: .now() + 90) { print("時間切れ"); exit(2) }
NSApplication.shared.setActivationPolicy(.prohibited)
RunLoop.main.run()
