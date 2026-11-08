import Foundation

/// No persistent preferences or network requests are needed for selection tests.
private final class SelectionDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    private var writeCount = 0

    init(places: [WeatherPlace]) throws {
        values = ["watchedCities.v1": try JSONEncoder().encode(places)]
        super.init(suiteName: "WeatherSelectionChecks.in-memory")!
    }

    override func data(forKey defaultName: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        precondition(defaultName == "watchedCities.v1", "Selection must not write other preferences")
        values[defaultName] = value as? Data
        writeCount += 1
    }

    var writes: Int {
        lock.lock()
        defer { lock.unlock() }
        return writeCount
    }
}

private final class SelectionRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func increment() { lock.lock(); stored += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class SelectionNetworkBlocker: URLProtocol, @unchecked Sendable {
    static let requests = SelectionRequestCounter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.increment()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@main
@MainActor
enum WatchedSelectionChecks {
    static func main() async throws {
        let cities = [
            WeatherPlace(name: "合成甲城", coordinate: .init(latitude: 31.2, longitude: 121.5)),
            WeatherPlace(name: "合成乙城", coordinate: .init(latitude: 40.7, longitude: -74.0)),
            WeatherPlace(name: "合成丙城", coordinate: .init(latitude: 35.7, longitude: 139.7))
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SelectionNetworkBlocker.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let weather = WeatherClient(session: session)
        let air = AirQualityClient(session: session)
        let defaults = try SelectionDefaults(places: cities)
        let watched = WatchedCities(defaults: defaults, client: weather, airQualityClient: air)
        precondition(watched.places == cities && watched.selectedPlace == cities[0])
        let originalStorage = defaults.data(forKey: "watchedCities.v1")
        watched.select(cities[1])
        precondition(watched.selectedPlace == cities[1] && watched.places == cities)
        precondition(defaults.writes == 0 && defaults.data(forKey: "watchedCities.v1") == originalStorage)
        watched.select(WeatherPlace(name: "不在列表", coordinate: .init(latitude: 0, longitude: 0)))
        precondition(watched.selectedPlace == cities[1])
        watched.select(cities[1])
        precondition(defaults.writes == 0)
        let reopened = WatchedCities(defaults: defaults, client: weather, airQualityClient: air)
        precondition(reopened.selectedPlace == cities[0], "Selection is session-only")

        watched.remove(cities[2])
        precondition(watched.selectedPlace == cities[1], "Removing another city preserves selection")
        watched.remove(cities[1])
        precondition(watched.selectedPlace == cities[0] && watched.places == [cities[0]])
        watched.remove(cities[0])
        precondition(watched.selectedPlace == nil && watched.places.isEmpty)
        let first = CityChoice(name: "新增首城", region: "测试", latitude: 22.3, longitude: 114.2)
        precondition(watched.add(first) == .added)
        precondition(watched.selectedPlace == watched.places.first)
        let selected = watched.selectedPlace
        precondition(watched.add(CityChoice(name: "新增次城", region: "测试", latitude: 23.1, longitude: 113.3)) == .added)
        precondition(watched.selectedPlace == selected, "Adding another city does not switch the chosen background")
        precondition(watched.add(first) == .alreadyWatched && watched.selectedPlace == selected)

        let nine = (0..<9).map { WeatherPlace(name: "合成城市\($0)", coordinate: .init(latitude: Double($0), longitude: 100)) }
        let limited = WatchedCities(defaults: try SelectionDefaults(places: nine), client: weather, airQualityClient: air)
        precondition(limited.places.count == 8 && limited.selectedPlace == nine[0] && limited.isFull)
        precondition(limited.add(CityChoice(name: "第九城", region: "测试", latitude: 45, longitude: 100)) == .limitReached)
        let empty = WatchedCities(defaults: try SelectionDefaults(places: []), client: weather, airQualityClient: air)
        precondition(empty.selectedPlace == nil)
        empty.select(cities[0])
        precondition(empty.selectedPlace == nil)
        for _ in 0..<8 { await Task.yield() }
        precondition(SelectionNetworkBlocker.requests.count == 0, "Selection and hidden list mutations must not request weather")
        print("PASS: restored first selection, in-memory switching without list/storage/network changes, rejected outsiders, removal fallback, first add, session reset and eight-city limit")
    }
}
