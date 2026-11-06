import Foundation

struct WeatherCoordinate: Codable, Sendable, Hashable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let dLat = (other.latitude - latitude) * radians
        let dLon = (other.longitude - longitude) * radians
        let a = pow(sin(dLat / 2), 2) + cos(latitude * radians)
            * cos(other.latitude * radians) * pow(sin(dLon / 2), 2)
        return 2 * 6_371_000 * asin(sqrt(min(1, max(0, a))))
    }
}

struct WeatherPlace: Codable, Sendable, Hashable {
    let name: String
    let coordinate: WeatherCoordinate
}

struct WeatherHour: Codable, Sendable, Equatable, Identifiable {
    let time: Date
    let temperature: Double?
    let code: Int?
    let daylight: Bool?
    /// Probability and mean UV for the hour ending at this timestamp.
    let rainProbability: Double?
    let uvIndex: Double?

    init(time: Date, temperature: Double?, code: Int?, daylight: Bool?,
         rainProbability: Double? = nil, uvIndex: Double? = nil) {
        self.time = time
        self.temperature = temperature
        self.code = code
        self.daylight = daylight
        self.rainProbability = rainProbability
        self.uvIndex = uvIndex
    }

    var id: Date { time }
}

struct WeatherCurrentDetails: Codable, Sendable, Equatable {
    let feelsLike: Double?
    let humidity: Double?
    /// Modeled 10 m wind speed in km/h and direction in degrees from north.
    let windSpeed: Double?
    let windDirection: Double?
    /// Mean sea-level pressure in hPa.
    let pressure: Double?
    let dewPoint: Double?
}

struct WeatherDay: Codable, Sendable, Equatable {
    let localDate: Int
    let high: Double?
    let low: Double?
    let sunrise: Date?
    let sunset: Date?
    /// Daily WMO condition. Older cached forecasts may not include it.
    let weatherCode: Int?

    init(localDate: Int, high: Double?, low: Double?, sunrise: Date?, sunset: Date?,
         weatherCode: Int? = nil) {
        self.localDate = localDate
        self.high = high
        self.low = low
        self.sunrise = sunrise
        self.sunset = sunset
        self.weatherCode = weatherCode
    }

    func date(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Use local noon to find the day even if a clock change skips midnight.
        let components = DateComponents(year: localDate / 10_000, month: localDate / 100 % 100,
                                        day: localDate % 100, hour: 12)
        guard let noon = calendar.date(from: components),
              WeatherSnapshot.localDateKey(noon, in: timeZone) == localDate else { return nil }
        return calendar.startOfDay(for: noon)
    }
}

struct WeatherSnapshot: Codable, Sendable, Equatable {
    let place: WeatherPlace
    let temperature: Double
    let code: Int
    /// Current precipitation in mm per hour, extrapolated from the API's sampling interval.
    let intensity: Double
    let validAt: Date
    let fetchedAt: Date
    let timezone: String
    let utcOffsetSeconds: Int
    let currentDaylight: Bool?
    let hours: [WeatherHour]
    let days: [WeatherDay]
    /// Modeled 10 m wind gust from the current conditions, in km/h.
    let gust: Double?
    let details: WeatherCurrentDetails?
    /// Positive signal for both liquid and snow in the current model interval.
    /// Older cached responses omit this field.
    private let mixedPrecipitation: Bool?

    init(place: WeatherPlace, temperature: Double, code: Int, intensity: Double,
         validAt: Date, fetchedAt: Date, timezone: String, utcOffsetSeconds: Int,
         currentDaylight: Bool?, hours: [WeatherHour], days: [WeatherDay], gust: Double? = nil,
         details: WeatherCurrentDetails? = nil, mixedPrecipitation: Bool? = nil) {
        self.place = place
        self.temperature = temperature
        self.code = code
        self.intensity = intensity
        self.validAt = validAt
        self.fetchedAt = fetchedAt
        self.timezone = timezone
        self.utcOffsetSeconds = utcOffsetSeconds
        self.currentDaylight = currentDaylight
        self.hours = hours
        self.days = days
        self.gust = gust.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.details = details
        self.mixedPrecipitation = mixedPrecipitation
    }

