import UtterContracts
import Foundation

extension PromptCatalog {
    static func runtimeContextSection(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        inputLanguage: InputLanguage
    ) -> String {
        let timestamp = runtimeTimestamp(now: now, timeZone: timeZone)
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return """
            当前时间，仅用于理解“今天、明天、下周”等相对时间表达；除非用户明确要求具体日期，否则不要把自然相对说法改成绝对日期：
            \(timestamp)
            """
        case .english:
            return """
            Current time for relative time references only. Do not convert natural relative wording into absolute dates unless the user explicitly asks for concrete dates:
            \(timestamp)
            """
        case .japanese:
            return """
            現在時刻。今日、明日、来週などの相対的な時間表現を理解するためだけに使ってください。ユーザーが具体的な日付を明示的に求めない限り、自然な相対表現を絶対日付に変換しないでください：
            \(timestamp)
            """
        case .korean:
            return """
            현재 시간입니다. 오늘, 내일, 다음 주 같은 상대 시간 표현을 이해하는 데만 사용하세요. 사용자가 구체적인 날짜를 명시적으로 요청하지 않는 한 자연스러운 상대 표현을 절대 날짜로 바꾸지 마세요:
            \(timestamp)
            """
        }
    }
}

private func runtimeTimestamp(now: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return "\(formatter.string(from: now)) \(utcOffset(for: timeZone, at: now)) (\(timeZone.identifier))"
}

private func utcOffset(for timeZone: TimeZone, at date: Date) -> String {
    let seconds = timeZone.secondsFromGMT(for: date)
    let sign = seconds >= 0 ? "+" : "-"
    let absoluteSeconds = abs(seconds)
    let hours = absoluteSeconds / 3_600
    let minutes = (absoluteSeconds % 3_600) / 60
    return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
}
