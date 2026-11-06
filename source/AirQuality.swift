import Foundation

/// US AQI categories as published by AirNow. The source reports modeled concentrations.
enum AirQualityCategory: Int, CaseIterable, Sendable {
    case good, moderate, sensitiveGroups, unhealthy, veryUnhealthy, hazardous

    init(index: Int) {
        switch index {
        case ...50: self = .good
        case 51...100: self = .moderate
        case 101...150: self = .sensitiveGroups
        case 151...200: self = .unhealthy
        case 201...300: self = .veryUnhealthy
        default: self = .hazardous
        }
    }

    var label: String {
        switch self {
        case .good: "良好"
        case .moderate: "中等"
        case .sensitiveGroups: "对敏感人群不健康"
        case .unhealthy: "不健康"
        case .veryUnhealthy: "很不健康"
        case .hazardous: "危险"
        }
    }
}

struct AirQualityReading: Codable, Sendable, Equatable {
    let place: WeatherPlace
    let validAt: Date
    let fetchedAt: Date
    let aqi: Int?
    /// Surface PM2.5 concentration in micrograms per cubic metre.
    let pm25: Double?

    var category: AirQualityCategory? { aqi.map(AirQualityCategory.init(index:)) }

    func age(at date: Date) -> TimeInterval {
        guard validAt.timeIntervalSince(date) <= 20 * 60,
              fetchedAt.timeIntervalSince(date) <= 20 * 60 else { return .infinity }
        return max(0, date.timeIntervalSince(min(validAt, fetchedAt)))
    }
}

struct AirQualityClient: Sendable {
    enum Failure: Error {
        case invalidCoordinate, unexpectedResponse, serverStatus(Int), incompleteReading
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

    func fetch(for place: WeatherPlace) async throws -> AirQualityReading {
        let request = try Self.request(for: place.coordinate)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.unexpectedResponse }
        guard (200..<300).contains(response.statusCode) else { throw Failure.serverStatus(response.statusCode) }
        return try Self.reading(from: data, place: place, fetchedAt: Date())
    }

    static func request(for coordinate: WeatherCoordinate) throws -> URLRequest {
        guard coordinate.isValid else { throw Failure.invalidCoordinate }
        func approximate(_ degrees: Double) -> String {
            String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), (degrees * 10).rounded() / 10)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "air-quality-api.open-meteo.com"
        components.path = "/v1/air-quality"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: approximate(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: approximate(coordinate.longitude)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        guard let url = components.url else { throw Failure.invalidCoordinate }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func reading(from data: Data, place: WeatherPlace, fetchedAt: Date) throws -> AirQualityReading {
        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard let current = payload.current, let epoch = current.time,
              (1..<32_503_680_000).contains(epoch) else { throw Failure.incompleteReading }

        let validAt = Date(timeIntervalSince1970: Double(epoch))
        guard validAt.timeIntervalSince(fetchedAt) <= 20 * 60 else { throw Failure.incompleteReading }

        let aqi = current.usAQI.flatMap { value in
            value >= 0 ? Int(exactly: value.rounded()) : nil
        }
        let pm25 = current.pm25.flatMap { value in value.isFinite && value >= 0 ? value : nil }
        guard aqi != nil || pm25 != nil else { throw Failure.incompleteReading }
        return AirQualityReading(place: place, validAt: validAt, fetchedAt: fetchedAt, aqi: aqi, pm25: pm25)
    }

    private struct Response: Decodable {
        let current: Current?

        struct Current: Decodable {
            let time: Int64?
            let usAQI: Double?
            let pm25: Double?

            enum CodingKeys: String, CodingKey {
                case time
                case usAQI = "us_aqi"
                case pm25 = "pm2_5"
            }
        }
    }
}
