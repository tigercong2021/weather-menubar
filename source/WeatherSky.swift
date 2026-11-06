import SwiftUI

/// The sky describes the weather. Air quality is a translucent layer over it.
struct WeatherSky: View {
    let code: Int?
    let daylight: Bool?
    let airTint: Color?
    var compact = false
    var daylightProgress: Double? = nil

    var body: some View {
        let kind = WeatherKind(code: code)
        GeometryReader { geometry in
            ZStack {
                if let daylight {
                    let palette = Self.palette(for: kind, day: daylight)
                    LinearGradient(colors: [Self.color(palette.upper), Self.color(palette.horizon)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                    RadialGradient(colors: [Self.color(palette.glow).opacity(daylight ? 0.42 : 0.25), .clear],
                                   center: UnitPoint(x: 0.83, y: daylight ? 0.10 : 0.65), startRadius: 0,
                                   endRadius: max(geometry.size.width * 0.59, geometry.size.height))
                    if daylight, !compact, let daylightProgress,
                       kind == .clear || kind == .mostlyClear || kind == .partlyCloudy {
                        let distanceToHorizon = min(daylightProgress, 1 - daylightProgress)
                        let warmth = max(0, 1 - distanceToHorizon / 0.19) * 0.55
                        RadialGradient(colors: [Color(red: 0.99, green: 0.67, blue: 0.42).opacity(warmth), .clear],
                                       center: UnitPoint(x: daylightProgress < 0.5 ? 0.15 : 0.85, y: 0.96),
                                       startRadius: 0, endRadius: geometry.size.width * 0.70)
                    }
                    if compact, !daylight, kind == .clear { stars }
                } else {
                    LinearGradient(colors: [Color(nsColor: .controlBackgroundColor),
                                            Color(nsColor: .windowBackgroundColor)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
                if let airTint {
                    WeatherAQIOverlay(tint: airTint, daylight: daylight)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var stars: some View {
        Canvas { context, size in
            let points: [(CGFloat, CGFloat, CGFloat)] = [
                (0.20, 0.28, 0.55), (0.34, 0.70, 0.64), (0.45, 0.20, 0.50),
                (0.51, 0.56, 0.75), (0.58, 0.36, 0.53), (0.63, 0.75, 0.58),
                (0.69, 0.18, 0.84), (0.75, 0.58, 0.63), (0.81, 0.32, 0.59),
                (0.87, 0.73, 0.56), (0.90, 0.15, 0.73), (0.95, 0.42, 0.53)
            ]
            for (x, y, radius) in points {
                let dot = CGRect(x: size.width * x - radius, y: size.height * y - radius,
                                 width: 2 * radius, height: 2 * radius)
                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(radius > 0.7 ? 0.54 : 0.34)))
            }
        }
    }

    private typealias Palette = (upper: UInt32, horizon: UInt32, glow: UInt32)

    private static func palette(for kind: WeatherKind, day: Bool) -> Palette {
        switch kind {
        case .clear:
            day ? (0x91C8F1, 0xE1F4FD, 0xB1DDFB) : (0x10224A, 0x243C62, 0x3B5F9C)
        case .mostlyClear, .partlyCloudy:
            day ? (0xA9C9E2, 0xE7F1F8, 0xCDDDEB) : (0x172943, 0x314765, 0x3C5277)
        case .overcast:
            day ? (0xB1BFCD, 0xE7ECEF, 0xD0DAE2) : (0x212A3A, 0x394653, 0x4B5A6B)
        case .fog:
            day ? (0xCCD8DB, 0xF0F3F1, 0xE1E9E6) : (0x2A3542, 0x475560, 0x57656E)
        case .drizzle, .rain, .showers:
            day ? (0xA3BBD1, 0xDDE9F0, 0xB1C9DF) : (0x172C46, 0x334760, 0x405979)
        case .freezingRain:
            day ? (0xA8C1D8, 0xE5EDF3, 0xC1DAED) : (0x192A49, 0x364B66, 0x527390)
        case .snow, .snowShowers:
            day ? (0xC4DDEA, 0xF1F7FC, 0xE8F4FB) : (0x23344F, 0x3C526D, 0x627997)
        case .thunder:
            day ? (0x9EABBF, 0xD8E0E9, 0xADB6D1) : (0x1C2039, 0x343D54, 0x494667)
        case .unknown:
            day ? (0xD2DCE4, 0xEFF3F5, 0xE1E8ED) : (0x273340, 0x3B4855, 0x4D5C69)
        }
    }

    private static func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 0xff) / 255,
              green: Double((rgb >> 8) & 0xff) / 255,
              blue: Double(rgb & 0xff) / 255)
    }
}

struct WeatherAQIOverlay: View {
    let tint: Color
    let daylight: Bool?
    var localized = false

    var body: some View {
        Group {
            if localized {
                GeometryReader { geometry in
                    RadialGradient(colors: [tint.opacity(daylight == false ? 0.20 : 0.23), .clear],
                                   center: UnitPoint(x: 0.90, y: 0.86), startRadius: 0,
                                   endRadius: max(60, geometry.size.width * 0.55))
                }
            } else {
                LinearGradient(colors: [tint.opacity(daylight == false ? 0.24 : 0.27), tint.opacity(0.10)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
