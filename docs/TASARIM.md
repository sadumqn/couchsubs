# CouchSubs tasarım standardı

Mac ve Windows uygulamaları aynı görünür. Bu belge neyin nasıl göründüğünü, `design/tokens.json`
ise sayısal değerleri tanımlar. Değer değişecekse yalnız `tokens.json` düzenlenir; uygulamalar onu
doğrudan okur. Belge ile kod çelişirse `tokens.json` geçerlidir.

## İlke

Bento: ekran, aynı boşlukla dizilmiş yuvarlak köşeli karolardan oluşur. Tek eylem rengi (altyazı sarısı),
oyun paketleri için mor, sakin koyu zemin, büyük ve okunaklı yazı. Uygulama TV karşısında, biraz uzaktan
bakılarak kullanılır; her şey bir bakışta okunmalı. Telefon uygulamalarıyla ortak dil; tasarım tuvali:
https://claude.ai/artifact/UQhATNYKLby6t52HQCvSu9 (masaüstü aynı dili daha geniş ölçülerle kullanır).

1. **Tek ızgara, tek boşluk.** Pencere kenarı her yerde 32, karolar arası 16, karo içi 20.
2. **Beş yazı boyu** (30/22/17/15/13). Altyazı içeriği hariç başka boy kullanılmaz.
3. **Bir ekranda tek birincil düğme.**
4. **Parıltı anlam taşır.** Yalnız etkin, canlı ya da öne çıkan şey parlar: birincil düğme, seçili karo, canlı
   altyazı karosu, canlı nokta, paket karosu. Her şey parlarsa hiçbir şey parlamaz.
5. **Metin her zaman okunur.** Parıltı ve degrade metin kontrastını AA'nın altına düşüremez.

Masaüstünde ücret, paywall ve Pro yoktur; oyun paketleri ücretsizdir ("Ücretsiz" hapı).

## Logo

- Kaynak: `design/logo.svg` (vektör). Arkalığı ekran gibi duran, üstünde iki sarı altyazı satırı
  olan bir kanepe; koyu grafit zemin.
- Simgeler `swift scripts/make-icons.swift` ile üretilir (macOS simge seti, uygulama içi logo,
  TV uygulaması simgeleri, `design/logo-1024.png`). Windows için `.ico` aynı SVG'den üretilir.
- Logo değiştirilmez, yeniden renklendirilmez, gölge eklenmez. Uygulama içinde en az 32 pt.

## Renk

Her renk açık ve koyu görünüm için ayrı tanımlıdır; uygulama sistemin görünümünü izler.

| Ad | Kullanım |
|---|---|
| `background` | Pencere zemini (üstüne iki yumuşak ışık, bkz. Parıltı) |
| `surface` | Karolar |
| `surface2` | Alan, ikincil düğme, kenar çubuğunda seçili satır |
| `tileBorder` | Karo çerçevesi (koyuda %7 beyazın düz karşılığı) |
| `border` | Alan çerçevesi, ayraçlar, ilerleme çubuğu zemini |
| `textPrimary` | Ana metin |
| `textSecondary` | Açıklamalar, ikincil bilgiler |
| `accent` | Birincil düğme, ilerleme, seçili bölge (yalnız dolgu olarak; metin rengi değildir) |
| `onAccent` | Sarı düğme üstündeki yazı |
| `accentText` | Sarı tonda metin ve simgeler (açık görünümde koyulaştırılmış) |
| `accentHi` | Birincil düğme degradesinin üstü |
| `accentSoft` | Simge rozeti ve numara dairesi zemini |
| `pro` / `proSoft` | Yalnız oyun paketleri: mor yazı ve simge / mor tonlu zemin. Sarı eylem demek, mor paket demek |
| `success` / `successSoft` | Bağlı, canlı; yeşil tonlu zemin (durum karosunun simgesi, "Ücretsiz" hapı) |
| `warning` | Dikkat |
| `danger` / `dangerSoft` / `dangerBorder` | "Çeviriyi durdur", "Yeniden kur": kırmızı yazı, kırmızı tonlu zemin ve çerçeve |
| `onDanger` | Dolu kırmızı zemin üstündeki yazı |

