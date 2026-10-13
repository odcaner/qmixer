import AppKit
import Combine

enum PanelSection: String, CaseIterable, Identifiable {
    case output, input, apps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .output: "Çıkış"
        case .input: "Giriş"
        case .apps: "Uygulamalar"
        }
    }
    var symbol: String {
        switch self {
        case .output: "speaker.wave.2.fill"
        case .input: "mic.fill"
        case .apps: "square.grid.2x2.fill"
        }
    }
}

enum AppSort: String, CaseIterable, Identifiable {
    case playingFirst, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playingFirst: "Ses çalanlar önce"
        case .name: "Ada göre"
        }
    }
}

enum MenuIcon: String, CaseIterable, Identifiable {
    case sliders, slidersHorizontal, dynamicSpeaker, waveform, dial, headphones, note
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sliders: "Kaydırıcılar"
        case .slidersHorizontal: "Yatay kaydırıcılar"
        case .dynamicSpeaker: "Hoparlör (ses seviyesine göre)"
        case .waveform: "Dalga"
        case .dial: "Düğme"
        case .headphones: "Kulaklık"
        case .note: "Nota"
        }
    }
    /// Önizleme ve sabit simgeler için.
    var symbol: String {
        switch self {
        case .sliders: "slider.vertical.3"
        case .slidersHorizontal: "slider.horizontal.3"
        case .dynamicSpeaker: "speaker.wave.2.fill"
        case .waveform: "waveform"
        case .dial: "dial.medium"
        case .headphones: "headphones"
        case .note: "music.note"
        }
    }
    func symbol(volume: Float, muted: Bool) -> String {
        if muted || volume <= 0.001 { return "speaker.slash.fill" }
        guard self == .dynamicSpeaker else { return symbol }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

/// Kullanıcı tercihleri; her değişiklik anında UserDefaults'a yazılır.
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    // Genel
    @Published var menuIcon: MenuIcon { didSet { d.set(menuIcon.rawValue, forKey: "menuIcon") } }
    @Published var placeNextToWiFi: Bool { didSet { d.set(placeNextToWiFi, forKey: "placeNextToWiFi") } }

    // Görünüm
    @Published var sectionOrder: [PanelSection] { didSet { d.set(sectionOrder.map(\.rawValue), forKey: "sectionOrder") } }
    @Published var hiddenSections: Set<PanelSection> { didSet { d.set(hiddenSections.map(\.rawValue), forKey: "hiddenSections") } }
    @Published var panelWidth: Double { didSet { d.set(panelWidth, forKey: "panelWidth") } }
    @Published var listMaxHeight: Double { didSet { d.set(listMaxHeight, forKey: "listMaxHeight") } }
    @Published var compactRows: Bool { didSet { d.set(compactRows, forKey: "compactRows") } }
    @Published var showPercent: Bool { didSet { d.set(showPercent, forKey: "showPercent") } }
    @Published var showAppIcons: Bool { didSet { d.set(showAppIcons, forKey: "showAppIcons") } }
    @Published var showDeviceKind: Bool { didSet { d.set(showDeviceKind, forKey: "showDeviceKind") } }

    // Uygulamalar
    @Published var appSort: AppSort { didSet { d.set(appSort.rawValue, forKey: "appSort") } }
    @Published var onlyPlaying: Bool { didSet { d.set(onlyPlaying, forKey: "onlyPlaying") } }
    @Published var hiddenApps: [String] { didSet { d.set(hiddenApps, forKey: "hiddenApps") } }

    // Cihazlar: UID → ad (bağlı değilken de adını gösterebilmek için)
    @Published var hiddenDevices: [String: String] { didSet { d.set(hiddenDevices, forKey: "hiddenDevices") } }

    static let defaultWidth = 340.0
    static let defaultListHeight = 400.0

    private init() {
        menuIcon = MenuIcon(rawValue: d.string(forKey: "menuIcon") ?? "") ?? .sliders
        placeNextToWiFi = d.object(forKey: "placeNextToWiFi") as? Bool ?? true

        let order = (d.stringArray(forKey: "sectionOrder") ?? []).compactMap(PanelSection.init(rawValue:))
        // Sonradan eklenen bölüm olursa sona ekle.
        sectionOrder = order + PanelSection.allCases.filter { !order.contains($0) }
        hiddenSections = Set((d.stringArray(forKey: "hiddenSections") ?? []).compactMap(PanelSection.init(rawValue:)))
        panelWidth = d.object(forKey: "panelWidth") as? Double ?? Self.defaultWidth
        listMaxHeight = d.object(forKey: "listMaxHeight") as? Double ?? Self.defaultListHeight
        compactRows = d.bool(forKey: "compactRows")
        showPercent = d.object(forKey: "showPercent") as? Bool ?? true
        showAppIcons = d.object(forKey: "showAppIcons") as? Bool ?? true
        showDeviceKind = d.object(forKey: "showDeviceKind") as? Bool ?? true

        appSort = AppSort(rawValue: d.string(forKey: "appSort") ?? "") ?? .playingFirst
        onlyPlaying = d.bool(forKey: "onlyPlaying")
        hiddenApps = d.stringArray(forKey: "hiddenApps") ?? []
        hiddenDevices = d.dictionary(forKey: "hiddenDevices") as? [String: String] ?? [:]
    }

    var visibleSections: [PanelSection] { sectionOrder.filter { !hiddenSections.contains($0) } }

    func resetAppearance() {
        sectionOrder = PanelSection.allCases
        hiddenSections = []
        panelWidth = Self.defaultWidth
        listMaxHeight = Self.defaultListHeight
        compactRows = false
        showPercent = true
        showAppIcons = true
        showDeviceKind = true
    }
}

/// Çalışmayan uygulamaların (sabitlenen/gizlenen) adını ve simgesini bundle ID'den bulur.
@MainActor
enum AppInfo {
    private static var cache: [String: (String, NSImage?)] = [:]

    static func lookup(_ id: String) -> (name: String, icon: NSImage?) {
        if let c = cache[id] { return c }
        var result: (String, NSImage?) = (id, nil)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let name = FileManager.default.displayName(atPath: url.path)
            result = (name.hasSuffix(".app") ? String(name.dropLast(4)) : name, NSWorkspace.shared.icon(forFile: url.path))
        }
        cache[id] = result
        return result
    }
}
