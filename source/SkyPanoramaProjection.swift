import Foundation
import CoreGraphics

/// A schematic 360-degree panorama, not a device-heading or camera projection.
/// All bodies share the same sky rectangle: N—E—S—W—N horizontally, and
/// horizon—zenith vertically. Keeping the horizon in the upper sky avoids
/// placing a low Sun underneath the weather-detail cards.
struct SkyPanoramaProjection {
    let bounds: CGRect

    init(width: Double, height: Double, compact: Bool = false) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            bounds = .zero
            return
        }
        let inset = min(20, width * 0.07)
        let top = compact ? height * 0.16 : min(48, height * 0.13)
        let horizon = compact ? height * 0.84 : min(192, height * 0.34)
        bounds = CGRect(x: inset, y: top, width: max(0, width - inset * 2),
                        height: max(0, horizon - top))
    }

    func point(altitudeDegrees: Double, azimuthDegrees: Double) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0,
              altitudeDegrees.isFinite, azimuthDegrees.isFinite,
              (0...90).contains(altitudeDegrees), (0...360).contains(azimuthDegrees) else { return nil }
        let azimuth = azimuthDegrees == 360 ? 0 : azimuthDegrees
        return CGPoint(x: bounds.minX + bounds.width * azimuth / 360,
                       y: bounds.maxY - bounds.height * altitudeDegrees / 90)
    }

    /// A daylight fade for the marker, not a prediction of unaided-eye
    /// visibility. Weather, light pollution and atmospheric extinction vary.
    static func starVisibility(sunAltitudeDegrees: Double) -> Double {
        guard sunAltitudeDegrees.isFinite, sunAltitudeDegrees < 0 else { return 0 }
        return min(1, max(0, -sunAltitudeDegrees / 16))
    }

    /// One soft emphasis at opening/selection. Static and elapsed scenes do not
    /// flicker, and this never changes the body's astronomical position.
    static func openingPulse(elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0.25, elapsed < 2.65 else { return 0 }
        return pow(sin(.pi * (elapsed - 0.25) / 2.4), 2)
    }
}