### Parıltı

`tokens.json` › `glow`: renk, saydamlık, bulanıklık yarıçapı (CSS biçiminde) ve dikey kayma.

| Ad | Nerede |
|---|---|
| `primary` + `primaryDrop` | Birincil düğme (basılıyken ve devre dışıyken yok) |
| `activeTile` + `activeBorder` | Etkin karo: canlı altyazı (çeviri sürerken), seçili çeviri motoru |
| `pro` | Paket karosu (mor→sarı degrade çerçeve) |
| `backgroundAccent` / `backgroundPro` | Pencere zemininde sağ üstte sarı, sol altta mor radyal ışık; hareketsiz |

Canlı nokta (8 pt yeşil, 1,6 sn'de bir genişleyip sönen halka) "Bağlı" ve "Çevriliyor" yanında; tarama ışığı
(canlı altyazı karosunun üst kenarında akan ince sarı çizgi) yalnız çeviri sürerken. Azaltılmış hareket açıkken
halka ve tarama durur, parıltılar kalır.

Okunaklılık kuralı (Mac'te `ThemeTests` ile denetlenir; Windows'ta da aynı test yazılır):
ana metin zeminlere karşı en az 7:1, diğer tüm metinler en az 4,5:1 kontrastta olur.

## Yazı

Sistem yazı tipi: Mac'te SF Pro, Windows'ta Segoe UI Variable. Boyutlar nokta (pt) cinsinden;
Windows'ta aynı sayılar efektif piksel (epx) olarak kullanılır.

| Ad | Boyut | Kalınlık | Kullanım |
|---|---|---|---|
| `display` | 30 | kalın, harf aralığı −0,4 | Ekran başlığı (sihirbaz adımı, ayarlar bölümü); ekran başına bir |
| `title` | 22 | yarı kalın | Uygulama adı, kenar çubuğu başlığı |
| `headline` | 17 | yarı kalın | Karo başlığı, karodaki değer |
| `body` | 15 | normal | Tüm metinler (varsayılan) |
| `callout` / `caption` | 13 | orta | Karo etiketi, açıklama ve ipuçları, rozet, yasal not; ikincil renkte |
| `button` | 17 | yarı kalın | Düğme yazısı (`headline` ile aynı boy) |
| `code` | 22 | yarı kalın, eş genişlikli rakam | PS5 eşleme kodu |

Altyazı içeriği arayüz değil içeriktir: canlı altyazı karosunda son satır 28 pt yarı kalın, öncekiler 17 pt
normal ve %75 / %60 opaklıkla. Paragraflarda satır arası yazı boyutunun yaklaşık 1,3 katıdır. 13 pt'nin altı
kullanılmaz.

## Boşluk ve biçim

- Boşluk: `screen` 32 (pencere kenarı), `gap` 16 (karolar ve bölümler arası), `tile` 20 (karo içi), `inline` 8
  (simge ile yazı), `hair` 4 (başlık ile altındaki satır). Eski ölçek (`xs` 4 … `xxl` 32) karo içindeki küçük
  aralıklar için durur.
- Köşe: karolar `card` 24, denetimler (düğme, alan, bölmeli seçim) `control` 16, karo içindeki küçük kutular
  (simge, paket rozeti, kenar çubuğu satırı) `inner` 12, hap ve anahtar `pill`.
- Pencere 1040 × 720 (iki sütun: sol `mainColumn` 380, sağ esnek); kenar çubuğu `sidebarWidth` 240.
  Mac'te Ayarlar pencerenin üstünde sayfa (sheet) olarak 976 × 656; Windows'ta ayrı pencere.

## Bileşenler

Her iki platformda aynı adla bulunur.

- **LogoView** – logo, kenar boşluğu kırpılmış hâliyle; koyu temada kenarı seçilsin diye 1 pt `border` çerçeve.
- **Düğme** – yükseklik 44 (`buttonHeight`), sihirbazın Geri / Devam ve Ayarların Bitti düğmesi 52 (`buttonLarge`),
  ana ekrandaki "Çeviriyi başlat/durdur" 64 (`primaryActionHeight`), yatay iç boşluk `tile`.
  - *Birincil*: `accentHi`→`accent` degrade dolgu, `onAccent` yazı, `primary` parıltı. Ekranda en fazla bir tane.
  - *İkincil*: `surface2` dolgu, `border` çerçeve, `textPrimary` yazı.
  - *Tehlikeli*: `dangerSoft` dolgu, `danger` yazı, `dangerBorder` çerçeve ("Çeviriyi durdur", "Yeniden kur").
  - *Hayalet*: dolgusuz, `accentText` yazı.
  - Basılıyken %96 ölçek ve parıltı yok; devre dışıyken %40 saydamlık, parıltı yok.
- **Card (karo)** – `surface` zemin, üstten %4 beyaz ışık, 1 pt `tileBorder` çerçeve, `card` köşe, `tile` iç boşluk,
  isteğe bağlı `headline` başlık. Türleri: *düz*, *etkin* (`activeBorder` çerçeve + `activeTile` parıltı),
  *paket* (`proSoft`→`surface` zemin, `pro`→`accent` degrade çerçeve, `pro` parıltı).
- **StatusTile** – durum karosu: solda 36 pt TileIcon (bağlıysa yeşil, `successSoft` zemin), sağda canlı nokta;
  altında `caption` ad ve `headline` değer.
- **TileIcon** – 36 × 36 (`tileIcon`), `inner` köşe, renkli simge ve aynı rengin yumuşak zemini.
- **Pill** – 28 yükseklik, yuvarlak uçlu, yarı kalın `caption`; tonlu zemin (sarı, mor, yeşil, gri), isteğe bağlı
  canlı nokta.
- **Kenar çubuğu** – `sidebarWidth` genişliğinde karo; üstte `title` başlık, altında satırlar (simge + `body`);
  seçili satır `surface2` zemin, sarı simge, yarı kalın yazı.
- **IconBadge** – 48 × 48, `accentSoft` zemin, `accentText` simge, `inner` köşe.
- **StepLayout** – sihirbaz adımı: IconBadge, `display` başlık, `body`/`textSecondary` açıklama, içerik.
- **NumberedRow** – 26 pt `accentSoft` dairede numara, yanında `body` metin.
- **StatusRow** – 10 pt durum noktası, kalın ad, sağda değer. Nokta: bağlı `success`, çeviri sürerken
  bağlantı yok `warning`, çeviri başlamamışken `textSecondary` (boşta olmak uyarı değildir).
- **Metin alanı** – `surface2` zemin, 1 pt `border` çerçeve, `control` köşe, en az 44 yükseklik; PS5 kodu
  alanı 52 yükseklik ve `code` yazı. Etiketi alanın üstünde `callout`/`textSecondary`.
- **Bölmeli seçim** – 2–4 seçenek: `surface2` ray (`control` köşe, 4 iç boşluk), seçili parça `surface` zeminli,
  ince sarı halka ve hafif parıltı (Mac'te sistemin büyük boy segmented denetimi).
- **Seçenek karoları** – her seçeneğin kısa notu olan seçim (çeviri motoru): yan yana küçük karolar (ad
  `headline`, not `caption`), seçili olan *etkin* karo.
- **Anahtar** – açık/kapalı ayarlar (oyun paketleri, ortak havuz): başlık solda, anahtar sağda.
- **Kaydırıcı** – ince ray (`border`), dolu kısım `accent`, yuvarlak tutamaç.
- **Bağlantı** – `accentText` renginde.
- **DoneLabel** – `success` renkli onay simgesi ve metin.
- **HintText** – `callout`, `textSecondary`.
- **ErrorText** – `callout`, `warning`, uyarı simgesi.
- **ProgressBar** – 6 pt yüksek, yuvarlak uçlu; zemin `border`, dolu kısım `accent`.

## Ekranlar

**Kurulum sihirbazı**: solda kenar çubuğu (logo + "Kurulum"; adımlar: biten adım yeşil onaylı, sıradaki adım sarı
numaralı ve vurgulu, gelecek adım gri numaralı; altta "Adım n / toplam" ve ilerleme çubuğu); sağda adımın karosu
(kaydırılabilir StepLayout), altında solda "Geri" (ikincil), sağda "Devam" (birincil). Son adım isteğe bağlı "Daha iyi çeviri (ücretsiz)": tek cümle
açıklama, numaralı üç satır ve "Ücretsiz anahtar al" (birincil, Google AI Studio'nun anahtar sayfası),
gizli anahtar alanı ve "Kaydet ve dene" (ikincil), altta veri kullanımı ve dakikalık sınır HintText'i.
Anahtar yokken alttaki düğme "Şimdilik geç" (ikincil) olur; kaydedilince "Gemini hazır" (DoneLabel) ve "Devam".

**Ana ekran** (bento, iki sütun): üstte logo + "CouchSubs" + sağda "Ayarlar" (ikincil, dişli simgeli).
Sol sütun: "Çeviriyi başlat" (birincil) ya da "Çeviriyi durdur" (tehlikeli), 64 yükseklik; altında iki sütunlu
karolar: PS5 ve TV durum karoları (altyazı yalnız bilgisayar ekranındaysa TV karosu yoktur; TV seçili ama bağlı
değilse "Kurulmadı" ve "TV bağla"), iki sütun genişliğinde "Altyazıyı göster: TV / Bilgisayar ekranı / İkisi de"
karosu (bilgisayar ekranı seçiliyse "Tıklamalar geçsin" ve "Altyazı penceresini ayarla"), "Çeviri" (seçili motor)
ve "Kısayol" (ekranı çevir) karoları; gerekiyorsa uyarı karoları (dil paketi, çevrimiçi motor, yazı tanıma).
Sağ sütun: oyun paketleri açıksa (İngilizce→Türkçe, paket kurulu) mor paket karosu "Oyun paketleri açık · n oyunun
çevirisi hazır"; altında kalan yüksekliği dolduran "Canlı altyazı" karosu: son çeviri 28 pt, altında özgün metin
`caption`; önceki satırlar ayraçlarla, soluk ve kaydırılabilir. Çeviri sürerken karo etkin parlar, sağ üstte
"Çevriliyor" hapı (canlı nokta) ve üst kenarda tarama ışığı.

**Ayarlar**: solda kenar çubuğu ("Ayarlar" ve bölümler: Altyazı görünümü, Türkçe dublaj, Çeviri, Oyun paketleri,
Dil, Altyazı bölgesi, OBS katmanı, Hakkında; Windows'ta TV uygulaması da), sağda seçili bölümün `display` başlığı
ve karoları; altta sağda "Bitti" (birincil). "Altyazı görünümü" bölümünde "Altyazıyı göster" karosu, "TV'de" karosu
(yazı boyutu, ekrandaki konum, test altyazısı) ve gerekiyorsa TV uygulaması karosu.
"Oyun paketleri" bölümünde başlığın yanında yeşil "Ücretsiz · n oyun" hapı, açıklama, iki sütunlu paket karoları
(mor kısaltma rozeti, ad, "n satır") ve altta anahtarlı satırlar: "Oyun paketlerini kullan", "Okunan İngilizce
altyazıları ortak havuza gönder" (varsayılan açık) ve tek satırlık HintText.
"Çeviri" bölümündeki "Çeviri motoru" karosunda motor seçimi seçenek karolarıyla (Ücretsiz, DeepL, Gemini, OpenAI,
Claude; her birinin altında kısa not); ücretli motorda kısa açıklama, model
seçimi, gizli anahtar alanı ve "Kaydet ve dene" (ikincil), anahtar sayfası bağlantısı, kayıtlıysa "Anahtar kayıtlı" (DoneLabel) ile
"Dene" ve "Anahtarı sil" (ikincil). Model yazılamaz; "Model" seçiminde yalnız ortak listedeki modeller
(`core/Sources/CouchSubsCore/Resources/ai-models.json`) sade adlarıyla görünür. Sonuç HintText, hata ErrorText olur.
Ücretsiz motor seçiliyken altında "Daha iyi çeviri için ücretsiz Gemini anahtarı alın." ve "Ücretsiz anahtar al"
(ikincil; Gemini'yi seçer ve anahtar sayfasını açar) durur; Gemini seçiliyken veri kullanımı ve dakikalık sınır HintText'i görünür.
Çevrimiçi motor çeviri sırasında hata verirse ana ekranda uyarı karosu çıkar. Kurulumun son adımında ortak havuz
bir HintText ile söylenir. Altyazı bilgisayar ekranında da gösteriliyorsa "TV'de" karosunun adı "Altyazı görünümü"
olur (aynı ayarlar pencereye de uygulanır).

**Kurulum, TV adımı**: TV aramasının altında "TV'm yok, bilgisayar ekranında göster" kartı (ikincil "Seç"). Seçilince
TV kurulumu atlanır, deneme adımı örnek altyazıyı bilgisayar ekranında gösterir.

**Bilgisayar ekranındaki altyazı penceresi**: kenarsız, saydam zeminli, her pencerenin (tam ekran oyun ve PS Remote
Play dahil) üstünde; odağı almaz, görev çubuğunda / Dock'ta görünmez. Altyazı kutusu TV'dekinin aynısıdır (yazı boyu
1080 satırlık ekrana göre ölçeklenir, beyaz ya da sarı yazı, siyah yarı saydam zemin, üstteki satırlar küçük ve soluk,
en çok üç satır). Altyazı yokken pencere gizlenir. "Tıklamalar geçsin" kapalıyken yazıdan tutup sürüklenir; açıkken
fare alttaki pencereye gider, geri almak için Mac'te ⌥⌘L ya da menü çubuğundaki CouchSubs simgesi, Windows'ta Num 7
ya da ana ekran. "Altyazı penceresini ayarla": `accent` kesik çizgili çerçeve, üstte açıklama ve "Bitti" (birincil),
iki yanda genişletme tutamakları; yer, genişlik ve ekran hatırlanır.

**Hakkında**: 88 pt logo, ad, sürüm, lisans, teşekkür, bağlantılar, Sony ile ilişkisizlik notu.

## TV uygulaması

TV'de her zaman koyu temanın renkleri kullanılır (oyunun üstünde durur). Bilgi paneli ve "uygulamayı açın"
ekranı `background` %92–94 saydam zemin, 2 px `border` çerçeve, 24–32 px köşe; başlıkta logo. Kumanda
tuşları satır satır, tuş adı `accent` renginde. Altyazı kutusu siyah %72 saydam zemin üstünde beyaz,
yarı kalın yazı (okunaklılık için tema rengi değil). Bekleme ekranı açıkken panel kendiliğinden açılmaz.
Bekleme ekranında tek düğme "Demoyu izle"dir; seçili düğme `accent` dolgu ve beyaz çerçeveyle belli olur.
Demo sırasında sağ üstte panel biçiminde "DEMO" notu durur. Geri tuşu önce demoyu ya da paneli kapatır,
giriş ekranında TV'nin ana ekranına döner (mağaza kuralı).

## Windows'a aktarım

- `tokens.json` uygulamayla birlikte paketlenir ve açılışta okunur (Mac ile aynı yöntem);
  renkler açık/koyu tema kaynaklarına, boyutlar yazı ve boşluk kaynaklarına dönüştürülür.
- Yazı tipi Segoe UI Variable; sayılar yukarıdaki tablodakiyle aynı.
- Pencere zemini `background` rengi ve iki radyal ışıktır (Mica/Acrylic gibi saydam efektler kullanılmaz);
  parıltılar `DropShadowEffect` ile çizilir.
- Bileşenler yukarıdaki adlarla kurulur; ekran düzenleri birebir aynıdır.
- Kontrast testi Windows test projesine de eklenir.
