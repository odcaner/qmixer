import Foundation

/// Çeviri anahtarları Türkçe metnin kendisi; diğer diller Resources/<dil>.lproj/Localizable.strings içinde.
/// SwiftUI `Text("...")` sabitlerini kendisi çevirir; `String` olarak taşınan metinler için bu kullanılır.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// Dile göre yüzde yazımı: tr "%25", en "25%", fr "25 %".
func percentText(_ n: Int) -> String {
    String(format: L("%%%d"), n)
}

/// Arayüzün o anki dili (büyük harfe çevirme vb. için; Türkçe i/İ doğru olsun).
let uiLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

enum AppLanguage {
    /// "" = sistem dili. Ad her dilde kendi yazımıyla gösterilir.
    static let options: [(code: String, name: String)] = [
        ("tr", "Türkçe"), ("en", "English"), ("fr", "Français"), ("es", "Español"),
        ("ru", "Русский"), ("ja", "日本語"), ("zh-Hans", "简体中文"),
    ]

    /// Açılıştaki seçim; değişiklik yeniden başlatınca geçerli olur.
    static let atLaunch = override

    /// Uygulamaya özel dil seçimi (macOS'un AppleLanguages tercihi, yalnızca bu uygulama için).
    static var override: String {
        get { (UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first ?? "" }
        set {
            if newValue.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            else { UserDefaults.standard.set([newValue], forKey: "AppleLanguages") }
        }
    }
}