    var hasMixedPrecipitation: Bool {
        guard mixedPrecipitation == true else { return false }
        switch WeatherKind(code: code) {
        case .drizzle, .rain, .showers, .snow, .snowShowers: return true
        default: return false
        }
    }

    var locationTimeZone: TimeZone {
        TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt
    }

    func isDay(at date: Date) -> Bool? {
        if let day = weatherDay(at: date), let sunrise = day.sunrise, let sunset = day.sunset, sunrise < sunset {
            return date >= sunrise && date < sunset
        }
        let dayKey = Self.localDateKey(date, in: locationTimeZone)
        if let currentDaylight,
           abs(date.timeIntervalSince(validAt)) <= 20 * 60,
           dayKey == Self.localDateKey(validAt, in: locationTimeZone) {
            return currentDaylight
        }
        // Hourly daylight is a fallback for missing solar times (including polar locations).
        if let hour = hours.last(where: { $0.time <= date }),
           date.timeIntervalSince(hour.time) < 3600,
           dayKey == Self.localDateKey(hour.time, in: locationTimeZone) {
            return hour.daylight
        }
        return nil
    }

    func highLow(at date: Date) -> (high: Double?, low: Double?) {
        let day = weatherDay(at: date)
        return (day?.high, day?.low)
    }

    func rainProbability(at date: Date) -> Double? {
        detailHour(at: date)?.rainProbability
    }

    func uvIndex(at date: Date) -> Double? {
        detailHour(at: date)?.uvIndex
    }

    func nextHours(at date: Date, limit: Int = 6) -> [WeatherHour] {
        Array(hours.lazy.filter { $0.time > date && ($0.temperature != nil || $0.code != nil) }
            .prefix(max(0, limit)))
    }

    func nextDays(at date: Date, limit: Int = 3) -> [WeatherDay] {
        let today = Self.localDateKey(date, in: locationTimeZone)
        return Array(days.lazy.filter {
            $0.localDate > today && ($0.high != nil || $0.low != nil || $0.weatherCode != nil)
        }.sorted { $0.localDate < $1.localDate }.prefix(max(0, limit)))
    }

    func age(at date: Date) -> TimeInterval {
        // After a large system clock correction, don't show future cache data as current.
        guard validAt.timeIntervalSince(date) <= 20 * 60,
              fetchedAt.timeIntervalSince(date) <= 20 * 60 else { return .infinity }
        return max(0, date.timeIntervalSince(min(validAt, fetchedAt)))
    }

    func weatherDay(at date: Date) -> WeatherDay? {
        let key = Self.localDateKey(date, in: locationTimeZone)
        return days.first { $0.localDate == key }
    }

    private func detailHour(at date: Date) -> WeatherHour? {
        // Both fields aggregate backward from the hour boundary in Open-Meteo.
        guard let hour = hours.first(where: { $0.time > date }), hour.time.timeIntervalSince(date) <= 3600 else {
            return nil
        }
        return hour
    }

    fileprivate static func localDateKey(_ date: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}

enum WeatherKind {
    case clear, mostlyClear, partlyCloudy, overcast, fog, drizzle, rain, freezingRain, showers, snow, snowShowers, thunder, unknown

    init(code: Int?) {
        switch code {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 61, 63, 65: self = .rain
        case 56, 57, 66, 67: self = .freezingRain
        case 80, 81, 82: self = .showers
        case 71, 73, 75, 77: self = .snow
        case 85, 86: self = .snowShowers
        case 95, 96, 97, 99: self = .thunder
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .clear: "晴"
        case .mostlyClear: "少云"
        case .partlyCloudy: "多云"
        case .overcast: "阴"
        case .fog: "雾"
        case .drizzle: "毛毛雨"
        case .rain: "雨"
        case .freezingRain: "冻雨"
        case .showers: "阵雨"
        case .snow: "雪"
        case .snowShowers: "阵雪"
        case .thunder: "雷雨"
        case .unknown: "天气状况未知"
        }
    }

