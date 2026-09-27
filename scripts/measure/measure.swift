import Foundation
import WebKit
import AppKit

// scripts/measure/measure.swift
//
// Mac の WebKit（WKWebView + WKContentRuleListStore＝iOS Safari のコンテンツブロッカーと同じ規則
// エンジン）で、指定した規則 JSON（複数可＝コンテンツブロッカー2本同時オンを再現）を読み込み、
// サイト一覧をスマホ UA（iPhone Safari）で開いて「漏れ・崩れの疑い・読み込み時間」を測る。
// scripts/check-popunder-rules-webkit.swift（対照実験の小さい前例）と同じ仕組みの拡張版。
//
// ビルド:
//   swiftc -O scripts/measure/measure.swift -o /tmp/measure -framework WebKit -framework AppKit
//
// 使い方（run = 一覧を全部測る）:
//   /tmp/measure run --config A0 --rules "" \
//     --sites scripts/measure/sites-jp.txt --out out/A0.json --wait 8 --repeat 2 --concurrency 3
//   /tmp/measure run --config A1 --rules docs/cdn/merged-rules.json,PopunderBlockerExtension/Resources/popunder-rules.json \
//     --sites scripts/measure/sites-jp.txt --out out/A1.json --wait 8 --repeat 2 --concurrency 3
//
// 使い方（shoot = 1 サイトだけ開いて PNG を1枚保存。崩れの疑いが出たページの前後比較用）:
//   /tmp/measure shoot --site yahoo.co.jp --rules "" --out out/shots/A0-yahoo.png --wait 8
//   /tmp/measure shoot --site yahoo.co.jp --rules docs/cdn/merged-rules.json --out out/shots/A1-yahoo.png --wait 8
//
// 数えるもの・仕組み:
//   - WKUserScript を forMainFrameOnly:false で全フレーム（iframe 含む）に注入し、各フレームが
//     自分の performance.getEntriesByType('resource') を window.webkit.messageHandlers 経由で
//     ネイティブ側に自己申告する。iframe の中身は同一オリジンでなくても「そのフレーム自身の
//     スクリプトが自分の情報を報告する」形なので同一生成元制限を受けない（＝iframe 内の通信も
//     数えられる。ただし iframe 自体が更に nested iframe を作る場合や、フレーム側で JS 実行が
//     完全に止められている場合は報告が来ない＝その分は数えられない。実行結果の
//     subframeReports が 0 のサイトは「iframe 内訳は取れなかった」ことを示す）
//   - ブロックされた通信は resource timing に出ない（WKContentRuleList は要求前に止めるため）
//     ＝ここが「規則あり」で観測される resources に広告ドメインが残っていたら「漏れ」という
//     判定の前提。実測で確かめてから analyze.py 側で解釈すること。
//   - 崩れの疑い（本文文字数・画像数の急減）は analyze.py 側で A0 と比較して判定する
//     （このツールは生の数値を出すだけ）。

let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"

func logmsg(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

var rawArgs = Array(CommandLine.arguments.dropFirst())
guard let mode = rawArgs.first else {
    logmsg("usage: measure <run|shoot> --...")
    exit(1)
}
rawArgs.removeFirst()

func opt(_ name: String, default def: String? = nil) -> String? {
    if let i = rawArgs.firstIndex(of: "--" + name), i + 1 < rawArgs.count {
        return rawArgs[i + 1]
    }
    return def
}

func userScriptSource(waitMs: Int) -> String {
    return """
    (function(){
      try { if (performance.setResourceTimingBufferSize) { performance.setResourceTimingBufferSize(10000); } } catch(e) {}
      function send(){
        try {
          var entries = performance.getEntriesByType('resource').map(function(e){ return e.name; });
          var isTop = false;
          try { isTop = (window === window.top); } catch(e) { isTop = false; }
          var payload = { frame: String(location.hostname || ''), top: isTop, resources: entries };
          if (isTop) {
            var nav = performance.getEntriesByType('navigation')[0];
            try { payload.textLen = (document.body && document.body.innerText || '').length; } catch(e) { payload.textLen = -1; }
            try { payload.imgCount = document.querySelectorAll('img').length; } catch(e) { payload.imgCount = -1; }
            payload.navMs = nav ? Math.round(nav.loadEventEnd - nav.startTime) : -1;
          }
          window.webkit.messageHandlers.collector.postMessage(payload);
        } catch(e) {
          try { window.webkit.messageHandlers.collector.postMessage({frame:'error', top:false, resources:[], err:String(e)}); } catch(e2) {}
        }
      }
      setTimeout(send, \(waitMs));
    })();
    """
}

// MARK: - 規則コンパイル（一度だけ・全ジョブで使い回す）

func compileRuleLists(_ paths: [String], done: @escaping ([WKContentRuleList]) -> Void) {
    if paths.isEmpty { done([]); return }
    var results = [Int: WKContentRuleList]()
    let group = DispatchGroup()
    for (i, path) in paths.enumerated() {
        group.enter()
        let t0 = Date()
        guard let data = FileManager.default.contents(atPath: path) else {
            logmsg("読み込み失敗: \(path)")
            group.leave()
            continue
        }
        let json = String(decoding: data, as: UTF8.self)
        let safeName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".", with: "_")
        let ident = "measure_\(safeName)_\(data.count)"
        logmsg("コンパイル開始: \(path) (\(data.count) bytes, id=\(ident))")
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: ident, encodedContentRuleList: json) { list, err in
            if let list = list {
                results[i] = list
                logmsg("コンパイル完了: \(path) (\(String(format: "%.1f", Date().timeIntervalSince(t0)))s)")
            } else {
                logmsg("コンパイル失敗: \(path) - \(String(describing: err))")
            }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        done((0..<paths.count).compactMap { results[$0] })
    }
}

