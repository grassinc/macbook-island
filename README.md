# Pill — macOS üçün Dynamic Island

2020-ci il M1 MacBook Air üçün yazılmış, ekranın yuxarı ortasında dayanan üzən
pill. Bu maşında fiziki notch yoxdur (notch 2022-ci ildə M2 Air ilə gəlib),
ona görə də pill menyu zolağının üstündə sərbəst şəkildə genişlənib yığıla bilir.

Native Swift/SwiftUI. Boş dayananda **0.0% CPU** — hər şey hadisəyə əsaslanır,
heç bir polling taymeri yoxdur.

---

## Necə işləyir

| Vəziyyət | Nə görünür |
|---|---|
| **Sakit** | `🔋 60%, Online` — batareya və şəbəkə |
| **Musiqi çalarkən** | Mahnının adı və ifaçı |
| **Üzərinə gələndə** | Tam panel: pleyer, rəf, sürətli əməliyyatlar |
| **Hadisə baş verəndə** | Səs/parlaqlıq, AirPods qoşulması, Caps Lock, ekran şəkli |

Pill fokusu heç vaxt oğurlamır, Mission Control və ⌘-Tab siyahısında görünmür.

---

## İmkanlar

### Media
- **Spotify pleyeri** — albom şəkli, ad və ifaçı, keçən/ümumi vaxt, canlı
  scrubber, əvvəlki/oynat-dayandır/növbəti düymələri
- **Səs mənbəyinin təyini** — hansı tətbiqin səs çıxardığını CoreAudio ilə görür
- **Çıxış cihazını dəyişmək** — `OUTPUT` düyməsi ilə bir kliklə

### Fayllar
- **Rəf (Shelf)** — faylı içinə atın, sonra istənilən tətbiqə sürüşdürün.
  Tətbiq bağlansa və kompüter söndürülsə də qalır
- **Çevirmə əməliyyatları** — HEIC→JPEG, ölçü dəyişmə, EXIF təmizləmə,
  PDF-ə çevirmə, zip. Orijinal fayl **heç vaxt** üzərinə yazılmır
- **Ekran şəkli tepsisi** — yeni ekran şəkilləri avtomatik rəfə düşür

### Sistem
- **Səs və parlaqlıq HUD-u** — Apple-ın öz overlay-ini əvəz edir
- **Batareya** — Mac və Bluetooth aksesuarları, aşağı səviyyə xəbərdarlığı
- **80%-də çıxart** — M-serialı üçün batareya ömrü məsləhəti
- **Bluetooth hadisələri** — AirPods və digər cihazların qoşulub-ayrılması,
  cihaz növünə uyğun ikonla