    var symbolName: String { symbolName(isDay: nil) }

    func symbolName(isDay: Bool?) -> String {
        switch self {
        case .clear:
            switch isDay {
            case true: "sun.max"
            case false: "moon.stars"
            case nil: "circle.dotted"
            }
        case .mostlyClear, .partlyCloudy:
            switch isDay {
            case true: "cloud.sun"
            case false: "cloud.moon"
            case nil: "cloud"
            }
        case .overcast: "cloud"
        case .fog: "cloud.fog"
        case .drizzle: "cloud.drizzle"
        case .rain, .freezingRain, .showers: "cloud.rain"
        case .snow, .snowShowers: "cloud.snow"
        case .thunder: "cloud.bolt.rain"
        case .unknown: "circle.dotted"
        }
    }
}

struct WeatherClient: Sendable {
    enum Failure: Error {
        case invalidCoordinate, unexpectedResponse, serverStatus(Int), incompleteWeather
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetch(for place: WeatherPlace) async throws -> WeatherSnapshot {
        let request = try Self.request(for: place.coordinate)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.unexpectedResponse }
        guard (200..<300).contains(response.statusCode) else { throw Failure.serverStatus(response.statusCode) }
        return try Self.snapshot(from: data, place: place, fetchedAt: Date())
    }

    static func request(for coordinate: WeatherCoordinate) throws -> URLRequest {
        guard coordinate.isValid else { throw Failure.invalidCoordinate }
        // Use one decimal (~11 km of latitude). The place label and original coordinate stay local.
        func approximate(_ degrees: Double) -> String {
            String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), (degrees * 10).rounded() / 10)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        let currentFields = [
            "temperature_2m", "weather_code", "is_day", "precipitation", "rain", "showers", "snowfall", "wind_gusts_10m",
            "apparent_temperature", "relative_humidity_2m", "wind_speed_10m", "wind_direction_10m",
            "pressure_msl", "dew_point_2m"
        ]
        let parameters: [(String, String)] = [
            ("latitude", approximate(coordinate.latitude)),
            ("longitude", approximate(coordinate.longitude)),
            ("current", currentFields.joined(separator: ",")),
            ("hourly", "temperature_2m,weather_code,is_day,precipitation_probability,uv_index"),
            ("daily", "temperature_2m_max,temperature_2m_min,sunrise,sunset,weather_code"),
            ("timezone", "auto"), ("timeformat", "unixtime"), ("forecast_days", "4"),
            ("temperature_unit", "celsius"), ("precipitation_unit", "mm"), ("wind_speed_unit", "kmh")
        ]
        components.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { throw Failure.invalidCoordinate }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func snapshot(from data: Data, place: WeatherPlace, fetchedAt: Date) throws -> WeatherSnapshot {
        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        guard let current = payload.current, let temperature = current.temperature_2m,
              (-150...100).contains(temperature), let validAt = date(from: current.time),
              validAt.timeIntervalSince(fetchedAt) <= 20 * 60,
              let apiTimeZone = TimeZone(secondsFromGMT: payload.utc_offset_seconds) else {
            throw Failure.incompleteWeather
        }
        let days = payload.daily.map { daily in
            daily.time.enumerated().compactMap { index, epoch -> WeatherDay? in
                guard let anchor = date(from: epoch) else { return nil }
                // Open-Meteo uses one fixed offset for response day boundaries across DST transitions.
                let key = WeatherSnapshot.localDateKey(anchor, in: apiTimeZone)
                return WeatherDay(localDate: key, high: daily.temperature_2m_max?[safe: index] ?? nil,
                                  low: daily.temperature_2m_min?[safe: index] ?? nil,
                                  sunrise: date(from: daily.sunrise?[safe: index] ?? nil),
                                  sunset: date(from: daily.sunset?[safe: index] ?? nil),
                                  weatherCode: daily.weather_code?[safe: index] ?? nil)
            }
        } ?? []
        let hours = payload.hourly.map { hourly in
            hourly.time.enumerated().compactMap { index, epoch -> WeatherHour? in
                guard let time = date(from: epoch) else { return nil }
                return WeatherHour(time: time, temperature: hourly.temperature_2m?[safe: index] ?? nil,
                                   code: hourly.weather_code?[safe: index] ?? nil,
                                   daylight: daylight(hourly.is_day?[safe: index] ?? nil),
                                   rainProbability: within(0...100, hourly.precipitation_probability?[safe: index] ?? nil),
                                   uvIndex: within(0...Double.greatestFiniteMagnitude, hourly.uv_index?[safe: index] ?? nil))
            }.sorted { $0.time < $1.time }
        } ?? []
        let interval = current.interval ?? 0
        let intensity = interval > 0 ? max(0, current.precipitation ?? 0) * 3600 / Double(interval) : 0
        // The current fields cover the same model interval. Liquid is in mm and snowfall in cm.
        let liquid = (within(0...Double.greatestFiniteMagnitude, current.rain) ?? 0)
            + (within(0...Double.greatestFiniteMagnitude, current.showers) ?? 0)
        let mixed = interval > 0 && liquid >= 0.05 && (current.snowfall ?? 0) >= 0.05
        return WeatherSnapshot(place: place, temperature: temperature, code: current.weather_code ?? -1,
                               intensity: intensity, validAt: validAt, fetchedAt: fetchedAt,
                               timezone: payload.timezone, utcOffsetSeconds: payload.utc_offset_seconds,
                               currentDaylight: daylight(current.is_day), hours: hours, days: days,
                               gust: current.wind_gusts_10m, details: details(from: current),
                               mixedPrecipitation: mixed ? true : nil)
    }

