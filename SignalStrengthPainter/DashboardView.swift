import SwiftUI

struct DashboardView: View {
    var onStartSurvey: (() -> Void)?

    @StateObject private var speedTest = SpeedTestManager()

    @State private var latestLatencyMs: Double?
    @State private var latencyHistory: [Double] = []
    @State private var isTesting = false
    @State private var testDate: Date?
    @State private var pingCount = 0
    @State private var serviceLatencies: [String: Double] = [:]

    private let probe = LatencyProbe()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                wifiHeader
                    .padding(.top, 8)

                topologyCard
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                sectionHeader("Speed Test")
                    .padding(.top, 28)
                    .padding(.horizontal, 20)

                speedTestCard
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                speedTestButton
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                sectionHeader("Latency Test", trailing: latencyHistory.isEmpty ? nil : "All Results")
                    .padding(.top, 28)
                    .padding(.horizontal, 20)

                latencyResultCard
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                testButton
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                sectionHeader("Network Latency")
                    .padding(.top, 28)
                    .padding(.horizontal, 20)

                serviceLatencyGrid
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                surveyCard
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea())
    }

    // MARK: - WiFi Header

    private var wifiHeader: some View {
        VStack(spacing: 4) {
            Image(systemName: "wifi")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.blue)
            Text("Wi-Fi")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Network Topology

    private var topologyCard: some View {
        HStack(spacing: 0) {
            topologyNode(
                icon: "globe",
                iconColor: .blue,
                label: "ISP",
                detail: "Internet",
                status: ("Available", Color(red: 0.25, green: 0.86, blue: 0.43))
            )

            topologyConnector

            topologyNode(
                icon: "wifi.router",
                iconColor: .white.opacity(0.8),
                label: "Router",
                detail: "192.168.0.1"
            )

            topologyConnector

            topologyNode(
                icon: "iphone",
                iconColor: Color(red: 0.25, green: 0.86, blue: 0.43),
                label: "Your iPhone",
                detail: "Connected",
                status: nil
            )
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func topologyNode(
        icon: String,
        iconColor: Color,
        label: String,
        detail: String,
        status: (String, Color)? = nil
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)

            if let status {
                Text(status.0)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(status.1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var topologyConnector: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.5), .blue.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .overlay(
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(.blue.opacity(0.6))
                                .frame(width: 3, height: 3)
                        }
                    }
                )
        }
        .frame(width: 36)
        .offset(y: -12)
    }

    // MARK: - Section Headers

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            if let trailing {
                Button(trailing) {}
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Latency Result Card

    private var latencyResultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let latestLatencyMs {
                HStack {
                    Text("Internet \u{2192} Your iPhone")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    if let testDate {
                        Text(formattedTime(testDate))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(latestLatencyMs))")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("ms")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(qualityLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(qualityColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(qualityColor.opacity(0.15))
                        )

                    Spacer()
                }

                if latencyHistory.count > 1 {
                    sparklineChart
                        .frame(height: 56)
                        .padding(.top, 4)
                }
            } else {
                emptyLatencyState
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var emptyLatencyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "network")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.15))
            Text("No test results yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("Tap the button below to measure\nyour network latency")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Sparkline

    private var sparklineChart: some View {
        Canvas { context, size in
            guard latencyHistory.count > 1 else { return }

            let minVal = max(0, (latencyHistory.min() ?? 0) - 5)
            let maxVal = (latencyHistory.max() ?? 100) + 5
            let range = max(maxVal - minVal, 1)
            let stepX = size.width / CGFloat(latencyHistory.count - 1)

            var linePath = Path()
            var fillPath = Path()

            for (index, value) in latencyHistory.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = (value - minVal) / range
                let y = size.height - CGFloat(normalized) * size.height

                if index == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    fillPath.move(to: CGPoint(x: 0, y: size.height))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let prevX = CGFloat(index - 1) * stepX
                    let midX = (prevX + x) / 2
                    let prevVal = latencyHistory[index - 1]
                    let prevNorm = (prevVal - minVal) / range
                    let prevY = size.height - CGFloat(prevNorm) * size.height
                    linePath.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: midX, y: prevY),
                        control2: CGPoint(x: midX, y: y)
                    )
                    fillPath.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: midX, y: prevY),
                        control2: CGPoint(x: midX, y: y)
                    )
                }
            }

            let lastX = CGFloat(latencyHistory.count - 1) * stepX
            fillPath.addLine(to: CGPoint(x: lastX, y: size.height))
            fillPath.closeSubpath()

            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.cyan.opacity(0.25),
                        Color.blue.opacity(0.08),
                        Color.clear,
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(
                linePath,
                with: .linearGradient(
                    Gradient(colors: [.cyan, .blue]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: 2.5
            )

            if let lastValue = latencyHistory.last {
                let lastNorm = (lastValue - minVal) / range
                let lastY = size.height - CGFloat(lastNorm) * size.height
                let dotCenter = CGPoint(x: lastX, y: lastY)
                let outerDot = Path(ellipseIn: CGRect(
                    x: dotCenter.x - 5, y: dotCenter.y - 5, width: 10, height: 10
                ))
                let innerDot = Path(ellipseIn: CGRect(
                    x: dotCenter.x - 3, y: dotCenter.y - 3, width: 6, height: 6
                ))
                context.fill(outerDot, with: .color(.blue.opacity(0.4)))
                context.fill(innerDot, with: .color(.white))
            }
        }
    }

    // MARK: - Test Button

    private var testButton: some View {
        Button {
            startLatencyTest()
        } label: {
            HStack(spacing: 8) {
                if isTesting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                    Text("Testing... \(pingCount)/10")
                } else {
                    Image(systemName: "bolt.fill")
                    Text("Start Latency Test")
                }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: isTesting
                                ? [Color.blue.opacity(0.5), Color.blue.opacity(0.4)]
                                : [Color.blue, Color.blue.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .disabled(isTesting)
    }

    // MARK: - Service Latency Grid

    private var serviceLatencyGrid: some View {
        HStack(spacing: 10) {
            serviceLatencyTile(label: "Google", host: "8.8.8.8", icon: "magnifyingglass", iconBg: .blue)
            serviceLatencyTile(label: "Cloudflare", host: "1.1.1.1", icon: "shield.fill", iconBg: .orange)
            serviceLatencyTile(label: "OpenDNS", host: "208.67.222.222", icon: "server.rack", iconBg: .purple)
            serviceLatencyTile(label: "Gateway", host: "192.168.0.1", icon: "wifi.router", iconBg: .green)
        }
    }

    private func serviceLatencyTile(label: String, host: String, icon: String, iconBg: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconBg.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(iconBg)
            }

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            if let ms = serviceLatencies[host] {
                Text("\(Int(ms))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Text("--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Survey Card

    private var surveyCard: some View {
        Button {
            onStartSurvey?()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "map.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Map Your WiFi Coverage")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Walk your space to paint signal quality onto a floor plan using AR")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speed Test Card

    private var speedTestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if speedTest.isTesting {
                activeSpeedTestContent
            } else if speedTest.phase == .complete {
                completedSpeedTestContent
            } else {
                emptySpeedTestContent
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var emptySpeedTestContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.15))
            Text("No speed test results yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("Tap the button below to measure\nyour download and upload speeds")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var activeSpeedTestContent: some View {
        VStack(spacing: 16) {
            HStack {
                speedTestPhaseIcon
                Text(speedTestPhaseLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(speedTestPhaseColor)
                Spacer()
            }

            if speedTest.phase == .latency {
                VStack(spacing: 8) {
                    if speedTest.pingMs > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(speedTest.pingMs))")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("ms")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    } else {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                            .padding(.vertical, 12)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatSpeed(speedTest.currentSpeed))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: formatSpeed(speedTest.currentSpeed))
                        Text("Mbps")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)

                    if speedTest.speedSamples.count > 1 {
                        speedSparkline
                            .frame(height: 60)
                    }
                }
            }

            speedTestPhaseIndicator

            ProgressView(value: speedTest.progress)
                .tint(speedTestPhaseColor)
        }
    }

    private var completedSpeedTestContent: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Internet \u{2192} Your iPhone")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if let date = speedTest.testDate {
                    Text(formattedTime(date))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            HStack(spacing: 12) {
                speedResultTile(
                    direction: "Download",
                    icon: "arrow.down",
                    speed: speedTest.downloadSpeed,
                    color: .cyan
                )
                speedResultTile(
                    direction: "Upload",
                    icon: "arrow.up",
                    speed: speedTest.uploadSpeed,
                    color: Color(red: 0.25, green: 0.86, blue: 0.43)
                )
            }

            HStack(spacing: 24) {
                speedStatBadge(label: "Ping", value: "\(Int(speedTest.pingMs)) ms")
                speedStatBadge(label: "Jitter", value: "\(Int(speedTest.jitterMs)) ms")
                Spacer()
            }
        }
    }

    private func speedResultTile(direction: String, icon: String, speed: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text(direction)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatSpeed(speed))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Mbps")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(color.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func speedStatBadge(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Speed Test Sparkline

    private var speedSparkline: some View {
        Canvas { context, size in
            let samples = speedTest.speedSamples
            guard samples.count > 1 else { return }

            let maxVal = (samples.max() ?? 1) * 1.1
            guard maxVal > 0 else { return }
            let stepX = size.width / CGFloat(samples.count - 1)

            var linePath = Path()
            var fillPath = Path()

            for (i, val) in samples.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - (val / maxVal) * size.height

                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    fillPath.move(to: CGPoint(x: 0, y: size.height))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let prevX = CGFloat(i - 1) * stepX
                    let prevVal = samples[i - 1]
                    let prevY = size.height - (prevVal / maxVal) * size.height
                    let midX = (prevX + x) / 2
                    linePath.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: midX, y: prevY),
                        control2: CGPoint(x: midX, y: y)
                    )
                    fillPath.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: midX, y: prevY),
                        control2: CGPoint(x: midX, y: y)
                    )
                }
            }

            let lastX = CGFloat(samples.count - 1) * stepX
            fillPath.addLine(to: CGPoint(x: lastX, y: size.height))
            fillPath.closeSubpath()

            let isDownload = speedTest.phase == .download
            let baseColor: Color = isDownload ? .cyan : Color(red: 0.25, green: 0.86, blue: 0.43)

            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [
                        baseColor.opacity(0.3),
                        baseColor.opacity(0.08),
                        .clear,
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(
                linePath,
                with: .linearGradient(
                    Gradient(colors: [baseColor, baseColor.opacity(0.6)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: 2.5
            )

            if let lastVal = samples.last {
                let lastY = size.height - (lastVal / maxVal) * size.height
                let center = CGPoint(x: lastX, y: lastY)
                let outer = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
                let inner = Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
                context.fill(outer, with: .color(baseColor.opacity(0.4)))
                context.fill(inner, with: .color(.white))
            }
        }
    }

    // MARK: - Speed Test Phase UI

    private var speedTestPhaseIndicator: some View {
        HStack(spacing: 20) {
            speedTestPhaseStep(
                "Ping",
                isActive: speedTest.phase == .latency,
                isDone: speedTest.phase == .download || speedTest.phase == .upload || speedTest.phase == .complete
            )
            speedTestPhaseStep(
                "Download",
                isActive: speedTest.phase == .download,
                isDone: speedTest.phase == .upload || speedTest.phase == .complete
            )
            speedTestPhaseStep(
                "Upload",
                isActive: speedTest.phase == .upload,
                isDone: speedTest.phase == .complete
            )
        }
    }

    private func speedTestPhaseStep(_ label: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? speedTestPhaseColor : isDone ? Color(red: 0.25, green: 0.86, blue: 0.43) : .white.opacity(0.2))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var speedTestPhaseIcon: some View {
        switch speedTest.phase {
        case .latency:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        case .download:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        case .upload:
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        default:
            Image(systemName: "bolt.fill")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        }
    }

    private var speedTestPhaseLabel: String {
        switch speedTest.phase {
        case .idle: return ""
        case .latency: return "Measuring Ping..."
        case .download: return "Downloading..."
        case .upload: return "Uploading..."
        case .complete: return "Complete"
        }
    }

    private var speedTestPhaseColor: Color {
        switch speedTest.phase {
        case .latency: return .yellow
        case .download: return .cyan
        case .upload: return Color(red: 0.25, green: 0.86, blue: 0.43)
        case .complete: return Color(red: 0.25, green: 0.86, blue: 0.43)
        default: return .blue
        }
    }

    // MARK: - Speed Test Button

    private var speedTestButton: some View {
        Button {
            if speedTest.isTesting {
                speedTest.cancelTest()
            } else {
                speedTest.startTest()
            }
        } label: {
            HStack(spacing: 8) {
                if speedTest.isTesting {
                    Image(systemName: "stop.fill")
                    Text("Stop Test")
                } else if speedTest.phase == .complete {
                    Image(systemName: "arrow.clockwise")
                    Text("Test Again")
                } else {
                    Image(systemName: "bolt.fill")
                    Text("Start Speed Test")
                }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: speedTest.isTesting
                                ? [.red.opacity(0.7), .red.opacity(0.5)]
                                : [.blue, .blue.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
    }

    // MARK: - Speed Formatting

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 100 { return "\(Int(mbps))" }
        if mbps >= 10 { return String(format: "%.1f", mbps) }
        if mbps > 0 { return String(format: "%.2f", mbps) }
        return "0"
    }

    // MARK: - Helpers

    private var qualityLabel: String {
        guard let ms = latestLatencyMs else { return "Unknown" }
        if ms < 50 { return "Excellent" }
        if ms <= 150 { return "Good" }
        return "Poor"
    }

    private var qualityColor: Color {
        guard let ms = latestLatencyMs else { return .gray }
        if ms < 50 { return Color(red: 0.25, green: 0.86, blue: 0.43) }
        if ms <= 150 { return Color(red: 0.98, green: 0.78, blue: 0.28) }
        return Color(red: 0.98, green: 0.39, blue: 0.34)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy, h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Test Logic

    private func startLatencyTest() {
        guard !isTesting else { return }
        isTesting = true
        pingCount = 0
        latencyHistory = []
        testDate = Date()
        serviceLatencies = [:]
        runNextPing()
    }

    private func runNextPing() {
        guard pingCount < 10 else {
            isTesting = false
            if !latencyHistory.isEmpty {
                latestLatencyMs = latencyHistory.reduce(0, +) / Double(latencyHistory.count)
            }
            testServiceLatencies()
            return
        }

        probe.measureLatency { value in
            pingCount += 1
            if let value {
                latencyHistory.append(value)
                latestLatencyMs = value
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                runNextPing()
            }
        }
    }

    private func testServiceLatencies() {
        let targets: [(String, UInt16)] = [
            ("8.8.8.8", 53),
            ("1.1.1.1", 53),
            ("208.67.222.222", 53),
            ("192.168.0.1", 80),
        ]

        for (host, port) in targets {
            probe.measureLatency(host: host, port: port) { value in
                if let value {
                    serviceLatencies[host] = value
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .preferredColorScheme(.dark)
}
