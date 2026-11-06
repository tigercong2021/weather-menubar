import SwiftUI

enum WeatherSceneSpecial: Equatable, Sendable {
    case haze
    case mixedPrecipitation
}

struct WeatherScene: View {
    @ObservedObject var motion: WeatherMotion
    @Environment(\.colorScheme) private var colorScheme
    let code: Int
    let isDay: Bool?
    let intensity: Double
    var gust: Double? = nil
    var cycloneDemo = false
    var windSpeed: Double? = nil
    var windDirection: Double? = nil
    var daylightProgress: Double? = nil
    var special: WeatherSceneSpecial? = nil

    var body: some View {
        let kind = WeatherKind(code: code)
        let palette = ScenePalette(day: isDay != false, dark: colorScheme == .dark)
        let cycle = CGFloat(motion.sceneCycle)
        let elapsed = CGFloat(motion.sceneElapsed)
        let profile = WeatherSceneProfile(
            code: cycloneDemo ? 65 : code,
            intensity: cycloneDemo ? 8 : intensity,
            windSpeed: windSpeed,
            gust: cycloneDemo ? max(gust ?? 0, 92) : gust,
            windDirection: windDirection
        )
        let solar = daylightProgress.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let scene = Scene(context: context, size: size, palette: palette, cycle: cycle, elapsed: elapsed)
            if kind != .unknown || cycloneDemo || special != nil { scene.horizon() }
            if cycloneDemo {
                scene.clouds(cover: 1, storm: true)
                scene.cyclone()
                scene.rain(tier: .heavy, icy: false, profile: profile)
                scene.wind(tier: .heavy, profile: profile)
                return
            }
            if let special {
                switch special {
                case .haze:
                    scene.haze()
                case .mixedPrecipitation:
                    scene.clouds(cover: 0.72)
                    scene.rain(tier: .light, icy: false, profile: profile)
                    scene.snow(tier: .light, profile: profile, mode: .mixed)
                }
                return
            }
            switch kind {
            case .clear:
                scene.light(solar: solar)
            case .mostlyClear, .partlyCloudy:
                scene.light(clouded: true, solar: solar)
                scene.clouds(cover: kind == .mostlyClear ? 0.46 : 0.68)
            case .overcast:
                scene.clouds(cover: 1)
            case .fog:
                scene.fog(frosted: code == 48)
            case .drizzle, .rain, .freezingRain, .showers, .thunder:
                scene.clouds(cover: kind == .showers ? 0.62 : 0.88, storm: profile.lightning || profile.rain == .heavy)
                if let rain = profile.rain {
                    let icyDrizzle = code == 56 || code == 57
                    scene.rain(tier: rain, icy: kind == .freezingRain,
                               drizzle: kind == .drizzle || icyDrizzle, shower: kind == .showers, profile: profile)
                    if kind == .freezingRain { scene.iceGlints(count: icyDrizzle ? 6 : 10) }
                }
                if let hail = profile.hail { scene.hail(tier: hail, profile: profile) }
                if profile.lightning { scene.lightning() }
            case .snow, .snowShowers:
                scene.clouds(cover: profile.snow == .heavy ? 0.83 : 0.51)
                if let snow = profile.snow {
                    scene.snow(tier: snow, profile: profile,
                               mode: code == 77 ? .grains : kind == .snowShowers ? .shower : .steady)
                }
            case .unknown:
                break
            }
            if let wind = profile.wind, kind != .unknown { scene.wind(tier: wind, profile: profile) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScenePalette {
    let day: Bool
    let dark: Bool

    var light: Color {
        day ? Color(red: 0.98, green: 0.62, blue: 0.24) : Color(red: 0.50, green: 0.61, blue: 0.96)
    }
    var cloud: Color {
        if dark { return Color(red: 0.55, green: 0.67, blue: 0.88) }
        return day ? Color(red: 0.27, green: 0.44, blue: 0.61) : Color(red: 0.34, green: 0.40, blue: 0.69)
    }
    var rain: Color {
        dark ? Color(red: 0.61, green: 0.79, blue: 1) : Color(red: 0.20, green: 0.44, blue: 0.71)
    }
    var ice: Color {
        dark ? Color(red: 0.85, green: 0.94, blue: 1) : Color(red: 0.36, green: 0.62, blue: 0.79)
    }
    var horizon: Color {
        dark ? Color(red: 0.60, green: 0.73, blue: 0.95) : Color(red: 0.96, green: 0.99, blue: 1)
    }
    var shadow: Color {
        dark ? Color(red: 0.08, green: 0.13, blue: 0.24) : Color(red: 0.21, green: 0.32, blue: 0.46)
    }
    var wind: Color {
        dark ? Color(red: 0.78, green: 0.90, blue: 1) : Color(red: 0.17, green: 0.45, blue: 0.53)
    }
}

private struct Scene {
    enum SnowMode { case steady, shower, grains, mixed }

    let context: GraphicsContext
    let size: CGSize
    let palette: ScenePalette
    let cycle: CGFloat
    let elapsed: CGFloat

    private var width: CGFloat { size.width }
    private var height: CGFloat { size.height }
    private var angle: CGFloat { 2 * .pi * cycle }

    // The layer order, drift periods, and crest rhythms follow the temps design.
    // The rounded card uses its own path, night palette, and clipping.
    func horizon() {
        let depth = min(35, height * 0.25)
        let driftPeriods: [CGFloat] = [50, 34, 22]
        let morphPeriods: [CGFloat] = [11, 9, 7]
        let strengths: [Double] = [0.30, 0.45, 1]
        for layer in driftPeriods.indices {
            let direction: CGFloat = layer == 0 ? -1 : 1
            let phase = 2 * .pi * direction * wrap(elapsed / driftPeriods[layer])
            let morph = 2 * .pi * wrap(elapsed / morphPeriods[layer])
            let top = height - depth * (1 - CGFloat(layer) * 0.26)
            let amplitude = depth * (0.10 + 0.055 * sin(morph))
            var wave = Path()
            for point in 0...24 {
                let fraction = CGFloat(point) / 24
                let wavePosition = fraction * 3 * .pi + phase + CGFloat(layer) * 1.7
                let y = top + amplitude * (sin(wavePosition) + 0.24 * sin(2 * wavePosition + morph))
                let position = CGPoint(x: width * fraction, y: y)
                if point == 0 { wave.move(to: position) } else { wave.addLine(to: position) }
            }
            wave.addLine(to: CGPoint(x: width, y: height))
            wave.addLine(to: CGPoint(x: 0, y: height))
            wave.closeSubpath()
            let ink = palette.horizon.opacity(strengths[layer] * (palette.dark ? 0.20 : 0.42))
            context.fill(wave, with: .linearGradient(Gradient(colors: [ink.opacity(0), ink]),
                                                      startPoint: CGPoint(x: 0, y: top - amplitude),
                                                      endPoint: CGPoint(x: 0, y: height)))
        }
    }

    func light(clouded: Bool = false, solar: Double?) {
        let sunPosition = CGFloat(solar ?? 0.72)
        let lightX = palette.day ? lerp(0.16, 0.86, sunPosition) : 0.79
        let lightY = palette.day ? 0.36 - 0.23 * sin(.pi * sunPosition) : 0.29
        let center = CGPoint(x: width * lightX + 3 * sin(angle), y: height * lightY + 1.4 * cos(angle))
        let radius = min(width * 0.53, height * 1.25)
        glow(palette.light, at: center, radius: radius, opacity: clouded ? 0.23 : 0.40)
        glow(palette.horizon, at: center, radius: radius * 0.40, opacity: palette.day ? 0.45 : 0.15)
        if palette.day {
            let strength = clouded ? 0.10 : 0.17
            for ray in 0..<7 {
                let bearing = CGFloat(ray) * (2 * .pi / 7) + 0.04 * sin(angle)
                let direction = CGPoint(x: cos(bearing), y: sin(bearing))
                let start = radius * 0.40
                let end = radius * (0.62 + 0.10 * sin(angle + CGFloat(ray)))
                stroke(
                    from: CGPoint(x: center.x + start * direction.x, y: center.y + start * direction.y),
                    to: CGPoint(x: center.x + end * direction.x, y: center.y + end * direction.y),
                    color: palette.light.opacity(strength * visibility(at: center.x)), width: 1.2
                )
            }
        } else if !clouded {
            let stars: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [(0.09, 0.14, 3), (0.80, 0.10, 2.3), (0.86, 0.24, 3.2)]
            for (index, star) in stars.enumerated() {
                let x = width * star.x
                let y = height * star.y
                let p = wrap((elapsed + 3 - CGFloat(index) * 0.9) / 3)
                let twinkle = 0.25 + 0.75 * (1 + cos(2 * .pi * p)) / 2
                let ink = Color(red: 0.96, green: 0.89, blue: 0.73).opacity(twinkle * 0.76)
                var sparkle = Path()
                let r = star.radius
                sparkle.move(to: CGPoint(x: x, y: y - r))
                sparkle.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + 0.4, y: y - 0.4))
                sparkle.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x + 0.4, y: y + 0.4))
                sparkle.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - 0.4, y: y + 0.4))
                sparkle.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x - 0.4, y: y - 0.4))
                sparkle.closeSubpath()
                context.fill(sparkle, with: .color(ink))
            }
        }
    }

    func clouds(cover: Double, storm: Bool = false) {
        for index in 0..<4 {
            let drift = sin(elapsed * 0.20 + CGFloat(index) * 0.62)
            let x = width * (0.12 + 0.29 * CGFloat(index)) + 8 * drift
            let y = height * (0.06 + 0.10 * CGFloat(index % 2)) + 2 * cos(elapsed * 0.27 + CGFloat(index))
            let radius = min(width * 0.40, height * 0.86)
            let opacity = cover * (0.19 + 0.16 * visibility(at: x))
            glow(palette.cloud, at: CGPoint(x: x, y: y), radius: radius,
                 opacity: opacity, verticalScale: 0.42 + 0.08 * CGFloat(index % 3))
        }
        let floor = height * (storm ? 0.46 : 0.34)
        let drift = width * 0.07 * sin(elapsed * (storm ? 0.37 : 0.23))
        var bank = Path()
        bank.move(to: CGPoint(x: -width * 0.2, y: 0))
        bank.addLine(to: CGPoint(x: width * 1.2, y: 0))
        bank.addLine(to: CGPoint(x: width * 1.2, y: floor * 0.66))
        bank.addCurve(to: CGPoint(x: width * 0.62 + drift, y: floor),
                      control1: CGPoint(x: width * 0.98, y: floor * 0.92),
                      control2: CGPoint(x: width * 0.84 + drift, y: floor * 0.68))
        bank.addCurve(to: CGPoint(x: width * 0.20 + drift, y: floor * 0.60),
                      control1: CGPoint(x: width * 0.44 + drift, y: floor * 1.22),
                      control2: CGPoint(x: width * 0.38 + drift, y: floor * 0.52))
        bank.addQuadCurve(to: CGPoint(x: -width * 0.2, y: floor * 0.60),
                          control: CGPoint(x: width * 0.06, y: floor * 0.68))
        bank.closeSubpath()
        let shadow = palette.shadow.opacity(cover * (storm ? 0.46 : 0.19))
        context.fill(bank, with: .linearGradient(Gradient(colors: [shadow, shadow.opacity(0)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: floor)))
    }

    func fog(frosted: Bool) {
        for index in 0..<5 {
            let drift = sin(angle + 0.64 * CGFloat(index))
            let x = width * (0.23 + 0.24 * CGFloat(index % 4)) + 15 * drift
            let y = height * (0.22 + 0.13 * CGFloat(index)) + 2 * cos(angle + CGFloat(index))
            let mist = frosted ? Color(red: 0.67, green: 0.83, blue: 0.97) : palette.ice
            glow(mist, at: CGPoint(x: x, y: y), radius: width * 0.48,
                 opacity: 0.22 + 0.12 * visibility(at: x), verticalScale: 0.13)
        }
        if frosted {
            let ice = palette.ice.opacity(palette.dark ? 0.48 : 0.37)
            for index in 0..<11 {
                let x = width * (index.isMultiple(of: 2) ? 0.015 + 0.10 * seed(index, 51) : 0.89 + 0.095 * seed(index, 51))
                let y = height * (0.28 + 0.62 * seed(index, 52))
                let size = 0.55 + 1.1 * seed(index, 53)
                stroke(from: CGPoint(x: x - size, y: y), to: CGPoint(x: x + size, y: y), color: ice, width: 0.65)
                stroke(from: CGPoint(x: x, y: y - size), to: CGPoint(x: x, y: y + size), color: ice, width: 0.65)
            }
        }
    }

    func haze() {
        let dust = palette.dark ? Color(red: 0.80, green: 0.58, blue: 0.36) : Color(red: 0.62, green: 0.37, blue: 0.19)
        for layer in 0..<3 {
            let center = CGPoint(x: width * (0.15 + 0.34 * CGFloat(layer)) + 11 * sin(elapsed * 0.15 + CGFloat(layer)),
                                 y: height * (0.39 + 0.19 * CGFloat(layer)))
            glow(dust, at: center, radius: width * 0.62, opacity: 0.28, verticalScale: 0.29)
        }
        for index in 0..<22 {
            let x = width * seed(index, 61) + 7 * sin(elapsed * 0.20 + CGFloat(index))
            let y = height * (0.20 + 0.58 * seed(index, 62)) + 2 * cos(elapsed * 0.12 + CGFloat(index))
            let depth = seed(index, 63)
            dot(at: CGPoint(x: x, y: y), radius: 0.45 + 0.60 * depth, color: dust.opacity(0.22 + 0.26 * depth))
        }
    }

    func iceGlints(count: Int) {
        let ink = palette.ice
        for index in 0..<count {
            let x = width * (index.isMultiple(of: 2) ? 0.035 + 0.105 * seed(index, 64) : 0.86 + 0.105 * seed(index, 64))
            let y = height * (0.56 + 0.36 * seed(index, 65))
            let radius = 0.65 + 0.88 * seed(index, 66)
            let glint = ink.opacity(0.34 + 0.23 * (1 + sin(elapsed * 0.78 + CGFloat(index))) / 2)
            stroke(from: CGPoint(x: x - radius, y: y), to: CGPoint(x: x + radius, y: y), color: glint, width: 0.65)
            stroke(from: CGPoint(x: x, y: y - radius), to: CGPoint(x: x, y: y + radius), color: glint, width: 0.65)
        }
    }

    func rain(tier: WeatherSceneStrength, icy: Bool, drizzle: Bool = false, shower: Bool = false,
              profile: WeatherSceneProfile) {
        let ink = icy ? palette.ice : (palette.dark ? Color.white : palette.rain)
        let crosswind = CGFloat(profile.flowX) * CGFloat(min(1, profile.windMagnitude / 64))
        let burst = shower ? showerOpacity(period: 7.6) : 1
        let layers: [(count: Int, length: CGFloat, duration: CGFloat, opacity: Double, width: CGFloat)]
        switch tier {
        case .light:
            layers = [(13, 0.038, 1.55, 0.31, 0.55), (8, 0.075, 1.22, 0.53, 0.74)]
        case .moderate:
            layers = [(23, 0.065, 1.18, 0.35, 0.60), (19, 0.125, 0.90, 0.66, 0.92)]
        case .heavy:
            layers = [(37, 0.112, 0.93, 0.50, 0.73), (27, 0.235, 0.58, 0.81, 1.34)]
            rainCurtain(flow: crosswind, opacity: burst)
        }
        let rate = sqrt(min(20, profile.rainRate) / 20)
        let lengthFactor = drizzle ? 0.57 : 1.0
        let opacityFactor = (drizzle ? 0.70 : 0.88 + 0.12 * rate) * burst
        for (layer, configuration) in layers.enumerated() {
            for particle in 0..<configuration.count {
                let index = particle + layer * 64
                let duration = configuration.duration * (0.76 + 0.54 * seed(index, 13)) * (drizzle ? 1.19 : 1)
                let progress = precipitationProgress(index, salt: 12, duration: duration)
                let length = height * configuration.length * lengthFactor * (0.62 + 0.76 * seed(index, 14))
                let x = width * seed(index, 11) + crosswind * 42 * progress
                let startY = -max(height * 0.14, length)
                let y = lerp(startY, height, progress)
                let tail = CGPoint(x: x, y: y)
                let tip = CGPoint(x: x + crosswind * 0.47 * length, y: y + length)
                let opacity = configuration.opacity * opacityFactor * (0.38 + 0.62 * seed(index, 15)) * edgeOpacity(y: tip.y)
                guard opacity > 0 else { continue }
                var streak = Path()
                streak.move(to: tail)
                streak.addLine(to: tip)
                let fade = Gradient(colors: [ink.opacity(0), ink.opacity(opacity)])
                context.stroke(streak, with: .linearGradient(fade, startPoint: tail, endPoint: tip),
                               style: StrokeStyle(lineWidth: configuration.width * (drizzle ? 0.72 : 1), lineCap: .round))
            }
        }
    }

    private func rainCurtain(flow: CGFloat, opacity: Double) {
        let ink = palette.shadow
        for index in 0..<3 {
            let phase = elapsed * (0.57 + 0.24 * CGFloat(index)) + CGFloat(index) * 2
            let x = width * (0.20 + 0.30 * CGFloat(index)) + width * 0.13 * sin(phase)
            let center = CGPoint(x: x + flow * 18, y: height * 0.53)
            let radius = min(width * 0.18, 48)
            glow(ink, at: center, radius: radius, opacity: (0.11 + 0.04 * Double(index)) * opacity, verticalScale: 2.4)
        }
    }

    func wind(tier: WeatherSceneStrength, profile: WeatherSceneProfile) {
        let configuration: (count: Int, length: CGFloat, duration: CGFloat, opacity: Double, width: CGFloat)
        switch tier {
        case .light: configuration = (4, 0.17, 3.35, 0.34, 1.0)
        case .moderate: configuration = (7, 0.36, 2.60, 0.61, 1.85)
        case .heavy: configuration = (10, 0.48, 1.96, 0.78, 2.30)
        }
        let east = CGFloat(profile.flowX)
        let south = CGFloat(profile.flowY)
        let alongSpan = abs(width * east) + abs(height * south)
        let crossSpan = abs(width * south) + abs(height * east)
        func point(along: CGFloat, across: CGFloat) -> CGPoint {
            CGPoint(x: width / 2 + east * along - south * across,
                    y: height / 2 + south * along + east * across)
        }
        for index in 0..<configuration.count {
            let depth = seed(index, 33)
            let phase = wrap(elapsed / (configuration.duration * (0.78 + 0.48 * depth)) + seed(index, 31))
            let distance = alongSpan * (1.55 * phase - 0.87)
            let lane = crossSpan * (0.72 * seed(index, 32) - 0.36) + 3 * sin(elapsed + CGFloat(index))
            let length = alongSpan * configuration.length * (0.60 + 0.70 * depth)
            let end = point(along: distance + length, across: lane - 5)
            let start = point(along: distance, across: lane)
            var trail = Path()
            trail.move(to: start)
            trail.addCurve(to: end,
                           control1: point(along: distance + length * 0.28, across: lane - 10),
                           control2: point(along: distance + length * 0.70, across: lane + 7))
            let opacity = configuration.opacity * sin(.pi * phase) * (0.58 + 0.42 * depth)
            let ink = palette.wind.opacity(opacity)
            context.stroke(trail, with: .linearGradient(Gradient(colors: [ink.opacity(0), ink, ink.opacity(0)]),
                                                        startPoint: start, endPoint: end),
                           style: StrokeStyle(lineWidth: configuration.width * (0.68 + 0.32 * depth), lineCap: .round))
        }
    }

    func cyclone() {
        let center = CGPoint(x: width * 0.73, y: height * 0.50)
        let radius = min(width * 0.39, height * 0.98)
        glow(palette.cloud, at: center, radius: radius, opacity: 0.41, verticalScale: 0.77)
        for arm in 0..<4 {
            var band = Path()
            let bearing = CGFloat(arm) * .pi / 2 + angle / 4
            for index in 0...26 {
                let progress = CGFloat(index) / 26
                let orbit = radius * (0.13 + 0.94 * progress)
                let turn = bearing + 3.55 * progress
                let point = CGPoint(x: center.x + cos(turn) * orbit, y: center.y + sin(turn) * orbit * 0.72)
                if index == 0 { band.move(to: point) } else { band.addLine(to: point) }
            }
            let bandGradient = Gradient(colors: [palette.ice.opacity(0.62), palette.ice.opacity(0.25), palette.ice.opacity(0)])
            context.stroke(band, with: .radialGradient(bandGradient, center: center, startRadius: 0, endRadius: radius),
                           style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
        }
        let eye = CGRect(x: center.x - 5.6, y: center.y - 4.0, width: 11.2, height: 8)
        context.stroke(Path(ellipseIn: eye), with: .color(palette.ice.opacity(0.66)), lineWidth: 1.1)
    }

    func snow(tier: WeatherSceneStrength, profile: WeatherSceneProfile, mode: SnowMode = .steady) {
        let drift: [CGFloat] = [0, 10, -6, 8, 0]
        let drop: [CGFloat] = [0, 0.28, 0.55, 0.82, 1.10]
        let ink = palette.dark ? Color.white : palette.ice
        let configuration: (count: Int, fall: CGFloat, range: CGFloat, radius: CGFloat, opacity: Double)
        switch (tier, mode) {
        case (_, .grains): configuration = (33, 5.5, 3.1, 0.48, 0.63)
        case (_, .mixed): configuration = (11, 5.6, 4.5, 1.01, 0.69)
        case (.light, _): configuration = (22, 7, 5, 0.83, 0.54)
        case (.moderate, _): configuration = (36, 5, 6, 1.21, 0.67)
        case (.heavy, _): configuration = (58, 3.3, 4.1, 1.52, 0.82)
        }
        let crosswind = CGFloat(profile.flowX) * CGFloat(min(1, profile.windMagnitude / 62))
        let burst = mode == .shower ? showerOpacity(period: 9.5) : 1
        for index in 0..<configuration.count {
            let depth = seed(index, 23)
            let duration = configuration.fall + configuration.range * (1 - depth)
            let progress = precipitationProgress(index, salt: 22, duration: duration)
            let piece = progress * 4
            let segment = min(3, Int(piece))
            let offset = piece - CGFloat(segment)
            let x = width * seed(index, 21) + lerp(drift[segment], drift[segment + 1], offset)
                + crosswind * width * 0.18 * progress
            let y = height * (-0.06 + lerp(drop[segment], drop[segment + 1], offset))
            let radius = configuration.radius * (0.58 + 0.92 * depth)
            let opacity = configuration.opacity * burst * (0.36 + 0.64 * depth) * edgeOpacity(y: y)
            let center = CGPoint(x: x, y: y)
            if depth > 0.85, tier == .heavy {
                dot(at: center, radius: radius * 1.8, color: ink.opacity(opacity * 0.14))
            }
            dot(at: center, radius: radius, color: ink.opacity(opacity))
        }
    }

    func hail(tier: WeatherSceneStrength, profile: WeatherSceneProfile) {
        let count = tier == .heavy ? 23 : 14
        let crosswind = CGFloat(profile.flowX) * CGFloat(min(1, profile.windMagnitude / 54))
        let ink = palette.dark ? Color.white : palette.ice
        for index in 0..<count {
            let depth = seed(index, 41)
            let duration = 0.55 + 0.57 * (1 - depth)
            let progress = precipitationProgress(index, salt: 42, duration: duration)
            let y = height * (-0.05 + 1.05 * progress)
            let x = width * seed(index, 43) + crosswind * 52 * progress
            let radius = (0.80 + 1.45 * depth) * (tier == .heavy ? 1.27 : 1)
            let center = CGPoint(x: x, y: y)
            let opacity = (0.49 + 0.40 * depth) * edgeOpacity(y: y)
            var pellet = Path()
            pellet.move(to: CGPoint(x: x, y: y - radius))
            pellet.addLine(to: CGPoint(x: x + radius, y: y + 0.14 * radius))
            pellet.addLine(to: CGPoint(x: x + 0.14 * radius, y: y + radius))
            pellet.addLine(to: CGPoint(x: x - radius, y: y))
            pellet.closeSubpath()
            context.fill(pellet, with: .color(ink.opacity(opacity)))
            dot(at: center, radius: radius * 0.35, color: Color.white.opacity(opacity * 0.80))
        }
    }

    func lightning() {
        let moment = elapsed.truncatingRemainder(dividingBy: 41)
        let flashes: [CGFloat] = [0.66, 9.30, 20.10, 32.90]
        let crest = flashes.map { onset -> CGFloat in
            let age = moment - onset
            guard age >= 0, age < 0.32 else { return 0 }
            return age <= 0.10 ? min(1, age / 0.065) : pow((0.32 - age) / 0.22, 2)
        }.max() ?? 0
        let x = width * 0.84
        let y = height * 0.11
        let reach = height * 0.43
        let boltColor = palette.dark ? Color(red: 0.73, green: 0.73, blue: 1)
            : Color(red: 0.34, green: 0.29, blue: 0.64)
        let glowColor = Color(red: 0.63, green: 0.68, blue: 0.99)
        glow(glowColor, at: CGPoint(x: x - 5, y: y + reach * 0.45), radius: height * 0.52,
             opacity: 0.035 + 0.26 * crest, verticalScale: 0.94)
        var bolt = Path()
        bolt.move(to: CGPoint(x: x + 12, y: y))
        bolt.addLine(to: CGPoint(x: x + 2, y: y + reach * 0.30))
        bolt.addLine(to: CGPoint(x: x + 8, y: y + reach * 0.27))
        bolt.addLine(to: CGPoint(x: x - 9, y: y + reach * 0.67))
        bolt.addLine(to: CGPoint(x: x - 4, y: y + reach * 0.62))
        bolt.addLine(to: CGPoint(x: x - 18, y: y + reach))
        bolt.move(to: CGPoint(x: x - 7, y: y + reach * 0.62))
        bolt.addLine(to: CGPoint(x: x + 4, y: y + reach * 0.75))
        bolt.addLine(to: CGPoint(x: x + 2, y: y + reach * 0.89))
        context.stroke(bolt, with: .color(glowColor.opacity(0.04 + 0.29 * crest)),
                       style: StrokeStyle(lineWidth: 5.2, lineCap: .round, lineJoin: .round))
        context.stroke(bolt, with: .color(boltColor.opacity(0.23 + 0.61 * crest)),
                       style: StrokeStyle(lineWidth: 1.45 + 0.65 * crest, lineCap: .round, lineJoin: .round))
        if crest > 0 {
            context.stroke(bolt, with: .color(Color.white.opacity(0.82 * crest)),
                           style: StrokeStyle(lineWidth: 0.70, lineCap: .round, lineJoin: .round))
        }
    }

    private func precipitationProgress(_ index: Int, salt: Int, duration: CGFloat) -> CGFloat {
        // Start with the staggered particles already active on opening the panel.
        wrap((elapsed + 4 - 4 * seed(index, salt)) / duration)
    }

    private func showerOpacity(period: CGFloat) -> Double {
        let phase = wrap(elapsed / period + 0.15)
        let swell = pow((1 + cos(2 * .pi * phase)) / 2, 2.4)
        return 0.32 + 0.68 * Double(swell)
    }

    private func edgeOpacity(y: CGFloat) -> Double {
        Double(min(1, max(0, (height - y) / (height * 0.22))))
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ amount: CGFloat) -> CGFloat {
        from + (to - from) * amount
    }

    private func glow(_ color: Color, at center: CGPoint, radius: CGFloat, opacity: Double, verticalScale: CGFloat = 1) {
        var shading = context
        shading.translateBy(x: center.x, y: center.y)
        shading.scaleBy(x: 1, y: verticalScale)
        let bounds = CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius)
        shading.fill(Path(ellipseIn: bounds), with: .radialGradient(
            Gradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.61), color.opacity(0)]),
            center: .zero, startRadius: 0, endRadius: radius
        ))
    }

    private func dot(at center: CGPoint, radius: CGFloat, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: 2 * radius, height: 2 * radius)), with: .color(color))
    }

    private func stroke(from start: CGPoint, to end: CGPoint, color: Color, width: CGFloat) {
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func visibility(at x: CGFloat) -> Double {
        0.20 + 0.80 * Double(min(1, max(0, x / width)))
    }

    private func seed(_ index: Int, _ salt: Int) -> CGFloat {
        let bits = UInt32(index + 1) &* 0x9E3779B9 &+ UInt32(salt) &* 0x85EBCA6B
        let mixed = (bits ^ (bits >> 16)) &* 0x7FEB352D
        return CGFloat((mixed ^ (mixed >> 15)) & 0xFFFF) / 65536
    }

    private func wrap(_ value: CGFloat) -> CGFloat {
        value - floor(value)
    }
}
