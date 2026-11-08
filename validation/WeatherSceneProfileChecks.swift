import Foundation

@main
struct WeatherSceneProfileChecks {
    static func main() {
        func expect(_ condition: Bool, _ message: String) {
            guard condition else {
                FileHandle.standardError.write(Data((message + "\n").utf8))
                exit(1)
            }
        }

        let light = WeatherSceneProfile(code: 61, intensity: 2)
        let medium = WeatherSceneProfile(code: 63, intensity: 2)
        let heavy = WeatherSceneProfile(code: 65, intensity: 2)
        expect(light.rain == .light && medium.rain == .moderate && heavy.rain == .heavy,
               "Rain modes must stay distinguishable even when the measured amount is equal.")
        expect(!heavy.lightning, "Heavy rain alone is not a thunderstorm.")
        let thunder = WeatherSceneProfile(code: 95, intensity: 1)
        let heavyThunder = WeatherSceneProfile(code: 97, intensity: 1)
        let hail = WeatherSceneProfile(code: 99, intensity: 0)
        expect(thunder.lightning && thunder.hail == nil && heavyThunder.lightning && heavyThunder.rain == .heavy
               && hail.lightning && hail.hail == .heavy,
               "Thunder and hail must use the source condition, not precipitation alone.")
        for rate in [1.0, 3.0] {
            let heavyHail = WeatherSceneProfile(code: 99, intensity: rate)
            expect(heavyHail.rain == .moderate && heavyHail.hail == .heavy && heavyHail.lightning,
                   "Heavy hail alone must not force the heavy-rain visual tier.")
        }
        let heavyHailAndRain = WeatherSceneProfile(code: 99, intensity: 9)
        expect(heavyHailAndRain.rain == .heavy && heavyHailAndRain.hail == .heavy && heavyHailAndRain.lightning,
               "A strong modeled rain rate can retain heavy rain alongside heavy hail.")
        expect(WeatherSceneProfile(code: 75, intensity: 0).snow == .heavy &&
               WeatherSceneProfile(code: 71, intensity: 0).snow == .light,
               "Light and heavy snow must follow the weather code.")
        let west = WeatherSceneProfile(code: 2, intensity: 0, windSpeed: 31, windDirection: 270)
        let east = WeatherSceneProfile(code: 2, intensity: 0, gust: 41, windDirection: 90)
        let calm = WeatherSceneProfile(code: 2, intensity: .nan, windSpeed: -.infinity, windDirection: 999)
        expect(west.wind == .moderate && west.flowX > 0.99 && east.wind == .moderate && east.flowX < -0.99,
               "Sustained wind and gusts both activate wind; opposite bearings must reverse horizontal motion.")
        expect(west.rain == nil && calm.wind == nil && calm.rainRate == 0,
               "Dry wind should stay dry and invalid values must not create weather effects.")
        let documentedCodes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67,
                               71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 97, 99]
        expect(documentedCodes.count == 29 &&
               documentedCodes.allSatisfy { WeatherKind(code: $0) != .unknown },
               "All documented Open-Meteo codes need a known scene family.")

        let calendar = ISO8601DateFormatter()
        func instant(_ value: String) -> Date? { calendar.date(from: value) }
        guard let rise = instant("2026-11-05T22:00:00Z"),
              let noon = instant("2026-11-06T04:00:00Z"),
              let set = instant("2026-11-06T10:00:00Z") else {
            expect(false, "Invalid date fixture.")
            return
        }
        let snapshot = WeatherSnapshot(place: .init(name: "合成城市", coordinate: .init(latitude: 31, longitude: 121)),
                                       temperature: 18, code: 0, intensity: 0, validAt: noon, fetchedAt: noon,
                                       timezone: "Asia/Shanghai", utcOffsetSeconds: 28800, currentDaylight: true,
                                       hours: [], days: [.init(localDate: 20261106, high: 21, low: 12,
                                                              sunrise: rise, sunset: set)])
        expect(snapshot.daylightProgress(at: rise) == 0 && snapshot.daylightProgress(at: noon) == 0.5,
               "Sun placement should use the selected city's local day.")
        expect(snapshot.daylightProgress(at: set) == nil &&
               snapshot.daylightProgress(at: rise.addingTimeInterval(-1)) == nil,
               "Nighttime must not receive a daylight sun position.")
        print("PASS: weather tiers, storm and hail, model wind direction, and local daylight progress.")
    }
}
