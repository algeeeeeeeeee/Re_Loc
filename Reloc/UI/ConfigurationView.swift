import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Redesigned loopback & on-device pairing configuration (preserving the Reukix/retools 3-step structure
/// without any MFi identity UI) + PiP floating pairing guide + Roam-Control-style preferences.
struct ConfigurationView: View {
    @ObservedObject var viewModel: RelocViewModel
    @ObservedObject private var pairing = DevicePairingCoordinator.shared
    @ObservedObject private var pip = PairingPiPPresenter.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showImporter = false
    @State private var copiedPinToast = false

    private var serviceStateText: String {
        if viewModel.connectionVerified { return "Connected" }
        if viewModel.isVerifyingConnection { return "Verifying" }
        return viewModel.connectionCheckFailed ? "Connection Failed" : "Not Verified"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    heroHeaderCard
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section {
                    HStack(spacing: 12) {
                        SettingsIconBadge(systemName: "network", color: RelocTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("External Proxy Provides Local Loopback")
                                .font(.subheadline.weight(.semibold))
                            Text("Enable the loopback mapping for \(viewModel.host) in your proxy app, then complete pairing and verification below. Reloc does not create a VPN.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    stepSectionHeader(number: "01", title: "Loopback Connection")
                }

                Section {
                    HStack {
                        SettingsIconBadge(
                            systemName: viewModel.pairingStatus.isLoaded ? "checkmark.seal.fill" : "iphone.radiowaves.left.and.right",
                            color: viewModel.pairingStatus.isLoaded ? RelocTheme.emerald : RelocTheme.amber
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pairing Record")
                                .font(.subheadline.weight(.medium))
                            Text(viewModel.pairingStatus.isLoaded
                                 ? "Saved (\(viewModel.pairingStatus.kind?.rawValue ?? "")）"
                                 : "This iPhone Has Not Been Paired")
                                .font(.caption)
                                .foregroundStyle(viewModel.pairingStatus.isLoaded ? RelocTheme.emerald : .secondary)
                        }
                        Spacer()
                    }

                    if #available(iOS 27.0, *) {
                        if !pairing.isRunning {
                            Button {
                                RelocTheme.hapticMedium()
                                viewModel.startDevicePairing()
                            } label: {
                                HStack {
                                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                        .font(.subheadline.weight(.semibold))
                                    Text(viewModel.pairingStatus.isLoaded ? "Pair This iPhone Again" : "Pair This iPhone")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("Floating Guide")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(RelocTheme.accent.opacity(0.14), in: Capsule())
                                }
                            }
                            .disabled(viewModel.isVerifyingConnection || viewModel.snapshot.isRunning)
                        }
                    } else {
                        Text("Import an existing pairing file on this iOS version.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if pairing.isRunning || pairing.error != nil {
                        activePairingGuideCard
                    }

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Existing Pairing File", systemImage: "square.and.arrow.down")
                    }
                    .disabled(pairing.isRunning || viewModel.isVerifyingConnection || viewModel.snapshot.isRunning)

                    if viewModel.pairingStatus.isLoaded {
                        Button("移除已保存Pairing Record", role: .destructive) {
                            viewModel.removePairingFile()
                        }
                        .disabled(pairing.isRunning || viewModel.isVerifyingConnection || viewModel.snapshot.isRunning)
                    }
                } header: {
                    stepSectionHeader(number: "02", title: "Device Pairing")
                } footer: {
                    Text("Starting pairing automatically opens the floating Picture in Picture guide. Go to Settings → Privacy & Security → Developer Mode and tap “Pair with Reloc” to view the 6-digit code in the floating guide.")
                }

                Section {
                    HStack(spacing: 10) {
                        if viewModel.isVerifyingConnection {
                            ProgressView().controlSize(.small)
                        } else {
                            SettingsIconBadge(
                                systemName: viewModel.connectionVerified
                                    ? "checkmark"
                                    : (viewModel.connectionCheckFailed ? "exclamationmark" : "link"),
                                color: viewModel.connectionVerified
                                    ? RelocTheme.emerald
                                    : (viewModel.connectionCheckFailed ? RelocTheme.amber : .secondary)
                            )
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.deviceConnectionStatus)
                                .font(.subheadline.weight(.medium))
                                .textSelection(.enabled)
                            if let port = viewModel.discoveredDevicePort {
                                Text("Connected回环端口：\(port)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        RelocTheme.hapticLight()
                        viewModel.testConnection(silent: false)
                    } label: {
                        Label(
                            viewModel.connectionVerified ? "Recheck Connection" : "Test Device Connection",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(!viewModel.pairingStatus.isLoaded || viewModel.isVerifyingConnection || pairing.isRunning || viewModel.snapshot.isRunning)

                    if !viewModel.deviceUDID.isEmpty {
                        LabeledContent("Device UDID") {
                            Text(viewModel.deviceUDID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    stepSectionHeader(number: "03", title: "Connection Verification")
                } footer: {
                    Text("自动发现 Remote Pairing 服务并用Pairing Record验证广播身份，最终通过Device Service确认连接可用。")
                }

                Section("Location Options") {
                    Stepper(value: $viewModel.intervalSeconds, in: 1.0...10.0, step: 0.5) {
                        Label {
                            Text(String(format: "NMEA Send Interval · %.1f sec", viewModel.intervalSeconds))
                                .monospacedDigit()
                        } icon: {
                            SettingsIconBadge(systemName: "timer", color: RelocTheme.accent)
                        }
                    }

                    Picker(selection: $viewModel.durationSeconds) {
                        Text("Continuous").tag(0.0)
                        Text("60 sec").tag(60.0)
                        Text("180 sec").tag(180.0)
                        Text("600 sec").tag(600.0)
                        Text("1800 sec").tag(1800.0)
                    } label: {
                        Label {
                            Text("Session Duration")
                        } icon: {
                            SettingsIconBadge(systemName: "hourglass", color: .purple)
                        }
                    }

                    Toggle(isOn: $viewModel.gcj02CorrectionEnabled) {
                        Label {
                            Text("GCJ-02 Correction for Mainland China Maps")
                        } icon: {
                            SettingsIconBadge(systemName: "globe.asia.australia.fill", color: RelocTheme.emerald)
                        }
                    }

                    Toggle(isOn: $viewModel.microJitterEnabled) {
                        Label {
                            Text("Natural GPS Micro-Jitter (±0.6 m)")
                        } icon: {
                            SettingsIconBadge(systemName: "dot.radiowaves.left.and.right", color: RelocTheme.amber)
                        }
                    }

                    Toggle(isOn: $viewModel.backgroundKeepAliveEnabled) {
                        Label {
                            Text("Background Keep-Alive (Stay Connected While Switching Maps)")
                        } icon: {
                            SettingsIconBadge(systemName: "bolt.shield.fill", color: .teal)
                        }
                    }
                }

                Section {
                    Picker(selection: $viewModel.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    } label: {
                        Label {
                            Text("Appearance Theme")
                        } icon: {
                            SettingsIconBadge(systemName: "circle.lefthalf.filled", color: .gray)
                        }
                    }

                    Picker(selection: $viewModel.mapSource) {
                        ForEach(MapSource.allCases) { src in
                            Text(src.title).tag(src)
                        }
                    } label: {
                        Label {
                            Text("Map Source")
                        } icon: {
                            SettingsIconBadge(systemName: "globe.americas.fill", color: RelocTheme.accent)
                        }
                    }

                    if viewModel.mapSource == .appleNative {
                        Picker(selection: $viewModel.mapStyle) {
                            ForEach(MapDisplayStyle.allCases) { s in
                                Text(s.title).tag(s)
                            }
                        } label: {
                            Label {
                                Text("Apple Maps Style")
                            } icon: {
                                SettingsIconBadge(systemName: "map.fill", color: RelocTheme.accent)
                            }
                        }
                    }
                } header: {
                    Text("Map & Appearance")
                } footer: {
                    Text("Apple Maps (native MapKit) is used by default. For global WGS-84 maps without Amap labels, switch to Global Streets, OpenStreetMap, or Global Satellite.")
                }
            }
            .navigationTitle("Device Pairing与连接")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.importDiscoveredPairing()
                await viewModel.verifyConnectionIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.importDiscoveredPairing()
                    Task {
                        await viewModel.verifyConnectionIfNeeded()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                PairingDocumentPicker(
                    onPick: { url in
                        showImporter = false
                        viewModel.importPairingFile(url: url)
                    },
                    onCancel: {
                        showImporter = false
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private var heroHeaderCard: some View {
        let ready = viewModel.connectionVerified
        let accent: Color = ready ? RelocTheme.emerald : (viewModel.pairingStatus.isLoaded ? RelocTheme.amber : RelocTheme.accent)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: ready ? "checkmark.shield.fill" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(ready ? "Device Loopback Ready" : "Configure Local Loopback")
                        .font(.headline)
                    Text(ready ? "Return to the Location tab to set a fixed location" : "依次完成Loopback Connection、本机配对与Connection Verification")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                MetricTile(
                    title: "Pairing Status",
                    value: viewModel.pairingStatus.isLoaded ? "已保存" : "Not Configured",
                    tint: viewModel.pairingStatus.isLoaded ? RelocTheme.emerald : .secondary
                )
                MetricTile(
                    title: "Device Service",
                    value: serviceStateText,
                    tint: ready ? RelocTheme.emerald : (viewModel.connectionCheckFailed ? RelocTheme.amber : .secondary)
                )
                MetricTile(
                    title: "Loopback Host",
                    value: viewModel.host,
                    tint: RelocTheme.accent
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
    }

    private var activePairingGuideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pairing.isRunning {
                HStack(spacing: 6) {
                    pairingStepPill(num: 1, title: "Broadcast Ready", active: pairing.stepIndex >= 1, current: pairing.stepIndex == 1)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    pairingStepPill(num: 2, title: "Enter Pairing Code", active: pairing.stepIndex >= 2, current: pairing.stepIndex == 2)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    pairingStepPill(num: 3, title: "Saved", active: pairing.stepIndex >= 3, current: pairing.stepIndex == 3)
                }
            }

            Text(pairing.status)
                .font(.footnote.weight(.medium))
                .foregroundStyle(pairing.error != nil ? RelocTheme.crimson : .primary)
                .textSelection(.enabled)

            if let pin = pairing.pin {
                let chars = Array(pin)
                HStack(spacing: 6) {
                    ForEach(Array(chars.enumerated()), id: \.offset) { idx, ch in
                        Text(String(ch))
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RelocTheme.amber.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(RelocTheme.amber.opacity(0.45), lineWidth: 1)
                            )
                        if idx == 2 && chars.count == 6 {
                            Spacer().frame(width: 4)
                        }
                    }
                }

                Button {
                    UIPasteboard.general.string = pin
                    RelocTheme.hapticLight()
                    copiedPinToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedPinToast = false }
                } label: {
                    Label(copiedPinToast ? "Pairing Code Copied" : "Copy Pairing Code", systemImage: copiedPinToast ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RelocTheme.amber.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(RelocTheme.amber)
            }

            if pairing.isRunning {
                if pip.isSupported {
                    Button {
                        RelocTheme.hapticLight()
                        pairing.toggleFloatingGuide()
                    } label: {
                        Label(pip.isActive ? "Hide Floating Guide" : "Show Floating Guide", systemImage: pip.isActive ? "pip.exit" : "pip.enter")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RelocTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RelocTheme.accent)
                }

                Button("Cancel Pairing", role: .destructive) {
                    pairing.cancel()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RelocTheme.crimson)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private func pairingStepPill(num: Int, title: String, active: Bool, current: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(num)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 16, height: 16)
                .background(active ? RelocTheme.accent : Color.secondary.opacity(0.25), in: Circle())
                .foregroundStyle(active ? .white : .secondary)
            Text(title)
                .font(.system(size: 11, weight: current ? .bold : .medium))
                .foregroundStyle(active ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(current ? RelocTheme.accent.opacity(0.14) : Color.clear, in: Capsule())
    }

    private func stepSectionHeader(number: String, title: String) -> some View {
        HStack(spacing: 6) {
            Text(number)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RelocTheme.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(RelocTheme.accent)
            Text(title)
                .font(.caption.weight(.bold))
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Native UIDocumentPicker wrapper using `forOpeningContentTypes: [.item], asCopy: true`
/// so custom extensions (`.rppairing`, `.mobiledevicepairing`, `.mobilepair`, `.plist`, or
/// extensionless files) from Files / Downloads / iCloud / WeChat are never greyed out.
private struct PairingDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            } else {
                onCancel()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
