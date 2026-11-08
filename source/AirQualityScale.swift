/// Display geometry only. US AQI values, health thresholds and category labels
/// remain unchanged. Historical frequency changes width, never health meaning.
struct AirQualityScale: Equatable, Sendable {
    static let boundaries = [0, 50, 100, 150, 200, 300, 500]
    static let gradeCount = boundaries.count - 1
    static let minimumGradeWidth = 0.06

    let gradeWidths: [Double]
    let colorStops: [ColorStop]

    /// The caller supplies six historical frequencies in health-category order.
    /// Positive counts or rounded fractions are normalized alike. A history
    /// coverage policy or prior belongs to the history provider, not this scale.
    /// Missing, malformed or empty history uses a neutral equal-width fallback.
    init(gradeFractions: [Double]? = nil) {
        let widths: [Double]
        if let fractions = gradeFractions,
           fractions.count == Self.gradeCount,
           fractions.allSatisfy({ $0.isFinite && $0 >= 0 }),
           let maximum = fractions.max(), maximum > 0 {
            // Scaling before summing also accepts finite, very large counts
            // without an overflow silently distorting the category widths.
            let scaled = fractions.map { $0 / maximum }
            let total = scaled.reduce(0, +)
            let distributable = 1 - Self.minimumGradeWidth * Double(Self.gradeCount)
            widths = scaled.map { Self.minimumGradeWidth + distributable * ($0 / total) }
        } else {
            widths = Array(repeating: 1 / Double(Self.gradeCount), count: Self.gradeCount)
        }
        gradeWidths = widths
        // All health boundaries and color anchors are multiples of five. Keeping
        // them in the sample set ensures no gradient interval straddles a change
        // of positional slope. Thus a given AQI retains the same interpolated
        // color for every history distribution, including between sample points.
        colorStops = stride(from: 0, through: 500, by: 5).map { value in
            let rgb = Self.color(at: Double(value))
            return ColorStop(red: rgb.0, green: rgb.1, blue: rgb.2,
                             location: Self.position(for: value, widths: widths))
        }
    }

    func position(for aqi: Int?) -> Double? {
        guard let aqi else { return nil }
        return Self.position(for: aqi, widths: gradeWidths)
    }

    struct ColorStop: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        let location: Double
    }

    private static func position(for aqi: Int, widths: [Double]) -> Double {
        if aqi <= 0 { return 0 }
        if aqi >= 500 { return 1 }
        var left = 0.0
        for grade in 0..<gradeCount {
            let lower = boundaries[grade]
            let upper = boundaries[grade + 1]
            if aqi <= upper {
                let fraction = Double(aqi - lower) / Double(upper - lower)
                return left + widths[grade] * fraction
            }
            left += widths[grade]
        }
        return 1
    }

    /// Reference colors are anchored to AQI, not to screen-space grade centers.
    /// Smoothstep blends continuously between distinct anchors without repeated
    /// flat-color stops. In particular AQI 75 is yellow regardless of history.
    private static func color(at value: Double) -> (Double, Double, Double) {
        let anchors: [(value: Double, rgb: (Double, Double, Double))] = [
            (0, (0.26, 0.82, 0.49)),
            (75, (0.95, 0.86, 0.29)),
            (125, (0.98, 0.62, 0.24)),
            (175, (0.95, 0.34, 0.35)),
            (250, (0.65, 0.33, 0.76)),
            (500, (0.37, 0.17, 0.58))
        ]
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where value <= upper.value {
            let t = min(1, max(0, (value - lower.value) / (upper.value - lower.value)))
            let blend = t * t * (3 - 2 * t)
            return (lower.rgb.0 + (upper.rgb.0 - lower.rgb.0) * blend,
                    lower.rgb.1 + (upper.rgb.1 - lower.rgb.1) * blend,
                    lower.rgb.2 + (upper.rgb.2 - lower.rgb.2) * blend)
        }
        return anchors[anchors.count - 1].rgb
    }
}