- **Şəbəkə** — onlayn/oflayn vəziyyəti
- **İstilik** — yalnız *serious*/*critical* səviyyəsində xəbərdarlıq edir
  (M1 Air soyuducusuzdur, ona görə bu vacibdir)
- **Caps Lock** — açılıb-bağlandığı an göstərilir
- **Sürətli əməliyyatlar** — ekran sahəsini çəkmək, ekran yazısı, tema dəyişmək

### Digər
- **Taymerlər** — Pomodoro, 5 dəq, 25 dəq
- **Təqvim** — növbəti hadisə, geri sayım, video linkə bir kliklə qoşulmaq
- **Ekran paylaşımı rejimi** — hadisə adlarını gizlədir, konfrans tətbiqlərini
  avtomatik tanıyır
- **Yerini dəyişmək** — pill-i sürüşdürün; `⌘/` onu ilkin yerinə qaytarır

---

## Tələblər

- macOS 26 (Tahoe) və ya daha yeni
- Apple silicon
- Xcode Command Line Tools (Swift 6.3+)

```bash
xcode-select --install
```

---

## Quraşdırma

```bash
git clone https://github.com/grassinc/macbook-island.git
cd macbook-island
./scripts/build-app.sh
open build/Pill.app
```

`build-app.sh` tətbiqi `Pill Local Dev` adlı lokal sertifikatla imzalayır.
Bu vacibdir: **ad-hoc imza hər yığımda dəyişir**, ona görə də verdiyiniz
icazələr hər dəfə sıfırlanır. Sertifikatla isə icazələr qalır.
Sertifikatın yaradılması `signing/README.md`-də izah olunub.

---

## İcazələr

| İcazə | Nəyə lazımdır | Olmasa nə olur |
|---|---|---|
| **Accessibility** | Səs/parlaqlıq HUD-u, Caps Lock | Apple-ın öz HUD-u qalır |
| **Automation** | Spotify pleyeri, tema dəyişmək | Yalnız tətbiqin adı görünür |
| **Bluetooth** | Cihaz qoşulma bildirişləri | Bluetooth hadisələri görünmür |
| **Təqvim** | Növbəti hadisə | Təqvim sətri gizli qalır |
| **Screen Recording** | Ekran şəkli və yazısı | Bu düymələr işləmir |

Hər biri lazım olan anda soruşulur, hamısı başlanğıcda deyil.

> **Qeyd:** Apple-ın öz səs HUD-unu tam söndürmək mümkün deyil — SIP buna
> imkan vermir (`launchctl bootout` → *"Operation not permitted while System
> Integrity Protection is engaged"*). Yeganə yol düymələri tutub sistemə
> ötürməməkdir, bu da Accessibility icazəsi tələb edir.

---

## `.env` faylı

API açarları `.env` faylında saxlanılır və **heç vaxt git-ə göndərilmir**.

```bash
cp .env.example .env
```

Fayl bu ardıcıllıqla axtarılır:

1. `PILL_ENV_FILE` mühit dəyişəni
2. `~/Library/Application Support/Pill/.env` — paketlənmiş tətbiq üçün
3. Cari qovluqdakı `.env` — `swift run` üçün

Hazırda heç bir açar tələb olunmur: Spotify AppleScript ilə idarə olunur,
bütün sistem məlumatları isə açıq API-lərdən oxunur.

---

## Şəbəkəyə görə profillər

Müəyyən bir Wi-Fi şəbəkəsinə qoşulanda pill özünü avtomatik tənzimləyə bilər —
məsələn universitetdə ekran paylaşımı rejimini özü açsın.

```bash
cp profiles.example.json ~/Library/Application\ Support/Pill/profiles.json
```

| Sahə | Mənası |
|---|---|
| `name` | Paneldə göstərilən ad |
| `ssid` | Şəbəkənin adı (Məkan icazəsi tələb edir) |
| `gateway` | Router-in MAC ünvanı — **icazə tələb etmir** |
| `screenShare` | Bu şəbəkədə ekran paylaşımı rejimini avtomatik aç |
| `hideFromCapture` | Pill-i ekran yazısından tamamilə gizlət |

**Niyə `gateway`?** macOS 14-dən sonra Wi-Fi adını (SSID) oxumaq üçün Məkan
(Location Services) icazəsi lazımdır — bu maşında yoxlanılıb: `CWInterface.ssid()`
`nil` qaytarır. Router-in MAC ünvanı isə icazəsiz oxunur, hər router üçün sabitdir
və şəbəkəni eyni dərəcədə yaxşı tanıdır — özü də harada olduğunuzu bilmədən.

MAC ünvanını tapmaq üçün:

```bash
arp -n $(route -n get default | awk '/gateway:/{print $2}')
```

Qısa və uzun yazılış (`0:9:f:...` və `00:09:0f:...`) eyni sayılır.

Profil tətbiq olunanda geri qaytarılmır: şəbəkədən çıxanda sizin əlinizlə
açdığınız rejim söndürülmür.

---

## Ekran yazısından gizlənmə

Paneldəki **göz** işarəsinə klikləyəndə (qırmızı olanda) pill ekran yazısı və
ekran şəkillərində **ümumiyyətlə görünmür** — mətnin gizlədilməsi deyil, pəncərə
tamamilə kadrın xaricində qalır (`NSWindow.sharingType = .none`).

Göz sönülü olanda pill normal görünür.

---

## Arxitektura

```
Sources/
  PillCore/     Təmiz məntiq — AppKit yoxdur, test olunandır
  Pill/
    Window/     Fokus oğurlamayan NSPanel, yerləşmə, qlobal qısayol
    Modules/    Hər imkan öz modulu (audio, shelf, HUD, bluetooth, ...)
    UI/         SwiftUI görünüşləri
Tests/          251 yoxlama
```

Modul yalnız `ModuleContext` görür — pəncərəyə, koordinatora və ya başqa modula
əli çatmır. Modul `Activity` dərc edir, koordinator isə hansının göstəriləcəyinə
prioritetə görə qərar verir: `ambient` → `info` → `transient` → `interruptive`.

Panelin hündürlüyü **ölçülür, hesablanmır**. Bölmələrin hündürlüyünü toplamaq
`VStack` aralıqlarını unudur və panelin altını kəsir.

### Testlər

```bash
swift run PillCoreTests
```

Command Line Tools nə XCTest, nə də swift-testing gətirir, ona görə
`Tests/PillCoreTests/Harness.swift` içində kiçik öz test qoşqumuz var.

---

## Məhdudiyyətlər (dürüst siyahı)

Bunlar sınaqdan keçirilib və **mümkün deyil**:

- **AirPods/Magic Mouse batareyası** — açıq API yoxdur
- **MediaRemote now-playing** — birbaşa çağırıldı, üçüncü tərəf tətbiqlər üçün
  `nil` qaytarır. Buna görə pleyer CoreAudio + AppleScript üzərindən işləyir
- **Klaviatura işığının HUD-u** — yazma yolu tapılmadı, düymələr toxunulmadan ötürülür
- **Tətbiq bildirişlərinin tutulması** — Notification Center bazasını oxumaq və
  Accessibility ilə banner-i qırxmaq layihə şərtlərində qadağandır, başqa açıq
  yol isə yoxdur. Bluetooth hadisələri bildiriş deyil, sistem vəziyyətidir —
  ona görə onlar işləyir

Hələ görülməyib: buferin tarixçəsi, endirmə göstəriciləri, mikrofon/kamera
indikatoru, Shortcuts inteqrasiyası, Focus rejiminə görə widget dəstləri.

Bilinən qüsur: tam ekran rejimində gizlənmə məntiqi yazılıb və test olunub,
lakin hələ `activeSpaceDidChange`-ə qoşulmayıb.

---

## Lisenziya

MIT
