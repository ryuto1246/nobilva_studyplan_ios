import Foundation

/// 日本標準時 (JST, UTC+9) 固定のカレンダー/フォーマッタユーティリティ。
/// Web 側と表示日付を揃えるため、生徒アプリでは常に JST 基準で日付を扱う。
enum JSTDate {
    static let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!

    static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "ja_JP")
        return cal
    }()

    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let displayShort: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E)"
        return f
    }()

    static let displayLong: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日(E)"
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 現在の JST 日付を "yyyy-MM-dd" で返す。
    static func todayString(offsetDays: Int = 0) -> String {
        let base = Date()
        let shifted = calendar.date(byAdding: .day, value: offsetDays, to: base) ?? base
        return iso.string(from: shifted)
    }

    /// "yyyy-MM-dd" 文字列を Date (JST 00:00) に。
    static func date(from ymd: String) -> Date? {
        iso.date(from: ymd)
    }

    /// ISO8601 timestamp (`2026-08-27T09:30:00Z` など) を Date に。
    static func parseTimestamp(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }
}
