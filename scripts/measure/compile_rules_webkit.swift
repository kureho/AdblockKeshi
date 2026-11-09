import Foundation
import WebKit
import AppKit

// 規則の JSON を macOS の WebKit（iOS Safari のコンテンツブロッカーと同じ規則エンジン）でコンパイルできるか確かめる。
// 1 本でも WebKit が読めない規則（例: url-filter の「|」）があると一覧ごと失敗し、何も止まらなくなる。
//
// 使い方:
//   swiftc -O scripts/measure/compile_rules_webkit.swift -o "$SCRATCH/compile" -framework WebKit -framework AppKit
//   "$SCRATCH/compile" docs/cdn/security-rules.json
// 成功: 「OK <件数> rules <秒>s」・終了コード 0 ／ 失敗: エラーを出して終了コード 1
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: compile <rules.json>\n".data(using: .utf8)!)
    exit(2)
}
let path = CommandLine.arguments[1]
guard let json = try? String(contentsOfFile: path, encoding: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else {
    print("ERROR cannot read a JSON array from \(path)")
    exit(1)
}
let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("compile-rules-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: storeDir) }
guard let store = WKContentRuleListStore(url: storeDir) else {
    print("ERROR cannot open WKContentRuleListStore")
    exit(1)
}
let started = Date()
var exitCode: Int32 = 1
var finished = false
store.compileContentRuleList(forIdentifier: "check", encodedContentRuleList: json) { list, error in
    let secs = String(format: "%.1f", Date().timeIntervalSince(started))
    if list != nil {
        print("OK \(parsed.count) rules \(secs)s")
        exitCode = 0
    } else {
        print("ERROR \(error.map { String(describing: $0) } ?? "unknown") \(secs)s")
    }
    finished = true
}
while !finished {
    RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
}
exit(exitCode)
