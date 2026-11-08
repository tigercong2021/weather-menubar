import SwiftUI

private struct ImmersiveWeatherKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var immersiveWeather: Bool {
        get { self[ImmersiveWeatherKey.self] }
        set { self[ImmersiveWeatherKey.self] = newValue }
    }
}

struct WeatherCardBoundsKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

private struct WeatherCardSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.immersiveWeather) private var immersive
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background {
                if immersive {
                    if reduceTransparency {
                        shape.fill(Color(red: 0.12, green: 0.18, blue: 0.26))
                    } else {
                        Color.clear.glassEffect(
                            .regular.tint(Color(red: 0.10, green: 0.17, blue: 0.26).opacity(0.18)),
                            in: shape)
                    }
                } else {
                    shape.fill(.quaternary.opacity(0.48))
                }
            }
            .overlay {
                if immersive {
                    shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .anchorPreference(key: WeatherCardBoundsKey.self, value: .bounds) { immersive ? [$0] : [] }
    }
}

extension View {
    func weatherGlassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(WeatherCardSurface(radius: cornerRadius))
    }
}
