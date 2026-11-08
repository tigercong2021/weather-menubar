import Foundation

/// The twelve complete calendar months preceding the current UTC month.
/// End is exclusive; hourly samples are instantaneous model AQI, not station observations.
struct AirQualityHistoryWindow: Codable, Sendable, Equatable {
    let start: Date
    let end: Date

    var expectedHours: Int { Int(end.timeIntervalSince(start) / 3_600) }
}

struct AirQualityHistoryMonthCoverage: Codable, Sendable, Equatable {
    let start: Date
    let end: Date
    let expectedHourCount: Int
    let validHourCount: Int

    var coverage: Double {
        expectedHourCount > 0 ? Double(validHourCount) / Double(expectedHourCount) : 0
    }
}

/// A compact, locally cacheable summary. Missing or invalid AQI never contributes a zero.
/// Fractions use the same rounded US AQI categories as the current reading. The mean
/// preserves the source's unrounded hourly values and is not a regulatory annual AQI.
struct AirQualityHistoryProfile: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1
    static let currentSource = "open-meteo/cams-auto/hourly-us-aqi/rounded-category-v1"

    let schemaVersion: Int
    let source: String
    let coordinateKey: String
    let windowStart: Date
    let windowEnd: Date
    let fetchedAt: Date
    let gradeFractions: [Double]
    let gradeHourCounts: [Int]
    let meanAQI: Double
    let coverage: Double
    let validHourCount: Int
    let expectedHourCount: Int
    let monthlyCoverage: [AirQualityHistoryMonthCoverage]

    /// Revalidate decoded caches, including their source and internal counts, before use.
    /// The window stays stable for a UTC month; a new month or 0.1-degree grid invalidates it.
    func isCurrent(for coordinate: WeatherCoordinate, at now: Date) -> Bool {
        guard let key = AirQualityHistoryClient.coordinateKey(for: coordinate),
              let window = AirQualityHistoryClient.window(for: now),
              schemaVersion == Self.currentSchemaVersion, source == Self.currentSource,
              coordinateKey == key, windowStart == window.start, windowEnd == window.end,
              fetchedAt.timeIntervalSince1970.isFinite,
              fetchedAt >= window.end, fetchedAt.timeIntervalSince(now) <= 20 * 60,
              expectedHourCount == window.expectedHours,
              (1...expectedHourCount).contains(validHourCount),
              meanAQI.isFinite, meanAQI >= 0, Int(exactly: meanAQI.rounded()) != nil,
              gradeFractions.count == 6, gradeHourCounts.count == 6,
              gradeHourCounts.allSatisfy({ (0...validHourCount).contains($0) }),
              gradeHourCounts.reduce(0, +) == validHourCount,
              gradeFractions.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              abs(gradeFractions.reduce(0, +) - 1) < 1e-9,
              zip(gradeFractions, gradeHourCounts).allSatisfy({ fraction, count in
                  abs(fraction - Double(count) / Double(validHourCount)) < 1e-9
              }),
              coverage.isFinite,
              abs(coverage - Double(validHourCount) / Double(expectedHourCount)) < 1e-9,
              validHourCount * 10 >= expectedHourCount * 9 else { return false }

        let months = AirQualityHistoryClient.months(in: window)
        guard months.count == 12, monthlyCoverage.count == months.count else { return false }
        var monthlyValid = 0
        for (month, recorded) in zip(months, monthlyCoverage) {
            guard recorded.start == month.start, recorded.end == month.end,
                  recorded.expectedHourCount == month.expectedHours,
                  (0...recorded.expectedHourCount).contains(recorded.validHourCount),
                  recorded.validHourCount * 5 >= recorded.expectedHourCount * 4 else { return false }
            monthlyValid += recorded.validHourCount
        }
        return monthlyValid == validHourCount
    }
}

struct AirQualityHistoryClient: Sendable {
    enum Failure: Error, Equatable {
        case invalidCoordinate, invalidWindow, unexpectedResponse, serverStatus(Int)
        case malformedResponse
        case insufficientCoverage(overall: Double, lowestMonth: Double)
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetch(for coordinate: WeatherCoordinate, now: Date) async throws -> AirQualityHistoryProfile {
        try Task.checkCancellation()
        let request = try Self.request(for: coordinate, now: now)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw Failure.unexpectedResponse }
        guard (200..<300).contains(response.statusCode) else { throw Failure.serverStatus(response.statusCode) }
        return try Self.profile(from: data, for: coordinate, now: now)
    }

    static func coordinateKey(for coordinate: WeatherCoordinate) -> String? {
        guard coordinate.isValid else { return nil }
        return "\(approximate(coordinate.latitude)),\(approximate(coordinate.longitude))"
    }

    /// Include the month window in in-flight/retry identities, so last month's
    /// failure cannot defer a new month's request even when the coordinate is unchanged.
    static func cacheKey(for coordinate: WeatherCoordinate, at now: Date) -> String? {
        guard let key = coordinateKey(for: coordinate), let window = window(for: now) else { return nil }
        return "\(AirQualityHistoryProfile.currentSource)|\(key)|\(dateString(window.start))|\(dateString(window.end))"
    }

