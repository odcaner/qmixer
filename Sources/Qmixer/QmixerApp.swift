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

struct MixerView: View {
    @ObservedObject var devices: DeviceController
    @ObservedObject var apps: AppAudioController
    @ObservedObject var login: LoginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceSection(
                title: "Çıkış", icon: "speaker.wave.2.fill", mutedIcon: "speaker.slash.fill",
                list: devices.outputs, selected: devices.defaultOutput, select: devices.setDefaultOutput,
                hasVolume: devices.outputHasVolume,
                volume: Binding(get: { devices.outputVolume }, set: devices.setOutputVolume),
                muted: Binding(get: { devices.outputMuted }, set: devices.setOutputMuted))

            DeviceSection(
                title: "Giriş", icon: "mic.fill", mutedIcon: "mic.slash.fill",
                list: devices.inputs, selected: devices.defaultInput, select: devices.setDefaultInput,
                hasVolume: devices.inputHasVolume,
                volume: Binding(get: { devices.inputVolume }, set: devices.setInputVolume),
                muted: Binding(get: { devices.inputMuted }, set: devices.setInputMuted))

            Divider()

            Text("Uygulamalar").font(.headline)
            if apps.apps.isEmpty {
                Text("Ses kullanan uygulama yok.")
                    .foregroundStyle(.secondary).font(.callout)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(apps.apps) { AppRow(app: $0) }
                    }
                }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Toggle("Girişte başlat", isOn: Binding(get: { login.enabled }, set: login.set))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

struct DeviceSection: View {
    let title: String
    let icon: String
    let mutedIcon: String
    let list: [AudioDevice]
    let selected: AudioObjectID
    let select: (AudioObjectID) -> Void
    let hasVolume: Bool
    @Binding var volume: Float
    @Binding var muted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Picker("", selection: Binding(get: { selected }, set: select)) {
                    ForEach(list) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            VolumeControl(icon: icon, mutedIcon: mutedIcon, volume: $volume, muted: $muted)
                .disabled(!hasVolume)
                .opacity(hasVolume ? 1 : 0.4)
        }
    }
}

struct AppRow: View {
    @ObservedObject var app: AppAudio

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(app.name).lineLimit(1)
                if app.isPlaying {
                    Image(systemName: "waveform").font(.caption2).foregroundStyle(.green)
                        .help("Şu an ses çalıyor")
                }
                Spacer()
            }
            VolumeControl(icon: "speaker.wave.2.fill", mutedIcon: "speaker.slash.fill",
                          volume: $app.volume, muted: $app.muted)
            if let err = app.error {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
    }
}

struct VolumeControl: View {
    let icon: String
    let mutedIcon: String
    @Binding var volume: Float
    @Binding var muted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button { muted.toggle() } label: {
                Image(systemName: muted ? mutedIcon : icon)
                    .foregroundStyle(muted ? .red : .primary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(muted ? "Sesi aç" : "Sustur")

            Slider(value: $volume, in: 0...1)
                .controlSize(.small)

            Text("\(Int((volume * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(muted ? .secondary : .primary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
