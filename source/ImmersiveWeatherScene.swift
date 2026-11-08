import SwiftUI

/// A single sky fills the local-weather page. All motion follows the panel clock,
/// which is stopped by the app for reduced motion, low power, or a closed panel.
struct ImmersiveWeatherBackdrop: View {
    @ObservedObject var motion: WeatherMotion
    let snapshot: WeatherSnapshot
    let now: Date
    var special: WeatherSceneSpecial? = nil
    var cycloneDemo = false
    var compact = false
    var motionEnabled = true

    var body: some View {
        let displayCode = cycloneDemo ? 65 : snapshot.code
        let kind = WeatherKind(code: displayCode)
        let sky = NightSkyAstronomy.sky(at: now, coordinate: snapshot.place.coordinate)
        // This changes the sky lighting only. Weather source fields and labels
        // remain untouched, including the currently displayed weather icon.
        let daylight = sky.map { $0.sun.altitudeDegrees >= 0 } ?? (snapshot.isDay(at: now) != false)
        let profile = WeatherSceneProfile(code: displayCode, intensity: cycloneDemo ? 12 : snapshot.intensity,
                                          windSpeed: cycloneDemo ? 78 : snapshot.details?.windSpeed,
                                          gust: cycloneDemo ? max(snapshot.gust ?? 0, 100) : snapshot.gust,
                                          windDirection: snapshot.details?.windDirection)
        let palette = ImmersiveSkyPalette(kind: kind, daylight: daylight, haze: special == .haze)
        let openSky = kind == .clear || kind == .mostlyClear || kind == .partlyCloudy
        let visibleMoon = openSky ? sky?.moon.flatMap { $0.isAboveHorizon ? $0 : nil } : nil
        let moonTexture = visibleMoon.flatMap { LunarDiskTexture.image(fraction: $0.phaseFraction, daylight: daylight) }
        let moonIllumination = visibleMoon?.illumination ?? 0
        let precipitation = WeatherPrecipitationLayers(profile: profile,
            mixed: snapshot.hasMixedPrecipitation || special == .mixedPrecipitation)
        let treatment = WeatherVideoTreatment.scene(kind: kind, daylight: daylight,
                                                     solar: snapshot.daylightProgress(at: now),
                                                     special: special, cycloneDemo: cycloneDemo, compact: compact,
                                                     moonIllumination: moonIllumination,
                                                     sunAltitudeDegrees: sky?.sun.altitudeDegrees)
        let videoAsset = treatment.flatMap { WeatherVideoAssets.asset(for: $0.key, compact: compact) }
        let wind = WeatherPrecipitationWind(direction: snapshot.details?.windDirection,
            sustainedSpeed: cycloneDemo ? 78 : snapshot.details?.windSpeed,
            gust: cycloneDemo ? max(snapshot.gust ?? 0, 100) : snapshot.gust,
            fallbackMagnitude: profile.windMagnitude, elapsed: motionEnabled ? motion.sceneElapsed : 0)
        ZStack {
            if let videoAsset, let treatment {
                WeatherVideoBackdrop(asset: videoAsset, isPlaying: motionEnabled && motion.sceneElapsed > 0,
                                     treatment: treatment)
            }
            Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let scene = ImmersiveSkyPainter(context: context, size: size,
                                            time: motionEnabled ? CGFloat(motion.sceneElapsed) : 0,
                                            palette: palette, rainWind: wind)
            let panorama = SkyPanoramaProjection(width: Double(size.width), height: Double(size.height), compact: compact)
            if videoAsset == nil {
                scene.base()
                if openSky && !daylight { scene.milkyWay(moonIllumination: moonIllumination) }
            }
            if openSky, let sky {
                scene.solarAtmosphere(sun: sky.sun, panorama: panorama)
                if sky.sun.isAboveHorizon,
                   let point = panorama.point(altitudeDegrees: sky.sun.altitudeDegrees,
                                              azimuthDegrees: sky.sun.azimuthDegrees) {
                    scene.sun(center: point, altitude: sky.sun.altitudeDegrees,
                              cloudCover: palette.cloudCover, diameter: compact ? 20 : 28)
                }
                if let moonTexture, let visibleMoon,
                   let point = panorama.point(altitudeDegrees: visibleMoon.altitudeDegrees,
                                              azimuthDegrees: visibleMoon.azimuthDegrees) {
                    scene.moon(texture: moonTexture, illumination: visibleMoon.illumination,
                               cloudCover: palette.cloudCover, center: point, diameter: compact ? 18 : 22)
                }
                if !daylight, let star = sky.brightest,
                   let point = panorama.point(altitudeDegrees: star.altitudeDegrees,
                                              azimuthDegrees: star.azimuthDegrees) {
                    scene.brightestStar(center: point, magnitude: star.visualMagnitude,
                                        sunAltitude: sky.sun.altitudeDegrees, cloudCover: palette.cloudCover)
                }
            }
            if videoAsset == nil {
                if kind != .clear && kind != .unknown {
                    scene.clouds(cover: palette.cloudCover, storm: profile.lightning || profile.rain == .heavy,
                                 profile: profile)
                }
                if kind == .fog || special == .haze { scene.fog() }
            } else if openSky {
                // Sun-free daytime footage needs the forecast's moving clouds.
                // A clear-night fallback similarly needs cloudy occlusion.
                if daylight && kind != .clear || kind == .mostlyClear
                    || kind == .partlyCloudy && videoAsset?.sceneKey != "partly-cloudy-night" {
                    scene.clouds(cover: palette.cloudCover, storm: false, profile: profile)
                }
            }
            if let rain = precipitation.rain {
                scene.rain(tier: rain, profile: profile, code: displayCode)
            }
            if let snow = precipitation.snow {
                scene.snow(tier: snow, profile: profile, code: displayCode)
            }
            if let hail = profile.hail { scene.hail(tier: hail, profile: profile) }
            if let wind = profile.wind { scene.windShear(tier: wind, profile: profile) }
            if snapshot.code == 48 { scene.frost() }
            if profile.lightning { scene.lightning() }
            scene.readabilityVeil()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Foreground droplets end at a measured card edge; their impact then becomes a
/// brief crown, two ballistic droplets and a fading ripple at that exact point.
struct WeatherCardRainOverlay: View {
    @ObservedObject var motion: WeatherMotion
    let snapshot: WeatherSnapshot
    let surfaces: [CGRect]

    var body: some View {
        let profile = WeatherSceneProfile(code: snapshot.code, intensity: snapshot.intensity,
                                          windSpeed: snapshot.details?.windSpeed, gust: snapshot.gust,
                                          windDirection: snapshot.details?.windDirection)
        Canvas { context, size in
            if profile.lightning { drawPageLightning(context: context, size: size, time: CGFloat(motion.sceneElapsed)) }
            guard let tier = WeatherPrecipitationLayers(profile: profile, mixed: snapshot.hasMixedPrecipitation).rain,
                  size.width > 0, size.height > 0 else { return }
            let edges = surfaces.filter { $0.width > 30 && $0.minY > 0 && $0.minY < size.height }
                .sorted { $0.minY < $1.minY }
            guard !edges.isEmpty else { return }
            let appearance = WeatherRainAppearance(tier: tier, code: snapshot.code, rate: profile.rainRate,
                                                    width: Double(size.width), height: Double(size.height))
            let drizzle = appearance.isDrizzle
            let totalEdgeWidth = edges.prefix(8).reduce(0) { $0 + $1.width }
            let time = CGFloat(motion.sceneElapsed)
            let wind = WeatherPrecipitationWind(direction: snapshot.details?.windDirection,
                sustainedSpeed: snapshot.details?.windSpeed, gust: snapshot.gust,
                fallbackMagnitude: profile.windMagnitude, elapsed: Double(time))
            let slant = CGFloat(wind.slope)
            let ink = Color(red: 0.70, green: 0.81, blue: 0.88)
            for (surfaceIndex, edge) in edges.prefix(8).enumerated() {
                let count = max(1, Int((Double(appearance.impactBudget) * Double(edge.width / totalEdgeWidth)).rounded()))
                for particle in 0..<count {
                    let seedIndex = surfaceIndex * 37 + particle
                    let inset = min(18, edge.width / 5)
                    let impactX = edge.minX + inset + (edge.width - 2 * inset) * immersiveSeed(seedIndex, 41)
                    let impact = CGPoint(x: impactX, y: edge.minY + 0.6)
                    // An upper card occludes the foreground trajectory. Only the
                    // unobstructed gap and the target's upper lip receive droplets.
                    let obstruction = edges.filter {
                        $0.maxY < edge.minY - 1 && $0.minX <= impactX && $0.maxX >= impactX
                    }.map(\.maxY).max() ?? -20
                    let startY = max(obstruction + 2, edge.minY - (surfaceIndex == 0 ? 260 : 72))
                    let distance = max(5, impact.y - startY)
                    let speed = CGFloat(appearance.speed.upperBound)
                    let fallDuration = max(0.09, distance / speed)
                    let splashDuration: CGFloat = drizzle ? 0.20 : 0.34
                    let pause = CGFloat(appearance.impactPause.lowerBound)
                        + CGFloat(appearance.impactPause.upperBound - appearance.impactPause.lowerBound)
                        * immersiveSeed(seedIndex, 44)
                    let duration = fallDuration + splashDuration + pause
                    let phase = immersiveWrap(time / duration + immersiveSeed(seedIndex, 43)) * duration
                    let opacity = (drizzle ? 0.25 : tier == .heavy ? 0.55 : tier == .moderate ? 0.47 : 0.38)
                        + 0.10 * Double(immersiveSeed(seedIndex, 42))
                    if phase < fallDuration {
                        let progress = phase / fallDuration
                        let y = startY + distance * progress
                        let remaining = impact.y - y
                        let x = impact.x - slant * remaining
                        let length = min(CGFloat(appearance.length.upperBound), max(2, distance * 0.30))
                        let visibleLength = min(length, max(0, y - startY))
                        let tail = CGPoint(x: x - slant * visibleLength, y: y - visibleLength)
                        let tip = CGPoint(x: x, y: min(impact.y, y))
                        drawWaterStreak(context: context, tail: tail, tip: tip,
                                        width: drizzle ? 0.55 : 0.82 + 0.26 * immersiveSeed(seedIndex, 45),
                                        opacity: opacity, depth: 0.72 + 0.28 * immersiveSeed(seedIndex, 46),
                                        icy: appearance.isIcy)
                    } else if phase < fallDuration + splashDuration {
                        let progress = (phase - fallDuration) / splashDuration
                        let fade = Double(pow(1 - progress, 1.4)) * opacity
                        let spread = (drizzle ? 3.4 : 6.2) * progress
                        let lift = (drizzle ? 2.4 : 4.6) * 4 * progress * (1 - progress)
                        var crown = Path()
                        crown.move(to: CGPoint(x: impact.x - spread, y: impact.y - lift * 0.55))
                        crown.addQuadCurve(to: impact, control: CGPoint(x: impact.x - spread * 0.4, y: impact.y - 0.5))
                        crown.addQuadCurve(to: CGPoint(x: impact.x + spread, y: impact.y - lift * 0.55),
                                           control: CGPoint(x: impact.x + spread * 0.4, y: impact.y - 0.5))
                        context.stroke(crown, with: .color(ink.opacity(fade * 0.65)), lineWidth: 0.45)
                        for direction: CGFloat in [-1, 1] {
                            let asymmetry = direction < 0 ? 0.82 + 0.22 * immersiveSeed(seedIndex, 47)
                                : 0.90 + 0.28 * immersiveSeed(seedIndex, 48)
                            let point = CGPoint(x: impact.x + direction * spread * asymmetry + slant * progress * 4,
                                                y: impact.y - lift * asymmetry)
                            let radius: CGFloat = drizzle ? 0.48 : 0.72
                            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                                width: radius * 2, height: radius * 2)),
                                         with: .radialGradient(Gradient(colors: [ink.opacity(fade * 0.15), ink.opacity(fade * 0.74), .clear]),
                                             center: CGPoint(x: point.x - radius * 0.3, y: point.y - radius * 0.3),
                                             startRadius: 0, endRadius: radius * 1.2))
                        }
                        let ripple = CGRect(x: impact.x - spread, y: impact.y - 0.35,
                                            width: spread * 2, height: 1.1)
                        context.stroke(Path(ellipseIn: ripple), with: .color(ink.opacity(fade * 0.7)), lineWidth: 0.55)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawPageLightning(context: GraphicsContext, size: CGSize, time: CGFloat) {
        // One softly exposed strike per 13.6 seconds. Static/off mode has t == 0.
        guard time > 0 else { return }
        let phase = immersiveWrap((time - 2.7) / 13.6)
        guard phase < 0.045 else { return }
        let exposure = sin(.pi * phase / 0.045)
        let width = size.width
        let height = size.height
        let strike = Int(max(0, floor((time - 2.7) / 13.6))) % 10_000
        let salt = strike * 97
        let count = 40 + Int(immersiveSeed(strike, 101) * 12)
        let steps = (0..<count).map { 0.55 + immersiveSeed($0 + salt, 102) }
        let total = steps.reduce(0, +)
        let originX = width * (0.58 + 0.18 * immersiveSeed(strike, 103))
        let endX = width * (0.34 + 0.24 * immersiveSeed(strike, 104))
        var vertices = [CGPoint(x: originX, y: -3)]
        var y: CGFloat = 0
        for segment in 0..<count {
            y += height * 0.84 * steps[segment] / total
            let progress = y / max(1, height * 0.84)
            let guide = originX + (endX - originX) * progress
                + width * 0.045 * sin(progress * 9 + CGFloat(strike))
            let jitter = width * (immersiveSeed(segment + salt, 105) - 0.5) * 0.052
            let x = min(width * 0.82, max(width * 0.28,
                                        vertices.last!.x * 0.54 + guide * 0.46 + jitter))
            vertices.append(CGPoint(x: x, y: y))
        }
        var bolt = Path()
        bolt.addLines(vertices)
        let ink = Color(red: 0.78, green: 0.86, blue: 1)
        let branchCount = 4 + Int(immersiveSeed(strike, 106) * 5)
        for branchIndex in 0..<branchCount {
            let seed = salt + branchIndex * 19
            let anchorIndex = 5 + Int(immersiveSeed(seed, 107) * CGFloat(count - 13))
            let origin = vertices[anchorIndex]
            let direction: CGFloat = immersiveSeed(seed, 108) < 0.5 ? -1 : 1
            let length = height * (0.065 + 0.095 * immersiveSeed(seed, 109))
            let spread = width * (0.08 + 0.13 * immersiveSeed(seed, 110)) * direction
            let subdivisions = 7 + Int(immersiveSeed(seed, 111) * 5)
            var points = [origin]
            for step in 1...subdivisions {
                let progress = CGFloat(step) / CGFloat(subdivisions)
                let jitter = width * (immersiveSeed(seed + step, 112) - 0.5) * 0.025
                points.append(CGPoint(x: origin.x + spread * progress + jitter,
                                      y: origin.y + length * progress))
            }
            var fork = Path()
            fork.addLines(points)
            context.stroke(fork, with: .linearGradient(
                Gradient(colors: [ink.opacity(Double(exposure) * 0.24), ink.opacity(0)]),
                startPoint: origin, endPoint: points.last!),
                style: StrokeStyle(lineWidth: 0.55, lineCap: .round, lineJoin: .round))
        }
        context.stroke(bolt, with: .color(ink.opacity(Double(exposure) * 0.065)),
                       style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        context.stroke(bolt, with: .color(ink.opacity(Double(exposure) * 0.13)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        context.stroke(bolt, with: .color(Color.white.opacity(Double(exposure) * 0.38)),
                       style: StrokeStyle(lineWidth: 0.65, lineCap: .round, lineJoin: .round))
    }
}

@MainActor
private enum LunarDiskTexture {
    private static var images: [Int: CGImage] = [:]

    static func image(fraction: Double, daylight: Bool = false) -> CGImage? {
        guard fraction.isFinite else { return nil }
        let phaseKey = Int((max(0, min(1, fraction)) * 512).rounded()) % 512
        let key = phaseKey + (daylight ? 512 : 0)
        if let image = images[key] { return image }
        let phase = Double(phaseKey) / 512
        let sunX = sin(phase * 2 * .pi)
        let sunZ = -cos(phase * 2 * .pi)
        let side = 96
        let center = Double(side - 1) / 2
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let craters: [(Double, Double, Double)] = [(-0.52, 0.38, 0.09), (0.49, -0.35, 0.075),
            (0.28, 0.55, 0.055), (-0.20, -0.61, 0.06), (0.59, 0.18, 0.045), (0.02, -0.24, 0.04)]
        for row in 0..<side {
            for column in 0..<side {
                let x = (Double(column) - center) / center
                let y = (center - Double(row)) / center
                let radiusSquared = x * x + y * y
                guard radiusSquared < 1 else { continue }
                let z = sqrt(1 - radiusSquared)
                let sunlight = x * sunX + z * sunZ
                let transition = min(1, max(0, (sunlight + 0.012) / 0.034))
                let lit = transition * transition * (3 - 2 * transition)
                let irradiance = 0.022 + lit * (0.20 + 0.78 * sqrt(max(0, sunlight)))
                // Low-contrast maria, mottling and small crater rims give the
                // sphere texture. This is decorative surface detail, not a map.
                let maria = 0.17 * exp(-pow((x + 0.24) / 0.37, 2) - pow((y - 0.25) / 0.49, 2))
                    + 0.12 * exp(-pow((x - 0.32) / 0.31, 2) - pow((y - 0.14) / 0.30, 2))
                let grain = 0.030 * (noise(x * 9.2 + y * 2.6, y * 8.9 - x * 2.3) - 0.5)
                    + 0.020 * (noise(x * 25.3 - y * 4.1, y * 24.7 + x * 2.7) - 0.5)
                var relief = 0.0
                for (craterX, craterY, radius) in craters {
                    let distance = hypot(x - craterX, y - craterY)
                    relief += 0.045 * exp(-pow((distance - radius) / 0.012, 2))
                        - 0.055 * exp(-pow(distance / (radius * 0.75), 2))
                }
                let surface = min(1, max(0, 0.80 - maria + grain + relief))
                let value = daylight ? 0.70 + surface * 0.25
                    : min(1, max(0, surface * irradiance * (0.88 + 0.12 * z)))
                let edge = min(1, max(0, (1 - sqrt(radiusSquared)) * center))
                // Daytime atmosphere shines in front of the Moon. Keep only
                // reflected light: the unlit face must not black out the blue
                // video behind this transparent Canvas and mimic an eclipse.
                let alpha = daylight ? edge * lit * (0.18 + 0.82 * sqrt(max(0, sunlight))) : edge
                let offset = (row * side + column) * 4
                pixels[offset] = UInt8(min(255, max(0, value * 0.98 * alpha * 255)))
                pixels[offset + 1] = UInt8(min(255, max(0, value * alpha * 255)))
                pixels[offset + 2] = UInt8(min(255, max(0, value * 1.025 * alpha * 255)))
                pixels[offset + 3] = UInt8(alpha * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return nil
        }
        if images.count >= 12 { images.removeAll(keepingCapacity: true) }
        images[key] = image
        return image
    }

    private static func noise(_ x: Double, _ y: Double) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let tx = fx * fx * (3 - 2 * fx), ty = fy * fy * (3 - 2 * fy)
        func hash(_ x: Int, _ y: Int) -> Double {
            var bits = UInt32(truncatingIfNeeded: x) &* 0x9E3779B9
                ^ UInt32(truncatingIfNeeded: y) &* 0x85EBCA6B
            bits = (bits ^ (bits >> 16)) &* 0x7FEB352D
            return Double((bits ^ (bits >> 15)) & 0xFFFF) / 65535
        }
        let upper = hash(ix, iy) * (1 - tx) + hash(ix + 1, iy) * tx
        let lower = hash(ix, iy + 1) * (1 - tx) + hash(ix + 1, iy + 1) * tx
        return upper * (1 - ty) + lower * ty
    }
}

private struct ImmersiveSkyPalette {
    let kind: WeatherKind
    let daylight: Bool
    var haze = false

    var upper: Color {
        if haze { return daylight ? rgb(0x756B5A) : rgb(0x463E36) }
        switch kind {
        case .clear, .mostlyClear: return daylight ? rgb(0x326D9F) : rgb(0x09182F)
        case .partlyCloudy: return daylight ? rgb(0x3C5D79) : rgb(0x101D32)
        case .overcast: return daylight ? rgb(0x465661) : rgb(0x101A2B)
        case .snow, .snowShowers: return daylight ? rgb(0x617B92) : rgb(0x24374C)
        case .fog: return daylight ? rgb(0x586D78) : rgb(0x1B2A3B)
        case .thunder: return daylight ? rgb(0x263246) : rgb(0x0C1425)
        case .unknown: return rgb(0x35495F)
        default: return daylight ? rgb(0x465B70) : rgb(0x0D1B2E)
        }
    }
    var lower: Color {
        if haze { return daylight ? rgb(0xA19883) : rgb(0x746B5C) }
        switch kind {
        case .clear, .mostlyClear: return daylight ? rgb(0x6D97B8) : rgb(0x1F3654)
        case .partlyCloudy: return daylight ? rgb(0x6F879A) : rgb(0x233A55)
        case .overcast: return daylight ? rgb(0x687681) : rgb(0x223247)
        case .snow, .snowShowers: return daylight ? rgb(0x92A6B4) : rgb(0x536477)
        case .fog: return daylight ? rgb(0x81949B) : rgb(0x35495A)
        case .thunder: return daylight ? rgb(0x4B596D) : rgb(0x243147)
        default: return daylight ? rgb(0x6C8195) : rgb(0x253950)
        }
    }
    var cloudCover: Double {
        switch kind {
        case .clear: 0
        case .mostlyClear: 0.28
        case .partlyCloudy: 0.54
        case .snow, .snowShowers: 0.76
        case .fog: 0.58
        default: 0.97
        }
    }
    func rgb(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255)
    }
}

private struct ImmersiveSkyPainter {
    let context: GraphicsContext
    let size: CGSize
    let time: CGFloat
    let palette: ImmersiveSkyPalette
    let rainWind: WeatherPrecipitationWind

    func base() {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [palette.upper, palette.lower]), startPoint: .zero,
            endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
    }

    func clouds(cover: Double, storm: Bool, profile: WeatherSceneProfile) {
        // Broad, slow cloud banks carry smaller shaded billows. Soft radial edges
        // produce volume without a full-frame blur/filter on every animation tick.
        let height = min(size.height * 0.39, 280)
        let shadow = palette.daylight ? Color(red: 0.12, green: 0.19, blue: 0.27)
            : Color(red: 0.03, green: 0.07, blue: 0.14)
        let highlight = palette.daylight ? Color(red: 0.83, green: 0.88, blue: 0.91)
            : Color(red: 0.52, green: 0.63, blue: 0.76)
        let windFactor = 1 + CGFloat(min(90, profile.windMagnitude) / 30)
        let windDirection: CGFloat = profile.flowX < 0 ? -1 : 1
        for layer in 0..<3 {
            let depth = CGFloat(layer)
            let drift = sin(time * (0.014 + depth * 0.009) * windFactor + depth * 1.7) * 37 * windDirection
            for puff in 0..<11 {
                let index = layer * 17 + puff
                let x = size.width * (-0.12 + 1.24 * immersiveSeed(index, 1)) + drift
                let y = height * (-0.22 + 0.75 * immersiveSeed(index, 2)) + depth * 17
                let radius = size.width * (0.16 + 0.16 * immersiveSeed(index, 3))
                let opacity = cover * (layer == 0 ? 0.26 : 0.15) * (storm ? 1.15 : 1)
                glow(shadow, center: CGPoint(x: x, y: y + radius * 0.16), radius: radius,
                     verticalScale: 0.48 + 0.19 * immersiveSeed(index, 4), opacity: opacity)
                glow(highlight, center: CGPoint(x: x - radius * 0.15, y: y - radius * 0.12),
                     radius: radius * 0.82, verticalScale: 0.48,
                     opacity: cover * (palette.daylight ? 0.11 : 0.07))
            }
        }
        // Wispy transparent layers extend the sky through the content area.
        for index in 0..<4 {
            let x = size.width * (0.15 + CGFloat(index) * 0.28)
                + 20 * sin(time * 0.018 * windFactor + CGFloat(index)) * windDirection
            glow(highlight, center: CGPoint(x: x, y: size.height * (0.28 + CGFloat(index) * 0.16)),
                 radius: size.width * 0.65, verticalScale: 0.17,
                 opacity: cover * (palette.daylight ? 0.045 : 0.026))
        }
    }

    func solarAtmosphere(sun: NightSkyPosition, panorama: SkyPanoramaProjection) {
        let altitude = sun.altitudeDegrees
        guard altitude > -16, altitude < 18 else { return }
        if altitude < 0 {
            // The galaxy is atmospheric artwork, not a registered star map.
            // Civil/nautical twilight masks it, then fades toward the dark sky.
            let veil = 1 - SkyPanoramaProjection.starVisibility(sunAltitudeDegrees: altitude)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.075, green: 0.17, blue: 0.28).opacity(veil),
                                  Color(red: 0.27, green: 0.25, blue: 0.29).opacity(veil),
                                  Color(red: 0.12, green: 0.17, blue: 0.25).opacity(veil)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: min(size.height, 560))))
        }
        guard let horizon = panorama.point(altitudeDegrees: 0, azimuthDegrees: sun.azimuthDegrees) else { return }
        let warmth = max(0, 1 - abs(altitude - 1) / 17)
        glow(Color(red: 0.95, green: 0.54, blue: 0.30), center: horizon,
             radius: size.width * 0.82, verticalScale: 0.42,
             opacity: warmth * (palette.daylight ? 0.17 : 0.14))
    }

    func sun(center: CGPoint, altitude: Double, cloudCover: Double, diameter: CGFloat) {
        let lowSun = max(0, 1 - altitude / 24)
        let light = Color(red: 1, green: 0.94 - lowSun * 0.19, blue: 0.77 - lowSun * 0.31)
        let visibility = cloudVisibility(cover: cloudCover, center: center)
        glow(light, center: center, radius: diameter * 3.1, verticalScale: 1,
             opacity: 0.21 * visibility)
        glow(light, center: center, radius: diameter * 1.16, verticalScale: 1,
             opacity: 0.30 * visibility)
        let disk = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                          width: diameter, height: diameter)
        context.fill(Path(ellipseIn: disk), with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.90).opacity(0.88 * visibility),
                              light.opacity(0.78 * visibility), light.opacity(0.12 * visibility)]),
            center: center, startRadius: 0, endRadius: diameter / 2))
        celestialCloudVeil(center: center, diameter: diameter, cover: cloudCover)
    }

    func brightestStar(center: CGPoint, magnitude: Double, sunAltitude: Double, cloudCover: Double) {
        let twilight = SkyPanoramaProjection.starVisibility(sunAltitudeDegrees: sunAltitude)
        guard twilight > 0 else { return }
        let visibility = twilight * cloudVisibility(cover: cloudCover, center: center)
        let pulse = SkyPanoramaProjection.openingPulse(elapsed: Double(time))
        let brightness = min(1, max(0, (2.5 - magnitude) / 7))
        let radius = 1.0 + brightness * 0.48 + pulse * 0.13
        let ink = Color(red: 0.94, green: 0.96, blue: 1)
        glow(ink, center: center, radius: 4 + pulse * 6, verticalScale: 1,
             opacity: (0.08 + pulse * 0.17) * visibility)
        // A tiny diffraction glint identifies the calculated point in the
        // photographed galaxy only near the single opening pulse's peak.
        let glint = max(0, (pulse - 0.72) / 0.28)
        if glint > 0 {
            let reach = 2.4 + glint * 2.0
            var rays = Path()
            rays.move(to: CGPoint(x: center.x - reach, y: center.y))
            rays.addLine(to: CGPoint(x: center.x + reach, y: center.y))
            rays.move(to: CGPoint(x: center.x, y: center.y - reach))
            rays.addLine(to: CGPoint(x: center.x, y: center.y + reach))
            context.stroke(rays, with: .radialGradient(
                Gradient(colors: [ink.opacity(0.65 * glint * visibility), .clear]),
                center: center, startRadius: 0.4, endRadius: reach), lineWidth: 0.55)
        }
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .radialGradient(Gradient(colors: [ink.opacity((0.72 + pulse * 0.26) * visibility),
                                                            ink.opacity(0.30 * visibility), .clear]),
                                           center: center, startRadius: 0, endRadius: radius))
    }

    private func cloudVisibility(cover: Double, center: CGPoint) -> Double {
        let passing = (1 + sin(time * 0.16 + center.x * 0.008 + center.y * 0.004)) / 2
        return 1 - cover * (0.45 + 0.55 * passing) * 0.88
    }

    private func celestialCloudVeil(center: CGPoint, diameter: CGFloat, cover: Double) {
        guard cover > 0 else { return }
        let opacity = 1 - cloudVisibility(cover: cover, center: center)
        let ink = palette.daylight ? Color(red: 0.44, green: 0.53, blue: 0.61)
            : Color(red: 0.10, green: 0.15, blue: 0.21)
        glow(ink, center: CGPoint(x: center.x + 15 * sin(time * 0.12), y: center.y + 2),
             radius: diameter * 2.4, verticalScale: 0.32, opacity: opacity * 0.48)
    }

    func milkyWay(moonIllumination: Double) {
        // Only the procedural/legacy fallback uses this subdued star band. The
        // production night movies contain their own photographic galaxy detail.
        let bandHeight = min(size.height * 0.70, size.width * 1.45)
        let drift = sin(time * 0.006) * 2.4
        let starlight = Color(red: 0.71, green: 0.76, blue: 0.80)
        let visibility = 1 - moonIllumination * 0.50
        for cloud in 0..<8 {
            let progress = CGFloat(cloud) / 7
            let center = CGPoint(x: size.width * (0.86 - progress * 0.60) + drift,
                                 y: 12 + bandHeight * progress)
            glow(starlight, center: center, radius: size.width * (0.16 + 0.06 * immersiveSeed(cloud, 121)),
                 verticalScale: 1.5, opacity: (0.018 + 0.014 * Double(immersiveSeed(cloud, 122))) * visibility)
        }
        for star in 0..<105 {
            let progress = immersiveSeed(star, 123)
            let across = (immersiveSeed(star, 124) - 0.5) * size.width * 0.19
            let x = size.width * (0.86 - progress * 0.60) + across + drift
            let y = 12 + bandHeight * progress + across * 0.28
            let radius = 0.24 + 0.42 * immersiveSeed(star, 125)
            let intensity = (0.14 + 0.28 * immersiveSeed(star, 126))
                * (0.88 + 0.12 * sin(time * 0.31 + CGFloat(star)))
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                         with: .color(starlight.opacity(Double(intensity) * visibility)))
        }
    }

    /// The phase and center both come from the same astronomical instant.
    /// Surface texture is illustrative; the panorama is not an optical star chart.
    func moon(texture: CGImage, illumination: Double, cloudCover: Double,
              center: CGPoint, diameter: CGFloat = 22) {
        guard illumination > 0.008 else { return }
        let daytimeVisibility = palette.daylight ? min(1, max(0, (illumination - 0.02) / 0.08)) : 1
        let visibility = cloudVisibility(cover: cloudCover, center: center) * daytimeVisibility
        guard visibility > 0 else { return }
        glow(Color(red: 0.73, green: 0.79, blue: 0.86), center: center, radius: diameter * 1.2,
             verticalScale: 1, opacity: illumination * 0.042 * visibility * (palette.daylight ? 0.3 : 1))
        var lunar = context
        lunar.opacity = visibility * (palette.daylight ? 0.47 : 0.90)
        lunar.draw(Image(decorative: texture, scale: 1),
                   in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                              width: diameter, height: diameter))
        celestialCloudVeil(center: center, diameter: diameter, cover: cloudCover)
    }

    func fog() {
        let ink = palette.haze ? Color(red: 0.78, green: 0.73, blue: 0.60)
            : Color(red: 0.81, green: 0.87, blue: 0.88)
        for layer in 0..<6 {
            let drift = sin(time * 0.035 + CGFloat(layer) * 1.4) * 50
            glow(ink,
                 center: CGPoint(x: size.width * 0.5 + drift, y: size.height * CGFloat(layer + 1) / 7),
                 radius: size.width * 0.8, verticalScale: 0.19,
                 opacity: palette.daylight ? 0.13 : 0.07)
        }
    }

    func rain(tier: WeatherSceneStrength, profile: WeatherSceneProfile, code: Int) {
        let appearance = WeatherRainAppearance(tier: tier, code: code, rate: profile.rainRate,
                                                width: Double(size.width), height: Double(size.height))
        let slant = CGFloat(rainWind.slope)
        let burst = appearance.showerEnvelope(at: Double(time))
        let ink = appearance.isIcy ? Color(red: 0.80, green: 0.92, blue: 1) : Color(red: 0.79, green: 0.86, blue: 0.93)
        if appearance.curtainOpacity > 0 {
            for sheet in 0..<3 {
                let x = size.width * (0.12 + CGFloat(sheet) * 0.38) + 18 * sin(time * 0.40 + CGFloat(sheet))
                glow(ink, center: CGPoint(x: x, y: size.height * 0.43), radius: size.width * 0.095,
                     verticalScale: max(1, size.height / size.width * 4),
                     opacity: appearance.curtainOpacity * burst)
            }
        }
        for index in 0..<appearance.particleCount {
            // 40% distant, 40% middle, 20% near; each band varies naturally.
            let band = index % 10
            let depth = (band < 4 ? 0.08 : band < 8 ? 0.40 : 0.76) + 0.24 * immersiveSeed(index, 10)
            let speed = interpolate(appearance.speed, at: depth)
            let length = interpolate(appearance.length, at: depth)
            let travel = size.height + CGFloat(appearance.length.upperBound)
            let progress = immersiveWrap(time * speed / travel + immersiveSeed(index, 11))
            let y = -CGFloat(appearance.length.upperBound) + travel * progress
            let x = immersiveWrap(immersiveSeed(index, 12) + slant * y / max(1, size.width)) * size.width
            let opacity = Double(interpolate(appearance.opacity, at: depth)) * burst
            let tail = CGPoint(x: x - slant * length, y: y - length)
            let tip = CGPoint(x: x, y: y)
            drawWaterStreak(context: context, tail: tail, tip: tip,
                            width: interpolate(appearance.lineWidth, at: depth), opacity: opacity,
                            depth: depth, icy: appearance.isIcy)
        }
    }

    func snow(tier: WeatherSceneStrength, profile: WeatherSceneProfile, code: Int) {
        let appearance = WeatherSnowAppearance(tier: tier, code: code,
                                                width: Double(size.width), height: Double(size.height))
        let burst = appearance.showerEnvelope(at: Double(time))
        let flow = CGFloat(rainWind.horizontalFlow * min(1, rainWind.effectiveSpeed / 65))
        for index in 0..<appearance.particleCount {
            let depth = immersiveSeed(index, 21)
            let speed = interpolate(appearance.speed, at: depth)
            let travel = size.height + 18
            let y = immersiveWrap(time * speed / travel + immersiveSeed(index, 22)) * travel - 9
            let x = immersiveWrap(immersiveSeed(index, 23) + flow * y / max(1, size.width) * 0.2
                                  + 0.018 * sin(time * (0.45 + depth) + CGFloat(index))) * size.width
            let radius = interpolate(appearance.radius, at: depth)
            let opacity = Double(interpolate(appearance.opacity, at: depth)) * burst
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(opacity), .white.opacity(0)]),
                                               center: CGPoint(x: x + radius, y: y + radius), startRadius: 0, endRadius: radius * 1.15))
        }
    }

    func hail(tier: WeatherSceneStrength, profile: WeatherSceneProfile) {
        let count = WeatherRainAppearance.scaledCount(reference: tier == .heavy ? 30 : 14,
                                                      minimum: tier == .heavy ? 5 : 3, maximum: 42,
                                                      width: Double(size.width), height: Double(size.height))
        for index in 0..<count {
            let y = immersiveWrap(time * 520 / (size.height + 20) + immersiveSeed(index, 61)) * (size.height + 20) - 10
            let x = immersiveSeed(index, 62) * size.width + CGFloat(rainWind.slope) * y * 0.35
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.1, height: 2.6)),
                         with: .color(.white.opacity(0.46)))
        }
    }

    func windShear(tier: WeatherSceneStrength, profile: WeatherSceneProfile) {
        guard rainWind.directionKnown else { return }
        // Sparse atmospheric wisps make a dry, windy sky visibly different from
        // calm weather. They travel with the forecast wind instead of curling.
        let east = CGFloat(profile.flowX)
        let south = CGFloat(profile.flowY)
        let direction = atan2(south, east)
        let span = abs(size.width * east) + abs(size.height * south)
        let crossSpan = abs(size.width * south) + abs(size.height * east)
        let count = tier.rawValue + 2
        for index in 0..<count {
            let speed = CGFloat(26 + 16 * tier.rawValue)
            let progress = immersiveWrap(time * speed / max(1, span) + immersiveSeed(index, 81))
            let along = span * (progress * 1.55 - 0.77)
            let across = crossSpan * (immersiveSeed(index, 82) * 0.84 - 0.42)
            let center = CGPoint(x: size.width / 2 + east * along - south * across,
                                 y: size.height / 2 + south * along + east * across)
            let radius = CGFloat(48 + 18 * tier.rawValue) * (0.7 + immersiveSeed(index, 83) * 0.6)
            let opacity = Double(sin(.pi * progress)) * (0.025 + Double(tier.rawValue) * 0.013)
            var mist = context
            mist.translateBy(x: center.x, y: center.y)
            mist.rotate(by: .radians(Double(direction)))
            mist.scaleBy(x: 1, y: 0.045 + 0.025 * immersiveSeed(index, 84))
            let ink = Color(red: 0.86, green: 0.92, blue: 0.96)
            mist.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                      with: .radialGradient(Gradient(colors: [ink.opacity(opacity), ink.opacity(opacity * 0.5), .clear]),
                                            center: .zero, startRadius: 0, endRadius: radius))
        }
    }

    func frost() {
        // Tiny edge crystals distinguish freezing fog without putting a frosted
        // glass texture over the text or implying actual ice measurements.
        for index in 0..<8 {
            let x = index.isMultiple(of: 2) ? 4 + 7 * immersiveSeed(index, 91)
                : size.width - 4 - 7 * immersiveSeed(index, 91)
            let y = size.height * (0.12 + 0.78 * immersiveSeed(index, 92))
            let radius = 1.5 + 1.3 * immersiveSeed(index, 93)
            var crystal = Path()
            crystal.move(to: CGPoint(x: x - radius, y: y))
            crystal.addLine(to: CGPoint(x: x + radius, y: y))
            crystal.move(to: CGPoint(x: x, y: y - radius))
            crystal.addLine(to: CGPoint(x: x, y: y + radius))
            context.stroke(crystal, with: .color(Color(red: 0.81, green: 0.93, blue: 1).opacity(0.34)), lineWidth: 0.5)
        }
    }

    func lightning() {
        guard time > 0 else { return }
        let phase = immersiveWrap((time - 2.7) / 13.6)
        let flare = phase < 0.045 ? sin(.pi * phase / 0.045) : 0
        guard flare > 0 else { return }
        glow(Color(red: 0.80, green: 0.86, blue: 1), center: CGPoint(x: size.width * 0.73, y: 65),
             radius: size.width * 0.9, verticalScale: 1.6, opacity: Double(flare) * 0.18)
    }

    func readabilityVeil() {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: .black.opacity(0.02), location: 0),
                             .init(color: .black.opacity(0.02), location: 0.22),
                             .init(color: .black.opacity(0.10), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func glow(_ color: Color, center: CGPoint, radius: CGFloat, verticalScale: CGFloat, opacity: Double) {
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.scaleBy(x: 1, y: verticalScale)
        layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(stops: [
                    .init(color: color.opacity(opacity), location: 0),
                    .init(color: color.opacity(opacity * 0.78), location: 0.36),
                    .init(color: color.opacity(opacity * 0.25), location: 0.72),
                    .init(color: color.opacity(0), location: 1)]),
                    center: .zero, startRadius: 0, endRadius: radius))
    }

    private func interpolate(_ range: ClosedRange<Double>, at fraction: CGFloat) -> CGFloat {
        CGFloat(range.lowerBound) + CGFloat(range.upperBound - range.lowerBound) * fraction
    }
}

