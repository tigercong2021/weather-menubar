import CoreLocation
import Foundation
import MapKit

enum LocationAuthorization: Equatable {
    case notDetermined, denied, restricted, authorized

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .authorizedAlways: self = .authorized
        @unknown default: self = .restricted
        }
    }
}

struct LocationFix: Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date

    func distance(to other: LocationFix) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    fileprivate init?(_ location: CLLocation, now: Date) {
        let age = now.timeIntervalSince(location.timestamp)
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              (0...10_000).contains(location.horizontalAccuracy),
              (-15...180).contains(age) else { return nil }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        accuracy = location.horizontalAccuracy
        timestamp = location.timestamp
    }
}

enum LocationError: LocalizedError {
    case notAuthorized, unavailable, timeout

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "定位权限不可用"
        case .unavailable: "暂时无法获取可靠位置"
        case .timeout: "定位超时"
        }
    }
}

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let authorizationManager = CLLocationManager()
    private var reportedAuthorization: LocationAuthorization = .notDetermined
    private var lastAuthorizationRequest: Date?
    private var currentRequest: LocationRequest?
    var onAuthorizationChange: ((LocationAuthorization) -> Void)?

    var authorization: LocationAuthorization {
        LocationAuthorization(authorizationManager.authorizationStatus)
    }

    override init() {
        super.init()
        reportedAuthorization = authorization
        authorizationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationManager.delegate = self
    }

    func requestAuthorization() {
        guard authorization == .notDetermined else { return }
        if let lastAuthorizationRequest, Date().timeIntervalSince(lastAuthorizationRequest) < 30 { return }
        lastAuthorizationRequest = Date()
        // On native macOS, starting location services lets the system ask for permission.
        // This method is called only in response to the explicit authorization button.
        authorizationManager.requestLocation()
    }

    func fix() async throws -> LocationFix {
        try Task.checkCancellation()
        guard authorization == .authorized else { throw LocationError.notAuthorized }
        currentRequest?.fail(CancellationError())
        let request = LocationRequest()
        currentRequest = request
        defer {
            if currentRequest === request { currentRequest = nil }
        }
        return try await request.run()
    }

    // Core Location dispatches callbacks on the run loop where the manager was created.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let current = authorization
        guard current != reportedAuthorization else { return }
        reportedAuthorization = current
        lastAuthorizationRequest = nil
        authorizationManager.stopUpdatingLocation()
        if current != .authorized { currentRequest?.fail(LocationError.notAuthorized) }
        onAuthorizationChange?(current)
    }

    // Required by requestLocation(). Only the independent authorized request supplies a fix.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

@MainActor
private final class LocationRequest: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationFix, Error>?
    private var timeout: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var hasRetried = false

    func run() async throws -> LocationFix {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(18)) } catch { return }
                    self?.fail(LocationError.timeout)
                }
                manager.desiredAccuracy = kCLLocationAccuracyKilometer
                manager.delegate = self
                manager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor in self.fail(CancellationError()) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let now = Date()
        if let fix = locations.reversed().lazy.compactMap({ LocationFix($0, now: now) }).first {
            finish(.success(fix))
        } else {
            retryOnce()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        switch (error as? CLError)?.code {
        case .denied: fail(LocationError.notAuthorized)
        case .locationUnknown: retryOnce()
        default: fail(LocationError.unavailable)
        }
    }

    private func retryOnce() {
        guard continuation != nil, retry == nil else { return }
        guard !hasRetried else { fail(LocationError.unavailable); return }
        hasRetried = true
        retry = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            guard let self, continuation != nil else { return }
            retry = nil
            manager.requestLocation()
        }
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<LocationFix, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        retry?.cancel()
        manager.delegate = nil
        manager.stopUpdatingLocation()
        continuation.resume(with: result)
    }
}

struct CityChoice: Identifiable, Sendable {
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    var id: String { "\(name)|\(region)|\(latitude)|\(longitude)" }
}