    private static func details(from current: OpenMeteoResponse.Current) -> WeatherCurrentDetails? {
        let details = WeatherCurrentDetails(
            feelsLike: within(-150...100, current.apparent_temperature),
            humidity: within(0...100, current.relative_humidity_2m),
            windSpeed: within(0...Double.greatestFiniteMagnitude, current.wind_speed_10m),
            windDirection: within(0...360, current.wind_direction_10m),
            pressure: current.pressure_msl.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            dewPoint: within(-150...100, current.dew_point_2m)
        )
        return [details.feelsLike, details.humidity, details.windSpeed, details.windDirection,
                details.pressure, details.dewPoint].contains { $0 != nil } ? details : nil
    }

    private static func within(_ range: ClosedRange<Double>, _ value: Double?) -> Double? {
        value.flatMap { range.contains($0) ? $0 : nil }
    }

    private static func date(from epoch: Int64?) -> Date? {
        guard let epoch, (1..<32_503_680_000).contains(epoch) else { return nil }
        return Date(timeIntervalSince1970: Double(epoch))
    }

    private static func daylight(_ value: Int?) -> Bool? {
        switch value {
        case 1: true
        case 0: false
        default: nil
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let timezone: String
    let utc_offset_seconds: Int
    let current: Current?
    let daily: Daily?
    let hourly: Hourly?

    struct Current: Decodable {
        let time: Int64?
        let interval: Int?
        let temperature_2m: Double?
        let weather_code: Int?
        let is_day: Int?
        let precipitation: Double?
        let rain: Double?
        let showers: Double?
        let snowfall: Double?
        let wind_gusts_10m: Double?
        let apparent_temperature: Double?
        let relative_humidity_2m: Double?
        let wind_speed_10m: Double?
        let wind_direction_10m: Double?
        let pressure_msl: Double?
        let dew_point_2m: Double?
    }

    struct Daily: Decodable {
        let time: [Int64]
        let temperature_2m_max: [Double?]?
        let temperature_2m_min: [Double?]?
        let sunrise: [Int64?]?
        let sunset: [Int64?]?
        let weather_code: [Int?]?
    }

    struct Hourly: Decodable {
        let time: [Int64]
        let temperature_2m: [Double?]?
        let weather_code: [Int?]?
        let is_day: [Int?]?
        let precipitation_probability: [Double?]?
        let uv_index: [Double?]?
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