/// A fast drop is a transparent, tapered motion smear with a tiny reflective
/// leading bead. The wider low-opacity skirt gives distant drops soft edges
/// without expensive full-frame blur passes or a luminous uniform stroke.
private func drawWaterStreak(context: GraphicsContext, tail: CGPoint, tip: CGPoint,
                             width: CGFloat, opacity: Double, depth: CGFloat, icy: Bool) {
    let dx = tip.x - tail.x
    let dy = tip.y - tail.y
    let length = hypot(dx, dy)
    guard length > 0.5, width > 0, opacity > 0 else { return }
    var drop = context
    drop.translateBy(x: tip.x, y: tip.y)
    drop.rotate(by: .radians(Double(atan2(dy, dx) - .pi / 2)))
    let water = icy ? Color(red: 0.64, green: 0.79, blue: 0.89)
        : Color(red: 0.61, green: 0.73, blue: 0.81)
    let reflection = icy ? Color(red: 0.86, green: 0.95, blue: 1)
        : Color(red: 0.82, green: 0.90, blue: 0.94)
    var axis = Path()
    axis.move(to: CGPoint(x: 0, y: -length))
    axis.addLine(to: .zero)
    drop.stroke(axis, with: .linearGradient(
        Gradient(colors: [water.opacity(0), water.opacity(opacity * (depth < 0.35 ? 0.22 : 0.12))]),
        startPoint: CGPoint(x: 0, y: -length), endPoint: .zero),
        style: StrokeStyle(lineWidth: width * (depth < 0.35 ? 2.1 : 1.6), lineCap: .round))

    let head = min(3.2, max(1.0, length * 0.13))
    var body = Path()
    body.move(to: CGPoint(x: -width * 0.04, y: -length))
    body.addQuadCurve(to: CGPoint(x: -width * 0.48, y: -head),
                      control: CGPoint(x: -width * 0.20, y: -length * 0.40))
    body.addQuadCurve(to: CGPoint(x: 0, y: width * 0.42), control: CGPoint(x: -width * 0.58, y: 0))
    body.addQuadCurve(to: CGPoint(x: width * 0.48, y: -head), control: CGPoint(x: width * 0.58, y: 0))
    body.addQuadCurve(to: CGPoint(x: width * 0.04, y: -length),
                      control: CGPoint(x: width * 0.20, y: -length * 0.40))
    body.closeSubpath()
    drop.fill(body, with: .linearGradient(Gradient(stops: [
        .init(color: water.opacity(0), location: 0),
        .init(color: water.opacity(opacity * 0.10), location: 0.20),
        .init(color: water.opacity(opacity * 0.46), location: 0.52),
        .init(color: water.opacity(opacity * 0.95), location: 0.88),
        .init(color: reflection.opacity(opacity * 0.82), location: 1)
    ]), startPoint: CGPoint(x: 0, y: -length), endPoint: .zero))

    if depth > 0.65 {
        let beadWidth = width * (0.95 + depth * 0.35)
        let bead = CGRect(x: -beadWidth / 2, y: -head * 0.67, width: beadWidth, height: min(2.8, head * 0.94))
        drop.fill(Path(ellipseIn: bead), with: .radialGradient(
            Gradient(stops: [.init(color: Color.black.opacity(opacity * 0.10), location: 0),
                             .init(color: water.opacity(opacity * 0.15), location: 0.35),
                             .init(color: reflection.opacity(opacity * 0.56), location: 0.78),
                             .init(color: .clear, location: 1)]),
            center: CGPoint(x: -beadWidth * 0.15, y: -head * 0.30), startRadius: 0, endRadius: head * 0.56))
        var glint = Path()
        glint.move(to: CGPoint(x: -width * 0.16, y: -head * 0.51))
        glint.addLine(to: CGPoint(x: -width * 0.28, y: -head * 0.18))
        drop.stroke(glint, with: .color(reflection.opacity(opacity * (0.42 + Double(depth) * 0.22))),
                    style: StrokeStyle(lineWidth: max(0.22, width * 0.20), lineCap: .round))
    }
}

private func immersiveSeed(_ index: Int, _ salt: Int) -> CGFloat {
    let bits = UInt32(index + 1) &* 0x9E3779B9 &+ UInt32(salt) &* 0x85EBCA6B
    let mixed = (bits ^ (bits >> 16)) &* 0x7FEB352D
    return CGFloat((mixed ^ (mixed >> 15)) & 0xFFFF) / 65536
}

private func immersiveWrap(_ value: CGFloat) -> CGFloat { value - floor(value) }
