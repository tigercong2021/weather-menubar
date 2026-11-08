import Foundation

@main
struct WeatherSkyPreviewChecks {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_794_096_000)
        let place = WeatherPlace(name: "测试城市", coordinate: .init(latitude: 31.2, longitude: 121.5))
        let other = WeatherPlace(name: "另一城市", coordinate: .init(latitude: 18.3, longitude: 109.5))
        let hour = WeatherHour(time: now.addingTimeInterval(3600), temperature: 12, code: 3,
                               daylight: false, rainProbability: 20, precipitation: 2)
        let snapshot = WeatherSnapshot(place: place, temperature: 20, code: 63, intensity: 3,
                                       validAt: now, fetchedAt: now, timezone: "Asia/Shanghai", utcOffsetSeconds: 28800,
                                       currentDaylight: true, hours: [hour], days: [], gust: 40,
                                       details: .init(feelsLike: 20, humidity: 80, windSpeed: 20,
                                                      windDirection: 90, pressure: 1012, dewPoint: 16),
                                       mixedPrecipitation: true)
        let selection = WeatherSkyPreview(place: place, time: hour.time)
        let future = snapshot.skySnapshot(for: selection)
        precondition(future.place == place && future.code == 3 && future.temperature == 12)
        precondition(future.isDay(at: hour.time) == false)
        precondition(future.intensity == 0 && future.gust == nil && future.details == nil && !future.hasMixedPrecipitation)
        precondition(future.hours == snapshot.hours && future.fetchedAt == snapshot.fetchedAt)
        precondition(snapshot.code == 63 && snapshot.intensity == 3 && snapshot.gust == 40)
        precondition(snapshot.skyTime(for: selection, now: now) == hour.time)
        precondition(snapshot.skySnapshot(for: nil) == snapshot && snapshot.skyTime(for: nil, now: now) == now)
        let wrongCity = WeatherSkyPreview(place: other, time: hour.time)
        precondition(snapshot.skySnapshot(for: wrongCity) == snapshot && snapshot.skyTime(for: wrongCity, now: now) == now)
        let unavailableHour = WeatherSkyPreview(place: place, time: now.addingTimeInterval(7200))
        precondition(snapshot.skySnapshot(for: unavailableHour) == snapshot)
        precondition(snapshot.skyTime(for: unavailableHour, now: now) == now)
        print("PASS: hourly sky follows selected city/time/code/daylight, current wind and precipitation are not copied to future, stale selections fall back to real time, and current weather remains unchanged")
    }
}
