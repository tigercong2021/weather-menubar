import Foundation

/// Date-based lunar appearance for a small decorative moon, not an ephemeris.
/// Uses absolute elapsed seconds: a city's time zone cannot change its phase.
/// Omitted latitude, parallax, nutation and TT−UTC corrections mean phase event
/// times and illuminated area are approximate; this does not predict visibility,
/// position, moonrise or eclipses. See validation/MoonPhaseChecks.swift for checks.
struct MoonPhase: Equatable, Sendable {
    /// Sun–Moon longitude separation as a cycle: new 0, first quarter .25,
    /// full .5, last quarter .75. Always in [0, 1) for a finite Date.
    let fraction: Double
    /// Approximate illuminated fraction of the visible disk, in [0, 1].
    let illumination: Double

    var isWaxing: Bool { fraction < 0.5 }

    /// Broad visual bins, not claims that a phase event occurs at this instant.
    var label: String {
        let names = ["新月", "蛾眉月", "上弦月", "盈凸月", "满月", "亏凸月", "下弦月", "残月"]
        return names[Int(floor(fraction * 8 + 0.5)) % 8]
    }

    init(at date: Date) {
        let seconds = date.timeIntervalSince1970
        precondition(seconds.isFinite, "MoonPhase requires a finite absolute Date")
        // J2000 is 2000-01-01 12:00 UTC (Unix day 10957.5). Using UTC in place
        // of ephemeris time is intentional for this approximate visual model.
        let days = seconds / 86_400 - 10_957.5
        let centuries = days / 36_525

        // Lunar ecliptic longitude, six leading periodic terms: D. G. Simpson,
        // NASA GSFC, "An Alternative Lunar Ephemeris Model", Eq. (1), p.176.
        // https://caps.gsfc.nasa.gov/simpson/pubs/slunar.pdf
        let moon = 218.32 + 481_267.883 * centuries
            + 6.29 * Self.sinDegrees(477_198.85 * centuries + 134.9)
            - 1.27 * Self.sinDegrees(-413_335.38 * centuries + 259.2)
            + 0.66 * Self.sinDegrees(890_534.23 * centuries + 235.7)
            + 0.21 * Self.sinDegrees(954_397.70 * centuries + 269.9)
            - 0.19 * Self.sinDegrees(35_999.05 * centuries + 357.5)
            - 0.11 * Self.sinDegrees(966_404.05 * centuries + 186.6)

        // USNO's approximate apparent solar ecliptic longitude.
        // https://aa.usno.navy.mil/faq/sun_approx
        let anomaly = 357.529 + 0.98560028 * days
        let meanLongitude = 280.459 + 0.98564736 * days
        let sun = meanLongitude + 1.915 * Self.sinDegrees(anomaly)
            + 0.020 * Self.sinDegrees(2 * anomaly)
        fraction = Self.normalizedDegrees(moon - sun) / 360
        illumination = min(1, max(0, (1 - cos(fraction * 2 * .pi)) / 2))
    }

    private static func sinDegrees(_ degrees: Double) -> Double {
        sin(normalizedDegrees(degrees) * .pi / 180)
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        let positive = remainder < 0 ? remainder + 360 : remainder
        // Avoid 360 if floating-point addition rounds a tiny negative to it.
        return positive < 360 ? positive : 0
    }
}
