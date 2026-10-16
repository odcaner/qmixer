import AppKit
import CoreAudio
import Combine

/// Sesli bir uygulama (yardımcı süreçleri dahil; örn. Chrome Helper, Safari WebContent).
@MainActor
final class AppAudio: ObservableObject, Identifiable {
    let id: String               // bundle ID (yoksa pid)
    @Published private(set) var name: String
    @Published private(set) var icon: NSImage?
    @Published private(set) var isPlaying = false
    /// "Sadece çalanlar" filtresinde satırlar her sessizlikte kaybolmasın diye kısa bir tolerans.
    private(set) var lastPlayed: Date?
    var recentlyPlaying: Bool { isPlaying || (lastPlayed.map { Date().timeIntervalSince($0) < 15 } ?? false) }
    @Published var volume: Float = 1 { didSet { apply(); Settings.save(self) } }
    @Published var muted = false { didSet { apply(); Settings.save(self) } }
    /// Uygulamaya özel çıkış cihazı (UID). nil = sistemin varsayılan çıkışı.
    @Published var outputDevice: String? { didSet { apply(); Settings.save(self) } }
    /// Cihaz bağlı değilken de adını gösterebilmek için.
    var outputDeviceName: String?
    @Published private(set) var error: String?

    fileprivate(set) var processObjects: [AudioObjectID] = []
    /// Sistemin varsayılan çıkışı ve bağlı çıkış cihazları (controller günceller).
    fileprivate var defaultUID: String?
    fileprivate var connectedUIDs: Set<String> = []
    private var tap: ProcessTap?

    init(id: String, name: String, icon: NSImage?) {
        self.id = id
        self.name = name
        self.icon = icon
    }

    /// Seçilen cihaz bağlı değilse varsayılana düşer.
    var effectiveOutput: String? {
        if let outputDevice, connectedUIDs.contains(outputDevice) { return outputDevice }
        return defaultUID
    }
    /// Ses varsayılandan farklı bir cihaza yönlendiriliyor.
    var isRouted: Bool { effectiveOutput != nil && effectiveOutput != defaultUID }
    /// Seçilen cihaz şu an bağlı değil.
    var outputMissing: Bool { outputDevice.map { !connectedUIDs.contains($0) } ?? false }

    fileprivate func update(name: String, icon: NSImage?, processObjects: [AudioObjectID], isPlaying: Bool,
                            defaultUID: String?, connectedUIDs: Set<String>) {
        if self.name != name { self.name = name }
        if self.icon == nil, let icon { self.icon = icon }
        if self.isPlaying != isPlaying { self.isPlaying = isPlaying }
        if isPlaying { lastPlayed = Date() }
        let changed = self.processObjects != processObjects || self.defaultUID != defaultUID
            || self.connectedUIDs != connectedUIDs
        if self.connectedUIDs != connectedUIDs || self.defaultUID != defaultUID { objectWillChange.send() }
        self.processObjects = processObjects
        self.defaultUID = defaultUID
        self.connectedUIDs = connectedUIDs
        if changed { apply() }
    }

    fileprivate func stop() {
        tap = nil
        processObjects = []
    }

