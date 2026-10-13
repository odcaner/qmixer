import SwiftUI
import CoreAudio

@main
struct QmixerApp: App {
    @StateObject private var devices: DeviceController
    @StateObject private var apps: AppAudioController
    @StateObject private var login = LoginItem()

    init() {
        MenuBarPlacement.placeNextToWiFi()
        let d = DeviceController()
        _devices = StateObject(wrappedValue: d)
        _apps = StateObject(wrappedValue: AppAudioController(devices: d))
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
        if devices.outputMuted || devices.outputVolume == 0 { return "speaker.slash.fill" }
        return "slider.vertical.3"
    }
}
