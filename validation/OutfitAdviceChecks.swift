import Foundation

@main
enum OutfitAdviceChecks {
    static let now = Date(timeIntervalSince1970: 1_794_100_200)
    static let place = WeatherPlace(name: "公开测试城市", coordinate: .init(latitude: 31.2, longitude: 121.5))

    static func weather(_ temperature: Double = 19, feelsLike: Double? = nil,
                        code: Int = 3, intensity: Double = 0, wind: Double? = nil,
                        gust: Double? = nil, probability: Double? = nil,
                        uv: Double? = nil, daylight: Bool? = true, age: TimeInterval = 0,
                        hourOffset: TimeInterval = 1_800, forecastCode: Int? = nil,
                        forecastAmount: Double? = nil, mixed: Bool = false,
                        validAt: Date? = nil, fetchedAt: Date? = nil) -> WeatherSnapshot {
        WeatherSnapshot(
            place: place, temperature: temperature, code: code, intensity: intensity,
            validAt: validAt ?? now.addingTimeInterval(-age),
            fetchedAt: fetchedAt ?? now.addingTimeInterval(-age),
            timezone: "Asia/Shanghai", utcOffsetSeconds: 28_800, currentDaylight: daylight,
            hours: [.init(time: now.addingTimeInterval(hourOffset), temperature: 19,
                          code: forecastCode, daylight: daylight, rainProbability: probability,
                          uvIndex: uv, precipitation: forecastAmount)], days: [], gust: gust,
            details: .init(feelsLike: feelsLike, humidity: nil, windSpeed: wind,
                           windDirection: nil, pressure: nil, dewPoint: nil),
            mixedPrecipitation: mixed)
    }

    static func advice(_ snapshot: WeatherSnapshot) -> OutfitAdvice {
        guard let result = OutfitAdvice.make(for: snapshot, at: now) else {
            preconditionFailure("Unexpected missing advice for test weather")
        }
        return result
    }

    static func has(_ advice: OutfitAdvice, _ accessory: String) -> Bool {
        advice.accessories.contains { $0.iconName == accessory }
    }

