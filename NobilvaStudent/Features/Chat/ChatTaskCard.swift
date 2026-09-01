import Foundation

/// Web (`lib/chat/task-card.ts`) と同じ仕様で、
/// メッセージ body 先頭に埋め込まれた ::task::{JSON} を取り出す。
///
/// フォーマット:
/// ```
/// ::task::{"title":"…","subject":"…","amount":"…"}
///
/// <本文>
/// ```
struct ChatTaskCard: Codable, Hashable {
    let title: String
    let subject: String
    let amount: String
}

enum ChatTaskCardParser {
    private static let marker = "::task::"

    static func parse(_ body: String) -> (card: ChatTaskCard, message: String)? {
        guard body.hasPrefix(marker) else { return nil }
        guard let newlineIdx = body.firstIndex(of: "\n") else { return nil }
        let jsonStart = body.index(body.startIndex, offsetBy: marker.count)
        let jsonPart = body[jsonStart..<newlineIdx].trimmingCharacters(in: .whitespaces)
        guard let data = jsonPart.data(using: .utf8),
              let card = try? JSONDecoder().decode(ChatTaskCard.self, from: data) else {
            return nil
        }
        var rest = String(body[body.index(after: newlineIdx)...])
        // marker 行の直後に空行がある場合はそれも 1 つスキップ (Web 実装と同じ)。
        if rest.first == "\n" { rest.removeFirst() }
        return (card, rest)
    }

    /// スレッド一覧のプレビュー用: `::task::` を含む body を
    /// 「【相談】<title> — <本文>」に平坦化する。
    /// 通常メッセージはそのまま (改行/連続 whitespace は 1 つに)。
    static func preview(_ body: String) -> String {
        let flatten: (String) -> String = { s in
            s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        guard let parsed = parse(body) else { return flatten(body) }
        let label = "【相談】\(parsed.card.title)"
        let msg = flatten(parsed.message)
        return msg.isEmpty ? label : "\(label) — \(msg)"
    }
}
