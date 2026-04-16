import SwiftUI

struct DeviceDiscoveryView: View {
    @Environment(\.theme) private var theme
    @StateObject private var scanner = NetworkScanner()
    @State private var selectedDevice: DiscoveredDevice?
    @State private var showTrustConfirm = false
    @State private var deviceToTrust: DiscoveredDevice?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                    .padding(.top, 20)

                networkInfoCard
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                scanButton
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                if scanner.isScanning {
                    scanProgressSection
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                }

                if !scanner.devices.isEmpty {
                    deviceSummary
                        .padding(.top, 24)
                        .padding(.horizontal, 20)

                    deviceList
                        .padding(.top, 14)
                        .padding(.horizontal, 20)

                    securityAssessment
                        .padding(.top, 24)
                        .padding(.horizontal, 20)
                }

                securityTips
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(item: $selectedDevice) { device in
            DeviceDetailSheet(device: device) { ip, trusted in
                scanner.setTrusted(ip, trusted: trusted)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Device Discovery")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text("See who's connected to your network")
                .font(.system(size: 15))
                .foregroundStyle(theme.tertiaryText)
        }
    }

    // MARK: - Network Info Card

    private var networkInfoCard: some View {
        HStack(spacing: 16) {
            networkInfoItem(icon: "wifi", label: "Your IP", value: scanner.localIP)
            dividerLine
            networkInfoItem(icon: "network", label: "Subnet", value: scanner.subnetMask)
            dividerLine
            networkInfoItem(icon: "desktopcomputer", label: "Devices", value: scanner.devices.isEmpty ? "—" : "\(scanner.devices.count)")
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.subtle, lineWidth: 1)
                )
        )
    }

    private func networkInfoItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(width: 1, height: 40)
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        Button {
            if scanner.isScanning {
                scanner.stopScan()
            } else {
                scanner.startScan()
            }
        } label: {
            HStack(spacing: 8) {
                if scanner.isScanning {
                    Image(systemName: "stop.fill")
                    Text("Stop Scan")
                } else if !scanner.devices.isEmpty {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan Again")
                } else {
                    Image(systemName: "magnifyingglass")
                    Text("Scan Network")
                }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(theme.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: scanner.isScanning
                                ? [.red.opacity(0.7), .red.opacity(0.5)]
                                : [.blue, .blue.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
    }

    // MARK: - Scan Progress

    private var scanProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .tint(.blue)
                    .scaleEffect(0.9)
                Text(scanner.scanStatusMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            }

            ProgressView(value: scanner.scanProgress)
                .tint(.blue)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Device Summary

    private var deviceSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected Devices")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(scanner.devices.count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
            }

            deviceTypeSummaryRow
        }
    }

    private var deviceTypeSummaryRow: some View {
        let grouped = Dictionary(grouping: scanner.devices, by: { $0.deviceType })
        let sortedTypes = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedTypes, id: \.rawValue) { type in
                    let count = grouped[type]?.count ?? 0
                    HStack(spacing: 5) {
                        Image(systemName: type.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(type.color)
                        Text("\(count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(type.color.opacity(0.1))
                            .overlay(Capsule().stroke(type.color.opacity(0.2), lineWidth: 1))
                    )
                }
            }
        }
    }

    // MARK: - Device List

    private var deviceList: some View {
        VStack(spacing: 8) {
            ForEach(scanner.devices) { device in
                Button {
                    selectedDevice = device
                } label: {
                    deviceRow(device)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(device.deviceType.color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: device.deviceType.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(device.deviceType.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(deviceDisplayName(device))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    if device.isCurrentDevice {
                        Text("YOU")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.2)))
                    }

                    if device.isTrusted {
                        Text("TRUSTED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 0.25, green: 0.86, blue: 0.43))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(red: 0.25, green: 0.86, blue: 0.43).opacity(0.2)))
                    }
                }

                HStack(spacing: 8) {
                    Text(device.ipAddress)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)

                    if let latency = device.latencyMs {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(latencyColor(latency))
                                .frame(width: 5, height: 5)
                            Text("\(Int(latency)) ms")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                }

                if let hostname = device.displayHostname,
                   hostname != deviceDisplayName(device) {
                    Text(hostname)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                if !device.services.isEmpty {
                    Text(device.services.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(device.deviceType.color.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.quaternaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(device.isTrusted ? Color(red: 0.25, green: 0.86, blue: 0.43).opacity(0.3) : theme.cardStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Security Assessment

    private var securityAssessment: some View {
        let unknownUntrustedCount = scanner.devices.filter { $0.deviceType == .unknown && !$0.isTrusted }.count
        let trustedCount = scanner.devices.filter { $0.isTrusted }.count
        let totalCount = scanner.devices.count
        let identifiedCount = totalCount - unknownUntrustedCount - trustedCount
        let level = securityLevel(total: totalCount, unknown: unknownUntrustedCount)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: level.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(level.color)
                Text("Network Assessment")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(level.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(level.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(level.color.opacity(0.15)))
            }

            Text(level.message(total: totalCount, unknown: unknownUntrustedCount))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                assessmentStat(value: "\(totalCount)", label: "Total", color: .blue)
                assessmentStat(value: "\(identifiedCount)", label: "Identified", color: Color(red: 0.25, green: 0.86, blue: 0.43))
                if trustedCount > 0 {
                    assessmentStat(value: "\(trustedCount)", label: "Trusted", color: .cyan)
                }
                assessmentStat(value: "\(unknownUntrustedCount)", label: "Unknown", color: unknownUntrustedCount > 0 ? Color(red: 0.98, green: 0.78, blue: 0.28) : .gray)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(level.color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func assessmentStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.06))
        )
    }

    // MARK: - Security Tips

    private var securityTips: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Protect Your Network")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.primaryText)

            tipRow(icon: "lock.shield.fill", color: .blue,
                   text: "Change your Wi-Fi password if you see unknown devices")
            tipRow(icon: "key.fill", color: .orange,
                   text: "Use WPA3 encryption if your router supports it")
            tipRow(icon: "eye.slash.fill", color: .purple,
                   text: "Hide your network name (SSID) from broadcasting")
            tipRow(icon: "arrow.triangle.2.circlepath", color: Color(red: 0.25, green: 0.86, blue: 0.43),
                   text: "Regularly scan to spot new or unauthorized devices")
            tipRow(icon: "person.badge.minus", color: .red,
                   text: "Use your router's admin page to block unknown devices")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.cardStroke, lineWidth: 1)
                    )
        )
    }

    private func tipRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func deviceDisplayName(_ device: DiscoveredDevice) -> String {
        if device.isCurrentDevice { return "This iPhone" }
        if device.deviceType == .router { return "Router / Gateway" }
        if let name = device.bonjourName, !name.isEmpty { return name }
        if let hostname = device.hostname, !hostname.isEmpty, hostname != device.ipAddress { return hostname }
        return device.deviceType.rawValue
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 10 { return Color(red: 0.25, green: 0.86, blue: 0.43) }
        if ms < 50 { return Color(red: 0.98, green: 0.78, blue: 0.28) }
        return Color(red: 0.98, green: 0.39, blue: 0.34)
    }

    private struct SecurityLevel {
        let label: String
        let icon: String
        let color: Color
        let messageBuilder: (Int, Int) -> String

        func message(total: Int, unknown: Int) -> String {
            messageBuilder(total, unknown)
        }
    }

    private func securityLevel(total: Int, unknown: Int) -> SecurityLevel {
        if unknown == 0 {
            return SecurityLevel(
                label: "Looks Good",
                icon: "checkmark.shield.fill",
                color: Color(red: 0.25, green: 0.86, blue: 0.43)
            ) { total, _ in
                "All \(total) device\(total == 1 ? "" : "s") on your network appear to be identifiable. Keep scanning regularly to stay on top of any new connections."
            }
        } else if unknown <= 2 {
            return SecurityLevel(
                label: "Review",
                icon: "exclamationmark.shield.fill",
                color: Color(red: 0.98, green: 0.78, blue: 0.28)
            ) { _, unknown in
                "\(unknown) unknown device\(unknown == 1 ? "" : "s") detected. This could be a smart home gadget or something you don't recognize. Tap on unknown devices for details."
            }
        } else {
            return SecurityLevel(
                label: "Attention",
                icon: "xmark.shield.fill",
                color: Color(red: 0.98, green: 0.39, blue: 0.34)
            ) { _, unknown in
                "\(unknown) unknown devices found on your network. Consider changing your Wi-Fi password and reviewing your router's connected device list."
            }
        }
    }
}

// MARK: - Device Detail Sheet

struct DeviceDetailSheet: View {
    let device: DiscoveredDevice
    var onToggleTrust: ((String, Bool) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showTrustConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(device.deviceType.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: device.deviceType.icon)
                    .font(.system(size: 34))
                    .foregroundStyle(device.deviceType.color)
            }
            .padding(.top, 24)

            Text(displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .padding(.top, 16)

            HStack(spacing: 6) {
                Text(device.deviceType.rawValue)
                    .font(.system(size: 14))
                    .foregroundStyle(device.deviceType.color)

                if device.isTrusted {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10))
                        Text("Trusted")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.25, green: 0.86, blue: 0.43))
                }
            }
            .padding(.top, 4)

            VStack(spacing: 0) {
                detailRow(label: "IP Address", value: device.ipAddress)

                if let hostname = device.displayHostname {
                    Divider().overlay(theme.divider)
                    detailRow(label: "Device Name", value: hostname)
                }

                Divider().overlay(theme.divider)
                detailRow(label: "Response Time", value: device.latencyMs.map { "\(Int($0)) ms" } ?? "—")
                Divider().overlay(theme.divider)
                detailRow(label: "First Seen", value: formattedTime(device.firstSeen))

                if !device.services.isEmpty {
                    Divider().overlay(theme.divider)
                    detailRow(label: "Services", value: device.services.joined(separator: ", "))
                }

                if device.isCurrentDevice {
                    Divider().overlay(theme.divider)
                    detailRow(label: "Status", value: "This is your device")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(theme.cardStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.top, 24)

            if !device.isCurrentDevice {
                trustButton
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .background(theme.background.ignoresSafeArea())
        .confirmationDialog(
            device.isTrusted ? "Remove trust for this device?" : "Trust this device?",
            isPresented: $showTrustConfirmation,
            titleVisibility: .visible
        ) {
            Button(device.isTrusted ? "Remove Trust" : "Trust Device", role: device.isTrusted ? .destructive : nil) {
                onToggleTrust?(device.ipAddress, !device.isTrusted)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(device.isTrusted
                 ? "This device will be counted as unknown again in your network assessment."
                 : "Only trust devices you recognize. Trusted devices won't be flagged in your network security assessment.")
        }
    }

    private var trustButton: some View {
        Button {
            showTrustConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: device.isTrusted ? "shield.slash" : "checkmark.shield.fill")
                Text(device.isTrusted ? "Remove Trust" : "Trust This Device")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(device.isTrusted ? Color(red: 0.98, green: 0.39, blue: 0.34) : Color(red: 0.25, green: 0.86, blue: 0.43))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(device.isTrusted
                          ? Color(red: 0.98, green: 0.39, blue: 0.34).opacity(0.1)
                          : Color(red: 0.25, green: 0.86, blue: 0.43).opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(device.isTrusted
                                    ? Color(red: 0.98, green: 0.39, blue: 0.34).opacity(0.3)
                                    : Color(red: 0.25, green: 0.86, blue: 0.43).opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(theme.tertiaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }

    private var displayName: String {
        if device.isCurrentDevice { return "This iPhone" }
        if device.deviceType == .router { return "Router / Gateway" }
        if let name = device.bonjourName, !name.isEmpty { return name }
        if let hostname = device.hostname, !hostname.isEmpty { return hostname }
        return device.deviceType.rawValue
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

#Preview {
    DeviceDiscoveryView()
        .withAppTheme()
}
