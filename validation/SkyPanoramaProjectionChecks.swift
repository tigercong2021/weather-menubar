import Foundation
import CoreGraphics

@main
enum SkyPanoramaProjectionChecks {
    static func main() {
        let sky = SkyPanoramaProjection(width: 348, height: 800)
        let north = sky.point(altitudeDegrees: 0, azimuthDegrees: 0)!
        let east = sky.point(altitudeDegrees: 0, azimuthDegrees: 90)!
        let south = sky.point(altitudeDegrees: 0, azimuthDegrees: 180)!
        let west = sky.point(altitudeDegrees: 0, azimuthDegrees: 270)!
        precondition(north.x < east.x && east.x < south.x && south.x < west.x)
        precondition(north.y == east.y && east.y == south.y && south.y == west.y)
        precondition(north.y == 192, "Low-altitude bodies must stay above AQI and precipitation cards")
        precondition(sky.point(altitudeDegrees: 0, azimuthDegrees: 360) == north)
        let zenith = sky.point(altitudeDegrees: 90, azimuthDegrees: 180)!
        let halfway = sky.point(altitudeDegrees: 45, azimuthDegrees: 180)!
        precondition(zenith.x == south.x && zenith.y < halfway.y && halfway.y < south.y)
        precondition(zenith.y == 48)
        precondition(abs(halfway.y - (zenith.y + south.y) / 2) < 1e-9)
        precondition(abs(south.x - 174) < 1e-9)
        for invalid in [-0.01, 90.01, Double.nan, .infinity] {
            precondition(sky.point(altitudeDegrees: invalid, azimuthDegrees: 90) == nil)
        }
        for invalid in [-1, 361, Double.nan, .infinity] {
            precondition(sky.point(altitudeDegrees: 30, azimuthDegrees: invalid) == nil)
        }
        precondition(SkyPanoramaProjection(width: 0, height: 800).point(altitudeDegrees: 30, azimuthDegrees: 90) == nil)
        let compact = SkyPanoramaProjection(width: 348, height: 96, compact: true)
        precondition(compact.bounds.minY > 0 && compact.bounds.maxY < 96)
        precondition(abs(compact.bounds.maxY - 96 * 0.84) < 1e-9)
        let short = SkyPanoramaProjection(width: 348, height: 400)
        precondition(short.bounds.maxY == 136)
        precondition(SkyPanoramaProjection.starVisibility(sunAltitudeDegrees: 10) == 0)
        precondition(SkyPanoramaProjection.starVisibility(sunAltitudeDegrees: 0) == 0)
        precondition(SkyPanoramaProjection.starVisibility(sunAltitudeDegrees: -8) == 0.5)
        precondition(SkyPanoramaProjection.starVisibility(sunAltitudeDegrees: -18) == 1)
        precondition(SkyPanoramaProjection.openingPulse(elapsed: 0) == 0)
        precondition(SkyPanoramaProjection.openingPulse(elapsed: 1.45) > 0.99)
        precondition(SkyPanoramaProjection.openingPulse(elapsed: 3) == 0)
        precondition(SkyPanoramaProjection.openingPulse(elapsed: 30) == 0)
        print("PASS: shared N/E/S/W panorama, linear true altitude, horizon rejection, compact bounds, daylight fade, and one opening pulse")
    }
}
