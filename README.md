# Qmixer

macOS menü çubuğu ses mikseri: her uygulamanın sesini ayrı ayrı kısın veya susturun,
giriş/çıkış cihazlarını tek yerden yönetin.

- Uygulama başına ses seviyesi ve sessiz (ayarlar kalıcı)
- Çıkış/giriş cihazı seçimi, cihaz sesi ve sessiz
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

## Nasıl çalışır

Ses seviyesi %100'den farklı (veya sessiz) olan her uygulama için:

```
uygulama süreçleri ─► CATap (mutedWhenTapped) ─► özel aggregate cihaz ─► IOProc (× kazanç) ─► varsayılan çıkış
```

%100'deki uygulamaların sesine hiç dokunulmaz. Yardımcı süreçler (Chrome Helper, Safari WebContent)
"sorumlu" uygulamaya göre gruplanır.
