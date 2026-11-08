import Foundation

/// A screen-sideways projection of meteorological wind-from bearings. The slow
/// gust envelope is visual interpolation between the reported mean and peak,
/// not a second-by-second wind forecast. Unknown direction has no lateral bias.
struct WeatherPrecipitationWind {
    let directionKnown: Bool
    let horizontalFlow: Double
    let effectiveSpeed: Double
    let slope: Double

    init(direction: Double?, sustainedSpeed: Double?, gust: Double?, fallbackMagnitude: Double, elapsed: Double) {
        func nonnegative(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        let base = nonnegative(sustainedSpeed) ?? nonnegative(fallbackMagnitude) ?? 0
        let peak = max(base, nonnegative(gust) ?? base)
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        let envelope = 0.12 + 0.88 * pow((1 + sin(time * 0.43 - 0.8)) / 2, 2)
        effectiveSpeed = base + (peak - base) * envelope
        if let direction, direction.isFinite, (0...360).contains(direction) {
            directionKnown = true
            let flow = -sin(direction * .pi / 180)
            horizontalFlow = abs(flow) < 1e-8 ? 0 : flow
        } else {
            directionKnown = false
            horizontalFlow = 0
        }
        slope = horizontalFlow * min(0.70, effectiveSpeed / 90)
    }
}

struct WeatherPrecipitationLayers {
    let rain: WeatherSceneStrength?
    let snow: WeatherSceneStrength?

    init(profile: WeatherSceneProfile, mixed: Bool) {
        rain = profile.rain ?? (mixed ? .light : nil)
        snow = profile.snow ?? (mixed ? .light : nil)
    }
}

/// Visual calibration in logical points, not a meteorological classification.
/// WMO/profile selects the tier; the current model rate only makes a small
/// bounded adjustment inside that tier. Forecast probability is never used.
struct WeatherRainAppearance {
    static let referenceArea = 348.0 * 800.0
    let particleCount: Int
    let speed: ClosedRange<Double>
    let length: ClosedRange<Double>
    let lineWidth: ClosedRange<Double>
    let opacity: ClosedRange<Double>
    let curtainOpacity: Double
    let impactBudget: Int
    let impactPause: ClosedRange<Double>
    let isDrizzle: Bool
    let isShower: Bool
    let isIcy: Bool

    init(tier: WeatherSceneStrength, code: Int, rate: Double, width: Double, height: Double) {
        isDrizzle = [51, 53, 55, 56, 57].contains(code)
        isShower = [80, 81, 82].contains(code)
        isIcy = [56, 57, 66, 67].contains(code)
        let referenceCount: Double
        let minimumCount: Int
        let typicalRate: Double
        if isDrizzle {
            // Strong drizzle stays fine and slow; its density increases.
            referenceCount = code == 55 || code == 57 ? 78 : code == 53 ? 64 : 50
            minimumCount = 8
            typicalRate = 0.8
            speed = 95...165
            length = 3.5...7.5
            lineWidth = 0.32...0.55
            opacity = 0.13...0.25
            curtainOpacity = 0
            impactBudget = code == 55 || code == 57 ? 20 : 12
            impactPause = 0.8...2.0
        } else {
            switch tier {
            case .light:
                referenceCount = 46
                minimumCount = 8
                typicalRate = 1.2
                speed = 230...390
                length = 8...17
                lineWidth = 0.45...0.80
                opacity = 0.16...0.32
                curtainOpacity = 0
                impactBudget = 22
                impactPause = 0.45...1.4
            case .moderate:
                referenceCount = 108
                minimumCount = 12
                typicalRate = 3
                speed = 400...620
                length = 17...29
                lineWidth = 0.62...1.08
                opacity = 0.25...0.48
                curtainOpacity = 0
                impactBudget = 42
                impactPause = 0.18...0.75
            case .heavy:
                referenceCount = 168
                minimumCount = 20
                typicalRate = 10
                speed = 600...890
                length = 28...46
                lineWidth = 0.78...1.48
                opacity = 0.32...0.63
                curtainOpacity = 0.065
                impactBudget = 62
                impactPause = 0.06...0.40
            }
        }
        let safeRate = rate.isFinite ? max(0, rate) : 0
        let rateScale = 0.94 + 0.12 * min(1, log1p(safeRate) / log1p(typicalRate * 2))
        particleCount = Self.scaledCount(reference: referenceCount * rateScale, minimum: minimumCount,
                                        maximum: 220, width: width, height: height)
    }

    func showerEnvelope(at time: Double) -> Double {
        guard isShower, time.isFinite else { return 1 }
        return 0.55 + 0.45 * pow((1 + sin(time * 0.62)) / 2, 2)
    }

    static func scaledCount(reference: Double, minimum: Int, maximum: Int,
                            width: Double, height: Double) -> Int {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return 0 }
        let scale = min(2, (width / 348) * (height / 800))
        return min(maximum, max(minimum, Int((reference * scale).rounded())))
    }
}

struct WeatherSnowAppearance {
    let particleCount: Int
    let speed: ClosedRange<Double>
    let radius: ClosedRange<Double>
    let opacity: ClosedRange<Double>
    let isGrains: Bool
    let isShower: Bool

    init(tier: WeatherSceneStrength, code: Int, width: Double, height: Double) {
        isGrains = code == 77
        isShower = code == 85 || code == 86
        let reference: Double
        let minimum: Int
        if isGrains {
            reference = 42
            minimum = 7
            speed = 90...140
            radius = 0.55...1.05
            opacity = 0.35...0.65
        } else {
            switch tier {
            case .light:
                reference = 42
                minimum = 7
                speed = 20...58
                radius = 0.7...2.0
                opacity = 0.32...0.68
            case .moderate:
                reference = 80
                minimum = 10
                speed = 30...80
                radius = 0.9...2.4
                opacity = 0.38...0.74
            case .heavy:
                reference = 140
                minimum = 17
                speed = 48...110
                radius = 1...2.8
                opacity = 0.42...0.80
            }
        }
        particleCount = WeatherRainAppearance.scaledCount(reference: reference, minimum: minimum, maximum: 190,
                                                         width: width, height: height)
    }

    func showerEnvelope(at time: Double) -> Double {
        guard isShower, time.isFinite else { return 1 }
        return 0.55 + 0.45 * pow((1 + sin(time * 0.49)) / 2, 2)
    }
}
