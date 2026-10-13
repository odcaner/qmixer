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
    @ObservedObject private var prefs = Prefs.shared
    @StateObject private var dragBox = Box<String?>(nil)

    var body: some View {
        let sections = prefs.visibleSections
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(sections.enumerated()), id: \.element) { i, section in
                // Uygulamalar bölümü cihaz kartlarından çizgiyle ayrılır.
                if i > 0, section == .apps || sections[i - 1] == .apps { Divider() }
                view(for: section)
            }
            if sections.isEmpty {
                Text("Tüm bölümler gizli. Ayarlar › Görünüm'den açabilirsiniz.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button {
                    SettingsWindow.show(devices: devices, apps: apps, login: login)
                } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                }
                .keyboardShortcut(",")
                .controlSize(.small)
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: prefs.panelWidth)
    }

    @ViewBuilder
    private func view(for section: PanelSection) -> some View {
        switch section {
        case .output:
            DeviceCard(
                title: "ÇIKIŞ", icon: "speaker.wave.2.fill", mutedIcon: "speaker.slash.fill",
                list: devices.outputs, selected: devices.defaultOutput, select: devices.setDefaultOutput,
                hasVolume: devices.outputHasVolume,
                volume: Binding(get: { devices.outputVolume }, set: devices.setOutputVolume),
                muted: Binding(get: { devices.outputMuted }, set: devices.setOutputMuted))
        case .input:
            DeviceCard(
                title: "GİRİŞ", icon: "mic.fill", mutedIcon: "mic.slash.fill",
                list: devices.inputs, selected: devices.defaultInput, select: devices.setDefaultInput,
                hasVolume: devices.inputHasVolume,
                volume: Binding(get: { devices.inputVolume }, set: devices.setInputVolume),
                muted: Binding(get: { devices.inputMuted }, set: devices.setInputMuted))
        case .apps:
            appList
        }
    }

    @ViewBuilder
    private var appList: some View {
        if apps.apps.isEmpty {
            SectionLabel(title: "UYGULAMALAR")
            Text(prefs.onlyPlaying ? "Şu an ses çalan uygulama yok." : "Ses kullanan uygulama yok.")
                .foregroundStyle(.secondary).font(.callout)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: prefs.compactRows ? 1 : 4) {
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
                // Kaydırma çubuğu sabitleme düğmesinin üstüne binmesin: içerik çubuk kadar içeride,
                // ScrollView da aynı miktar dışarı taşıyor; böylece çubuk pencerenin kenar boşluğunda kalır.
                .padding(.trailing, 12)
            }
            .padding(.trailing, -12)
            .frame(maxHeight: prefs.listMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
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

    @ObservedObject private var prefs = Prefs.shared
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
                            if prefs.showDeviceKind, let kind = current?.kind, !kind.isEmpty {
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
                        // Gizlenen cihazlar listede yok; ama seçiliyse görünmeye devam eder.
                        ForEach(list.filter { prefs.hiddenDevices[$0.uid] == nil || $0.id == selected }) { d in
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
    @ObservedObject private var prefs = Prefs.shared
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
                    if prefs.showDeviceKind, !device.kind.isEmpty {
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
    @ObservedObject private var prefs = Prefs.shared
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.v } nonmutating set { hoverBox.v = newValue } }

    private var pinned: Bool { controller.isPinned(app.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row
            if let err = app.error {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, prefs.compactRows ? 3 : 5)
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
            Divider()
            Button("Listeden gizle") { withAnimation { controller.hide(app.id) } }
        }
    }

    @ViewBuilder
    private var row: some View {
        if prefs.compactRows {
            // Tek satır: [tutamaç simge ad] [sustur ──slider── %] [iğne]
            HStack(spacing: 6) {
                identity
                    .frame(width: prefs.panelWidth * 0.3, alignment: .leading)
                    .contentShape(Rectangle())
                    .modifier(PinDrag(enabled: pinned, id: app.id, dragging: $dragging))
                volume
                pinButton
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    identity
                    Spacer()
                    pinButton
                }
                .contentShape(Rectangle())
                .modifier(PinDrag(enabled: pinned, id: app.id, dragging: $dragging))
                volume
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 6) {
            if pinned {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(hover ? 1 : 0)
                    .help("Sıralamak için sürükleyin")
            }
            if prefs.showAppIcons, let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(app.name).lineLimit(1).truncationMode(.tail)
            if app.isPlaying {
                Image(systemName: "waveform").font(.caption2).foregroundStyle(.green)
                    .help("Şu an ses çalıyor")
            }
        }
    }

    private var volume: some View {
        VolumeControl(icon: "speaker.wave.2.fill", mutedIcon: "speaker.slash.fill",
                      volume: $app.volume, muted: $app.muted)
    }

    private var pinButton: some View {
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
    @ObservedObject private var prefs = Prefs.shared
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

            if prefs.showPercent {
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(muted ? .secondary : .primary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}
