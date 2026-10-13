# Qmixer

macOS menü çubuğu ses mikseri: her uygulamanın sesini ayrı ayrı kısın veya susturun,
giriş/çıkış cihazlarını tek yerden yönetin.

- Uygulama başına ses seviyesi ve sessiz (ayarlar kalıcı)
- %25 / %50 / %75 / %100 dilimli, dilimlere yapışan kaydırıcılar (⌥ ile serbest)
- Uygulamaları üste sabitleme, sürükle-bırak ile sıralama, listeden gizleme
- Çıkış/giriş cihazı seçimi (Denetim Merkezi tarzı), cihaz sesi ve sessiz
- Ayarlar: bölüm sırası/görünürlüğü, panel boyutu, kompakt mod, menü çubuğu simgesi,
  cihaz gizleme, dil
- Diller: Türkçe, English, Français, Español, Русский, 日本語, 简体中文
- Dock'ta görünmez, menü çubuğunda Wi-Fi'ın soluna yerleşir
- Girişte otomatik başlar

Gereksinim: macOS 14.2+ (Core Audio process tap API'si). Apple Silicon + Intel.

## Kurulum

[Releases](../../releases) sayfasından `Qmixer-x.y.z.dmg` indirin; ayrıntılar `KURULUM.txt` içinde.
Uygulama notarize edilmediği için ilk açılışta macOS engeller:
Sistem Ayarları › Gizlilik ve Güvenlik › **Yine de Aç**, ya da

```sh
xattr -dr com.apple.quarantine /Applications/Qmixer.app
```

## Derleme

Xcode gerekmez, Command Line Tools yeterli.

```sh
./build.sh               # derle, imzala, /Applications'a kur ve çalıştır
./build.sh --no-install  # sadece dist/Qmixer.app
./dmg.sh                 # dist/Qmixer-<sürüm>.dmg
```

Sürüm numarası `Resources/Info.plist` içindeki `CFBundleShortVersionString`.

Çeviriler `Resources/<dil>.lproj/Localizable.strings` içinde; anahtarlar Türkçe kaynak metinlerdir.
Test için: `open -n dist/Qmixer.app --args -AppleLanguages "(ja)" --panel` (veya `--settings 0-3`).

## Nasıl çalışır

Ses seviyesi %100'den farklı (veya sessiz) olan her uygulama için:

```
uygulama süreçleri ─► CATap (mutedWhenTapped) ─► özel aggregate cihaz ─► IOProc (× kazanç) ─► varsayılan çıkış
```

%100'deki uygulamaların sesine hiç dokunulmaz. Yardımcı süreçler (Chrome Helper, Safari WebContent)
"sorumlu" uygulamaya göre gruplanır.