    /// %100, sesli ve varsayılan çıkışta ise tap tutmayız: uygulamanın sesine hiç dokunulmaz.
    func apply() {
        let g: Float = muted ? 0 : volume
        guard g < 0.999 || isRouted, !processObjects.isEmpty, let outputUID = effectiveOutput else {
            tap = nil
            error = nil
            return
        }
        if let tap, tap.processObjects == processObjects, tap.outputUID == outputUID {
            tap.setGain(g)
            return
        }
        tap = nil
        do {
            tap = try ProcessTap(processObjects: processObjects, outputUID: outputUID, name: name, initialGain: g)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Core Audio'ya bağlanmış süreçleri izler, sahibi olan uygulamaya göre gruplar.
@MainActor
final class AppAudioController: ObservableObject {
    @Published private(set) var apps: [AppAudio] = []
    /// Sabitlenen uygulamalar (bundle ID), görüntülenme sırasıyla. Çalışmayanlar da sırasını korur.
    @Published private(set) var pinned: [String] = UserDefaults.standard.stringArray(forKey: "pinnedApps") ?? []

    /// Uygulama kapanıp açılınca ayarlar korunsun diye kaybolanları da tutarız.
    private var store: [String: AppAudio] = [:]
    let devices: DeviceController
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(devices: DeviceController) {
        self.devices = devices
        refresh()
        devices.$outputs.map { $0.map(\.uid) }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
        CA.listen(.system, propAddr(kAudioHardwarePropertyProcessObjectList)) { [weak self] in self?.refresh() }
        Prefs.shared.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
        devices.$defaultOutput.removeDuplicates().dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
        // "Çalıyor" durumu için özellik dinleyicisi süreç başına gerekir; periyodik okuma daha basit.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let defaultUID = devices.defaultOutputUID
        let connected = Set(devices.outputs.map(\.uid))
        let myPID = ProcessInfo.processInfo.processIdentifier
        let objects: [AudioObjectID] = CA.array(.system, propAddr(kAudioHardwarePropertyProcessObjectList))

        struct Group { var app: NSRunningApplication?; var name: String; var objects: [AudioObjectID] = []; var playing = false }
        var groups: [String: Group] = [:]

        for obj in objects {
            guard let pid: pid_t = CA.get(obj, propAddr(kAudioProcessPropertyPID)), pid != myPID else { continue }
            let owner = Self.owningApp(of: pid)
            guard let owner, owner.activationPolicy != .prohibited,
                  owner.processIdentifier != myPID else { continue }
            let key = owner.bundleIdentifier ?? "pid-\(owner.processIdentifier)"
            let running: UInt32 = CA.get(obj, propAddr(kAudioProcessPropertyIsRunningOutput)) ?? 0
            var g = groups[key] ?? Group(app: owner, name: owner.localizedName ?? key)
            g.objects.append(obj)
            g.playing = g.playing || running != 0
            groups[key] = g
        }

        var visible: [AppAudio] = []
        for (key, g) in groups {
            let app = store[key] ?? Settings.load(AppAudio(id: key, name: g.name, icon: g.app?.icon))
            store[key] = app
            app.update(name: g.name, icon: g.app?.icon, processObjects: g.objects.sorted(),
                       isPlaying: g.playing, defaultUID: defaultUID, connectedUIDs: connected)
            visible.append(app)
        }
        for (key, app) in store where groups[key] == nil && !app.processObjects.isEmpty {
            app.stop()
        }

        present = visible
        publish(visible)
    }

    /// Şu an ses oturumu olan tüm uygulamalar (gizlenenler dahil).
    private var present: [AppAudio] = []

    /// Sabitlenenler kendi sıralarıyla üstte; diğerleri tercihe göre sıralanır ve süzülür.
    private func publish(_ visible: [AppAudio]) {
        let prefs = Prefs.shared
        let shown = visible.filter { !prefs.hiddenApps.contains($0.id) }
        let pinnedVisible = pinned.compactMap { id in shown.first { $0.id == id } }
        let others = shown
            .filter { !pinned.contains($0.id) && (!prefs.onlyPlaying || $0.recentlyPlaying) }
            .sorted {
                if prefs.appSort == .playingFirst, $0.isPlaying != $1.isPlaying { return $0.isPlaying }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        let ordered = pinnedVisible + others
        if ordered.map(\.id) != apps.map(\.id) { apps = ordered }
    }

    // MARK: - Sabitleme

    var pinnedApps: [AppAudio] { apps.filter { pinned.contains($0.id) } }
    var otherApps: [AppAudio] { apps.filter { !pinned.contains($0.id) } }

    func isPinned(_ id: String) -> Bool { pinned.contains(id) }

    /// Yeni sabitlenen, sabitlenenlerin en altına eklenir.
    func togglePin(_ id: String) {
        if let i = pinned.firstIndex(of: id) { pinned.remove(at: i) } else { pinned.append(id) }
        savePinned()
    }

    /// `id`'yi `target`'ın yerine taşır (sürükle-bırak).
    func movePinned(_ id: String, to target: String) {
        guard id != target, let from = pinned.firstIndex(of: id), let to = pinned.firstIndex(of: target) else { return }
        // Aşağı taşırken hedefin altına, yukarı taşırken üstüne düşer.
        pinned.insert(pinned.remove(at: from), at: to)
        savePinned()
    }

    /// Görünen sabitlenenler arasında bir yukarı (-1) / aşağı (+1) taşır.
    func movePinned(_ id: String, by delta: Int) {
        let visible = pinnedApps.map(\.id)
        guard let i = visible.firstIndex(of: id), visible.indices.contains(i + delta) else { return }
        movePinned(id, to: visible[i + delta])
    }

    func setPinned(_ ids: [String]) {
        pinned = ids
        savePinned()
    }

    /// Listeden gizler (sabitlemeyi de kaldırır). Ses ayarı uygulanmaya devam eder.
    func hide(_ id: String) {
        pinned.removeAll { $0 == id }
        UserDefaults.standard.set(pinned, forKey: "pinnedApps")
        if !Prefs.shared.hiddenApps.contains(id) { Prefs.shared.hiddenApps.append(id) }
    }

    /// Kayıtlı ses/sessiz/çıkış ayarlarını siler; uygulamalar %100 ve varsayılan çıkışa döner.
    func resetVolumes() {
        UserDefaults.standard.removeObject(forKey: "appSettings")
        for app in store.values {
            app.muted = false
            app.volume = 1
            app.outputDevice = nil
        }
    }

    private func savePinned() {
        UserDefaults.standard.set(pinned, forKey: "pinnedApps")
        publish(present)
    }

    // MARK: - Süreç → uygulama

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    /// XPC yardımcı süreçlerinin (WebContent, Helper vb.) "sorumlu" uygulamasını bulur.
    private static let responsiblePID: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        if let fn = responsiblePID {
            let rp = fn(pid)
            if rp > 0, let app = NSRunningApplication(processIdentifier: rp), app.bundleURL != nil { return app }
        }
        return NSRunningApplication(processIdentifier: pid)
    }
}

/// Uygulama başına ses/sessiz/çıkış ayarı; yalnızca varsayılandan farklı olanlar saklanır.
@MainActor
enum Settings {
    private static let key = "appSettings"
    private static var loading = false

    static func load(_ app: AppAudio) -> AppAudio {
        guard let s = UserDefaults.standard.dictionary(forKey: key)?[app.id] as? [String: Any] else { return app }
        loading = true
        app.volume = (s["volume"] as? Double).map(Float.init) ?? 1
        app.muted = s["muted"] as? Bool ?? false
        app.outputDeviceName = s["outputName"] as? String
        app.outputDevice = s["output"] as? String
        loading = false
        return app
    }

    static func save(_ app: AppAudio) {
        guard !loading else { return }
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        if app.volume >= 0.999 && !app.muted && app.outputDevice == nil {
            all[app.id] = nil
        } else {
            var s: [String: Any] = ["volume": Double(app.volume), "muted": app.muted]
            if let output = app.outputDevice {
                s["output"] = output
                s["outputName"] = app.outputDeviceName
            }
            all[app.id] = s
        }
        UserDefaults.standard.set(all, forKey: key)
    }
}
