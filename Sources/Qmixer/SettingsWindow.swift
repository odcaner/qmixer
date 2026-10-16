import SwiftUI

/// Dock'ta görünmeyen (LSUIElement) uygulamada SwiftUI `Settings` sahnesi öne gelmiyor;
/// pencereyi elle yönetiyoruz.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(devices: DeviceController, apps: AppAudioController, login: LoginItem, tab: Int = 0) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(devices: devices, apps: apps, login: login, initialTab: tab))
            let w = NSWindow(contentViewController: host)
            w.title = L("Qmixer Ayarları")
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.7; open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var devices: DeviceController
    @ObservedObject var apps: AppAudioController
    @ObservedObject var login: LoginItem
    @StateObject private var tab: Box<Int>

    init(devices: DeviceController, apps: AppAudioController, login: LoginItem, initialTab: Int = 0) {
        self.devices = devices
        self.apps = apps
        self.login = login
        _tab = StateObject(wrappedValue: Box(initialTab))
    }

    var body: some View {
        TabView(selection: $tab.v) {
            GeneralTab(login: login, apps: apps)
                .tabItem { Label("Genel", systemImage: "gearshape") }.tag(0)
            AppearanceTab()
                .tabItem { Label("Görünüm", systemImage: "paintbrush") }.tag(1)
            AppsTab(apps: apps)
                .tabItem { Label("Uygulamalar", systemImage: "square.grid.2x2") }.tag(2)
            DevicesTab(devices: devices)
                .tabItem { Label("Cihazlar", systemImage: "hifispeaker.2") }.tag(3)
        }
        .frame(width: 520, height: 580)
    }
}

// MARK: - Genel

private struct GeneralTab: View {
    @ObservedObject var login: LoginItem
    @ObservedObject var apps: AppAudioController
    @ObservedObject private var prefs = Prefs.shared
    @StateObject private var confirmReset = Box(false)
    @StateObject private var language = Box(AppLanguage.override)
    private let placementAtLaunch = Prefs.shared.placeNextToWiFi

