import SwiftUI
import CoreAudio

@main
struct QmixerApp: App {
    @StateObject private var devices: DeviceController
    @StateObject private var apps: AppAudioController
    @StateObject private var login = LoginItem()
    @StateObject private var prefs = Prefs.shared

    init() {
        if Prefs.shared.placeNextToWiFi { MenuBarPlacement.placeNextToWiFi() }
        let d = DeviceController()
        _devices = StateObject(wrappedValue: d)
        let a = AppAudioController(devices: d)
        _apps = StateObject(wrappedValue: a)
        // `open Qmixer.app --args --settings [sekme 0-3]`: ayarlar penceresiyle başlat.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--settings") {
            let tab = args.indices.contains(i + 1) ? Int(args[i + 1]) ?? 0 : 0
            let login = LoginItem()
            _login = StateObject(wrappedValue: login)
            DispatchQueue.main.async { SettingsWindow.show(devices: d, apps: a, login: login, tab: tab) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MixerView(devices: devices, apps: apps, login: login)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuIcon: String {
        prefs.menuIcon.symbol(volume: devices.outputVolume, muted: devices.outputMuted)
    }
}
