import Foundation

@main
enum PrecipitationAppearanceChecks {
    static func main() {
        func rain(_ code: Int, _ rate: Double, width: Double = 348, height: Double = 800) -> WeatherRainAppearance {
            let profile = WeatherSceneProfile(code: code, intensity: rate)
            return WeatherRainAppearance(tier: profile.rain!, code: code, rate: profile.rainRate,
                                          width: width, height: height)
        }
        let light = rain(61, 1.2), moderate = rain(63, 3), heavy = rain(65, 10)
        precondition((40...55).contains(light.particleCount))
        precondition((90...120).contains(moderate.particleCount))
        precondition((150...180).contains(heavy.particleCount))
        precondition(moderate.particleCount > light.particleCount * 2)
        precondition(heavy.particleCount > moderate.particleCount * 3 / 2)
        precondition(light.speed.upperBound < moderate.speed.lowerBound)
        precondition(moderate.speed.upperBound < heavy.speed.upperBound)
        precondition(light.length.upperBound <= moderate.length.lowerBound)
        precondition(moderate.length.upperBound < heavy.length.upperBound)
        precondition(light.opacity.upperBound < moderate.opacity.upperBound && moderate.opacity.upperBound < heavy.opacity.upperBound)
        precondition(light.curtainOpacity == 0 && moderate.curtainOpacity == 0 && heavy.curtainOpacity > 0)
        precondition(light.impactBudget < moderate.impactBudget && moderate.impactBudget < heavy.impactBudget)
        precondition(light.impactPause.upperBound > moderate.impactPause.upperBound && moderate.impactPause.upperBound > heavy.impactPause.upperBound)

        for code in [61, 63, 65] {
            let minimum = rain(code, 0), maximum = rain(code, 500)
            precondition(Double(maximum.particleCount) / Double(minimum.particleCount) < 1.16,
                         "Rate must only tune within the WMO tier")
            let compact = rain(code, 3, height: 96)
            let full = rain(code, 3)
            precondition(compact.particleCount < full.particleCount / 5,
                         "Compact cards must not use full-page particle counts")
            precondition(compact.speed == full.speed && compact.length == full.length,
                         "Particles keep physical point-size and speed across viewports")
        }
        precondition(rain(61, 500).particleCount < rain(63, 0).particleCount)
        precondition(rain(63, 500).particleCount < rain(65, 0).particleCount)
        precondition(rain(63, .nan).particleCount == rain(63, 0).particleCount)
        precondition(rain(63, 3, width: 0).particleCount == 0)
        precondition(rain(63, 3, width: .infinity).particleCount == 0)

        let drizzles = [51, 53, 55].map { rain($0, 0.8) }
        precondition(drizzles[0].particleCount < drizzles[1].particleCount && drizzles[1].particleCount < drizzles[2].particleCount)
        precondition(drizzles.allSatisfy { $0.isDrizzle && $0.length.upperBound < light.length.lowerBound && $0.speed.upperBound < light.speed.lowerBound })
        for code in [56, 57] {
            let icyDrizzle = rain(code, 0.8)
            precondition(icyDrizzle.isDrizzle && icyDrizzle.isIcy && icyDrizzle.length.upperBound < light.length.lowerBound)
        }
        for code in [66, 67] { precondition(rain(code, 3).isIcy && !rain(code, 3).isDrizzle) }
        for code in [80, 81, 82] {
            let shower = rain(code, 3)
            let values = (0...100).map { shower.showerEnvelope(at: Double($0) / 10) }
            precondition(shower.isShower && values.min()! < 0.60 && values.max()! > 0.99)
        }
        precondition(moderate.showerEnvelope(at: 0) == 1 && moderate.showerEnvelope(at: 5) == 1)

        func snow(_ code: Int, height: Double = 800) -> WeatherSnowAppearance {
            let profile = WeatherSceneProfile(code: code, intensity: 1)
            return WeatherSnowAppearance(tier: profile.snow!, code: code, width: 348, height: height)
        }
        let snowLight = snow(71), snowMedium = snow(73), snowHeavy = snow(75)
        precondition(snowLight.particleCount < snowMedium.particleCount && snowMedium.particleCount < snowHeavy.particleCount)
        precondition(snow(75, height: 96).particleCount < snowHeavy.particleCount / 5)
        precondition(snow(77).isGrains && snow(77).radius.upperBound < snowLight.radius.upperBound)
        for code in [85, 86] {
            let shower = snow(code)
            let values = (0...140).map { shower.showerEnvelope(at: Double($0) / 10) }
            precondition(shower.isShower && values.min()! < 0.60 && values.max()! > 0.99)
        }
        for code in [61, 71, 73, 75] {
            let layers = WeatherPrecipitationLayers(profile: WeatherSceneProfile(code: code, intensity: 1), mixed: true)
            precondition(layers.rain != nil && layers.snow != nil, "Mixed precipitation must include both layers regardless of primary code")
        }
        let clear = WeatherPrecipitationLayers(profile: WeatherSceneProfile(code: 0, intensity: 0), mixed: false)
        precondition(clear.rain == nil && clear.snow == nil)
        func wind(_ bearing: Double?, speed: Double = 18, gust: Double? = 45, time: Double = 4) -> WeatherPrecipitationWind {
            WeatherPrecipitationWind(direction: bearing, sustainedSpeed: speed, gust: gust,
                                     fallbackMagnitude: 45, elapsed: time)
        }
        precondition(wind(0).slope == 0 && wind(180).slope == 0 && wind(360).slope == 0)
        precondition(wind(90).slope < 0 && wind(270).slope > 0, "Wind-from east moves rain left; wind-from west moves it right")
        precondition(abs(wind(90).slope + wind(270).slope) < 1e-9)
        for bearing: Double? in [nil, .nan, .infinity, -1, 361] {
            precondition(!wind(bearing).directionKnown && wind(bearing).slope == 0,
                         "Unknown wind must not invent a lateral direction")
        }
        let gusts = (0...100).map { wind(270, time: Double($0) / 5) }
        precondition(gusts.allSatisfy { (18...45).contains($0.effectiveSpeed) && (0...0.70).contains($0.slope) })
        precondition(gusts.map(\.effectiveSpeed).max()! - gusts.map(\.effectiveSpeed).min()! > 20)
        precondition(wind(270, speed: 10, gust: 5).effectiveSpeed == 10)
        precondition(wind(270, speed: 900, gust: 1000).slope == 0.70)
        let backgroundWind = wind(90, time: 3.5), impactWind = wind(90, time: 3.5)
        precondition(backgroundWind.slope == impactWind.slope, "Both render layers share the same wind projection")
        print("PASS: distinct rain tiers, bounded rate tuning, full/compact density, drizzle/freezing drizzle, shower cadence, snow/grains, and both mixed-precipitation directions")
        print("PASS: four wind bearings, unknown-direction fallback, bounded visual gust interpolation, and shared background/impact slope")
        for (name, code, rate) in [("毛毛雨", 51, 0.3), ("小雨", 61, 1.2), ("中雨", 63, 3.0), ("大雨", 65, 10.0)] {
            let full = rain(code, rate), compact = rain(code, rate, height: 96)
            print("\(name): full=\(full.particleCount), compact=\(compact.particleCount), speed=\(full.speed), length=\(full.length), opacity=\(full.opacity), impactBudget=\(full.impactBudget)")
        }
    }
}
