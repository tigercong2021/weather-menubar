import Foundation

/// Ordinary clothing heuristics for a single weather reading, not a personal comfort
/// guarantee or medical advice. No location, previous advice, or persistence is retained.
struct OutfitAdvice: Equatable, Sendable {
    enum TemperatureSource: Sendable {
        case feelsLike, airTemperature

        var label: String { self == .feelsLike ? "体感" : "气温" }
    }

    struct Accessory: Equatable, Sendable {
        let iconName: String
        let label: String
    }

    let iconName: String
    /// Keeps the temperature-selected layer explicit when a shell is shown over it.
    let baseIconName: String
    let description: String
    let effectiveTemperature: Double
    let temperatureSource: TemperatureSource
    let accessories: [Accessory]
    /// One current-condition reminder, not an official weather warning.
    private(set) var weatherNote: String? = nil

    /// Compact menu hint; the full tooltip retains the optional accessories.
    var menuSummary: String {
        let clothing = description
            .replacingOccurrences(of: "短袖 T 恤", with: "短袖")
            .replacingOccurrences(of: "短袖T恤", with: "短袖")
            .replacingOccurrences(of: "羽绒服配保暖内层", with: "羽绒服＋保暖内搭")
            .replacingOccurrences(of: "，外加", with: "＋")
            .replacingOccurrences(of: "，另加", with: "＋")
            .replacingOccurrences(of: "，加", with: "＋")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(clothing) · \(temperatureSource.label)\(Int(effectiveTemperature.rounded()))°"
    }

    var tooltip: String {
        var lines = ["穿搭参考：\(description)",
                     "依据\(temperatureSource.label) \(Int(effectiveTemperature.rounded()))°C"]
        if !accessories.isEmpty {
            lines.append("随身建议：" + accessories.map(\.label).joined(separator: "、"))
        }
        if let weatherNote { lines.append(weatherNote) }
        return lines.joined(separator: "\n")
    }

