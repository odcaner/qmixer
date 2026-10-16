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
                title: "Çıkış", icon: "speaker.wave.2.fill", mutedIcon: "speaker.slash.fill",
                list: devices.outputs, selected: devices.defaultOutput, select: devices.setDefaultOutput,
                hasVolume: devices.outputHasVolume,
                volume: Binding(get: { devices.outputVolume }, set: devices.setOutputVolume),
                muted: Binding(get: { devices.outputMuted }, set: devices.setOutputMuted))
        case .input:
            DeviceCard(
                title: "Giriş", icon: "mic.fill", mutedIcon: "mic.slash.fill",
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
            SectionLabel(title: "Uygulamalar")
            Text(L(prefs.onlyPlaying ? "Şu an ses çalan uygulama yok." : "Ses kullanan uygulama yok."))
                .foregroundStyle(.secondary).font(.callout)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: prefs.compactRows ? 1 : 4) {
                    let pinned = apps.pinnedApps
                    let others = apps.otherApps
                    if !pinned.isEmpty {
                        SectionLabel(title: "Sabitlenenler", symbol: "pin.fill")
                        ForEach(pinned) { app in
                            AppRow(app: app, controller: apps, dragging: $dragBox.v)
                                .onDrop(of: [.text], delegate: PinDropDelegate(target: app.id, controller: apps, dragging: $dragBox.v))
                        }
                    }
                    if !others.isEmpty {
                        SectionLabel(title: pinned.isEmpty ? "Uygulamalar" : "Diğer")
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
            Text(L(title).uppercased(with: uiLocale)).font(.system(size: 10, weight: .semibold)).tracking(0.6)
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
                            Text(current?.name ?? L("Cihaz yok"))
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
            Button(L(pinned ? "Sabitlemeyi kaldır" : "Üste sabitle")) {
                withAnimation(.snappy(duration: 0.2)) { controller.togglePin(app.id) }
            }
            if pinned {
                Divider()
                Button("Yukarı taşı") { withAnimation { controller.movePinned(app.id, by: -1) } }
                Button("Aşağı taşı") { withAnimation { controller.movePinned(app.id, by: 1) } }
            }
            Divider()
            Menu("Çıkış") { outputPicker }
            Divider()
            ForEach(VolumeSlider.stops, id: \.self) { stop in
                Button(String(format: L("Ses %@"), percentText(Int(stop * 100)))) {
                    app.volume = stop
                    app.muted = false
                }
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
                outputButton
                pinButton
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    identity
                    Spacer()
                    outputButton
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
            if !prefs.compactRows, app.isRouted || app.outputMissing, let name = outputName {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(app.outputMissing ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
    }

    // MARK: Çıkış cihazı

    private var devices: DeviceController { controller.devices }

    /// Seçilen cihazın adı (bağlı değilse kayıtlı adı).
    private var outputName: String? {
        guard let uid = app.outputDevice else { return nil }
        return devices.outputs.first { $0.uid == uid }?.name ?? app.outputDeviceName ?? uid
    }

    private var outputSymbol: String {
        if app.outputMissing { return "exclamationmark.triangle.fill" }
        if app.isRouted, let d = devices.outputs.first(where: { $0.uid == app.outputDevice }) {
            return NSImage(systemSymbolName: d.symbol, accessibilityDescription: nil) != nil ? d.symbol : "hifispeaker"
        }
        return "hifispeaker"
    }

    private var outputHelp: String {
        guard let name = outputName else { return L("Çıkış: varsayılan") }
        return String(format: L(app.outputMissing ? "%@ bağlı değil; varsayılan çıkış kullanılıyor" : "Çıkış: %@"), name)
    }

    @ViewBuilder
    private var outputPicker: some View {
        let def = devices.outputs.first { $0.id == devices.defaultOutput }
        Picker("Çıkış", selection: Binding(
            get: { app.outputDevice ?? "" },
            set: { uid in
                app.outputDeviceName = devices.outputs.first { $0.uid == uid }?.name
                app.outputDevice = uid.isEmpty ? nil : uid
            })) {
            Text(String(format: L("Varsayılan (%@)"), def?.name ?? "-")).tag("")
            Divider()
            ForEach(devices.outputs.filter { prefs.hiddenDevices[$0.uid] == nil || $0.uid == app.outputDevice }) { d in
                Text(d.name).tag(d.uid)
            }
            if app.outputMissing, let uid = app.outputDevice {
                Text(String(format: L("%@ (bağlı değil)"), outputName ?? uid)).tag(uid)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private var outputButton: some View {
        // Menü etiketi foregroundStyle'ı yok saydığı için renk simgenin kendisine işlenir.
        let color: NSColor = app.outputMissing ? .systemOrange : app.isRouted ? .controlAccentColor : .secondaryLabelColor
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: app.outputMissing ? [.white, color] : [color]))
        let image = NSImage(systemSymbolName: outputSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        return Menu { outputPicker } label: {
            Image(nsImage: image ?? NSImage())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 22, height: 18)
        .opacity(app.isRouted || app.outputMissing || hover ? 1 : 0)
        .help(outputHelp)
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
        .help(L(pinned ? "Sabitlemeyi kaldır" : "Üste sabitle"))
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
            .help(L(muted ? "Sesi aç" : "Sustur"))

            VolumeSlider(value: $volume, dimmed: muted)

            if prefs.showPercent {
                Text(percentText(Int((volume * 100).rounded())))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(muted ? .secondary : .primary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

/// %25/%50/%75/%100 dilimli, dilimlere yapışan ses kaydırıcısı.
struct VolumeSlider: View {
    static let stops: [Float] = [0.25, 0.5, 0.75, 1]

    @Binding var value: Float
    var dimmed = false
    @ObservedObject private var prefs = Prefs.shared
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var dragging = Box(false)

    private let knob: CGFloat = 14
    private let track: CGFloat = 4
    private let snapDistance: Float = 0.025

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - knob)
            let x = CGFloat(value) * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: track)
                Capsule()
                    .fill(dimmed ? Color.secondary : Color.accentColor)
                    .frame(width: x + knob / 2, height: track)

                if prefs.showVolumeStops {
                    ForEach(Self.stops, id: \.self) { stop in
                        Capsule()
                            .fill(value >= stop ? Color.white.opacity(0.75) : Color.primary.opacity(0.35))
                            .frame(width: 2, height: 8)
                            .offset(x: CGFloat(stop) * usable + knob / 2 - 1)
                    }
                }

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .frame(width: knob, height: knob)
                    .scaleEffect(dragging.v ? 1.12 : 1)
                    .offset(x: x)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard isEnabled else { return }
                        if !dragging.v { withAnimation(.easeOut(duration: 0.1)) { dragging.v = true } }
                        update(Float((g.location.x - knob / 2) / usable))
                    }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.1)) { dragging.v = false } }
            )
        }
        .frame(height: 16)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel("Ses seviyesi")
        .accessibilityValue(percentText(Int((value * 100).rounded())))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }

    private func update(_ raw: Float) {
        var v = min(1, max(0, raw))
        if prefs.snapToStops, !NSEvent.modifierFlags.contains(.option),
           let stop = ([0] + Self.stops).first(where: { abs($0 - v) < snapDistance }) {
            // Dilime yeni oturduysa trackpad'de hafif titreşim.
            if value != stop {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            v = stop
        }
        if v != value { value = v }
    }
}