// MARK: - 1サイト1回分のジョブ

final class Job: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let domain: String
    let repeatIndex: Int
    var webView: WKWebView!
    var window: NSWindow?
    var resources = Set<String>()
    var mainTextLen: Int = -1
    var mainImgCount: Int = -1
    var mainNavMs: Int = -1
    var subframeReports = 0
    var mainReported = false
    var failed = false
    var failReason = ""
    let startedAt = Date()
    var finished = false
    var finalizeTimer: DispatchWorkItem?
    var hardTimer: DispatchWorkItem?
    let onDone: (Job) -> Void
    // ★ WebKit 実測の既知不具合対策（再現するバグではなく確率的フレーキーさ）:
    // WKUserScript(forMainFrameOnly:false) + 分離ワールド + WKScriptMessageHandler の
    // 組み合わせで、ページ読込・JS実行は正常なのに postMessage が届かない回が
    // 単発試行の約4〜6割で発生することを実測で確認（dbg7.swift を5連続実行し2/5成功）。
    // 原因は特定できず（コード構造由来ではない＝WebKit内部の競合と推定）。
    // 実用対策として「主報告(mainReported)が来ないままハードタイムアウトに達したら
    // 1回だけ reload してやり直す」リトライを入れる。
    var retriesLeft = 1
    var waitMsStored: Int = 0
    var hardTimeoutSecStored: Double = 0
    var ruleListsStored: [WKContentRuleList] = []
    // shoot モード用: finalize() 内で window を閉じると、直後の takeSnapshot が
    // クローズ済みウィンドウ相手にクラッシュする（実測: SIGSEGV, exit 139）。
    // shoot モードは finalize() に window を触らせず、スナップショット取得後に
    // 呼び出し側が明示的に閉じる。
    var keepWindowOnFinalize = false

    init(domain: String, repeatIndex: Int, onDone: @escaping (Job) -> Void) {
        self.domain = domain
        self.repeatIndex = repeatIndex
        self.onDone = onDone
        super.init()
    }

    // ★ webView・WKUserScript・メッセージハンドラの登録は必ず init の「外」（コンストラクタが
    // 返った後）で行う。init の中で self を WKScriptMessageHandler / WKNavigationDelegate として
    // WKUserContentController / WKWebView に登録すると、postMessage が一切届かない不具合を実測で
    // 確認した（Swift の2段階初期化中の self を Objective-C ブリッジ越しに強参照させる経路が
    // 何かおかしくなる。init の外＝通常のメソッド呼び出しにすると解消する。原因の深追いはせず、
    // 再現しない書き方に倒した）。
    func setup(ruleLists: [WKContentRuleList], waitMs: Int, hardTimeoutSec: Double, needsWindow: Bool) {
        waitMsStored = waitMs
        hardTimeoutSecStored = hardTimeoutSec
        ruleListsStored = ruleLists
        let config = WKWebViewConfiguration()
        for l in ruleLists { config.userContentController.add(l) }
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        webView = WKWebView(frame: frame, configuration: config)
        webView.customUserAgent = ua
        webView.navigationDelegate = self
        // 分離された JS ワールド（.defaultClient）で注入する。ページ本体の JS 実行と同じ
        // ワールド（既定の .page）だと、ページの CSP（script-src）に巻き込まれて注入
        // スクリプトごとブロックされるサイトがある（実測: yahoo.co.jp（m.yahoo.co.jp
        // にリダイレクト）は .page ワールドだと document は complete まで進むのに
        // 注入スクリプトの postMessage が一切届かなかった。.defaultClient に切り替えて解消）。
        // 分離ワールドでも DOM・performance 等の組み込み API はそのまま使える。
        let liveUCC = webView.configuration.userContentController
        let world = WKContentWorld.defaultClient
        let script = WKUserScript(source: userScriptSource(waitMs: waitMs), injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: world)
        liveUCC.addUserScript(script)
        liveUCC.add(self, contentWorld: world, name: "collector")
        if needsWindow {
            let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = webView
            win.setIsVisible(false)
            self.window = win
        }
        armHardTimer(after: hardTimeoutSec)
    }

    func armHardTimer(after seconds: Double) {
        hardTimer?.cancel()
        let ht = DispatchWorkItem { [weak self] in self?.handleHardTimeout() }
        hardTimer = ht
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: ht)
    }

    // ハードタイムアウトに達した時点で主報告(mainReported)がまだ来ていなければ、
    // ネットワーク自体の失敗ではない限り1回だけ reload してやり直す（上のコメント参照）。
    func handleHardTimeout() {
        if finished { return }
        if !mainReported && !failed && retriesLeft > 0 {
            retriesLeft -= 1
            logmsg("  [debug] retry \(domain) (mainReported=false, retriesLeft=\(retriesLeft))")
            finalizeTimer?.cancel()
            resources.removeAll()
            subframeReports = 0
            start()
            armHardTimer(after: hardTimeoutSecStored)
            return
        }
        finalize(reason: "timeout")
    }

    func start() {
        guard let url = URL(string: "https://" + domain) else {
            failed = true
            failReason = "invalid-url"
            finalize(reason: "invalid-url")
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        webView.load(req)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logmsg("  [debug] didFailProvisionalNavigation \(domain): \(error)")
        failed = true
        failReason = error.localizedDescription
        finalize(reason: "fail-provisional")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logmsg("  [debug] didFail \(domain): \(error)")
        failed = true
        failReason = error.localizedDescription
        scheduleFinalize(after: 1.0)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if ProcessInfo.processInfo.environment["MEASURE_DEBUG"] != nil {
            logmsg("  [debug] didCommit \(domain): \(webView.url?.absoluteString ?? "nil")")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if ProcessInfo.processInfo.environment["MEASURE_DEBUG"] != nil {
            logmsg("  [debug] didFinish \(domain): \(webView.url?.absoluteString ?? "nil")")
            webView.evaluateJavaScript("document.readyState + ' ' + location.href") { v, e in
                logmsg("  [debug] eval \(self.domain): \(String(describing: v)) err=\(String(describing: e))")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if ProcessInfo.processInfo.environment["MEASURE_DEBUG"] != nil {
            logmsg("  [debug] didReceive \(domain): \(message.body)")
        }
        guard let body = message.body as? [String: Any] else { return }
        if let res = body["resources"] as? [String] {
            for r in res {
                if let host = URL(string: r)?.host {
                    resources.insert(host)
                }
            }
        }
        if let top = body["top"] as? Bool, top {
            mainReported = true
            mainTextLen = body["textLen"] as? Int ?? -1
            mainImgCount = body["imgCount"] as? Int ?? -1
            mainNavMs = body["navMs"] as? Int ?? -1
        } else {
            subframeReports += 1
        }
        scheduleFinalize(after: 1.5)
    }

    func scheduleFinalize(after seconds: Double) {
        finalizeTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.finalize(reason: "settled") }
        finalizeTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func finalize(reason: String) {
        if finished { return }
        finished = true
        hardTimer?.cancel()
        finalizeTimer?.cancel()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "collector", contentWorld: .defaultClient)
        webView.navigationDelegate = nil
        if !keepWindowOnFinalize {
            window?.close()
            window = nil
        }
        onDone(self)
    }
}

var jobsKeepAlive: [ObjectIdentifier: Job] = [:]

// MARK: - run モード（一覧を全部測る）

func loadSites(_ path: String) -> [String] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        logmsg("サイト一覧を読めない: \(path)")
        exit(1)
    }
    var out: [String] = []
    for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
        let t = rawLine.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("SKIP") { continue }
        out.append(t)
    }
    return out
}

