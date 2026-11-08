import Foundation

@main
struct WeatherDataChecks {
    static func main() async throws {
        let date = ISO8601DateFormatter()
        func instant(_ iso: String) -> Date { date.date(from: iso)! }
        func epoch(_ iso: String) -> Int { Int(instant(iso).timeIntervalSince1970) }
        let place = WeatherPlace(name: "合成测试地点", coordinate: .init(latitude: 31.2349, longitude: 121.4567))
        let currentTime = instant("2026-11-05T15:45:00Z")
        let downloaded = instant("2026-11-05T15:50:00Z")
        let syntheticJSON = """
        {
          "timezone": "Asia/Shanghai", "utc_offset_seconds": 28800,
          "current": {
            "time": \(Int(currentTime.timeIntervalSince1970)), "interval": 900,
            "temperature_2m": 13.1, "weather_code": 3, "is_day": 0, "precipitation": 0.25, "wind_gusts_10m": 28.4,
            "apparent_temperature": 10.7, "relative_humidity_2m": 82, "wind_speed_10m": 12.5,
            "wind_direction_10m": 275, "pressure_msl": 1012.7, "dew_point_2m": 9.4
          },
          "daily": {
            "time": [\(epoch("2026-11-04T16:00:00Z")), \(epoch("2026-11-05T16:00:00Z")),
                     \(epoch("2026-11-06T16:00:00Z")), \(epoch("2026-11-07T16:00:00Z"))],
            "temperature_2m_max": [20.4, 18.2, null, 22.1], "temperature_2m_min": [11.1, 12.3, 12.9, 14.1],
            "weather_code": [3, 61, null, 1],
            "sunrise": [\(epoch("2026-11-04T22:10:00Z")), \(epoch("2026-11-05T22:11:00Z"))],
            "sunset": [\(epoch("2026-11-05T09:00:00Z")), \(epoch("2026-11-06T08:59:00Z"))]
          },
          "hourly": {
            "time": [\(epoch("2026-11-05T16:00:00Z")), \(epoch("2026-11-05T17:00:00Z")), \(epoch("2026-11-05T18:00:00Z"))],
            "temperature_2m": [13.5, null, 12.8], "weather_code": [97, null, 51], "is_day": [0, 0, 0],
            "precipitation_probability": [70, null, 20], "uv_index": [1.2, null, 0],
            "wind_gusts_10m": [120, 110, 95]
          }
        }
        """
        let snapshot = try WeatherClient.snapshot(from: Data(syntheticJSON.utf8), place: place, fetchedAt: downloaded)
        precondition(!snapshot.hasMixedPrecipitation)
        precondition(snapshot.place == place && snapshot.validAt == currentTime && snapshot.fetchedAt == downloaded)
        precondition(snapshot.age(at: downloaded) == 300 && snapshot.age(at: currentTime - 4000).isInfinite)
        precondition(snapshot.age(at: instant("2026-11-05T16:16:00Z")) == 1860)
        precondition(snapshot.isDay(at: instant("2026-11-05T16:00:00Z")) == false)
        precondition(snapshot.isDay(at: instant("2026-11-05T22:10:59Z")) == false)
        precondition(snapshot.isDay(at: instant("2026-11-05T22:11:00Z")) == true)
        precondition(snapshot.isDay(at: instant("2026-11-06T08:59:00Z")) == false)
        precondition(snapshot.isDay(at: instant("2026-11-07T03:00:00Z")) == nil)
        precondition(snapshot.highLow(at: downloaded).high == 20.4)
        precondition(snapshot.highLow(at: instant("2026-11-05T16:00:00Z")).high == 18.2)
        precondition(snapshot.highLow(at: instant("2026-11-07T03:00:00Z")).high == nil)
        precondition(snapshot.code == 3 && snapshot.intensity == 1 && snapshot.gust == 28.4)
        precondition(snapshot.details == .init(feelsLike: 10.7, humidity: 82, windSpeed: 12.5,
                                              windDirection: 275, pressure: 1012.7, dewPoint: 9.4))
        precondition(snapshot.weatherDay(at: downloaded)?.sunrise == instant("2026-11-04T22:10:00Z"))
        precondition(snapshot.weatherDay(at: downloaded)?.sunset == instant("2026-11-05T09:00:00Z"))
        precondition(snapshot.rainProbability(at: downloaded) == 70 && snapshot.uvIndex(at: downloaded) == 1.2)
        let midnight = instant("2026-11-05T16:00:00Z")
        precondition(snapshot.rainProbability(at: midnight) == nil && snapshot.uvIndex(at: midnight) == nil)
        precondition(snapshot.rainProbability(at: midnight + 3600) == 20 && snapshot.uvIndex(at: midnight + 3600) == 0)
        precondition(snapshot.rainProbability(at: midnight - 3601) == nil && snapshot.uvIndex(at: midnight + 7200) == nil)
        precondition(snapshot.nextHours(at: downloaded).map(\.code) == [97, 51])
        precondition(snapshot.nextHours(at: downloaded, limit: 1).count == 1)
        let comingDays = snapshot.nextDays(at: downloaded)
        precondition(comingDays.map(\.localDate) == [20261106, 20261107, 20261108])
        precondition(comingDays.map(\.weatherCode) == [61, nil, 1])
        precondition(comingDays.map(\.high) == [18.2, nil, 22.1] && comingDays.map(\.low) == [12.3, 12.9, 14.1])
        precondition(comingDays.first?.date(in: snapshot.locationTimeZone) == instant("2026-11-05T16:00:00Z"))
        precondition(snapshot.nextDays(at: instant("2026-11-05T16:00:00Z")).map(\.localDate) == [20261107, 20261108])
        precondition(snapshot.nextDays(at: downloaded, limit: 1).count == 1 && snapshot.nextDays(at: downloaded, limit: 0).isEmpty)
        precondition(WeatherKind(code: 97).label == "雷雨" && WeatherKind(code: 1234).label == "天气状况未知")
        let saved = try JSONEncoder().encode(snapshot)
        let roundTrip = try JSONDecoder().decode(WeatherSnapshot.self, from: saved)
        precondition(roundTrip == snapshot)
        var legacy = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        legacy.removeValue(forKey: "gust")
        legacy.removeValue(forKey: "details")
        let legacyHours = legacy["hours"] as! [[String: Any]]
        legacy["hours"] = legacyHours.map { $0.filter { $0.key != "rainProbability" && $0.key != "uvIndex" } }
        let legacyDays = legacy["days"] as! [[String: Any]]
        legacy["days"] = legacyDays.prefix(2).map { $0.filter { $0.key != "weatherCode" } }
        let oldCache = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldCache.gust == nil && oldCache.validAt == snapshot.validAt && oldCache.place == snapshot.place)
        precondition(oldCache.details == nil && oldCache.rainProbability(at: downloaded) == nil && oldCache.uvIndex(at: downloaded) == nil)
        precondition(!oldCache.hasMixedPrecipitation)
        precondition(oldCache.nextDays(at: downloaded).count == 1)
        precondition(oldCache.nextDays(at: downloaded).first?.weatherCode == nil)
        precondition(oldCache.nextDays(at: downloaded).first?.high == 18.2)
        let invalidGustJSON = syntheticJSON.replacingOccurrences(of: "\"wind_gusts_10m\": 28.4", with: "\"wind_gusts_10m\": -1")
        let invalidGust = try WeatherClient.snapshot(from: Data(invalidGustJSON.utf8), place: place, fetchedAt: downloaded)
        precondition(invalidGust.gust == nil && invalidGust.code == snapshot.code)
        let invalidDetailsJSON = syntheticJSON.replacingOccurrences(of: "\"relative_humidity_2m\": 82", with: "\"relative_humidity_2m\": 182")
            .replacingOccurrences(of: "\"wind_direction_10m\": 275", with: "\"wind_direction_10m\": 465")
            .replacingOccurrences(of: "\"precipitation_probability\": [70", with: "\"precipitation_probability\": [170")
            .replacingOccurrences(of: "\"uv_index\": [1.2", with: "\"uv_index\": [-1")
        let invalidDetails = try WeatherClient.snapshot(from: Data(invalidDetailsJSON.utf8), place: place, fetchedAt: downloaded)
        precondition(invalidDetails.details?.humidity == nil && invalidDetails.details?.windDirection == nil)
        precondition(invalidDetails.details?.feelsLike == 10.7 && invalidDetails.details?.pressure == 1012.7)
        precondition(invalidDetails.rainProbability(at: downloaded) == nil && invalidDetails.uvIndex(at: downloaded) == nil)

