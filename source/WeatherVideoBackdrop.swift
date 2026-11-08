import AppKit
import AVFoundation
import SwiftUI

/// The video provides distant atmospheric detail. Local Canvas particles remain
/// responsible for rain, snow, card impacts, and the timed lightning foreground.
struct WeatherVideoBackdrop: View {
    let asset: WeatherVideoAsset
    let isPlaying: Bool
    let treatment: WeatherVideoTreatment

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(nsImage: asset.poster)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                if isPlaying {
                    WeatherLoopingVideo(url: asset.videoURL)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                Color.black.opacity(treatment.darkening)
                if treatment.nightCooling > 0 {
                    Color(red: 0.035, green: 0.09, blue: 0.19).opacity(treatment.nightCooling)
                }
                if treatment.moonlightWash > 0 {
                    Color(red: 0.07, green: 0.10, blue: 0.15).opacity(treatment.moonlightWash)
                }
                if treatment.twilightWarmth > 0 {
                    Color(red: 0.47, green: 0.24, blue: 0.18).opacity(treatment.twilightWarmth)
                }
                if treatment.warmHaze {
                    Color(red: 0.48, green: 0.39, blue: 0.22).opacity(0.22)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WeatherVideoTreatment: Equatable {
    let key: String
    let darkening: Double
    var warmHaze = false
    var nightCooling = 0.0
    var moonlightWash = 0.0
    var twilightWarmth = 0.0

    static func scene(kind: WeatherKind, daylight: Bool, solar: Double?,
                      special: WeatherSceneSpecial? = nil, cycloneDemo: Bool = false, compact: Bool = false,
                      moonIllumination: Double? = nil, sunAltitudeDegrees: Double? = nil) -> Self? {
        guard let base = baseScene(kind: kind, daylight: daylight, solar: solar,
                                   special: special, cycloneDemo: cycloneDemo,
                                   sunAltitudeDegrees: sunAltitudeDegrees) else { return nil }
        let starryNight = !daylight && (kind == .clear || kind == .mostlyClear || kind == .partlyCloudy)
        let illumination = moonIllumination.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
        return Self(key: base.key, darkening: min(0.80, base.darkening + (compact ? 0.10 : 0)),
                    warmHaze: base.warmHaze, nightCooling: base.nightCooling,
                    moonlightWash: starryNight ? illumination * 0.15 : 0,
                    twilightWarmth: base.twilightWarmth)
    }

    private static func baseScene(kind: WeatherKind, daylight: Bool, solar: Double?,
                                  special: WeatherSceneSpecial?, cycloneDemo: Bool,
                                  sunAltitudeDegrees: Double?) -> Self? {
        if special == .haze {
            return Self(key: "fog", darkening: daylight ? 0.38 : 0.67,
                        warmHaze: true, nightCooling: daylight ? 0 : 0.16)
        }
        if cycloneDemo {
            return Self(key: "storm-clouds", darkening: daylight ? 0.30 : 0.48, nightCooling: daylight ? 0 : 0.26)
        }
        if special == .mixedPrecipitation {
            return Self(key: "snow-clouds", darkening: daylight ? 0.38 : 0.66, nightCooling: daylight ? 0 : 0.25)
        }
        switch kind {
        case .clear, .mostlyClear:
            return openSky(daylight: daylight, clouded: false, sunAltitudeDegrees: sunAltitudeDegrees)
        case .partlyCloudy:
            return openSky(daylight: daylight, clouded: true, sunAltitudeDegrees: sunAltitudeDegrees)
        case .overcast:
            return Self(key: "overcast", darkening: daylight ? 0.39 : 0.66, nightCooling: daylight ? 0 : 0.28)
        case .drizzle, .rain, .freezingRain, .showers:
            return Self(key: "rain-clouds", darkening: daylight ? 0.32 : 0.61, nightCooling: daylight ? 0 : 0.25)
        case .snow, .snowShowers:
            return Self(key: "snow-clouds", darkening: daylight ? 0.38 : 0.66, nightCooling: daylight ? 0 : 0.25)
        case .fog:
            return Self(key: "fog", darkening: daylight ? 0.42 : 0.68, nightCooling: daylight ? 0 : 0.28)
        case .thunder:
            return Self(key: "storm-clouds", darkening: daylight ? 0.30 : 0.48, nightCooling: daylight ? 0 : 0.26)
        case .unknown:
            return nil
        }
    }

    private static func openSky(daylight: Bool, clouded: Bool, sunAltitudeDegrees: Double?) -> Self {
        let altitude = sunAltitudeDegrees.flatMap { $0.isFinite ? $0 : nil }
        // This clip has no baked-in sun or glow. The old clear-day, partly-cloudy
        // and dawn-dusk movies cannot represent a calculated solar position.
        if daylight {
            let lowSun = altitude.map { min(1, max(0, (14 - $0) / 14)) } ?? 0
            return Self(key: "clear-day-atmosphere",
                        darkening: (clouded ? 0.26 : 0.20) + lowSun * 0.18,
                        twilightWarmth: lowSun * 0.27)
        }
        return Self(key: clouded ? "partly-cloudy-night" : "milky-way-night",
                    darkening: clouded ? 0.06 : 0.04, nightCooling: clouded ? 0.04 : 0.03)
    }
}

@MainActor
struct WeatherVideoAsset {
    let videoURL: URL
    let poster: NSImage

    var sceneKey: String {
        videoURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-compact", with: "")
    }
}

@MainActor
enum WeatherVideoAssets {
    private static var cached: [String: WeatherVideoAsset] = [:]
    private static var unavailable = Set<String>()

    static func asset(for key: String, compact: Bool = false) -> WeatherVideoAsset? {
        let fallbackKeys: [String]
        switch key {
        // Legacy clear-night contains a baked-in crescent. A procedural fallback
        // avoids showing that fixed moon alongside today's calculated phase.
        case "milky-way-night": fallbackKeys = []
        case "partly-cloudy-night": fallbackKeys = ["milky-way-night"]
        default: fallbackKeys = []
        }
        for candidate in [key] + fallbackKeys {
            if compact, let small = loadAsset(key: candidate + "-compact") { return small }
            if let full = loadAsset(key: candidate) { return full }
        }
        return nil
    }

    private static func loadAsset(key: String) -> WeatherVideoAsset? {
        guard let directory = resourceDirectory else { return nil }
        let cacheKey = directory.path + "/" + key
        if let asset = cached[cacheKey] { return asset }
        guard !unavailable.contains(cacheKey) else { return nil }
        let movie = directory.appendingPathComponent(key).appendingPathExtension("mp4")
        let posterURL = directory.appendingPathComponent(key).appendingPathExtension("jpg")
        guard movie.isFileURL, FileManager.default.isReadableFile(atPath: movie.path),
              let poster = NSImage(contentsOf: posterURL), poster.isValid else {
            unavailable.insert(cacheKey)
            return nil
        }
        let asset = WeatherVideoAsset(videoURL: movie, poster: poster)
        cached[cacheKey] = asset
        return asset
    }

    private static var resourceDirectory: URL? {
        #if WEATHER_CAPTURE
        if let directory = ProcessInfo.processInfo.environment["WEATHER_SCENE_RESOURCE_DIR"], !directory.isEmpty {
            return URL(fileURLWithPath: directory, isDirectory: true)
        }
        #endif
        return Bundle.main.resourceURL?.appendingPathComponent("WeatherScenes", isDirectory: true)
    }
}

private struct WeatherLoopingVideo: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WeatherVideoPlayerView {
        let view = WeatherVideoPlayerView()
        view.play(url)
        return view
    }

    func updateNSView(_ view: WeatherVideoPlayerView, context: Context) { view.play(url) }

    static func dismantleNSView(_ view: WeatherVideoPlayerView, coordinator: ()) { view.stop() }
}

@MainActor
private final class WeatherVideoPlayerView: NSView {
    private let movieLayer = AVPlayerLayer()
    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        movieLayer.videoGravity = .resizeAspectFill
        movieLayer.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        layer?.addSublayer(movieLayer)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        movieLayer.frame = bounds
        CATransaction.commit()
    }

    func play(_ url: URL) {
        guard url.isFileURL, currentURL != url else { return }
        stop()
        currentURL = url
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        queue = player
        movieLayer.player = player
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
    }

    func stop() {
        queue?.pause()
        looper?.disableLooping()
        looper = nil
        queue?.removeAllItems()
        movieLayer.player = nil
        queue = nil
        currentURL = nil
    }
}