func runMode() {
    let config = opt("config") ?? "unknown"
    let rulesArg = opt("rules") ?? ""
    let rulePaths = rulesArg.isEmpty ? [] : rulesArg.split(separator: ",").map(String.init)
    guard let sitesPath = opt("sites"), let outPath = opt("out") else {
        logmsg("run には --sites と --out が必須"); exit(1)
    }
    let waitSec = Double(opt("wait") ?? "8") ?? 8
    let repeatCount = Int(opt("repeat") ?? "2") ?? 2
    let concurrency = Int(opt("concurrency") ?? "3") ?? 3

    let sites = loadSites(sitesPath)
    logmsg("config=\(config) sites=\(sites.count) rules=\(rulePaths) wait=\(waitSec)s repeat=\(repeatCount) concurrency=\(concurrency)")

    compileRuleLists(rulePaths) { lists in
        logmsg("ルール準備完了: \(lists.count) 本 -> 測定開始")
        var pending: [(String, Int)] = []
        for s in sites { for r in 0..<repeatCount { pending.append((s, r)) } }
        var active = 0
        var results: [[String: Any]] = []
        let total = pending.count

        func maybeFinishAll() {
            if pending.isEmpty && active == 0 {
                let out: [String: Any] = ["config": config, "waitSec": waitSec, "rules": rulePaths, "results": results]
                do {
                    let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted])
                    try data.write(to: URL(fileURLWithPath: outPath))
                    logmsg("書き出し完了: \(outPath) (\(results.count) 件)")
                } catch {
                    logmsg("書き出し失敗: \(error)")
                }
                exit(0)
            }
        }

        func startNext() {
            while active < concurrency && !pending.isEmpty {
                let (site, rep) = pending.removeFirst()
                active += 1
                let job = Job(domain: site, repeatIndex: rep) { j in
                    let elapsedMs = Int(Date().timeIntervalSince(j.startedAt) * 1000)
                    let rec: [String: Any] = [
                        "site": j.domain,
                        "repeat": j.repeatIndex,
                        "resources": Array(j.resources).sorted(),
                        "resourceCount": j.resources.count,
                        "textLen": j.mainTextLen,
                        "imgCount": j.mainImgCount,
                        "navMs": j.mainNavMs,
                        "elapsedMs": elapsedMs,
                        "mainReported": j.mainReported,
                        "subframeReports": j.subframeReports,
                        "failed": j.failed,
                        "failReason": j.failReason
                    ]
                    results.append(rec)
                    active -= 1
                    logmsg("[\(results.count)/\(total)] \(config) \(j.domain) rep\(j.repeatIndex) resources=\(j.resources.count) textLen=\(j.mainTextLen) failed=\(j.failed)")
                    jobsKeepAlive.removeValue(forKey: ObjectIdentifier(j))
                    startNext()
                    maybeFinishAll()
                }
                jobsKeepAlive[ObjectIdentifier(job)] = job
                job.setup(ruleLists: lists, waitMs: Int(waitSec * 1000), hardTimeoutSec: waitSec + 15, needsWindow: false)
                job.start()
            }
        }
        startNext()
    }
}