        func precipitationSnapshot(code: Int, rain: Double, showers: Double, snow: Double, interval: Int = 900) throws -> WeatherSnapshot {
            let json = syntheticJSON
                .replacingOccurrences(of: "\"weather_code\": 3", with: "\"weather_code\": \(code)")
                .replacingOccurrences(of: "\"interval\": 900", with: "\"interval\": \(interval)")
                .replacingOccurrences(of: "\"precipitation\": 0.25",
                                      with: "\"precipitation\": 0.25, \"rain\": \(rain), \"showers\": \(showers), \"snowfall\": \(snow)")
            return try WeatherClient.snapshot(from: Data(json.utf8), place: place, fetchedAt: downloaded)
        }
        for code in [51, 61, 71, 80, 85] {
            let mixed = try precipitationSnapshot(code: code, rain: 0.02, showers: 0.04, snow: 0.05)
            let cachedMixed = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONEncoder().encode(mixed))
            precondition(mixed.hasMixedPrecipitation && cachedMixed.hasMixedPrecipitation)
        }
        for code in [3, 56, 66, 95, 96, 99, -1] {
            let other = try precipitationSnapshot(code: code, rain: 0.12, showers: 0.06, snow: 0.1)
            precondition(!other.hasMixedPrecipitation)
        }
        let traceRain = try precipitationSnapshot(code: 71, rain: 0.04, showers: 0, snow: 0.1)
        let traceSnow = try precipitationSnapshot(code: 61, rain: 0.1, showers: 0, snow: 0.04)
        let invalidInterval = try precipitationSnapshot(code: 61, rain: 0.1, showers: 0, snow: 0.1, interval: 0)
        precondition(!traceRain.hasMixedPrecipitation && !traceSnow.hasMixedPrecipitation && !invalidInterval.hasMixedPrecipitation)

        // The response's November 2 anchor uses the request offset (04:00Z), but after
        // daylight saving ends the local calendar's November 2 starts at 05:00Z.
        let dstJSON = """
        {
          "timezone": "America/New_York", "utc_offset_seconds": -14400,
          "current": { "time": \(epoch("2026-11-01T03:45:00Z")), "temperature_2m": 12, "is_day": 0 },
          "daily": {
            "time": [\(epoch("2026-11-01T04:00:00Z")), \(epoch("2026-11-02T04:00:00Z"))],
            "temperature_2m_max": [17, 16], "sunrise": [null, null], "sunset": [null, null]
          },
          "hourly": { "time": [\(epoch("2026-11-02T12:00:00Z"))], "is_day": [1] }
        }
        """
        let dst = try WeatherClient.snapshot(from: Data(dstJSON.utf8), place: place,
                                             fetchedAt: instant("2026-11-01T03:50:00Z"))
        precondition(dst.code == -1 && WeatherKind(code: dst.code).label == "天气状况未知")
        precondition(dst.highLow(at: instant("2026-11-02T04:59:59Z")).high == 17)
        precondition(dst.highLow(at: instant("2026-11-02T05:00:00Z")).high == 16)
        let dstFutureDay = dst.nextDays(at: instant("2026-11-02T04:59:59Z")).first
        precondition(dstFutureDay?.localDate == 20261102 && dstFutureDay?.date(in: dst.locationTimeZone) == instant("2026-11-02T05:00:00Z"))
        precondition(dst.nextDays(at: instant("2026-11-02T05:00:00Z")).isEmpty)
        precondition(dst.isDay(at: instant("2026-11-01T03:55:00Z")) == false)
        precondition(dst.isDay(at: instant("2026-11-02T12:30:00Z")) == true)
        precondition(dst.isDay(at: instant("2026-11-02T13:00:00Z")) == nil)

        let request = try WeatherClient.request(for: place.coordinate)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        let values = Dictionary(uniqueKeysWithValues: query.compactMap { item in item.value.map { (item.name, $0) } })
        precondition(values["latitude"] == "31.23" && values["longitude"] == "121.46")
        precondition(values["timezone"] == "auto" && values["timeformat"] == "unixtime")
        precondition(values["forecast_days"] == "4" && values["daily"]?.contains("weather_code") == true)
        precondition(values["temperature_unit"] == "celsius" && values["precipitation_unit"] == "mm")
        precondition(values["wind_speed_unit"] == "kmh" && values["current"]?.contains("wind_gusts_10m") == true)
        precondition(values["hourly"]?.contains("wind_gusts_10m") == false)
        let currentFields = Set((values["current"] ?? "").split(separator: ",").map(String.init))
        let hourlyFields = Set((values["hourly"] ?? "").split(separator: ",").map(String.init))
        precondition(currentFields.isSuperset(of: ["apparent_temperature", "relative_humidity_2m",
                                                   "wind_speed_10m", "wind_direction_10m", "pressure_msl", "dew_point_2m"]))
        precondition(currentFields.isSuperset(of: ["rain", "showers", "snowfall"]))
        precondition(hourlyFields.isSuperset(of: ["precipitation_probability", "uv_index"]))
        precondition(values["apikey"] == nil && request.url!.host == "api.open-meteo.com")
        precondition(!request.url!.absoluteString.contains("31.2349") && !request.url!.absoluteString.contains("121.4567"))
        do {
            _ = try WeatherClient.request(for: .init(latitude: .nan, longitude: 0))
            preconditionFailure("Invalid coordinates were accepted")
        } catch WeatherClient.Failure.invalidCoordinate {}
        do {
            _ = try WeatherClient.snapshot(from: Data(syntheticJSON.utf8), place: place, fetchedAt: currentTime - 4000)
            preconditionFailure("Far-future weather was accepted")
        } catch WeatherClient.Failure.incompleteWeather {}

        print("PASS: synthetic Open-Meteo payload, civil midnight, DST, sunrise/sunset, stale validity, location binding, hourly and daily forecast alignment, detail fields, mixed precipitation, cache compatibility, request rounding, and malformed input")
        if CommandLine.arguments.contains("--live-public") {
            let publicExample = WeatherPlace(name: "上海公开测试网格", coordinate: .init(latitude: 31.2, longitude: 121.5))
            let live = try await WeatherClient().fetch(for: publicExample)
            let now = Date()
            precondition(live.place == publicExample && live.timezone == "Asia/Shanghai")
            precondition(live.age(at: now) < 3600 && live.isDay(at: now) != nil)
            precondition(live.highLow(at: now).high != nil && live.nextHours(at: now).count == 6)
            precondition(live.nextHours(at: now).allSatisfy { $0.precipitation != nil && $0.rainProbability != nil })
            precondition(live.gust != nil)
            guard let details = live.details else { preconditionFailure("Live weather details were absent") }
            precondition([details.feelsLike, details.humidity, details.windSpeed, details.windDirection,
                          details.pressure, details.dewPoint].allSatisfy { $0 != nil })
            precondition(live.rainProbability(at: now) != nil && live.uvIndex(at: now) != nil)
            precondition(live.weatherDay(at: now)?.sunrise != nil && live.weatherDay(at: now)?.sunset != nil)
            let liveFuture = live.nextDays(at: now)
            precondition(liveFuture.count == 3)
            precondition(liveFuture.allSatisfy { $0.weatherCode != nil && $0.high != nil && $0.low != nil })
            print("PASS: Swift URLSession live public grid, current weather details, hourly rain and UV, local solar times, six-hour forecast, and 3 future days with condition and high/low")
        }
    }
}