    /// The caller also guards that this snapshot belongs to the current place.
    /// Like the current menu weather glyph, advice expires after two hours.
    static func make(for snapshot: WeatherSnapshot, at now: Date) -> OutfitAdvice? {
        guard now.timeIntervalSince1970.isFinite,
              snapshot.validAt.timeIntervalSince1970.isFinite,
              snapshot.fetchedAt.timeIntervalSince1970.isFinite,
              snapshot.age(at: now) < 2 * 3_600 else { return nil }

        let temperature: Double
        let source: TemperatureSource
        if let apparent = validTemperature(snapshot.details?.feelsLike) {
            temperature = apparent
            source = .feelsLike
        } else if let measured = validTemperature(snapshot.temperature) {
            temperature = measured
            source = .airTemperature
        } else {
            return nil
        }

        // These Celsius boundaries are a small, adjustable everyday heuristic.
        // They do not encode a universal comfort rule or depend on sun/night icons.
        let base: (icon: String, label: String)
        switch temperature {
        case 26...: base = ("short-sleeve", "短袖 T 恤")
        case 20..<26: base = ("long-sleeve", "长袖衬衫")
        case 15..<20: base = ("knit", "针织衫")
        case 8..<15: base = ("light-jacket", "轻夹克")
        default: base = ("puffer", "羽绒服配保暖内层")
        }

        let kind = WeatherKind(code: snapshot.code)
        let snow = kind == .snow || kind == .snowShowers || snapshot.hasMixedPrecipitation
        let currentPrecipitation: Bool
        switch kind {
        case .drizzle, .rain, .freezingRain, .showers, .snow, .snowShowers:
            currentPrecipitation = true
        default:
            // A current-interval amount is evidence of precipitation, unlike an hourly
            // probability or accumulation. Thunder alone does not prove rain at the point.
            currentPrecipitation = (nonnegative(snapshot.intensity) ?? 0) > 0
        }
        let sustained = nonnegative(snapshot.details?.windSpeed) ?? 0
        let gust = nonnegative(snapshot.gust) ?? 0
        // Practical outer-layer choices in km/h, not official wind warning thresholds.
        // Apparent temperature already includes wind; never subtract wind chill again.
        let windy = sustained >= 25 || gust >= 40
        let strongWind = sustained >= 48 || gust >= 65
        let thunder = kind == .thunder
        let preserveBase = base.icon == "puffer" || strongWind || thunder

        var mainIcon = base.icon
        var description = base.label
        if currentPrecipitation {
            if preserveBase {
                description += "，另加防湿外层"
            } else {
                mainIcon = "shell"
                // A shell adds weather protection; it does not replace the warm layer.
                description += "，外加防风雨外套"
            }
        } else if windy && temperature < 22 {
            if !preserveBase { mainIcon = "shell" }
            description += "，加防风外层"
        }

        // Hourly values describe the current hour ending at the next boundary.
        // Only that hour may suggest preparation; future amounts/codes never override
        // the current weather or determine the thickness of the main garment.
        let hour = snapshot.hours.filter {
            let interval = $0.time.timeIntervalSince(now)
            return interval > 0 && interval <= 3_600
        }.min { $0.time < $1.time }
        let probability = hour?.rainProbability.flatMap { value in
            value.isFinite && (0...100).contains(value) ? value : nil
        }
        let forecastKind = WeatherKind(code: hour?.code)
        let forecastSnow = forecastKind == .snow || forecastKind == .snowShowers
        let forecastThunder = forecastKind == .thunder
        let umbrellaIsSuitable = !windy && !thunder && !snow && !forecastThunder

        var accessories: [Accessory] = []
        if currentPrecipitation && (temperature < 15 || snow) {
            accessories.append(.init(iconName: "boots", label: "防水短靴"))
        }
        if currentPrecipitation && umbrellaIsSuitable {
            accessories.append(.init(iconName: "umbrella", label: "雨伞"))
        } else if !currentPrecipitation, let probability, probability >= 50 {
            if umbrellaIsSuitable && !forecastSnow {
                accessories.append(.init(iconName: "umbrella",
                                         label: "备伞（本小时降水概率\(Int(probability.rounded()))%）"))
            } else if forecastSnow && !thunder && !strongWind {
                accessories.append(.init(iconName: "boots", label: "防水短靴（本小时可能降雪）"))
            }
        }
        if temperature < 8 { accessories.append(.init(iconName: "scarf", label: "围巾")) }
        if temperature <= 2 { accessories.append(.init(iconName: "beanie", label: "针织帽")) }
        if temperature <= 0 { accessories.append(.init(iconName: "gloves", label: "手套")) }

        // Sun accessories supplement the same temperature-selected clothing. Unknown
        // daylight and nighttime cannot trigger them, even if an old UV value is high.
        let uv = nonnegative(hour?.uvIndex)
        if snapshot.isDay(at: now) == true, !thunder, !strongWind, let uv, uv >= 3 {
            accessories.append(.init(iconName: "sun-hat", label: "遮阳帽"))
            if uv >= 6 { accessories.append(.init(iconName: "sunglasses", label: "太阳镜")) }
        }

        var advice = OutfitAdvice(iconName: mainIcon, baseIconName: base.icon,
                                  description: description, effectiveTemperature: temperature,
                                  temperatureSource: source, accessories: accessories)
        advice.weatherNote = currentWeatherNote(code: snapshot.code, strongWind: strongWind)
        return advice
    }

    private static func currentWeatherNote(code: Int, strongWind: Bool) -> String? {
        // Use only the current WMO code and measured/modelled current wind.
        // Hourly probability, future weather and accessories cannot promote a note.
        switch code {
        case 96, 99: return "雷雨伴冰雹，建议减少户外活动"
        case 95: return "雷雨，建议减少户外活动"
        default: break
        }
        if strongWind { return "风力较强，留意高处坠物" }
        switch code {
        case 56, 57, 66, 67: return "路面可能结冰，出行注意湿滑"
        case 65, 82: return "雨势较强，出行留意积水"
        case 75, 86: return "降雪较强，出行注意湿滑"
        default: return nil
        }
    }

    private static func validTemperature(_ value: Double?) -> Double? {
        // Match the existing WeatherClient's accepted range; corrupted caches stay unknown.
        value.flatMap { $0.isFinite && (-150...100).contains($0) ? $0 : nil }
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}
