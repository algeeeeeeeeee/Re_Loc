import SwiftUI

@main
struct RelocApp: App {
    @StateObject private var viewModel = RelocViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .tint(RelocTheme.accent)
                .preferredColorScheme(viewModel.appearanceMode.colorScheme)
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: RelocViewModel
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if viewModel.isUnsupportedIPad {
                UnsupportedIPadView()
            } else {
                TabView(selection: $selectedTab) {
                    MapPickerView(viewModel: viewModel, switchToConfig: { selectedTab = 1 })
                        .tabItem {
                            Label("Location", systemImage: "location.north.circle.fill")
                        }
                        .tag(0)

                    ConfigurationView(viewModel: viewModel)
                        .tabItem {
                            Label("Device Connection", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .tag(1)

                    ProtocolLogsView(viewModel: viewModel)
                        .tabItem {
                            Label("Diagnostics & Logs", systemImage: "waveform.path.ecg")
                        }
                        .tag(2)
                }
                .onOpenURL { url in
                    viewModel.importPairingFile(url: url)
                    selectedTab = 1
                }
            }
        }
        .alert("Notice", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.alertMessage = nil
            }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }
}

private struct UnsupportedIPadView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(RelocTheme.amber.opacity(0.16))
                    .frame(width: 88, height: 88)
                Image(systemName: "ipad")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(RelocTheme.amber)
                Image(systemName: "slash.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(RelocTheme.crimson)
                    .background(Color(.systemGroupedBackground), in: Circle())
                    .offset(x: 24, y: 22)
            }

            VStack(spacing: 10) {
                Text("Device Not Available")
                    .font(.title2.weight(.bold))

                Text("Reloc Supports iPhone Only")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RelocTheme.amber)

                Text("Reloc uses the iOS CarKit (com.apple.carkit.service) accessory-location channel to provide GPS coordinates to the system. iPadOS does not provide this service, so location simulation is unavailable on iPad.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 420)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
