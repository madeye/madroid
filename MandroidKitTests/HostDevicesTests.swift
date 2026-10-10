import Foundation
import Testing
@testable import MandroidKit

/// Host camera and microphone passthrough (GitHub issue #14).
@Suite struct HostDevicesTests {
    private let image = "system-images;android-36.1;google_apis_playstore;arm64-v8a"

    @Test func defaultsKeepFakeDevicesAndNoPrompts() throws {
        let settings = RunnerSettings()
        #expect(settings.hostMicrophone == false)
        #expect(settings.hostCamera == false)
        var config = AVDConfig(systemImagePath: image)
        settings.apply(to: &config)
        let ini = config.renderConfigINI()
        #expect(ini.contains("hw.camera.front=emulated\n"))
        #expect(ini.contains("hw.camera.back=virtualscene\n"))
        #expect(ini.contains("hw.audioInput=yes\n"))
        var options = EmulatorLaunchOptions(avdName: "t", consolePort: 5554, grpcPort: 8554, adbServerPort: 5137)
        settings.apply(to: &options)
        #expect(!options.arguments.contains("-allow-host-audio"))
    }

    @Test func settingsRoundTripAndReachEmulator() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var settings = RunnerSettings()
        settings.hostMicrophone = true
        settings.hostCamera = true
        settings.save(to: defaults)
        let loaded = RunnerSettings.load(from: defaults)
        #expect(loaded.hostMicrophone && loaded.hostCamera)

        var config = AVDConfig(systemImagePath: image)
        loaded.apply(to: &config)
        let ini = config.renderConfigINI()
        #expect(ini.contains("hw.camera.front=webcam0\n"))
        // Only the front camera is replaced; the back camera keeps the virtual scene.
        #expect(ini.contains("hw.camera.back=virtualscene\n"))

        var options = EmulatorLaunchOptions(avdName: "t", consolePort: 5554, grpcPort: 8554, adbServerPort: 5137)
        loaded.apply(to: &options)
        #expect(options.arguments.contains("-allow-host-audio"))
        #expect(options.gpuBackend == loaded.gpuBackend)
    }

    @Test func togglingCameraRequiresColdBootButMicrophoneDoesNot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AVDStore(paths: SDKPaths(root: root))
        var settings = RunnerSettings()
        var config = AVDConfig(systemImagePath: image)
        settings.apply(to: &config)
        #expect(try store.write(config) == false)
        #expect(try store.write(config) == false)
        // The microphone is a launch flag; the AVD profile is unchanged.
        settings.hostMicrophone = true
        settings.apply(to: &config)
        #expect(try store.write(config) == false)
        // The guest camera HAL enumerates cameras at boot: drop the snapshot.
        settings.hostCamera = true
        settings.apply(to: &config)
        #expect(try store.write(config))
        #expect(try store.write(config) == false)
        settings.hostCamera = false
        settings.apply(to: &config)
        #expect(try store.write(config))
    }
}
