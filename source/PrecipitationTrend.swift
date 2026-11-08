import Foundation

/// A conservative reading of hourly model output, never a minute-by-minute nowcast.
struct PrecipitationTrend {
    let hours: [WeatherHour]
    let headline: String
    let detail: String
    let isAvailable: Bool

    init(snapshot: WeatherSnapshot, now: Date) {
        // Keep missing values in their time slots. Stop at missing timestamps rather
        // than visually joining hours that were never forecast consecutively.
        let upcoming = snapshot.hours.filter { $0.time > now }.sorted { $0.time < $1.time }
        var contiguous: [WeatherHour] = []
        if let first = upcoming.first, first.time.timeIntervalSince(now) <= 3600 {
            for hour in upcoming.prefix(6) {
                if let previous = contiguous.last,
                   abs(hour.time.timeIntervalSince(previous.time) - 3600) > 1 { break }
                contiguous.append(hour)
            }
        }
        hours = contiguous
        isAvailable = contiguous.contains { Self.amount($0) != nil }

        guard snapshot.age(at: now) < 30 * 60 else {
            headline = "降水趋势待更新"
            detail = "当前为上次预报，刷新后查看变化"
            return
        }
        guard contiguous.count == 6, contiguous.allSatisfy({ Self.amount($0) != nil }) else {
            headline = "降水趋势数据暂缺"
            detail = isAvailable ? "部分小时数据缺失，暂不判断变化" : "获取完整小时预报后显示"
            return
        }

        let wetNow = Self.isPrecipitating(code: snapshot.code)
            || (snapshot.intensity.isFinite && snapshot.intensity >= 0.1)
        let hasCurrentIntensity = snapshot.intensity.isFinite && snapshot.intensity >= 0.1
        let wetHours = contiguous.map { (Self.amount($0) ?? 0) >= 0.1 }
        let lowHours = contiguous.map { hour in
            guard let amount = Self.amount(hour), let probability = hour.rainProbability,
                  probability.isFinite, (0...30).contains(probability) else { return false }
            return amount < 0.1
        }
        detail = "逐小时模型预报 · 仅供趋势参考"

        if wetNow {
            // Require at least two low-probability, low-amount hours through the
            // remainder of the chart; an isolated dip is not the end of a shower.
            if let start = (0...4).first(where: { index in
                lowHours[index...].allSatisfy { $0 }
                    && (hasCurrentIntensity || wetHours[..<index].contains(true))
            }) {
                let beginning = contiguous[start].time.addingTimeInterval(-3600)
                headline = beginning <= now ? "预计接下来降水减弱"
                    : "预计\(Self.clockLabel(beginning, relativeTo: now, in: snapshot.locationTimeZone))后降水减弱"
            } else if wetHours.contains(true) {
                let hasBreak = wetHours.enumerated().contains { index, wet in
                    !wet && index < wetHours.count - 1 && wetHours[(index + 1)...].contains(true)
                }
                headline = hasBreak ? "未来几小时降水或有间歇" : "未来几小时仍可能有降水"
            } else {
                headline = "当前有降水，后续变化待观察"
            }
        } else if let firstWet = wetHours.firstIndex(of: true) {
            let hour = contiguous[firstWet]
            let beginning = hour.time.addingTimeInterval(-3600)
            if beginning <= now {
                // The current interval includes time already elapsed. Its amount
                // cannot locate an onset in the remaining part of this hour.
                headline = "本小时仍需留意降水"
            } else {
                headline = "\(Self.intervalLabel(for: hour, relativeTo: now, in: snapshot.locationTimeZone))可能有降水"
            }
        } else if lowHours.allSatisfy({ $0 }) {
            headline = "未来几小时降水可能性较低"
        } else {
            headline = "降水量较少，仍需留意天气"
        }
    }

    /// The displayed timestamp is the end of the accumulation interval.
    static func intervalLabel(for hour: WeatherHour, relativeTo now: Date, in timeZone: TimeZone) -> String {
        let beginning = hour.time.addingTimeInterval(-3600)
        return "\(clockLabel(beginning, relativeTo: now, in: timeZone))—\(clockLabel(hour.time, relativeTo: beginning, in: timeZone))"
    }

    private static func amount(_ hour: WeatherHour) -> Double? {
        hour.precipitation.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    private static func isPrecipitating(code: Int) -> Bool {
        switch WeatherKind(code: code) {
        case .drizzle, .rain, .freezingRain, .showers, .snow, .snowShowers, .thunder: true
        default: false
        }
    }

    private static func clockLabel(_ date: Date, relativeTo reference: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                                to: calendar.startOfDay(for: date)).day ?? 0
        let prefix = dayOffset == 1 ? "明天" : dayOffset > 1 ? "后天" : ""
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = calendar.component(.minute, from: date) == 0 ? "H时" : "H:mm"
        return prefix + formatter.string(from: date)
    }
}
