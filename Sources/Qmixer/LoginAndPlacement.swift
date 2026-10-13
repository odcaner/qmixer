import Foundation
import ServiceManagement

/// Girişte otomatik başlatma (Sistem Ayarları > Genel > Giriş Öğeleri'nde görünür).
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled

    init() {
        // İlk açılışta varsayılan olarak etkinleştir; kullanıcı kapatırsa bir daha dokunma.
        if !UserDefaults.standard.bool(forKey: "loginItemInitialized") {
            UserDefaults.standard.set(true, forKey: "loginItemInitialized")
            set(true)
        }
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Qmixer login item: \(error)")
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

/// Menü çubuğu simgesini Wi-Fi'ın hemen soluna yerleştirir.
/// macOS konumu "sağ kenardan uzaklık" olarak saklar; Wi-Fi'ın değerini Control Center ayarlarından okuyup
/// biraz büyüğünü yazıyoruz. Status item oluşturulmadan önce çağrılmalı.
enum MenuBarPlacement {
    private static let ourKey = "NSStatusItem Preferred Position Item-0"

    static func placeNextToWiFi() {
        guard let cc = UserDefaults(suiteName: "com.apple.controlcenter"),
              let wifi = cc.object(forKey: "NSStatusItem Preferred Position WiFi") as? Double else { return }
        UserDefaults.standard.set(wifi + 1, forKey: ourKey)
    }
}
