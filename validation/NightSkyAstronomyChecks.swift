import Foundation

@main
@MainActor
enum NightSkyAstronomyChecks {
    static func main() {
        let formatter = ISO8601DateFormatter()
        func date(_ string: String) -> Date { formatter.date(from: string)! }
        let shanghai = WeatherCoordinate(latitude: 31.2, longitude: 121.5)
        func sky(_ string: String, at coordinate: WeatherCoordinate? = nil) -> NightSkyState {
            NightSkyAstronomy.sky(at: date(string), coordinate: coordinate ?? shanghai)!
        }
        func near(_ actual: Double, _ expected: Double, tolerance: Double = 0.1) {
            precondition(abs(actual - expected) < tolerance, "\(actual) disagrees with independent reference \(expected)")
        }

        // Independent JPL Horizons topocentric, refracted observer results.
        // Site is a public synthetic Shanghai coordinate, elevation 0 km.
        // Raw responses: validation/20261108-astronomy/jpl-references/
        // API: https://ssd-api.jpl.nasa.gov/doc/horizons.html
        let noon = sky("2026-11-08T04:00:00Z")
        near(noon.sun.altitudeDegrees, 41.961848)
        near(noon.sun.azimuthDegrees, 187.186415)
        precondition(noon.brightest == nil, "The daytime UI must not claim a visible brightest star")

        let full = sky("2026-11-24T14:53:00Z")
        let moon = full.moon!
        near(moon.altitudeDegrees, 78.693492)
        near(moon.azimuthDegrees, 118.250961)
        precondition(moon.illumination > 0.99 && abs(moon.phaseFraction - 0.5) < 0.001)
        precondition(moon.isAboveHorizon)

        let dawn = sky("2026-11-08T20:00:00Z")
        let jupiter = dawn.brightest!
        precondition(jupiter.id == "planet-jupiter" && jupiter.kind == .planet)
        near(jupiter.altitudeDegrees, 50.936070)
        near(jupiter.azimuthDegrees, 107.671235)
        near(jupiter.visualMagnitude, -2.047, tolerance: 0.2)

        // Same absolute instant, different written local dates, and requests
        // within one minute reuse exactly the same evaluated state.
        let utc = sky("2026-11-08T20:00:00Z")
        precondition(utc == sky("2026-11-09T04:00:00+08:00"))
        precondition(utc == sky("2026-11-08T12:00:00-08:00"))
        precondition(utc == sky("2026-11-08T20:00:59Z"))
        precondition(utc.evaluatedAt == date("2026-11-08T20:00:00Z"))
        let nextHour = sky("2026-11-08T21:00:00Z")
        precondition(abs(nextHour.sun.altitudeDegrees - utc.sun.altitudeDegrees) > 1)
        let otherCity = sky("2026-11-08T20:00:00Z", at: .init(latitude: -33.9, longitude: 151.2))
        precondition(abs(otherCity.sun.altitudeDegrees - utc.sun.altitudeDegrees) > 1,
                     "Changing city must invalidate the position cache")

        // Crossing the horizon does not clamp the Moon into view or emit a
        // bright point during daylight. Check both sides across two days.
        let start = date("2026-11-08T00:00:00Z")
        var moonAbove = false, moonBelow = false, sawStar = false, sawPlanet = false
        for hour in 0..<48 {
            let state = NightSkyAstronomy.sky(at: start + Double(hour) * 3600, coordinate: shanghai)!
            precondition((-90...90).contains(state.sun.altitudeDegrees))
            precondition((0..<360).contains(state.sun.azimuthDegrees))
            if let moon = state.moon {
                precondition((-90...90).contains(moon.altitudeDegrees) && (0..<360).contains(moon.azimuthDegrees))
                precondition((0..<1).contains(moon.phaseFraction) && (0...1).contains(moon.illumination))
                moonAbove = moonAbove || moon.isAboveHorizon
                moonBelow = moonBelow || !moon.isAboveHorizon
            }
            if let object = state.brightest {
                precondition(state.sun.altitudeDegrees < 0 && object.altitudeDegrees > 0)
                precondition((0..<360).contains(object.azimuthDegrees) && object.visualMagnitude.isFinite)
                precondition(object.id != "sun" && object.id != "moon")
                sawStar = sawStar || object.kind == .star
                sawPlanet = sawPlanet || object.kind == .planet
            } else {
                precondition(state.sun.altitudeDegrees >= 0, "The validated all-sky bright catalog supplies a nighttime candidate")
            }
        }
        precondition(moonAbove && moonBelow && sawStar && sawPlanet)

        // An invalid location/time is unknown, never a decorative fake marker.
        precondition(NightSkyAstronomy.sky(at: start, coordinate: .init(latitude: 100, longitude: 0)) == nil)
        precondition(NightSkyAstronomy.sky(at: start, coordinate: .init(latitude: .nan, longitude: 0)) == nil)
        precondition(NightSkyAstronomy.sky(at: Date(timeIntervalSince1970: .infinity), coordinate: shanghai) == nil)
        // Exceed the small cache and make sure recomputation remains identical.
        precondition(utc == sky("2026-11-08T20:00:00Z"))

        let dayStart = date("2026-11-07T16:00:00Z") // Shanghai midnight.
        let events = NightSkyAstronomy.sunEvents(dayStartingAt: dayStart, coordinate: shanghai)
        let sunrise = events.sunrise!, sunset = events.sunset!
        precondition(sunrise > dayStart && sunset > sunrise && sunset < dayStart + 86_400)
        precondition(NightSkyAstronomy.sky(at: sunrise - 1200, coordinate: shanghai)!.sun.altitudeDegrees < 0)
        precondition(NightSkyAstronomy.sky(at: sunrise + 1200, coordinate: shanghai)!.sun.altitudeDegrees > 0)
        precondition(NightSkyAstronomy.sky(at: sunset - 1200, coordinate: shanghai)!.sun.altitudeDegrees > 0)
        precondition(NightSkyAstronomy.sky(at: sunset + 1200, coordinate: shanghai)!.sun.altitudeDegrees < 0)
        print("NightSkyAstronomy passed: independent JPL Sun/Moon/Jupiter positions; planetary brightness; UTC/minute/city cache; 48h horizons and star/planet selection; invalid inputs.")
        print("JPL comparison: Sun alt \(noon.sun.altitudeDegrees), Moon alt \(moon.altitudeDegrees), Jupiter alt \(jupiter.altitudeDegrees).")
    }
}
