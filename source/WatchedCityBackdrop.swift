import SwiftUI
import Combine

@MainActor
private final class WatchedCityVisibility: ObservableObject {
    @Published var isVisible = false
}

/// Each visible city owns its weather scene. Cards outside the scrolling viewport
/// keep a static poster so an eight-city list does not decode eight movies.
struct WatchedCityBackdrop: View {
    @ObservedObject var motion: WeatherMotion
    let snapshot: WeatherSnapshot
    let now: Date
    @StateObject private var visibility = WatchedCityVisibility()

    var body: some View {
        ImmersiveWeatherBackdrop(motion: motion, snapshot: snapshot, now: now,
                                 compact: true, motionEnabled: visibility.isVisible)
            .environment(\.colorScheme, .dark)
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                visibility.isVisible = visible
            }
            .onDisappear { visibility.isVisible = false }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
