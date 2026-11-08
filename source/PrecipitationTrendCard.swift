import SwiftUI

struct PrecipitationTrendCard: View {
    let snapshot: WeatherSnapshot
    let now: Date
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.38, green: 0.77, blue: 0.96)
            : Color(red: 0.08, green: 0.40, blue: 0.65)
    }

    var body: some View {
        let trend = PrecipitationTrend(snapshot: snapshot, now: now)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("降水趋势", systemImage: "cloud.rain")
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text("小时预报")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary)

            Text(trend.headline)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            if trend.isAvailable {
                chart(trend.hours)
            }

            Text(trend.detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .weatherGlassCard()
    }

    private func chart(_ hours: [WeatherHour]) -> some View {
        let ceiling = max(0.5, hours.compactMap(\.precipitation).max() ?? 0.5)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                ForEach(hours) { hour in
                    let value = hour.precipitation
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            VStack {
                                Rectangle().fill(.secondary.opacity(0.12)).frame(height: 0.5)
                                Spacer()
                                Rectangle().fill(.secondary.opacity(0.12)).frame(height: 0.5)
                                Spacer()
                                Rectangle().fill(.secondary.opacity(0.24)).frame(height: 0.5)
                            }
                            VStack(spacing: 3) {
                                Text(amountText(value))
                                    .font(.system(size: 9, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(value == nil ? Color.secondary : accent)
                                if let value, value > 0 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(LinearGradient(colors: [accent.opacity(0.75), accent],
                                                             startPoint: .top, endPoint: .bottom))
                                        .frame(width: 13, height: max(3, 33 * value / ceiling))
                                } else {
                                    Capsule()
                                        .fill(value == nil ? Color.clear : accent.opacity(0.4))
                                        .frame(width: 13, height: 2)
                                }
                            }
                            .padding(.bottom, 1)
                        }
                        .frame(height: 50)
                        Text(clockLabel(hour.time))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(PrecipitationTrend.intervalLabel(for: hour, relativeTo: now, in: snapshot.locationTimeZone))，预计降水量\(value.map { "\(amountText($0))毫米" } ?? "暂缺")")
                    .help("\(PrecipitationTrend.intervalLabel(for: hour, relativeTo: now, in: snapshot.locationTimeZone))：\(value.map { "\(amountText($0)) mm" } ?? "数据暂缺")")
                }
            }
            Text("截至标注时刻的1小时降水量 · mm")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func amountText(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value > 0 && value < 0.1 { return "<0.1" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func clockLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = snapshot.locationTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
