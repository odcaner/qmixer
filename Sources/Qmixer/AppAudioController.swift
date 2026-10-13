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
    @Published var volume: Float = 1 { didSet { apply(); Settings.save(self) } }
    @Published var muted = false { didSet { apply(); Settings.save(self) } }
    @Published private(set) var error: String?

    fileprivate(set) var processObjects: [AudioObjectID] = []
    fileprivate var outputUID: String?
    private var tap: ProcessTap?

    init(id: String, name: String, icon: NSImage?) {
        self.id = id
        self.name = name
        self.icon = icon
    }

    fileprivate func update(name: String, icon: NSImage?, processObjects: [AudioObjectID], isPlaying: Bool, outputUID: String?) {
        if self.name != name { self.name = name }
        if self.icon == nil, let icon { self.icon = icon }
        if self.isPlaying != isPlaying { self.isPlaying = isPlaying }
        let changed = self.processObjects != processObjects || self.outputUID != outputUID
        self.processObjects = processObjects
        self.outputUID = outputUID
        if changed { apply() }
    }

    fileprivate func stop() {
        tap = nil
        processObjects = []
    }

    /// %100 ve sessiz değilse tap tutmayız: uygulamanın sesine hiç dokunulmaz.
    func apply() {
        let g: Float = muted ? 0 : volume
        guard g < 0.999, !processObjects.isEmpty, let outputUID else {
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

    /// Uygulama kapanıp açılınca ayarlar korunsun diye kaybolanları da tutarız.
    private var store: [String: AppAudio] = [:]
    private let devices: DeviceController
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(devices: DeviceController) {
        self.devices = devices
        refresh()
        CA.listen(.system, propAddr(kAudioHardwarePropertyProcessObjectList)) { [weak self] in self?.refresh() }
        devices.$defaultOutput.removeDuplicates().dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
        // "Çalıyor" durumu için özellik dinleyicisi süreç başına gerekir; periyodik okuma daha basit.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let outputUID = devices.defaultOutputUID
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
                       isPlaying: g.playing, outputUID: outputUID)
            visible.append(app)
        }
        for (key, app) in store where groups[key] == nil && !app.processObjects.isEmpty {
            app.stop()
        }

        visible.sort {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if visible.map(\.id) != apps.map(\.id) { apps = visible }
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

/// Uygulama başına ses/sessiz ayarı; yalnızca varsayılandan (%100, sesli) farklı olanlar saklanır.
@MainActor
enum Settings {
    private static let key = "appSettings"
    private static var loading = false

    static func load(_ app: AppAudio) -> AppAudio {
        guard let s = UserDefaults.standard.dictionary(forKey: key)?[app.id] as? [String: Any] else { return app }
        loading = true
        app.volume = (s["volume"] as? Double).map(Float.init) ?? 1
        app.muted = s["muted"] as? Bool ?? false
        loading = false
        return app
    }

    static func save(_ app: AppAudio) {
        guard !loading else { return }
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        if app.volume >= 0.999 && !app.muted {
            all[app.id] = nil
        } else {
            all[app.id] = ["volume": Double(app.volume), "muted": app.muted]
        }
        UserDefaults.standard.set(all, forKey: key)
    }
}
