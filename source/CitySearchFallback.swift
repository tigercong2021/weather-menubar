import Foundation

enum CitySearchFallback {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    static func search(_ query: String) async throws -> [CityChoice] {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ",")
        guard name.count >= 2 else { return [] }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "geocoding-api.open-meteo.com"
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "count", value: "12")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let results = try JSONDecoder().decode(SearchResponse.self, from: data).results ?? []
        var seen = Set<String>()
        return results.compactMap { result in
            guard let choice = result.city,
                  seen.insert("\(choice.name.lowercased())|\(choice.region.lowercased())").inserted else { return nil }
            return choice
        }
    }

    private struct SearchResponse: Decodable {
        let results: [Result]?
    }

    private struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let featureCode: String?
        let country: String?
        let countryCode: String?
        let admin1: String?
        let admin2: String?

        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, country, admin1, admin2
            case featureCode = "feature_code"
            case countryCode = "country_code"
        }

        var city: CityChoice? {
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let featureCode, featureCode.hasPrefix("PPL"),
                  !["PPLH", "PPLQ", "PPLW", "PPLX"].contains(featureCode),
                  !title.isEmpty, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            var seen = Set([title.lowercased()])
            let region = [admin2, admin1, country ?? countryCode]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
                .joined(separator: " · ")
            return CityChoice(name: title, region: region, latitude: latitude, longitude: longitude)
        }
    }
}