@MainActor
enum CityLookup {
    static func reverse(_ fix: LocationFix) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(
            location: CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        ) else { return nil }
        request.preferredLocale = Locale(identifier: "zh-Hans")
        return try await MapRequest<String?>().run(cancel: { request.cancel() }) { complete in
            request.getMapItems { items, error in
                if let error {
                    complete(.failure(error))
                } else {
                    let city = items?.lazy.compactMap {
                        clean($0.addressRepresentations?.cityName)
                    }.first
                    complete(.success(city))
                }
            }
        }
    }

    static func search(_ query: String) async throws -> [CityChoice] {
        guard let query = clean(query) else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        request.addressFilter = MKAddressFilter(including: [.locality, .subAdministrativeArea])
        let search = MKLocalSearch(request: request)
        let choices = try await MapRequest<[CityChoice]>().run(cancel: { search.cancel() }) { complete in
            search.start { response, error in
                if let error {
                    if (error as? MKError)?.code == .placemarkNotFound {
                        complete(.success([]))
                    } else {
                        complete(.failure(error))
                    }
                    return
                }
                complete(.success(cityChoices(response?.mapItems ?? [])))
            }
        }
        guard !choices.isEmpty else { return [] }
        return try await localizedChoices(choices, query: query)
    }

    private static func cityChoices(_ items: [MKMapItem]) -> [CityChoice] {
        var choices: [CityChoice] = []
        for item in items {
            let coordinate = item.location.coordinate
            let address = item.addressRepresentations
            guard CLLocationCoordinate2DIsValid(coordinate),
                  let name = clean(address?.cityName) ?? clean(item.name) else { continue }
            let context = clean(address?.cityWithContext(.full))
            let region = (context == name ? nil : context) ?? clean(address?.regionName) ?? ""
            let choice = CityChoice(name: name, region: region,
                                    latitude: coordinate.latitude, longitude: coordinate.longitude)
            if !choices.contains(where: { $0.name == name && $0.region == region && $0.distance(to: choice) < 5_000 }) {
                choices.append(choice)
            }
            if choices.count == 8 { break }
        }
        return choices
    }

    private static func localizedChoices(_ choices: [CityChoice], query: String) async throws -> [CityChoice] {
        guard let request = MKGeocodingRequest(addressString: query) else { return choices }
        request.preferredLocale = Locale(identifier: "zh-Hans")
        // Local search determines the candidates. Geocoding provides translated labels
        // for confirmed matches, without introducing new cities or changing their coordinates.
        let labels = try? await MapRequest<[CityChoice]>().run(
            timeoutAfter: .seconds(4), cancel: { request.cancel() }
        ) { complete in
            request.getMapItems { items, error in
                if let error {
                    complete(.failure(error))
                } else {
                    let cities = (items ?? []).filter { item in
                        guard let name = clean(item.name) else { return false }
                        return name == clean(item.addressRepresentations?.cityName)
                    }
                    complete(.success(cityChoices(cities)))
                }
            }
        }
        try Task.checkCancellation()
        guard let labels, !labels.isEmpty else { return choices }
        return choices.map { choice in
            guard let match = labels.first(where: { $0.distance(to: choice) < 5_000 }) else { return choice }
            return CityChoice(name: match.name, region: match.region,
                              latitude: choice.latitude, longitude: choice.longitude)
        }
    }

    private static func clean(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private extension CityChoice {
    func distance(to other: CityChoice) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

@MainActor
private final class MapRequest<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeout: Task<Void, Never>?
    private var cancelRequest: (() -> Void)?

    func run(
        timeoutAfter: Duration = .seconds(12),
        cancel: @escaping () -> Void,
        start: (@escaping @MainActor (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                cancelRequest = cancel
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: timeoutAfter) } catch { return }
                    self?.finish(.failure(URLError(.timedOut)), shouldCancelRequest: true)
                }
                start { [weak self] result in
                    self?.finish(result, shouldCancelRequest: false)
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError()), shouldCancelRequest: true) }
        }
    }

    private func finish(_ result: Result<Value, Error>, shouldCancelRequest: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        if shouldCancelRequest { cancelRequest?() }
        cancelRequest = nil
        continuation.resume(with: result)
    }
}
