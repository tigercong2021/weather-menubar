import Foundation

/// A transient sky-only selection. It never replaces the current weather cache
/// or the menu-bar city/temperature.
struct WeatherSkyPreview: Equatable, Sendable {
    let place: WeatherPlace
    let time: Date
}

extension WeatherSnapshot {
    func skySnapshot(for selection: WeatherSkyPreview?) -> WeatherSnapshot {
        guard let selection, selection.place == place,
              let hour = hours.first(where: { $0.time == selection.time }) else { return self }
        return WeatherSnapshot(place: place, temperature: hour.temperature ?? temperature,
                               code: hour.code ?? -1, intensity: 0,
                               validAt: hour.time, fetchedAt: fetchedAt,
                               timezone: timezone, utcOffsetSeconds: utcOffsetSeconds,
                               currentDaylight: hour.daylight ?? isDay(at: hour.time),
                               hours: hours, days: days)
        // Current wind/gust and mixed precipitation are deliberately not copied
        // into a future hour. Hourly amounts are not instantaneous rain rates.
    }

    func skyTime(for selection: WeatherSkyPreview?, now: Date) -> Date {
        guard let selection, selection.place == place,
              hours.contains(where: { $0.time == selection.time }) else { return now }
        return selection.time
    }
}
