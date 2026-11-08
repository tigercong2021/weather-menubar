import Foundation

enum WeatherSceneStrength: Int, Comparable {
    case light = 1
    case moderate = 2
    case heavy = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct WeatherSceneProfile {
    let rain: WeatherSceneStrength?
    let snow: WeatherSceneStrength?
    let hail: WeatherSceneStrength?
    let wind: WeatherSceneStrength?
    let lightning: Bool
    let flowX: Double
    let flowY: Double
    let rainRate: Double
    let windMagnitude: Double
    let label: String

    init(code: Int, intensity: Double, windSpeed: Double? = nil, gust: Double? = nil,
         windDirection: Double? = nil) {
        let kind = WeatherKind(code: code)
        rainRate = intensity.isFinite ? max(0, intensity) : 0
        let sustained = windSpeed.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0
        let gustValue = gust.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0
        windMagnitude = max(sustained, gustValue)
        lightning = kind == .thunder

        switch code {
        case 51, 56, 61, 66, 80: rain = .light
        case 53, 55, 57, 63, 81: rain = .moderate
        case 65, 67, 82: rain = .heavy
        case 95, 96, 97, 99:
            // 99 specifies heavy hail, not heavy rain. Keep hail severity below
            // independent of this visual rain-rate tuning and code 97's storm tier.
            rain = rainRate >= 7 || code == 97 ? .heavy : .moderate
        default: rain = nil
        }

        switch code {
        case 71, 77, 85: snow = .light
        case 73: snow = .moderate
        case 75, 86: snow = .heavy
        default: snow = nil
        }

        switch code {
        case 96: hail = .light
        case 99: hail = .heavy
        default: hail = nil
        }

        // Visual thresholds in km/h, not meteorological alerts.
        if gustValue >= 65 || sustained >= 48 {
            wind = .heavy
        } else if gustValue >= 40 || sustained >= 30 {
            wind = .moderate
        } else if gustValue >= 25 || sustained >= 18 {
            wind = .light
        } else {
            wind = nil
        }

        if let windDirection, windDirection.isFinite, (0...360).contains(windDirection) {
            // Forecast bearings specify where wind comes from. Canvas Y grows downward.
            let bearing = windDirection * .pi / 180
            flowX = -sin(bearing)
            flowY = cos(bearing)
        } else {
            flowX = 1
            flowY = 0
        }

        switch code {
        case 48: label = "雾伴霜"
        case 56, 57: label = "冻毛毛雨"
        case 61: label = "小雨"
        case 63: label = "中雨"
        case 65: label = "大雨"
        case 67: label = "强冻雨"
        case 71: label = "小雪"
        case 75: label = "大雪"
        case 77: label = "雪粒"
        case 80: label = "小阵雨"
        case 82: label = "强阵雨"
        case 86: label = "强阵雪"
        case 97: label = "强雷雨"
        case 96, 99: label = "雷雨伴冰雹"
        default: label = kind.label
        }
    }
}

extension WeatherSnapshot {
    func daylightProgress(at date: Date) -> Double? {
        guard let today = weatherDay(at: date), let sunrise = today.sunrise, let sunset = today.sunset,
              sunrise < sunset, date >= sunrise, date < sunset else { return nil }
        return date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
    }
}
