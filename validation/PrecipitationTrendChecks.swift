import Foundation

@main
struct PrecipitationTrendChecks {
    static func main() throws {
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-11-08T02:30:00Z")! // Shanghai 10:30.
        let first = formatter.date(from: "2026-11-08T03:00:00Z")!
        let place = WeatherPlace(name: "合成测试地点", coordinate: .init(latitude: 31.2, longitude: 121.5))
        func snapshot(_ amounts: [Double?], probabilities: [Double?]? = nil, code: Int = 61,
                      intensity: Double = 1, age: TimeInterval = 0, anchor: Date = first,
                      at time: Date = now, timezone: String = "Asia/Shanghai") -> WeatherSnapshot {
            let hours = amounts.enumerated().map { index, amount in
                WeatherHour(time: anchor.addingTimeInterval(Double(index) * 3600),
                            temperature: 19, code: amount.map { $0 >= 0.1 ? 61 : 3 }, daylight: true,
                            rainProbability: probabilities == nil ? amount.map { $0 >= 0.1 ? 80 : 10 } : probabilities![index],
                            precipitation: amount)
            }
            return WeatherSnapshot(place: place, temperature: 19, code: code, intensity: intensity,
                                   validAt: time - age, fetchedAt: time - age, timezone: timezone,
                                   utcOffsetSeconds: 28800, currentDaylight: true, hours: hours, days: [])
        }
        func trend(_ amounts: [Double?], probabilities: [Double?]? = nil, code: Int = 61,
                   intensity: Double = 1) -> PrecipitationTrend {
            PrecipitationTrend(snapshot: snapshot(amounts, probabilities: probabilities,
                                                  code: code, intensity: intensity), now: now)
        }
        let taper = trend([1, 0.02, 0, 0, 0, 0])
        precondition(taper.headline == "预计11时后降水减弱") // First dry interval is 11—12, not 12—13.
        precondition(taper.hours.count == 6 && taper.isAvailable)
        precondition(trend([0, 0, 0, 0, 0, 0]).headline == "预计接下来降水减弱")
        precondition(trend([0, 1, 1, 1, 1, 1]).headline == "未来几小时降水或有间歇")
        precondition(trend([1, 1, 1, 1, 1, 0]).headline == "未来几小时仍可能有降水")
        precondition(trend([1, 0, 1, 0, 0, 1]).headline == "未来几小时降水或有间歇")
        precondition(trend([1, 0, 0, 0, 0, 0], probabilities: [80, 70, 70, 70, 70, 70]).headline
                     == "未来几小时仍可能有降水")
        precondition(trend([1, 0, 0, 0, 0, 0], probabilities: [80, nil, nil, nil, nil, nil]).headline
                     == "未来几小时仍可能有降水")
        precondition(trend([0, 0, 0, 0, 0, 0], probabilities: [80, 80, 80, 80, 80, 80],
                           code: 3, intensity: 0).headline == "降水量较少，仍需留意天气")
        precondition(trend([0, 0, 0, 0, 0, 0], code: 3, intensity: 0).headline == "未来几小时降水可能性较低")
        precondition(trend([0, 0, 0, 0, 0, 0], code: 61, intensity: 0).headline == "当前有降水，后续变化待观察")
        precondition(trend([0, 0, 0.5, 1, 1, 0.1], code: 3, intensity: 0).headline == "12时—13时可能有降水")
        precondition(trend([0.5, 1, 1, 1, 1, 1], code: 3, intensity: 0).headline == "本小时仍需留意降水")
        // At 10:59 an accumulated 10—11 amount may have fallen entirely in the
        // preceding 59 minutes; it must not imply an onset in the next hour.
        let nearlyEleven = formatter.date(from: "2026-11-08T02:59:00Z")!
        let priorRain = snapshot([1, 0, 0, 0, 0, 0], code: 3, intensity: 0, at: nearlyEleven)
        let nearBoundary = PrecipitationTrend(snapshot: priorRain, now: nearlyEleven)
        precondition(nearBoundary.headline == "本小时仍需留意降水")
        precondition(nearBoundary.detail == "逐小时模型预报 · 仅供趋势参考")
        precondition(trend([1, 0, 0, 0, 0, 0], code: 71).headline == "预计11时后降水减弱")
        let missing = trend([1, nil, 0, 0, 0, 0])
        precondition(missing.headline == "降水趋势数据暂缺" && missing.hours[1].precipitation == nil)
        precondition(!trend([nil, nil, nil, nil, nil, nil]).isAvailable)
        precondition(trend([1, -1, 0, 0, 0, 0]).headline == "降水趋势数据暂缺")
        precondition(trend([1, .nan, 0, 0, 0, 0]).headline == "降水趋势数据暂缺")
        let stale = PrecipitationTrend(snapshot: snapshot([1, 0, 0, 0, 0, 0], age: 1800), now: now)
        precondition(stale.headline == "降水趋势待更新")
        let valid = snapshot([1, 0, 0, 0, 0, 0])
        let gapped = WeatherSnapshot(place: place, temperature: 19, code: 61, intensity: 1,
                                    validAt: now, fetchedAt: now, timezone: "Asia/Shanghai",
                                    utcOffsetSeconds: 28800, currentDaylight: true,
                                    hours: valid.hours.enumerated().filter { $0.offset != 1 }.map(\.element), days: [])
        let gapTrend = PrecipitationTrend(snapshot: gapped, now: now)
        precondition(gapTrend.hours.count == 1 && gapTrend.headline == "降水趋势数据暂缺")
        let lateStart = snapshot([0, 0, 0, 0, 0, 0], anchor: first + 3600)
        precondition(PrecipitationTrend(snapshot: lateStart, now: now).hours.isEmpty)
        let overnightNow = formatter.date(from: "2026-11-08T15:30:00Z")! // 23:30 Shanghai
        let overnight = snapshot([1, 0, 0, 0, 0, 0], anchor: first + 13 * 3600, at: overnightNow)
        precondition(PrecipitationTrend(snapshot: overnight, now: overnightNow).headline == "预计明天0时后降水减弱")
        precondition(PrecipitationTrend.intervalLabel(for: overnight.hours[0], relativeTo: overnightNow,
                                                    in: overnight.locationTimeZone) == "23时—明天0时")

        // Legacy caches must decode without the new optional field.
        let encoded = try JSONEncoder().encode(valid)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy["hours"] = (legacy["hours"] as! [[String: Any]]).map { $0.filter { $0.key != "precipitation" } }
        let oldCache = try JSONDecoder().decode(WeatherSnapshot.self,
                                               from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldCache.hours.allSatisfy { $0.precipitation == nil })
        precondition(oldCache.hours.map(\.rainProbability) == valid.hours.map(\.rainProbability))
        let roundTrip = try JSONDecoder().decode(WeatherSnapshot.self, from: encoded)
        precondition(roundTrip == valid)

        // Exercise the real response parser: explicit zero is dry, negative/missing is unknown.
        let json = """
        {"timezone":"Asia/Shanghai","utc_offset_seconds":28800,
         "current":{"time":\(Int(now.timeIntervalSince1970)),"temperature_2m":19,"weather_code":61},
         "hourly":{"time":[\(Int(first.timeIntervalSince1970)),\(Int(first.timeIntervalSince1970) + 3600),
                            \(Int(first.timeIntervalSince1970) + 7200),\(Int(first.timeIntervalSince1970) + 10800)],
                   "precipitation":[0,-1,null,0.8],"precipitation_probability":[0,20,null,75]}}
        """
        let parsed = try WeatherClient.snapshot(from: Data(json.utf8), place: place, fetchedAt: now)
        precondition(parsed.hours.map(\.precipitation) == [0, nil, nil, 0.8])
        let query = URLComponents(url: try WeatherClient.request(for: place.coordinate).url!, resolvingAgainstBaseURL: false)!
        let fields = query.queryItems!.first { $0.name == "hourly" }!.value!.split(separator: ",")
        precondition(fields.contains("precipitation") && fields.contains("precipitation_probability"))
        print("PASS: hourly amount parsing/cache/request; taper, onset, gap/rebound, stale/missing data, probability conflicts, snow and local overnight timing")
    }
}
