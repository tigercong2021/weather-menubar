import Foundation

/// Decides when a resolved location is stable enough to replace the automatic
/// target. Request scheduling and district extraction remain outside this type.
struct AutomaticLocationPolicy {
    static let fallbackName = "当前位置（地区名暂不可用）"
    private static let legacyFallbackName = "当前位置（城市名暂不可用）"
    private static let confirmationDelay: TimeInterval = 45
    private static let minimumConfirmationAge: TimeInterval = 30
    private static let candidateLifetime: TimeInterval = 180

    enum Decision: Equatable, Sendable {
        case retain
        case accept(WeatherPlace)
        case confirm(after: TimeInterval)
    }

    private struct Candidate {
        let original: WeatherPlace
        let place: WeatherPlace
        let accuracy: Double
        let firstObserved: Date
    }
    private var candidate: Candidate?

    mutating func reset() { candidate = nil }

    /// `at` is the location sample's timestamp, not the time the callback ran.
    /// Re-delivering the same cached fix therefore cannot confirm a boundary crossing.
    mutating func evaluate(current: WeatherPlace?, coordinate: WeatherCoordinate,
                           accuracy: Double, resolvedName: String?, at: Date) -> Decision {
        guard coordinate.isValid, accuracy.isFinite, (0...2_000).contains(accuracy),
              at.timeIntervalSince1970.isFinite else { return .retain }
        let name = Self.cleaned(resolvedName).flatMap { Self.isFallback($0) ? nil : $0 }
        guard let current, current.coordinate.isValid else {
            return accept(WeatherPlace(name: name ?? Self.fallbackName, coordinate: coordinate))
        }

        let distance = current.coordinate.distance(to: coordinate)
        let movementThreshold = max(1_000, 2 * accuracy)
        let largeMovementThreshold = max(20_000, 3 * accuracy)
        let currentIdentity = Self.identity(current.name)

        if let candidate,
           candidate.original != current
            || at < candidate.firstObserved
            || at.timeIntervalSince(candidate.firstObserved) > Self.candidateLifetime {
            self.candidate = nil
        }

        guard let name else {
            // Keep a nearby known district when the map service is unavailable.
            // Once meaningfully displaced, use an honest unnamed location rather
            // than attach the old district's name to new coordinates/weather.
            if distance < movementThreshold { return retain() }
            return accept(WeatherPlace(name: Self.fallbackName, coordinate: coordinate))
        }
        let proposed = WeatherPlace(name: name, coordinate: coordinate)
        let proposedIdentity = Self.identity(name)

        // Recover a missing label, or refine the same known city to a district,
        // without treating better address precision as a geographic transition.
        if Self.isFallback(current.name) || Self.isDistrictUpgrade(from: current.name, to: name) {
            return accept(proposed)
        }

        if distance < movementThreshold {
            if proposedIdentity == currentIdentity || Self.isCityOnlyDowngrade(from: current.name, to: name) {
                return retain()
            }
            // A changed administrative identity intentionally bypasses the
            // distance gate: a district boundary can be only a few meters away.
        }
        if distance >= largeMovementThreshold { return accept(proposed) }

        if let candidate, Self.identity(candidate.place.name) == proposedIdentity {
            let separation = candidate.place.coordinate.distance(to: coordinate)
            let stabilityRadius = max(1_000, 2 * max(candidate.accuracy, accuracy))
            if separation <= stabilityRadius {
                let age = at.timeIntervalSince(candidate.firstObserved)
                if age >= Self.minimumConfirmationAge { return accept(proposed) }
                return .confirm(after: max(1, Self.confirmationDelay - age))
            }
        }
        candidate = Candidate(original: current, place: proposed, accuracy: accuracy, firstObserved: at)
        return .confirm(after: Self.confirmationDelay)
    }

    private mutating func retain() -> Decision {
        candidate = nil
        return .retain
    }

    private mutating func accept(_ place: WeatherPlace) -> Decision {
        candidate = nil
        return .accept(place)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func parts(_ name: String) -> [String] {
        name.split(separator: "·").compactMap { cleaned(String($0)) }
    }

    private static func identity(_ name: String) -> String {
        let components = parts(name)
        guard let city = components.first else { return "" }
        return ([cityIdentity(city)] + components.dropFirst()).joined(separator: "·")
    }

    private static func cityIdentity(_ name: String) -> String {
        let text = cleaned(name) ?? ""
        return text.hasSuffix("市") ? String(text.dropLast()) : text
    }

    private static func isFallback(_ name: String) -> Bool {
        let name = cleaned(name)
        return name == fallbackName || name == legacyFallbackName
    }

    private static func isDistrictUpgrade(from old: String, to new: String) -> Bool {
        let oldParts = parts(old), newParts = parts(new)
        return oldParts.count == 1 && newParts.count > 1
            && cityIdentity(oldParts[0]) == cityIdentity(newParts[0])
    }

    private static func isCityOnlyDowngrade(from old: String, to new: String) -> Bool {
        let oldParts = parts(old), newParts = parts(new)
        return oldParts.count > 1 && newParts.count == 1
            && cityIdentity(oldParts[0]) == cityIdentity(newParts[0])
    }
}
