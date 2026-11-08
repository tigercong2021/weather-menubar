import Foundation
import AstronomyEngine

struct NightSkyPosition: Equatable, Sendable {
    let altitudeDegrees: Double
    /// Clockwise from true north, in [0, 360).
    let azimuthDegrees: Double
    var isAboveHorizon: Bool { altitudeDegrees > 0 }
}

struct NightSkyObject: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable { case star, planet }
    let id: String
    let name: String
    let kind: Kind
    let altitudeDegrees: Double
    /// Clockwise from true north: north 0, east 90, south 180, west 270.
    let azimuthDegrees: Double
    /// Apparent V magnitude before atmospheric extinction; smaller is brighter.
    let visualMagnitude: Double
}

struct NightSkyMoon: Equatable, Sendable {
    let altitudeDegrees: Double
    let azimuthDegrees: Double
    let illumination: Double
    /// Engine-derived elongation cycle, new 0 and full .5.
    let phaseFraction: Double
    var isWaxing: Bool { phaseFraction < 0.5 }
    var isAboveHorizon: Bool { altitudeDegrees > 0 }
}

struct NightSkyState: Equatable, Sendable {
    let evaluatedAt: Date
    let sun: NightSkyPosition
    var sunAltitudeDegrees: Double { sun.altitudeDegrees }
    /// A valid moon is retained below the horizon so rendering can hide it
    /// rather than pinning it to a decorative location.
    let moon: NightSkyMoon?
    /// Brightest modeled V magnitude above the horizon among the local bright
    /// star catalog and planets. Daylight suppresses this marker.
    let brightest: NightSkyObject?
}

struct NightSkySunEvents: Equatable, Sendable {
    let sunrise: Date?
    let sunset: Date?
}

/// Local Astronomy Engine calculation only. Sea-level observer and standard
/// refraction; no terrain, cloud extinction or visual-detection prediction.
/// All C calls stay on MainActor because DefineStar reuses a global C slot.
@MainActor
enum NightSkyAstronomy {
    private struct Key: Hashable {
        let minute: Double
        let coordinate: WeatherCoordinate
    }
    private struct Entry { let state: NightSkyState? }
    private static var cache: [Key: Entry] = [:]
    private static var insertionOrder: [Key] = []
    private static let capacity = 24
    private static var solarCache: [Key: NightSkySunEvents] = [:]
    private static var solarOrder: [Key] = []

    /// Used by explicit synthetic galleries to choose a real dawn/dusk instant.
    /// The caller supplies an absolute local-day start; no time zone is guessed.
    static func sunEvents(dayStartingAt date: Date, coordinate: WeatherCoordinate) -> NightSkySunEvents {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, abs(seconds) < 1.0e12, coordinate.isValid else {
            return NightSkySunEvents(sunrise: nil, sunset: nil)
        }
        let key = Key(minute: floor(seconds / 60), coordinate: coordinate)
        if let cached = solarCache[key] { return cached }
        let time = Astronomy_TimeFromDays(key.minute / 1440 - 10_957.5)
        let observer = Astronomy_MakeObserver(coordinate.latitude, coordinate.longitude, 0)
        func event(_ direction: astro_direction_t) -> Date? {
            let found = Astronomy_SearchRiseSetEx(BODY_SUN, observer, direction, time, 1, 0)
            guard found.status == ASTRO_SUCCESS, found.time.ut.isFinite else { return nil }
            return Date(timeIntervalSince1970: (found.time.ut + 10_957.5) * 86_400)
        }
        let result = NightSkySunEvents(sunrise: event(DIRECTION_RISE), sunset: event(DIRECTION_SET))
        if solarOrder.count >= capacity { solarCache.removeValue(forKey: solarOrder.removeFirst()) }
        solarCache[key] = result
        solarOrder.append(key)
        return result
    }

    static func sky(at date: Date, coordinate: WeatherCoordinate) -> NightSkyState? {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, abs(seconds) < 1.0e12, coordinate.isValid else { return nil }
        let key = Key(minute: floor(seconds / 60), coordinate: coordinate)
        if let entry = cache[key] { return entry.state }
        let instant = Date(timeIntervalSince1970: key.minute * 60)
        let state = calculate(at: instant, coordinate: coordinate)
        if insertionOrder.count >= capacity {
            cache.removeValue(forKey: insertionOrder.removeFirst())
        }
        cache[key] = Entry(state: state)
        insertionOrder.append(key)
        return state
    }

