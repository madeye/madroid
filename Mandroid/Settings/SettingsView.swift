import MandroidKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let coordinator: RunnerCoordinator
    let windows: WindowManager
    @State private var settings = RunnerSettings.load()
    @State private var saved = RunnerSettings.load()
    @State private var volume: Double = 0
    @State private var volumeReady = false
    @State private var applyingVolume = false
    @State private var volumeError: String?


    private var needsRestart: Bool {
        if let session = coordinator.session {
            if (session.options.kernelSURamdisk != nil) != settings.kernelSUEnabled { return true }
            let display = settings.deviceDisplay
            if session.deviceWidth != display.widthPixels || session.deviceHeight != display.heightPixels
                || session.deviceDpi != display.density { return true }
        }
        return settings.requiresRestart(comparedTo: saved)
    }

    var body: some View {
        Form {
            Section("Virtual device") {
                Picker("Device screen profile", selection: $settings.deviceProfile) {
                    ForEach(DeviceProfile.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if settings.deviceProfile == .custom {
                    Stepper("Width: \(settings.customDeviceWidthDP) dp", value: $settings.customDeviceWidthDP,
                            in: DeviceDisplay.dimensionRange, step: 20)
                    Stepper("Height: \(settings.customDeviceHeightDP) dp", value: $settings.customDeviceHeightDP,
                            in: DeviceDisplay.dimensionRange, step: 20)
                    Stepper("Density: \(settings.customDeviceDensity) dpi", value: $settings.customDeviceDensity,
                            in: DeviceDisplay.densityRange, step: 20)
                }
                Text(settings.deviceDisplay.summary).font(.caption).foregroundStyle(.secondary)
                Text("Open Device Screen to test apps with this display profile. Separate app windows use their own window size.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Memory", selection: $settings.ramMB) {
                    ForEach(RunnerSettings.ramChoices, id: \.self) { Text("\($0 / 1024) GB").tag($0) }
                }
                Picker("CPU cores", selection: $settings.cores) {
                    ForEach(RunnerSettings.coreChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Graphics", selection: $settings.gpuBackend) {
                    ForEach(GPUBackend.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if needsRestart {
                    HostNotice(message: "Changes saved. Restart the emulator to apply them.", symbol: "arrow.clockwise.circle")
                        .transition(.opacity)
                }
                HStack {
                    Button("Restart Emulator") { restart(cold: false) }
                    Button("Cold Boot") { restart(cold: true) }
                }
            }
            Section("KernelSU (experimental)") {
                Toggle("Boot with KernelSU", isOn: $settings.kernelSUEnabled)
                Text("Adds root support to the supported Android 36.1 ARM64 image. A separate patched image preserves the stock image. Turn this off and restart to return to stock; installed apps and data are kept.")
                    .font(.caption).foregroundStyle(.secondary)
                if coordinator.session?.options.kernelSURamdisk != nil {
                    Label("KernelSU is active", systemImage: "checkmark.circle")
                } else {
                    Text("KernelSU is not active in this session.").font(.caption).foregroundStyle(.secondary)
                }
                Text(coordinator.kernelSUStatus).font(.caption).foregroundStyle(.secondary)
                if let error = coordinator.kernelSUError { HostNotice(message: error) }
                HStack {
                    if coordinator.preparingKernelSU {
                        ProgressView().controlSize(.small)
                        Button("Cancel Preparation") { coordinator.cancelKernelSUPreparation() }
                    } else {
                        Button("Prepare Patched Image") {
                            Task { _ = try? await coordinator.prepareKernelSU() }
                        }
                        .disabled(!coordinator.bootstrap.isReady)
                    }
                    Button("Restart to Apply") { restart(cold: true) }
                        .disabled(coordinator.preparingKernelSU)
                }
                Link("KernelSU project and license", destination: URL(string: "https://github.com/tiann/KernelSU")!)
                    .font(.caption)
            }
            Section("Audio") {
                HStack {
                    Slider(value: $volume, in: 0...100, step: 1, label: { Text("Media volume") }, onEditingChanged: { editing in
                        if !editing { applyVolume() }
                    })
                    .disabled(!volumeReady || applyingVolume || !coordinator.state.isReady)
                    Text(volumeReady ? "\(Int(volume))%" : "—")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Text("Controls all Android apps. Changes apply immediately; 0% mutes media audio.")
                    .font(.caption).foregroundStyle(.secondary)
                if !coordinator.state.isReady {
                    Text("Available when Android is running.").font(.caption).foregroundStyle(.secondary)
                }
                if let volumeError { HostNotice(message: volumeError).transition(.opacity) }
            }
            Section("Camera & Microphone") {
                Toggle("Let Android apps use this Mac's microphone", isOn: $settings.hostMicrophone)
                Toggle("Let Android apps use this Mac's camera", isOn: $settings.hostCamera)
                Text("For voice and video calls. macOS asks for permission the first time an app records; the Mac's camera acts as the front camera. Takes effect after a restart.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Windows") {
                Picker("New windows open", selection: $settings.landscapeByDefault) {
                    Text("Landscape").tag(true)
                    Text("Portrait").tag(false)
                }
                .pickerStyle(.segmented)
                Stepper("Default window height: \(settings.defaultWindowHeight) pt",
                        value: $settings.defaultWindowHeight, in: 500...1600, step: 50)
                Toggle("Create launchers in ~/Applications/Android Apps", isOn: $settings.launcherStubs)
                Text("Launchers let Android apps appear in Spotlight and the Dock.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Downloads") {
                Picker("Download SDK from", selection: $settings.downloadMirror) {
                    Text("Automatic").tag(DownloadMirror.Preference.auto)
                    Text(DownloadMirror.google.name).tag(DownloadMirror.Preference.google)
                    Text(DownloadMirror.china.name).tag(DownloadMirror.Preference.china)
                }
                Text("Automatic uses the China mirror only when this Mac's region or time zone is mainland China. Applies to the next download.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Files") {
                LabeledContent("System image") {
                    Text(coordinator.bootstrap.installedSystemImage()?.packagePath ?? "none").textSelection(.enabled)
                }
                HStack {
                    Button("Show Logs") { NSWorkspace.shared.open(coordinator.paths.logs) }
                    Button("Show Data Folder") { NSWorkspace.shared.open(coordinator.paths.root) }
                }
                Text("Data folder: \(coordinator.paths.root.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 720)
        .animation(HostStyle.motion(reduceMotion: reduceMotion), value: needsRestart)
        .animation(HostStyle.motion(reduceMotion: reduceMotion), value: volumeError != nil)
        .task(id: coordinator.state.isReady) {
            volumeReady = false
            guard coordinator.state.isReady, let adb = coordinator.session?.adb else { return }
            do {
                volume = Double(try await adb.mediaVolume().percent)
                volumeReady = true
                volumeError = nil
            } catch { volumeError = error.localizedDescription }
        }
        .onChange(of: settings) { _, new in
            new.save()
            if !new.launcherStubs {
                LauncherStubBuilder.sync([])
            } else if !coordinator.apps.isEmpty {
                LauncherStubBuilder.sync(coordinator.apps)
            }
        }
    }

    private func applyVolume() {
        guard volumeReady, !applyingVolume, let adb = coordinator.session?.adb else { return }
        applyingVolume = true
        let requested = Int(volume)
        Task {
            defer { applyingVolume = false }
            do {
                let actual = try await adb.setMediaVolume(percent: requested)
                volume = Double(actual.percent)
                settings.mediaVolumePercent = actual.percent
                volumeError = nil
            } catch { volumeError = error.localizedDescription }
        }
    }

    private func restart(cold: Bool) {
        saved = settings
        windows.closeAll()
        Task { await coordinator.restart(coldBoot: cold) }
    }
}

final class SettingsWindowController: NSWindowController {
    init(coordinator: RunnerCoordinator, windows: WindowManager) {
        let host = NSHostingController(rootView: SettingsView(coordinator: coordinator, windows: windows))
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.contentMinSize = NSSize(width: 480, height: 420)
        window.setContentSize(NSSize(width: 560, height: 720))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}
