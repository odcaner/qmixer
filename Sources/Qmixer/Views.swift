import SwiftUI
import CoreAudio
import UniformTypeIdentifiers

/// Komut satırı araçlarında SwiftUI makro eklentisi (@State) yok; yerel görünüm durumu için küçük kutu.
final class Box<T>: ObservableObject {
    @Published var v: T
    init(_ v: T) { self.v = v }
}

struct MixerView: View {
    @ObservedObject var devices: DeviceController
    @ObservedObject var apps: AppAudioController
    @ObservedObject var login: LoginItem
    @StateObject private var dragBox = Box<String?>(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeviceCard(
                title: "ÇIKIŞ", icon: "speaker.wave.2.fill", mutedIcon: "speaker.slash.fill",
                list: devices.outputs, selected: devices.defaultOutput, select: devices.setDefaultOutput,
                hasVolume: devices.outputHasVolume,
                volume: Binding(get: { devices.outputVolume }, set: devices.setOutputVolume),
                muted: Binding(get: { devices.outputMuted }, set: devices.setOutputMuted))

            DeviceCard(
                title: "GİRİŞ", icon: "mic.fill", mutedIcon: "mic.slash.fill",
                list: devices.inputs, selected: devices.defaultInput, select: devices.setDefaultInput,
                hasVolume: devices.inputHasVolume,
                volume: Binding(get: { devices.inputVolume }, set: devices.setInputVolume),
                muted: Binding(get: { devices.inputMuted }, set: devices.setInputMuted))

            Divider()

            if apps.apps.isEmpty {
                SectionLabel(title: "UYGULAMALAR")
                Text("Ses kullanan uygulama yok.")
                    .foregroundStyle(.secondary).font(.callout)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        let pinned = apps.pinnedApps
                        let others = apps.otherApps
                        if !pinned.isEmpty {
                            SectionLabel(title: "SABİTLENENLER", symbol: "pin.fill")
                            ForEach(pinned) { app in
                                AppRow(app: app, controller: apps, dragging: $dragBox.v)
                                    .onDrop(of: [.text], delegate: PinDropDelegate(target: app.id, controller: apps, dragging: $dragBox.v))
                            }
                        }
                        if !others.isEmpty {
                            SectionLabel(title: pinned.isEmpty ? "UYGULAMALAR" : "DİĞER")
                                .padding(.top, pinned.isEmpty ? 0 : 8)
                            ForEach(others) { AppRow(app: $0, controller: apps, dragging: $dragBox.v) }
                        }
                    }
                }
                .frame(maxHeight: 400)
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
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

struct SectionLabel: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.6)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Cihaz kartı

struct DeviceCard: View {
    let title: String
    let icon: String
    let mutedIcon: String
    let list: [AudioDevice]
    let selected: AudioObjectID
    let select: (AudioObjectID) -> Void
    let hasVolume: Bool
    @Binding var volume: Float
    @Binding var muted: Bool

    @StateObject private var expandedBox = Box(false)
    private var expanded: Bool { get { expandedBox.v } nonmutating set { expandedBox.v = newValue } }
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.v } nonmutating set { hoverBox.v = newValue } }

    private var current: AudioDevice? { list.first { $0.id == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title)

            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        DeviceIcon(symbol: current?.symbol ?? icon, active: true, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(current?.name ?? "Cihaz yok")
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if let kind = current?.kind, !kind.isEmpty {
                                Text(kind).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 }

                if expanded {
                    Divider().padding(.horizontal, 8)
                    VStack(spacing: 1) {
                        ForEach(list) { d in
                            DeviceOption(device: d, selected: d.id == selected) {
                                select(d.id)
                                withAnimation(.snappy(duration: 0.22)) { expanded = false }
                            }
                        }
                    }
                    .padding(4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hover || expanded ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VolumeControl(icon: icon, mutedIcon: mutedIcon, volume: $volume, muted: $muted)
                .disabled(!hasVolume)
                .opacity(hasVolume ? 1 : 0.4)
        }
    }
}

struct DeviceOption: View {
    let device: AudioDevice
    let selected: Bool
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.v } nonmutating set { hoverBox.v = newValue } }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DeviceIcon(symbol: device.symbol, active: selected, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name).font(.system(size: 12.5)).lineLimit(1)
                    if !device.kind.isEmpty {
                        Text(device.kind).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover ? Color.accentColor.opacity(0.15) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Denetim Merkezi tarzı yuvarlak cihaz simgesi.
struct DeviceIcon: View {
    let symbol: String
    let active: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(active ? Color.accentColor : Color.primary.opacity(0.1))
            Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : "speaker.wave.2")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Uygulama satırı

struct AppRow: View {
    @ObservedObject var app: AppAudio
    @ObservedObject var controller: AppAudioController
    @Binding var dragging: String?
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.v } nonmutating set { hoverBox.v = newValue } }

    private var pinned: Bool { controller.isPinned(app.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if pinned {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hover ? 1 : 0)
                        .help("Sıralamak için sürükleyin")
                }
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(app.name).lineLimit(1)
                if app.isPlaying {
                    Image(systemName: "waveform").font(.caption2).foregroundStyle(.green)
                        .help("Şu an ses çalıyor")
                }
                Spacer()
                Button { withAnimation(.snappy(duration: 0.2)) { controller.togglePin(app.id) } } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(pinned || hover ? 1 : 0)
                .help(pinned ? "Sabitlemeyi kaldır" : "Üste sabitle")
            }
            .contentShape(Rectangle())
            .modifier(PinDrag(enabled: pinned, id: app.id, dragging: $dragging))

            VolumeControl(icon: "speaker.wave.2.fill", mutedIcon: "speaker.slash.fill",
                          volume: $app.volume, muted: $app.muted)
            if let err = app.error {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(dragging == app.id ? 0.12 : hover ? 0.05 : 0))
        )
        .onHover {
            hover = $0
            // Pencere dışına bırakılan sürüklemede performDrop gelmez; vurguyu temizle.
            if $0, dragging != nil, NSEvent.pressedMouseButtons == 0 { dragging = nil }
        }
        .contextMenu {
            Button(pinned ? "Sabitlemeyi kaldır" : "Üste sabitle") {
                withAnimation(.snappy(duration: 0.2)) { controller.togglePin(app.id) }
            }
            if pinned {
                Divider()
                Button("Yukarı taşı") { withAnimation { controller.movePinned(app.id, by: -1) } }
                Button("Aşağı taşı") { withAnimation { controller.movePinned(app.id, by: 1) } }
            }
        }
    }
}

/// Yalnızca sabitlenen satırlar sürüklenebilir.
struct PinDrag: ViewModifier {
    let enabled: Bool
    let id: String
    @Binding var dragging: String?

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                dragging = id
                return NSItemProvider(object: id as NSString)
            }
        } else {
            content
        }
    }
}

/// Sabitlenenler arasında sürükle-bırak: üzerine gelinen satırın yerine canlı olarak kayar.
struct PinDropDelegate: DropDelegate {
    let target: String
    let controller: AppAudioController
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, controller.isPinned(dragging) else { return }
        withAnimation(.snappy(duration: 0.2)) { controller.movePinned(dragging, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropExited(info: DropInfo) {}
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
