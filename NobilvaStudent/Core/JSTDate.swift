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

    /// "10月9日(金)" 形式。Web (BusySlotsPanel/helpers.ts) と同じ見た目。
    static let displayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f
    }()

    /// "yyyy-MM-dd" を "10月9日(金)" に。パースできなければ元の文字列。
    static func monthDay(_ ymd: String) -> String {
        guard let d = date(from: ymd) else { return ymd }
        return displayMonthDay.string(from: d)
    }

    /// 一覧の時刻表示 (メッセージアプリと同じ考え方): 今日は "14:20"、昨日は "昨日"、
    /// 1 週間以内は "水曜日"、それ以前は "10/26"。
    static func listTimestamp(_ date: Date, now: Date = Date()) -> String {
        let cal = calendar
        if cal.isDate(date, inSameDayAs: now) { return time.string(from: date) }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return "昨日" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 99
        if days < 7 {
            let f = DateFormatter()
            f.calendar = cal; f.timeZone = timeZone; f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "EEEE"
            return f.string(from: date)
        }
        return displayShort.string(from: date).replacingOccurrences(of: #"\(.\)"#, with: "", options: .regularExpression)
    }

    /// チャットの日付区切り: "今日" / "昨日" / "10月26日(月)"。
    static func dayHeader(_ date: Date, now: Date = Date()) -> String {
        let cal = calendar
        if cal.isDate(date, inSameDayAs: now) { return "今日" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return "昨日" }
        return displayMonthDay.string(from: date)
    }

    /// DB の TIME 型 ("09:00:00") を "9:00" に。
    static func hourMinute(_ time: String) -> String {
        let parts = time.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]) else { return time }
        return "\(h):\(parts[1])"
    }

    /// 今日 (JST) から見て ymd が何日前か。未来や当日は 0。
    static func daysOverdue(_ ymd: String) -> Int {
        guard let d = date(from: ymd), let today = date(from: todayString()) else { return 0 }
        let days = calendar.dateComponents([.day], from: d, to: today).day ?? 0
        return max(0, days)
    }

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