    var body: some View {
        Form {
            Section {
                Toggle("Girişte başlat", isOn: Binding(get: { login.enabled }, set: login.set))
                Picker("Dil", selection: Binding(get: { language.v }, set: { language.v = $0; AppLanguage.override = $0 })) {
                    Text("Sistem").tag("")
                    ForEach(AppLanguage.options, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                }
                if language.v != AppLanguage.atLaunch {
                    HStack {
                        Text("Yeniden başlatınca geçerli olur.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Şimdi yeniden başlat") { SettingsWindow.relaunch() }
                    }
                }
            }

            Section("Menü çubuğu simgesi") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(MenuIcon.allCases) { icon in
                        IconTile(symbol: icon.symbol, selected: prefs.menuIcon == icon) { prefs.menuIcon = icon }
                            .help(icon.title)
                    }
                }
                .padding(.vertical, 4)
                Text(prefs.menuIcon.title + ". " + L("Ses kapalıyken simge her zaman üstü çizili hoparlöre döner."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Wi-Fi simgesinin hemen soluna yerleştir", isOn: $prefs.placeNextToWiFi)
                if prefs.placeNextToWiFi != placementAtLaunch {
                    HStack {
                        Text("Yeniden başlatınca geçerli olur.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Şimdi yeniden başlat") { SettingsWindow.relaunch() }
                    }
                }
            } header: {
                Text("Konum")
            } footer: {
                Text("Kapalıysa simgeyi ⌘ tuşuna basılı tutup menü çubuğunda istediğiniz yere sürükleyebilirsiniz.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sıfırla") {
                HStack {
                    Text("Görünüm ayarları")
                    Spacer()
                    Button("Varsayılana döndür") { prefs.resetAppearance() }
                }
                HStack {
                    Text("Uygulama ses ve çıkış ayarları")
                    Spacer()
                    Button("Sıfırla…") { confirmReset.v = true }
                }
            }

            Section {
                LabeledContent("Sürüm", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                Link("github.com/odcaner/qmixer", destination: URL(string: "https://github.com/odcaner/qmixer")!)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(Text(L("Tüm uygulamalar %100 sese ve varsayılan çıkışa dönsün mü?")),
                            isPresented: $confirmReset.v) {
            Button("Sıfırla", role: .destructive) { apps.resetVolumes() }
        }
    }
}

private struct IconTile: View {
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Görünüm

private struct AppearanceTab: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                ForEach(Array(prefs.sectionOrder.enumerated()), id: \.element) { i, section in
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Toggle(section.title, isOn: Binding(
                            get: { !prefs.hiddenSections.contains(section) },
                            set: { on in
                                if on { prefs.hiddenSections.remove(section) } else { prefs.hiddenSections.insert(section) }
                            }))
                        Spacer()
                        MoveButtons(index: i, count: prefs.sectionOrder.count) { delta in
                            withAnimation { prefs.sectionOrder.swapAt(i, i + delta) }
                        }
                    }
                }
                .onMove { prefs.sectionOrder.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Paneldeki bölümler")
            } footer: {
                Text("Sırayı oklarla veya sürükleyerek değiştirin; kapattığınız bölüm panelde görünmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Boyut") {
                LabeledSlider(title: "Panel genişliği", value: $prefs.panelWidth, range: 300...480, step: 10)
                LabeledSlider(title: "Uygulama listesi en fazla", value: $prefs.listMaxHeight, range: 160...800, step: 20)
            }

            Section("Ayrıntılar") {
                Toggle("Kompakt uygulama satırları (tek satır)", isOn: $prefs.compactRows)
                Toggle("Ses yüzdesini göster", isOn: $prefs.showPercent)
                Toggle("Uygulama simgelerini göster", isOn: $prefs.showAppIcons)
                Toggle("Cihaz türünü göster (Bluetooth, USB…)", isOn: $prefs.showDeviceKind)
            }

            Section {
                Toggle(L("%25 · %50 · %75 · %100 dilimlerini göster"), isOn: $prefs.showVolumeStops)
                Toggle("Sürüklerken dilimlere yapış", isOn: $prefs.snapToStops)
            } header: {
                Text("Ses kaydırıcısı")
            } footer: {
                Text("Yapışma açıkken ⌥ (Option) tuşuna basılı tutarak ara değerleri hassas ayarlayabilirsiniz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack {
            Text(L(title))
            // `step:` macOS'ta sık çentik çiziyor; adımı bağlamada yuvarlıyoruz.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
            Text("\(Int(value)) pt")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

private struct MoveButtons: View {
    let index: Int
    let count: Int
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(index >= count - 1)
        }
        .buttonStyle(.borderless)
        .help("Sırayı değiştir")
    }
}

// MARK: - Uygulamalar

private struct AppsTab: View {
    @ObservedObject var apps: AppAudioController
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Liste") {
                Picker("Sıralama", selection: $prefs.appSort) {
                    ForEach(AppSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Yalnızca ses çalan uygulamaları göster", isOn: $prefs.onlyPlaying)
                    Text("Sabitlenenler her zaman görünür. Susan uygulama 15 saniye sonra listeden çıkar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                if apps.pinned.isEmpty {
                    Text("Sabitlenen uygulama yok. Paneldeki 📌 düğmesiyle sabitleyebilirsiniz.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(apps.pinned.enumerated()), id: \.element) { i, id in
                    HStack(spacing: 8) {
                        AppLabel(id: id)
                        Spacer()
                        MoveButtons(index: i, count: apps.pinned.count) { delta in
                            var ids = apps.pinned
                            ids.swapAt(i, i + delta)
                            withAnimation { apps.setPinned(ids) }
                        }
                        Button("Kaldır") { withAnimation { apps.togglePin(id) } }
                    }
                }
                .onMove { from, to in
                    var ids = apps.pinned
                    ids.move(fromOffsets: from, toOffset: to)
                    apps.setPinned(ids)
                }
            } header: {
                Text("Sabitlenenler")
            }

            Section {
                if prefs.hiddenApps.isEmpty {
                    Text("Gizlenen uygulama yok. Paneldeki bir uygulamaya sağ tıklayıp \"Listeden gizle\" diyebilirsiniz.")
                        .foregroundStyle(.secondary)
                }
                ForEach(prefs.hiddenApps, id: \.self) { id in
                    HStack(spacing: 8) {
                        AppLabel(id: id)
                        Spacer()
                        Button("Göster") { withAnimation { prefs.hiddenApps.removeAll { $0 == id } } }
                    }
                }
            } header: {
                Text("Gizlenenler")
            } footer: {
                Text("Gizlenen uygulamanın kayıtlı ses ayarı uygulanmaya devam eder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppLabel: View {
    let id: String

    var body: some View {
        let info = AppInfo.lookup(id)
        HStack(spacing: 8) {
            if let icon = info.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20)
            }
            Text(info.name)
        }
    }
}

// MARK: - Cihazlar

private struct DevicesTab: View {
    @ObservedObject var devices: DeviceController
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            deviceSection("Çıkış cihazları", devices.outputs, footer: false)
            deviceSection("Giriş cihazları", devices.inputs, footer: true)

            let connected = Set((devices.outputs + devices.inputs).map(\.uid))
            let offline = prefs.hiddenDevices.filter { !connected.contains($0.key) }.sorted { $0.value < $1.value }
            if !offline.isEmpty {
                Section("Bağlı olmayan gizli cihazlar") {
                    ForEach(offline, id: \.key) { uid, name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Göster") { prefs.hiddenDevices[uid] = nil }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func deviceSection(_ title: String, _ list: [AudioDevice], footer: Bool) -> some View {
        Section {
            ForEach(list) { d in
                HStack(spacing: 10) {
                    DeviceIcon(symbol: d.symbol, active: prefs.hiddenDevices[d.uid] == nil, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.name)
                        if !d.kind.isEmpty {
                            Text(d.kind).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("Listede göster", isOn: Binding(
                        get: { prefs.hiddenDevices[d.uid] == nil },
                        set: { prefs.hiddenDevices[d.uid] = $0 ? nil : d.name }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        } header: {
            Text(L(title))
        } footer: {
            if footer {
                Text("Kapattığınız cihaz panelin cihaz listesinde görünmez (seçiliyse görünmeye devam eder).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
