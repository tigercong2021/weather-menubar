import SwiftUI

/// A continuous, locally weighted color ribbon with fixed US AQI meanings.
struct AirQualityIndexLine: View {
    let reading: AirQualityReading?
    let now: Date
    var isLoading = false
    var isUnavailable = false
    var history: AirQualityHistoryProfile?

    private var validReading: AirQualityReading? {
        reading.flatMap { $0.age(at: now) < 6 * 3600 ? $0 : nil }
    }

    private var stale: Bool { (validReading?.age(at: now) ?? .infinity) >= 2 * 3600 }

    private var validHistory: AirQualityHistoryProfile? {
        guard let coordinate = reading?.place.coordinate,
              let history, history.isCurrent(for: coordinate, at: now) else { return nil }
        return history
    }

    private var scale: AirQualityScale { AirQualityScale(gradeFractions: validHistory?.gradeFractions) }

    private var colorStops: [Gradient.Stop] {
        scale.colorStops.map {
            .init(color: Color(red: $0.red, green: $0.green, blue: $0.blue), location: CGFloat($0.location))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("空气质量 · AQI")
                Spacer()
                Text(categoryLabel)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            GeometryReader { geometry in
                let width = max(0, geometry.size.width)
                let value = validReading?.aqi
                let position = CGFloat(scale.position(for: value) ?? 0)
                // Match the gradient's full-width coordinate system; only inset
                // the endpoints enough to keep the seven-point marker in view.
                let x = min(max(4, position * width), max(4, width - 4))
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(LinearGradient(stops: colorStops, startPoint: .leading, endPoint: .trailing))
                        .saturation(stale ? 0 : 1)
                        .opacity(value == nil ? 0.25 : stale ? 0.45 : 0.95)
                        .frame(height: 4)
                        .offset(y: 25)
                    if let value {
                        Text("\(value)")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 36, height: 13)
                            .position(x: min(max(18, x), max(18, width - 18)), y: 7)
                        Rectangle().fill(.primary.opacity(0.75))
                            .frame(width: 1, height: 7)
                            .position(x: x, y: 19)
                        Circle().fill(.white)
                            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                            .frame(width: 7, height: 7)
                            .position(x: x, y: 27)
                    }
                }
            }
            .frame(height: 32)
        }
        .padding(.horizontal, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .help(helpText)
    }

    private var helpText: String {
        let layout: String
        if let history = validHistory {
            layout = "色带按过去12个完整月份的模型AQI分布调整；平均 \(Int(history.meanAQI.rounded()))，有效小时占比 \(Int((history.coverage * 100).rounded()))%。等级阈值不变。"
        } else {
            layout = "当前使用通用色带；历史数据完整后按主城分布调整。等级阈值不变。"
        }
        return "美国 AQI 口径 · CAMS / Open-Meteo 模型估计。" + layout + (stale ? "当前为空气质量旧数据。" : "")
    }

    private var categoryLabel: String {
        if let category = validReading?.category { return category.label + (stale ? " · 旧数据" : "") }
        return isLoading ? "获取中" : isUnavailable ? "暂不可用" : "暂缺"
    }

    private var accessibilityLabel: String {
        guard let value = validReading?.aqi else { return "空气质量\(categoryLabel)" }
        return "当地空气质量指数\(value)，\(categoryLabel)，美国AQI口径"
    }
}
