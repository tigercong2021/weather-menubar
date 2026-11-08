import SwiftUI

enum WeatherTemperaturePalette {
    static func color(for value: Double?) -> Color {
        guard let value, value.isFinite else { return .secondary.opacity(0.36) }
        let rounded = value.rounded()
        let rgb: UInt32
        switch rounded {
        case let degrees where degrees > 30: rgb = 0xB1695A
        case let degrees where degrees > 26: rgb = 0xDB9864
        case let degrees where degrees > 22: rgb = 0xE3BB88
        case let degrees where degrees > 18: rgb = 0xD0C7A8
        case let degrees where degrees > 14: rgb = 0xB1C2A3
        case let degrees where degrees > 10: rgb = 0x80BBB2
        case let degrees where degrees > 6: rgb = 0x6D9E96
        case let degrees where degrees > 2: rgb = 0x8F95A5
        default: rgb = 0x6F7685
        }
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }

    static func range(low: Double?, high: Double?) -> some View {
        Capsule().fill(LinearGradient(colors: [color(for: low ?? high), color(for: high ?? low)],
                                     startPoint: .leading, endPoint: .trailing))
            .accessibilityHidden(true)
    }
}

struct WeatherDetailsGrid: View {
    let snapshot: WeatherSnapshot
    let now: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        let details = snapshot.details
        let today = snapshot.weatherDay(at: now)
        VStack(alignment: .leading, spacing: 7) {
            Text("天气详情")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 6) {
                tile("降水概率", symbol: "umbrella", value: number(snapshot.rainProbability(at: now), unit: "%"),
                     note: "本小时")
                tile("紫外线", symbol: "sun.max", value: number(snapshot.uvIndex(at: now), decimals: 1),
                     note: "本小时")
                tile("风速", symbol: "wind", value: number(details?.windSpeed, unit: " km/h"),
                     note: windNote(details?.windDirection))
                tile("体感温度", symbol: "thermometer.medium", value: temperatureText(details?.feelsLike))
                tile("相对湿度", symbol: "humidity", value: number(details?.humidity, unit: "%"),
                     note: details?.dewPoint.map { "露点 \(temperatureText($0))" })
                tile("海平面气压", symbol: "barometer", value: number(details?.pressure, unit: " hPa"))
            }
            if today?.sunrise != nil || today?.sunset != nil {
                HStack {
                    solarLabel("日出", symbol: "sunrise", date: today?.sunrise)
                    Spacer(minLength: 6)
                    solarLabel("日落", symbol: "sunset", date: today?.sunset)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .weatherGlassCard(cornerRadius: 8)
            }
        }
    }

    private func tile(_ title: String, symbol: String, value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let note {
                Text(note).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 45, alignment: .topLeading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .weatherGlassCard(cornerRadius: 8)
        .accessibilityElement(children: .combine)
    }

    private func solarLabel(_ title: String, symbol: String, date: Date?) -> some View {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = snapshot.locationTimeZone
        formatter.dateFormat = "HH:mm"
        return HStack(spacing: 4) {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Text(date.map { formatter.string(from: $0) } ?? "—")
                .monospacedDigit()
        }
        .font(.system(size: 10, weight: .medium))
    }

    private func number(_ value: Double?, unit: String = "", decimals: Int = 0) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...decimals))) + unit
    }

    private func windNote(_ direction: Double?) -> String? {
        let compass = direction.flatMap { value -> String? in
            guard value.isFinite, (0...360).contains(value) else { return nil }
            let names = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
            return names[Int((value / 45).rounded()) % names.count] + "风"
        }
        let gust = snapshot.gust.map { "阵风 \(number($0))" }
        let parts = [compass, gust].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
