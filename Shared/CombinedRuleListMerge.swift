import Foundation

/// 標準ルール JSON と自己学習ルールを 1 つの JSON 配列に結合する純粋ロジック。
///
/// - `splice`: truncation 不要な state 用。標準の **バイト列をそのまま使い**末尾に reported を
///   差し込む（130k〜150k の full decode を避け、起動時のメモリスパイク/フリーズを防ぐ）。
/// - `truncatedMerge`: ad-only state（標準が上限ちょうど）用。標準を decode して先頭 keep 件 +
///   reported を結合する（truncation が必要な唯一のケース）。
enum CombinedRuleListMerge {
    enum MergeError: Error { case invalidStandardJSON }

    /// 有効な JSON 配列バイト列 `standardJSON` の末尾へ `reported` を連結したバイト列を返す。
    /// reported が空なら standardJSON をそのまま返す（コピーのみ・full decode しない）。
    static func splice(standardJSON: Data, appending reported: [ContentBlockerRule]) throws -> Data {
        // reported が空なら full decode せずバイト列そのまま返す（最速・最小メモリ）。
        guard !reported.isEmpty else { return standardJSON }

        // 配列終端の ']' を探す。JSON 配列では終端 ']' が（末尾 whitespace を除く）最後の ']' バイトで、
        // 内容（url-filter の `[/:]` 等）の ']' は必ずその手前にあるため lastIndex で正しく取れる。
        guard let lastBracket = standardJSON.lastIndex(of: UInt8(ascii: "]")) else {
            throw MergeError.invalidStandardJSON
        }

        // reported を JSON 配列にして外側の [ ] を剥がし inner 要素列を得る。
        let reportedArray = try JSONEncoder().encode(reported)
        guard reportedArray.count >= 2,
              reportedArray.first == UInt8(ascii: "["),
              reportedArray.last == UInt8(ascii: "]") else {
            throw MergeError.invalidStandardJSON
        }
        let reportedInner = reportedArray.dropFirst().dropLast()

        // 終端 ']' 手前までを prefix とし、標準配列に既存要素があれば ',' を挟む。
        var result = Data(standardJSON[..<lastBracket])
        guard let openIdx = result.firstIndex(of: UInt8(ascii: "[")) else {
            throw MergeError.invalidStandardJSON
        }
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0a, 0x0d] // space tab lf cr
        let hasElement = result[result.index(after: openIdx)...].contains { !whitespace.contains($0) }
        if hasElement { result.append(UInt8(ascii: ",")) }
        result.append(contentsOf: reportedInner)
        result.append(UInt8(ascii: "]"))
        return result
    }

    /// JSON 配列のバイト列 2 つを、デコードせずに 1 つの配列に繋ぐ（`first` の要素 → `second` の要素）。
    /// どちらかが配列でなければ throw。
    static func concatenate(_ first: Data, _ second: Data) throws -> Data {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0a, 0x0d]
        guard let firstOpen = first.firstIndex(where: { !whitespace.contains($0) }),
              first[firstOpen] == UInt8(ascii: "["),
              let firstClose = first.lastIndex(where: { !whitespace.contains($0) }),
              first[firstClose] == UInt8(ascii: "]"), firstClose > firstOpen,
              let secondOpen = second.firstIndex(where: { !whitespace.contains($0) }),
              second[secondOpen] == UInt8(ascii: "["),
              let secondClose = second.lastIndex(where: { !whitespace.contains($0) }),
              second[secondClose] == UInt8(ascii: "]"), secondClose > secondOpen
        else { throw MergeError.invalidStandardJSON }

        let firstInner = first[first.index(after: firstOpen)..<firstClose]
        let secondInner = second[second.index(after: secondOpen)..<secondClose]
        let firstHasElement = firstInner.contains { !whitespace.contains($0) }
        let secondHasElement = secondInner.contains { !whitespace.contains($0) }

        var result = Data([UInt8(ascii: "[")])
        result.append(contentsOf: firstInner)
        if firstHasElement && secondHasElement { result.append(UInt8(ascii: ",")) }
        result.append(contentsOf: secondInner)
        result.append(UInt8(ascii: "]"))
        return result
    }

    /// 標準ルール配列の先頭 `keepStandard` 件 + `reported` を結合して JSON 化する（truncation 版）。
    static func truncatedMerge(standardRules: [ContentBlockerRule],
                               keepStandard: Int,
                               reported: [ContentBlockerRule]) throws -> Data {
        let kept = Array(standardRules.prefix(max(0, keepStandard)))
        // 配信ファイルと同じく「/」をそのまま書く（既定の「\/」は 1 文字ごとに 1 バイト膨らむ）。
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(kept + reported)
    }
}
