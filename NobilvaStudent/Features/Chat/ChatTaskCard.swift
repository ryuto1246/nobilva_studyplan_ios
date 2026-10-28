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

    /// Web `getPlanAmountLabel` 相当。title に `（xxx）` が含まれていればそれを、
    /// 無ければ `約{formatMinutes(minutes)}` を amount として使う。
    static func fromPlanItem(title: String, subject: String, durationMinutes: Int) -> ChatTaskCard {
        return ChatTaskCard(title: title, subject: subject, amount: planAmountLabel(title: title, minutes: durationMinutes))
    }

    /// タスクベース (StudentTask 等) 用。Web の taskToActionable と同じく「約」は付けない。
    static func fromTask(title: String, subject: String, estimatedMinutes: Int) -> ChatTaskCard {
        return ChatTaskCard(title: title, subject: subject, amount: formatMinutes(estimatedMinutes))
    }
}

/// Web `lib/utils.ts formatMinutes` 相当: "60分" / "1時間" / "1時間30分"。
func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m)分" }
    if m == 0 { return "\(h)時間" }
    return "\(h)時間\(m)分"
}

/// Web `getPlanAmountLabel`: title に `（...）` があれば括弧内、無ければ `約{分}`。
private func planAmountLabel(title: String, minutes: Int) -> String {
    if let range = title.range(of: #"（([^）]+)）"#, options: .regularExpression) {
        let inside = title[range].dropFirst().dropLast()
        return String(inside)
    }
    return "約\(formatMinutes(minutes))"
}

enum ChatTaskCardParser {
    static let marker = "::task::"

    /// Web `encodeTaskCardBody` と同じ仕様で body を組み立てる。
    /// `::task::{JSON}\n\n<trimmed message>`。
    static func encode(card: ChatTaskCard, message: String) -> String {
        let payload = ChatTaskCard(
            title: card.title.trimmingCharacters(in: .whitespaces),
            subject: card.subject.trimmingCharacters(in: .whitespaces),
            amount: card.amount.trimmingCharacters(in: .whitespaces)
        )
        // JSONEncoder の key 順は非決定的だが、パース側は key 名でデコードするので問題ない。
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let jsonData = (try? encoder.encode(payload)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(marker)\(jsonString)\n\n\(trimmed)"
    }

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