// MARK: - shoot モード（1サイト1枚 PNG）

func shootMode() {
    guard let site = opt("site"), let outPath = opt("out") else {
        logmsg("shoot には --site と --out が必須"); exit(1)
    }
    let rulesArg = opt("rules") ?? ""
    let rulePaths = rulesArg.isEmpty ? [] : rulesArg.split(separator: ",").map(String.init)
    let waitSec = Double(opt("wait") ?? "8") ?? 8

    compileRuleLists(rulePaths) { lists in
        let job = Job(domain: site, repeatIndex: 0) { j in
            let webView = j.webView
            let win = j.window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                webView?.takeSnapshot(with: nil) { image, err in
                    win?.close()
                    guard let image = image else {
                        logmsg("スクショ失敗: \(String(describing: err))")
                        exit(1)
                    }
                    guard let tiff = image.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else {
                        logmsg("PNG化失敗")
                        exit(1)
                    }
                    do {
                        try png.write(to: URL(fileURLWithPath: outPath))
                        logmsg("保存: \(outPath) textLen=\(j.mainTextLen) imgCount=\(j.mainImgCount)")
                        exit(0)
                    } catch {
                        logmsg("保存失敗: \(error)")
                        exit(1)
                    }
                }
            }
        }
        jobsKeepAlive[ObjectIdentifier(job)] = job
        job.keepWindowOnFinalize = true
        job.setup(ruleLists: lists, waitMs: Int(waitSec * 1000), hardTimeoutSec: waitSec + 20, needsWindow: true)
        job.start()
    }
}

NSApplication.shared.setActivationPolicy(.prohibited)

switch mode {
case "run": runMode()
case "shoot": shootMode()
default:
    logmsg("unknown mode: \(mode) (run|shoot)")
    exit(1)
}

RunLoop.main.run()