    static func window(for now: Date) -> AirQualityHistoryWindow? {
        guard now.timeIntervalSince1970.isFinite,
              (31_536_000..<32_503_680_000).contains(now.timeIntervalSince1970),
              let end = utcCalendar.dateInterval(of: .month, for: now)?.start,
              let start = utcCalendar.date(byAdding: .month, value: -12, to: end) else { return nil }
        return AirQualityHistoryWindow(start: start, end: end)
    }

    static func request(for coordinate: WeatherCoordinate, now: Date) throws -> URLRequest {
        guard coordinateKey(for: coordinate) != nil else { throw Failure.invalidCoordinate }
        guard let window = window(for: now) else { throw Failure.invalidWindow }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "air-quality-api.open-meteo.com"
        components.path = "/v1/air-quality"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: approximate(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: approximate(coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "us_aqi"),
            URLQueryItem(name: "domains", value: "auto"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "start_date", value: dateString(window.start)),
            URLQueryItem(name: "end_date", value: dateString(window.end.addingTimeInterval(-86_400)))
        ]
        guard let url = components.url else { throw Failure.invalidCoordinate }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func profile(from data: Data, for coordinate: WeatherCoordinate,
                        now: Date) throws -> AirQualityHistoryProfile {
        try Task.checkCancellation()
        guard let key = coordinateKey(for: coordinate) else { throw Failure.invalidCoordinate }
        guard let window = window(for: now) else { throw Failure.invalidWindow }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard let hourly = payload.hourly,
              hourly.time.count == hourly.usAQI.count,
              payload.utcOffsetSeconds == nil || payload.utcOffsetSeconds == 0 else {
            throw Failure.malformedResponse
        }
        let monthWindows = months(in: window)
        let startEpoch = Int64(window.start.timeIntervalSince1970)
        let endEpoch = Int64(window.end.timeIntervalSince1970)
        let monthEnds = monthWindows.map { Int64($0.end.timeIntervalSince1970) }
        var seen = Set<Int64>()
        var gradeCounts = Array(repeating: 0, count: 6)
        var monthlyCounts = Array(repeating: 0, count: 12)
        var total = 0.0
        var count = 0
        for (offset, epoch) in hourly.time.enumerated() {
            if offset.isMultiple(of: 256) { try Task.checkCancellation() }
            // Reject ambiguous duplicate or off-hour records, even if they are outside the window.
            // Legitimate unsorted samples are accepted; out-of-window samples cannot inflate coverage.
            guard (1..<32_503_680_000).contains(epoch), epoch.isMultiple(of: 3_600),
                  seen.insert(epoch).inserted else { throw Failure.malformedResponse }
            guard epoch >= startEpoch, epoch < endEpoch,
                  let value = hourly.usAQI[offset], value.isFinite, value >= 0,
                  let index = Int(exactly: value.rounded()) else { continue }
            guard let month = monthEnds.firstIndex(where: { epoch < $0 }) else { continue }
            gradeCounts[AirQualityCategory(index: index).rawValue] += 1
            monthlyCounts[month] += 1
            total += value
            count += 1
        }
        let monthly = zip(monthWindows, monthlyCounts).map { month, valid in
            AirQualityHistoryMonthCoverage(start: month.start, end: month.end,
                                           expectedHourCount: month.expectedHours, validHourCount: valid)
        }
        let coverage = Double(count) / Double(window.expectedHours)
        guard count * 10 >= window.expectedHours * 9,
              monthly.allSatisfy({ $0.validHourCount * 5 >= $0.expectedHourCount * 4 }) else {
            throw Failure.insufficientCoverage(overall: coverage,
                                               lowestMonth: monthly.map(\.coverage).min() ?? 0)
        }
        let profile = AirQualityHistoryProfile(
            schemaVersion: AirQualityHistoryProfile.currentSchemaVersion,
            source: AirQualityHistoryProfile.currentSource, coordinateKey: key,
            windowStart: window.start, windowEnd: window.end, fetchedAt: now,
            gradeFractions: gradeCounts.map { Double($0) / Double(count) },
            gradeHourCounts: gradeCounts, meanAQI: total / Double(count), coverage: coverage,
            validHourCount: count, expectedHourCount: window.expectedHours, monthlyCoverage: monthly)
        guard profile.isCurrent(for: coordinate, at: now) else { throw Failure.malformedResponse }
        return profile
    }

    static func months(in window: AirQualityHistoryWindow) -> [AirQualityHistoryWindow] {
        (0..<12).compactMap { offset in
            guard let start = utcCalendar.date(byAdding: .month, value: offset, to: window.start),
                  let end = utcCalendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return AirQualityHistoryWindow(start: start, end: end)
        }
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func approximate(_ degrees: Double) -> String {
        let rounded = (degrees * 10).rounded() / 10
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded == 0 ? 0 : rounded)
    }

    private static func dateString(_ date: Date) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    private struct Response: Decodable {
        let hourly: Hourly?
        let utcOffsetSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case hourly
            case utcOffsetSeconds = "utc_offset_seconds"
        }

        struct Hourly: Decodable {
            let time: [Int64]
            let usAQI: [Double?]

            enum CodingKeys: String, CodingKey {
                case time
                case usAQI = "us_aqi"
            }
        }
    }
}