    static func main() {
        // Boundaries are tested on both sides, not merely one example per case.
        let temperatures: [(Double, String)] = [
            (-20, "puffer"), (7.999, "puffer"), (8, "light-jacket"), (14.999, "light-jacket"),
            (15, "knit"), (19.999, "knit"), (20, "long-sleeve"), (25.999, "long-sleeve"),
            (26, "short-sleeve"), (36, "short-sleeve")
        ]
        for (temperature, expected) in temperatures {
            let result = advice(weather(temperature))
            precondition(result.iconName == expected && result.baseIconName == expected,
                         "Wrong clothing at \(temperature)°C")
        }

        let apparent = advice(weather(30, feelsLike: 7))
        precondition(apparent.iconName == "puffer" && apparent.effectiveTemperature == 7)
        precondition(apparent.temperatureSource == .feelsLike && apparent.tooltip.contains("依据体感 7°C"))
        let withoutApparent = advice(weather(19))
        precondition(withoutApparent.temperatureSource == .airTemperature)
        precondition(withoutApparent.tooltip.contains("依据气温 19°C"))
        for invalid in [Double.nan, .infinity, -.infinity, 101, -151] {
            precondition(advice(weather(19, feelsLike: invalid)).iconName == "knit")
            precondition(OutfitAdvice.make(for: weather(invalid), at: now) == nil)
        }
        // A valid apparent temperature is itself temperature data; invalid air data need not erase it.
        precondition(advice(weather(.nan, feelsLike: 21)).iconName == "long-sleeve")

        // Appearance/night does not determine garment thickness.
        for dryCode in [-1, 0, 1, 2, 3, 45, 48] {
            precondition(advice(weather(4, code: dryCode)).iconName == "puffer")
            precondition(advice(weather(29, code: dryCode, daylight: false)).iconName == "short-sleeve")
        }

        // Current WMO precipitation remains evidence even when an amount rounds to zero.
        let wetCodes = [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86]
        for code in wetCodes {
            let mildWet = advice(weather(17, code: code, intensity: 0))
            precondition(mildWet.iconName == "shell" && mildWet.baseIconName == "knit")
            precondition(mildWet.description.contains("针织衫") && mildWet.description.contains("外加"))
            let coldWet = advice(weather(-3, code: code, intensity: 1))
            precondition(coldWet.iconName == "puffer" && coldWet.baseIconName == "puffer")
            precondition(coldWet.description.contains("保暖") && coldWet.description.contains("防湿"))
            precondition(has(coldWet, "boots") && has(coldWet, "scarf") && has(coldWet, "gloves"))
        }
        precondition(advice(weather(29, code: 61)).description.contains("短袖"))
        precondition(advice(weather(29, code: 61)).iconName == "shell")
        precondition(advice(weather(19, code: -1, intensity: 0.1)).iconName == "shell")
        for invalidAmount in [Double.nan, .infinity, -1] {
            precondition(advice(weather(19, code: 3, intensity: invalidAmount)).iconName == "knit")
        }
        let mixed = advice(weather(1, code: 61, intensity: 1, mixed: true))
        precondition(mixed.iconName == "puffer" && has(mixed, "boots") && !has(mixed, "umbrella"))
        let snow = advice(weather(-2, code: 73, intensity: 1, probability: 100))
        precondition(!has(snow, "umbrella") && has(snow, "beanie"))

        // A high hourly probability prepares equipment; it cannot manufacture current rain.
        let likely = advice(weather(19, probability: 90, forecastCode: 61, forecastAmount: 5))
        precondition(likely.iconName == "knit" && likely.baseIconName == "knit")
        precondition(likely.description == "针织衫" && has(likely, "umbrella"))
        precondition(likely.tooltip.contains("降水概率90%") && !likely.tooltip.contains("正在下雨"))
        precondition(!has(advice(weather(19, probability: 49.99)), "umbrella"))
        precondition(has(advice(weather(19, probability: 50)), "umbrella"))
        precondition(!has(advice(weather(19, forecastCode: 61, forecastAmount: 5)), "umbrella"))
        for invalidProbability in [Double.nan, .infinity, -1, 101] {
            precondition(!has(advice(weather(19, probability: invalidProbability)), "umbrella"))
        }
        for offset in [-60.0, 0, 3_601] {
            let outside = advice(weather(19, probability: 100, uv: 9, hourOffset: offset))
            precondition(!has(outside, "umbrella") && !has(outside, "sun-hat"))
        }
        precondition(has(advice(weather(19, probability: 100, hourOffset: 3_600)), "umbrella"))
        let possibleSnow = advice(weather(5, probability: 70, forecastCode: 71))
        precondition(possibleSnow.iconName == "puffer" && !has(possibleSnow, "umbrella"))
        precondition(possibleSnow.tooltip.contains("可能降雪") && possibleSnow.description == "羽绒服配保暖内层")

        // Wind adjusts only an outer layer. It never applies a second wind-chill subtraction.
        precondition(advice(weather(19, wind: 24.99)).iconName == "knit")
        precondition(advice(weather(19, wind: 25)).iconName == "shell")
        precondition(advice(weather(19, gust: 39.99)).iconName == "knit")
        precondition(advice(weather(19, gust: 40)).iconName == "shell")
        precondition(advice(weather(22, wind: 25)).iconName == "long-sleeve")
        let noDoubleChill = advice(weather(8, feelsLike: 17, wind: 30))
        precondition(noDoubleChill.effectiveTemperature == 17 && noDoubleChill.baseIconName == "knit")
        for invalidWind in [Double.nan, .infinity, -1] {
            precondition(advice(weather(19, wind: invalidWind, gust: invalidWind)).iconName == "knit")
        }
        // Avoid umbrella advice in windy or thunderstorm conditions, even with 100% probability.
        for result in [advice(weather(19, wind: 25, probability: 100)),
                       advice(weather(19, code: 61, gust: 40, probability: 100))] {
            precondition(!has(result, "umbrella") && !result.tooltip.contains("备伞"))
        }
        for result in [advice(weather(19, code: 61, wind: 48, probability: 100)),
                       advice(weather(19, code: 61, gust: 65, probability: 100))] {
            precondition(result.iconName == "knit" && !has(result, "umbrella"))
        }
        for code in [95, 96, 97, 99] {
            let storm = advice(weather(19, code: code, intensity: 1, probability: 100, uv: 8))
            precondition(storm.iconName == "knit" && !has(storm, "umbrella") && !has(storm, "sun-hat"))
            let dryThunder = advice(weather(19, code: code, intensity: 0, probability: 100))
            precondition(dryThunder.description == "针织衫" && !has(dryThunder, "umbrella"))
        }
        precondition(!has(advice(weather(19, probability: 100, forecastCode: 95)), "umbrella"))

        // Current severe conditions add one reminder, independently of hourly
        // forecasts. Priority is thunder/hail, strong wind, freezing rain, rain/snow.
        let noteGroups: [([Int], String)] = [
            ([95], "雷雨，建议减少户外活动"),
            ([96, 99], "雷雨伴冰雹，建议减少户外活动"),
            ([56, 57, 66, 67], "路面可能结冰，出行注意湿滑"),
            ([65, 82], "雨势较强，出行留意积水"),
            ([75, 86], "降雪较强，出行注意湿滑")
        ]
        for (codes, expected) in noteGroups {
            for code in codes {
                let current = advice(weather(19, code: code, intensity: 0))
                precondition(current.weatherNote == expected, "Missing/wrong current note for code \(code)")
                precondition(current.tooltip.contains(expected))
                precondition(!current.menuSummary.contains("\n") && !current.menuSummary.contains("\r"))
                precondition(!current.menuSummary.contains(expected), "Compact clothing summary must stay separate")
            }
        }
        for code in [-1, 0, 1, 2, 3, 45, 48, 51, 53, 55, 61, 63, 71, 73, 77, 80, 81, 85] {
            precondition(advice(weather(19, code: code)).weatherNote == nil,
                         "Ordinary weather must not acquire a severe-condition note")
        }
        let windNote = "风力较强，留意高处坠物"
        precondition(advice(weather(19, wind: 47.99, gust: 64.99)).weatherNote == nil)
        precondition(advice(weather(19, wind: 48)).weatherNote == windNote)
        precondition(advice(weather(19, gust: 65)).weatherNote == windNote)
        for invalidWind in [Double.nan, .infinity, -1] {
            precondition(advice(weather(19, wind: invalidWind, gust: invalidWind)).weatherNote == nil)
        }
        for code in [56, 65, 75] {
            precondition(advice(weather(19, code: code, wind: 48)).weatherNote == windNote)
        }
        precondition(advice(weather(19, code: 95, wind: 100, gust: 150)).weatherNote == noteGroups[0].1)
        precondition(advice(weather(19, code: 99, wind: 100, gust: 150)).weatherNote == noteGroups[1].1)
        for forecastCode in [95, 99, 65] {
            let future = advice(weather(19, code: 3, probability: 100,
                                        forecastCode: forecastCode, forecastAmount: 20))
            precondition(future.weatherNote == nil, "A future severe code/probability is not a current condition")
        }
        precondition(advice(weather(19, code: 99, age: 7_199)).weatherNote != nil)
        precondition(OutfitAdvice.make(for: weather(19, code: 99, age: 7_200), at: now) == nil)

        // The visual hint is one short line; accessibility retains the original
        // clothing, temperature basis, accessories and separate weather note.
        let summary = advice(weather(18, feelsLike: 18, code: 63))
        precondition(summary.menuSummary == "针织衫＋防风雨外套 · 体感18°")
        precondition(advice(weather(29)).menuSummary == "短袖 · 气温29°")
        let coldReminder = advice(weather(-12, feelsLike: -12, code: 67))
        precondition(coldReminder.menuSummary == "羽绒服＋保暖内搭＋防湿外层 · 体感-12°")
        precondition(!coldReminder.menuSummary.contains("\n") && !coldReminder.menuSummary.contains("\r"))
        precondition(coldReminder.tooltip.contains("穿搭参考：\(coldReminder.description)"))
        precondition(coldReminder.tooltip.contains("依据体感 -12°C") && coldReminder.tooltip.contains("随身建议："))
        precondition(coldReminder.accessories.allSatisfy { coldReminder.tooltip.contains($0.label) })
        precondition(coldReminder.tooltip.components(separatedBy: "\n").last == coldReminder.weatherNote)
        let existingInitializer = OutfitAdvice(iconName: "knit", baseIconName: "knit", description: "针织衫",
                                              effectiveTemperature: 18, temperatureSource: .feelsLike, accessories: [])
        precondition(existingInitializer.weatherNote == nil, "Existing memberwise callers remain compatible")

        // UV accessories use a valid daylight signal and do not replace the main garment.
        precondition(!has(advice(weather(21, uv: 2.99)), "sun-hat"))
        let sunnyMild = advice(weather(21, code: 0, uv: 6))
        precondition(sunnyMild.iconName == "long-sleeve")
        precondition(has(sunnyMild, "sun-hat") && has(sunnyMild, "sunglasses"))
        precondition(advice(weather(-3, code: 0, uv: 6)).iconName == "puffer")
        for daylight: Bool? in [false, nil] {
            let nightOrUnknown = advice(weather(21, uv: 12, daylight: daylight))
            precondition(!has(nightOrUnknown, "sun-hat") && !has(nightOrUnknown, "sunglasses"))
        }
        for invalidUV in [Double.nan, .infinity, -1] {
            precondition(!has(advice(weather(21, uv: invalidUV)), "sun-hat"))
        }

        // Stale display policy matches the menu weather icon. No hidden state or previous city persists.
        precondition(OutfitAdvice.make(for: weather(19, age: 1_800), at: now) != nil)
        precondition(OutfitAdvice.make(for: weather(19, age: 7_199), at: now) != nil)
        precondition(OutfitAdvice.make(for: weather(19, age: 7_200), at: now) == nil)
        precondition(OutfitAdvice.make(for: weather(19, validAt: now.addingTimeInterval(1_201)), at: now) == nil)
        precondition(OutfitAdvice.make(for: weather(19, fetchedAt: now.addingTimeInterval(1_201)), at: now) == nil)
        precondition(OutfitAdvice.make(for: weather(19, validAt: Date(timeIntervalSince1970: .nan)), at: now) == nil)
        precondition(OutfitAdvice.make(for: weather(), at: Date(timeIntervalSince1970: .nan)) == nil)
        let fixed = weather(14, feelsLike: 12, code: 63, wind: 10)
        precondition(advice(fixed) == advice(fixed))
        precondition(Set(advice(fixed).accessories.map(\.iconName)).count == advice(fixed).accessories.count)

        print("PASS: temperature boundaries/apparent priority/fallback; missing and stale weather; six upper garments; cold wet warmth preservation; current versus forecast precipitation; wind layering without double chill; no umbrella in wind/thunder; daytime UV accessories; deterministic stateless output; current severe-code notes and ordinary nil; strong-wind boundaries/priority; future severe forecasts cannot add a current note; single-line menu summary and complete accessibility tooltip; compatible memberwise initializer")
    }
}