    static func brightest(at date: Date, coordinate: WeatherCoordinate) -> NightSkyObject? {
        sky(at: date, coordinate: coordinate)?.brightest
    }

    private static func calculate(at date: Date, coordinate: WeatherCoordinate) -> NightSkyState? {
        // Engine UT is days since 2000-01-01 12:00 UTC. Neither the computer's
        // local time zone nor the weather city's display time zone enters here.
        var time = Astronomy_TimeFromDays(date.timeIntervalSince1970 / 86_400 - 10_957.5)
        let observer = Astronomy_MakeObserver(coordinate.latitude, coordinate.longitude, 0)
        guard let sun = horizon(BODY_SUN, time: &time, observer: observer) else { return nil }

        var moon: NightSkyMoon?
        if let position = horizon(BODY_MOON, time: &time, observer: observer) {
            let lighting = Astronomy_Illumination(BODY_MOON, time)
            let phase = Astronomy_MoonPhase(time)
            if lighting.status == ASTRO_SUCCESS, phase.status == ASTRO_SUCCESS,
               lighting.phase_fraction.isFinite, phase.angle.isFinite {
                let angle = phase.angle.truncatingRemainder(dividingBy: 360)
                moon = NightSkyMoon(altitudeDegrees: position.altitude, azimuthDegrees: position.azimuth,
                                    illumination: min(1, max(0, lighting.phase_fraction)),
                                    phaseFraction: (angle < 0 ? angle + 360 : angle) / 360)
            }
        }

        var best: NightSkyObject?
        if sun.altitude < 0 {
            let planets: [(astro_body_t, String, String)] = [
                (BODY_MERCURY, "mercury", "水星"), (BODY_VENUS, "venus", "金星"),
                (BODY_MARS, "mars", "火星"), (BODY_JUPITER, "jupiter", "木星"),
                (BODY_SATURN, "saturn", "土星"), (BODY_URANUS, "uranus", "天王星"),
                (BODY_NEPTUNE, "neptune", "海王星")
            ]
            for (body, id, name) in planets {
                guard let position = horizon(body, time: &time, observer: observer), position.altitude > 0 else { continue }
                let lighting = Astronomy_Illumination(body, time)
                guard lighting.status == ASTRO_SUCCESS, lighting.mag.isFinite else { continue }
                choose(NightSkyObject(id: "planet-" + id, name: name, kind: .planet,
                                     altitudeDegrees: position.altitude, azimuthDegrees: position.azimuth,
                                     visualMagnitude: lighting.mag), into: &best)
            }
            for star in BrightStarCatalog.stars {
                guard star.visualMagnitude.isFinite,
                      Astronomy_DefineStar(BODY_STAR1, star.rightAscensionHours,
                                           star.declinationDegrees, star.distanceLightYears) == ASTRO_SUCCESS,
                      let position = horizon(BODY_STAR1, time: &time, observer: observer),
                      position.altitude > 0 else { continue }
                choose(NightSkyObject(id: "star-" + star.id, name: star.name, kind: .star,
                                     altitudeDegrees: position.altitude, azimuthDegrees: position.azimuth,
                                     visualMagnitude: star.visualMagnitude), into: &best)
            }
        }
        return NightSkyState(evaluatedAt: date,
                             sun: NightSkyPosition(altitudeDegrees: sun.altitude, azimuthDegrees: sun.azimuth),
                             moon: moon, brightest: best)
    }

    private static func choose(_ candidate: NightSkyObject, into best: inout NightSkyObject?) {
        if best == nil || candidate.visualMagnitude < best!.visualMagnitude
            || (candidate.visualMagnitude == best!.visualMagnitude && candidate.id < best!.id) {
            best = candidate
        }
    }

    private static func horizon(_ body: astro_body_t, time: inout astro_time_t,
                                observer: astro_observer_t) -> (altitude: Double, azimuth: Double)? {
        let equator = Astronomy_Equator(body, &time, observer, EQUATOR_OF_DATE, ABERRATION)
        guard equator.status == ASTRO_SUCCESS, equator.ra.isFinite, equator.dec.isFinite else { return nil }
        let result = Astronomy_Horizon(&time, observer, equator.ra, equator.dec, REFRACTION_NORMAL)
        guard result.altitude.isFinite, result.azimuth.isFinite,
              (-90...90).contains(result.altitude), (0...360).contains(result.azimuth) else { return nil }
        return (result.altitude, result.azimuth == 360 ? 0 : result.azimuth)
    }
}
