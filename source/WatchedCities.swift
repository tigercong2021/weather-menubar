import Combine
import Foundation

@MainActor
final class WatchedCities: ObservableObject {
    enum AddResult {
        case added, alreadyWatched, limitReached, invalidCity
    }

    enum State {
        case waiting
        case loading(WeatherSnapshot?)
        case ready(WeatherSnapshot)
        case unavailable(WeatherSnapshot?)

        var snapshot: WeatherSnapshot? {
            switch self {
            case .waiting: nil
            case .ready(let snapshot): snapshot
            case .loading(let snapshot), .unavailable(let snapshot): snapshot
            }
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    private struct Key: Hashable {
        let name: String
        let latitude: Double
        let longitude: Double

        init(_ place: WeatherPlace) {
            name = place.name
            latitude = place.coordinate.latitude
            longitude = place.coordinate.longitude
        }
    }

    private static let storageKey = "watchedCities.v1"
    private static let maxCities = 8
    private static let maxConcurrentRequests = 2
    private let defaults: UserDefaults
    private let client: WeatherClient
    private let airQualityClient: AirQualityClient
    @Published private(set) var places: [WeatherPlace]
    @Published private var states: [Key: State] = [:]
    @Published private var airReadings: [Key: AirQualityReading] = [:]
    private var inFlight: [Key: Task<Void, Never>] = [:]
    private var nextAttempt: [Key: TimeInterval] = [:]
    private var airInFlight: [Key: Task<Void, Never>] = [:]
    private var nextAirAttempt: [Key: TimeInterval] = [:]
    private var isVisible = false

    init(defaults: UserDefaults = .standard, client: WeatherClient = WeatherClient(),
         airQualityClient: AirQualityClient = AirQualityClient()) {
        self.defaults = defaults
        self.client = client
        self.airQualityClient = airQualityClient
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([WeatherPlace].self, from: $0) } ?? []
        var restored: [WeatherPlace] = []
        for place in stored where place.coordinate.isValid && !place.name.isEmpty {
            if !restored.contains(where: { Self.sameCity($0, place) }) { restored.append(place) }
            if restored.count == Self.maxCities { break }
        }
        places = restored
    }

    var isFull: Bool { places.count >= Self.maxCities }

    func state(for place: WeatherPlace) -> State {
        states[Key(place)] ?? .waiting
    }

    func airQuality(for place: WeatherPlace) -> AirQualityReading? {
        guard let reading = airReadings[Key(place)], reading.age(at: Date()) < 6 * 3600 else { return nil }
        return reading
    }

    @discardableResult
    func add(_ choice: CityChoice) -> AddResult {
        let name = choice.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let coordinate = WeatherCoordinate(latitude: choice.latitude, longitude: choice.longitude)
        guard !name.isEmpty, coordinate.isValid else { return .invalidCity }
        let place = WeatherPlace(name: name, coordinate: coordinate)
        guard !places.contains(where: { Self.sameCity($0, place) }) else { return .alreadyWatched }
        guard !isFull else { return .limitReached }
        places.append(place)
        savePlaces()
        refreshIfNeeded()
        return .added
    }

    func remove(_ place: WeatherPlace) {
        guard let index = places.firstIndex(of: place) else { return }
        places.remove(at: index)
        savePlaces()
        let key = Key(place)
        inFlight[key]?.cancel()
        airInFlight[key]?.cancel()
        nextAttempt.removeValue(forKey: key)
        nextAirAttempt.removeValue(forKey: key)
        states.removeValue(forKey: key)
        airReadings.removeValue(forKey: key)
        refreshIfNeeded()
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            refreshIfNeeded()
        } else {
            for request in inFlight.values { request.cancel() }
            for request in airInFlight.values { request.cancel() }
        }
    }

    func refreshIfNeeded() {
        guard isVisible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        refreshWeather(at: now)
        refreshAirQuality(at: now)
    }

    private func refreshWeather(at now: TimeInterval) {
        for place in places {
            guard inFlight.count < Self.maxConcurrentRequests else { return }
            let key = Key(place)
            guard inFlight[key] == nil, (nextAttempt[key] ?? 0) <= now else { continue }
            let previous = state(for: place).snapshot
            states[key] = .loading(previous)
            inFlight[key] = Task { [weak self, client] in
                let result: Result<WeatherSnapshot, Error>
                do {
                    try Task.checkCancellation()
                    let snapshot = try await client.fetch(for: place)
                    result = .success(snapshot)
                } catch {
                    result = .failure(error)
                }
                self?.finish(result, for: place, key: key, cancelled: Task.isCancelled)
            }
        }
    }

    private func refreshAirQuality(at now: TimeInterval) {
        for place in places {
            guard airInFlight.count < Self.maxConcurrentRequests else { return }
            let key = Key(place)
            guard airInFlight[key] == nil, (nextAirAttempt[key] ?? 0) <= now else { continue }
            airInFlight[key] = Task { [weak self, airQualityClient] in
                let reading: AirQualityReading?
                do {
                    try Task.checkCancellation()
                    reading = try await airQualityClient.fetch(for: place)
                } catch {
                    reading = nil
                }
                self?.finishAirQuality(reading, for: place, key: key, cancelled: Task.isCancelled)
            }
        }
    }

    private func finish(
        _ result: Result<WeatherSnapshot, Error>, for place: WeatherPlace, key: Key, cancelled: Bool
    ) {
        inFlight.removeValue(forKey: key)
        defer { refreshIfNeeded() }
        guard places.contains(place) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let previous = state(for: place).snapshot
        if cancelled {
            states[key] = previous.map(State.ready) ?? .waiting
            nextAttempt[key] = now + 15
            return
        }
        switch result {
        case .success(let snapshot) where snapshot.place == place:
            states[key] = .ready(snapshot)
            nextAttempt[key] = now + 15 * 60
        default:
            states[key] = .unavailable(previous)
            nextAttempt[key] = now + 2 * 60
        }
    }

    private func finishAirQuality(
        _ reading: AirQualityReading?, for place: WeatherPlace, key: Key, cancelled: Bool
    ) {
        airInFlight.removeValue(forKey: key)
        let now = ProcessInfo.processInfo.systemUptime
        defer { if isVisible { refreshAirQuality(at: now) } }
        guard places.contains(place) else { return }
        if cancelled {
            nextAirAttempt[key] = now + 15
        } else if let reading, reading.place == place {
            if airReadings[key].map({ $0.validAt <= reading.validAt }) ?? true {
                airReadings[key] = reading
            }
            nextAirAttempt[key] = now + 30 * 60
        } else {
            nextAirAttempt[key] = now + 2 * 60
        }
    }

    private func savePlaces() {
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func sameCity(_ a: WeatherPlace, _ b: WeatherPlace) -> Bool {
        if a.coordinate == b.coordinate { return true }
        return a.name.caseInsensitiveCompare(b.name) == .orderedSame &&
            a.coordinate.distance(to: b.coordinate) < 5_000
    }
}
