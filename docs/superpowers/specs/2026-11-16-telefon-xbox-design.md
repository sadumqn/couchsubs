# Telefonda Xbox ev yayını (Beta): tasarım

Tarih: 2026-11-16. Kapsam: Android (Kotlin) ve iPhone (Swift) uygulamalarına Xbox ev yayınıyla (xHome) altyazı çevirisi.
Windows'taki Xbox desteği (PR #139, `windows/xbox-bridge`) referanstır; ağ uçları, başlıklar ve gövdeler onunla birebir
aynıdır. Varsayılan konsol PlayStation'dır; Xbox isteğe bağlıdır ve her yerde "Beta" yazar. PS5 akışı değişmez.

## 1. Windows köprüsünün adımları ve telefondaki karşılıkları

Windows'ta Node köprüsü (`bridge.cjs`) xal-node ve xbox-webapi ile HTTPS işlerini yapar, WebView2'deki
xbox-xcloud-player (`player.html`) WebRTC'yi yürütür. Telefonda Node yok: aynı HTTPS çağrıları doğrudan
(Android `HttpURLConnection`, iOS `URLSession`), WebRTC yerel kütüphaneyle yapılır.

| Adım | Windows (köprü) | Android | iPhone |
| --- | --- | --- | --- |
| Microsoft girişi | `Msal.doDeviceCodeAuth` → `login.microsoftonline.com/consumers/oauth2/v2.0/devicecode`, istemci `1f907974-e22b-4810-a9de-d9647380c97e`, kapsam `xboxlive.signin openid profile offline_access` | `XboxAuth.startDeviceCode` (aynı istek) | `XboxAuth.startDeviceCode` |
| Kodun onayı | `doPollForDeviceCodeAuth`: `/consumers/oauth2/v2.0/token`, `grant_type=urn:ietf:params:oauth:grant-type:device_code`, saniyede bir | `XboxAuth.pollDeviceCode` (sunucunun `interval` değeri, en az 1 sn) | aynı |
| Kullanıcı jetonu yenileme | `refreshUserToken` (`grant_type=refresh_token`, 60 sn kala) | `XboxAuth.userAccessToken` | aynı |
| Xbox Live kullanıcı jetonu | `user.auth.xboxlive.com/user/authenticate`, `RpsTicket: d=<access_token>` | `XboxAuth.xblUserToken` | aynı |
| XSTS (konsol listesi) | `xsts.auth.xboxlive.com/xsts/authorize`, RP `http://xboxlive.com` | `XboxAuth.xsts("http://xboxlive.com")` | aynı |
| XSTS (yayın) | RP `http://gssv.xboxlive.com/` | `XboxAuth.xsts("http://gssv.xboxlive.com/")` | aynı |
| Yayın jetonu | `xhome.gssv-play-prod.xboxlive.com/v2/login/user`, `offeringId: xhome`; varsayılan bölgenin `baseUri`'si ve `gsToken` | `XboxAuth.homeEndpoint` | aynı |
| Konsola aktarım jetonu | `login.live.com/oauth20_token.srf`, kapsam `service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN` | `XboxAuth.transferToken` | aynı |
| Konsol listesi | xbox-webapi smartglass: `xccs.xboxlive.com/lists/devices?queryCurrentDevice=false&includeStorageDevices=true`, `Authorization: XBL3.0 x=<uhs>;<xsts>`, `x-xbl-contract-version: 4`, `skillplatform: RemoteManagement` | `XboxHome.consoles` | aynı |
| Oturum açma | `POST /v5/sessions/home/play` (gövde birebir: `nanoVersion V3;WebrtcTransport.dll`, `sdkType web`, `osName windows`, saat dilimi farkı) | `XboxHome.play` | aynı |
| Durum | `GET …/state`; `ReadyToConnect` ise `POST …/connect {userToken: <aktarım jetonu>}`; `Provisioned` olunca WebRTC | `XboxSessionMachine` + `XboxHome.state/connect` | aynı |
| SDP | `POST …/sdp` (teklif + kanal sürümleri), sonra `GET …/sdp` 250 ms arayla en çok 30 kez, `exchangeResponse` | `XboxHome.sdp` | aynı |
| ICE | `POST …/ice {messageType: iceCandidate, candidate: [...]}`, aynı bekleme; Teredo (`2001…`) adayından IPv4 adayları türetilir (9002 ve Teredo bağlantı noktası) | `XboxHome.ice` + `Teredo` | aynı |
| Canlı tutma | bağlantıdan sonra 30 sn'de bir `POST …/keepalive` | aynı | aynı |
| Kapatma | `DELETE /v5/sessions/home/<id>` | `XboxHome.stop` | aynı |

Gssv isteklerinin başlıkları köprüdekiyle aynıdır: `Authorization: Bearer <gsToken>`, `X-Gssv-Client: XboxComBrowser`,
`X-MS-Device-Info` (Surface Pro / Windows 11 JSON'u birebir). Telefon kendini masaüstü tarayıcısı gibi tanıtır; Xbox
yalnız bu istemci türünü kabul ediyor.

### SISU hakkında

Köprü xal-node'un `Msal` yolunu kullanır; `Xal` sınıfındaki SISU (cihaz jetonu, ECDSA P-256 imzalı istekler) bu yolda
yoktur. Telefonda da yalnız Msal yolu kurulur: imzalı istek, cihaz anahtarı ya da SISU jetonu gerekmez. Microsoft Msal
yolunu kapatırsa SISU'ya geçmek ayrı bir iş olur (xal-node `xal.ts`).

### Jetonların saklanması

Kalıcı olan yalnız Microsoft kullanıcı jetonudur (`access_token`, `refresh_token`, `expires_on`); biçimi Windows'un DPAPI'yle
sakladığı `userToken` JSON'uyla aynıdır. Android'de `SecretStore` (Android Keystore AES-GCM), iPhone'da Anahtar Zinciri
(`SecureStore`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). XSTS, gssv ve yayın jetonları bellekte tutulur, süresi
dolmadan (60 sn pay) yenilenir. Çıkışta kullanıcı jetonu silinir.

## 2. Görüntü: iki seçenek

### (a) Yerel WebRTC

- Android: `io.github.webrtc-sdk:android` (Maven Central, Google libwebrtc'nin LiveKit/webrtc-sdk derlemesi, BSD-3).
  H.264 donanım çözücüsü `DefaultVideoDecoderFactory` ile gelir.
- iPhone: `stasel/WebRTC` (SPM, Google libwebrtc'nin hazır xcframework'ü, BSD-3). H.264 VideoToolbox ile çözülür.
- xbox-xcloud-player'ın yaptığı her şey telefonda yeniden yazılır: dört veri kanalı (`input` ordered/`1.0`, `chat`/`chatV1`,
  `control`/`controlV1`, `message`/`messageV1`), ses `sendrecv` + görüntü `recvonly` alıcıları, SDP'de
  `useinbandfec=1` → `useinbandfec=1; stereo=1`, `message` kanalında Handshake → HandshakeAck → altı yapılandırma
  iletisi, `control` kanalında `authorizationRequest` ve `gamepadChanged`, `input` kanalında 15 baytlık ClientMetadata
  paketi. Kumanda ve dokunma girdisi gönderilmez (oyuncu konsolun kendi kumandasıyla oynar).

Kare yolu:
- Android: `VideoSink.onFrame(org.webrtc.VideoFrame)` → `buffer.toI420()` → `dataY` + `strideY`. Bu, OCR hattının
  beklediği parlaklık düzlemidir (`remoteplay.VideoFrame`); kopya ve renk dönüşümü yok.
- iPhone: `RTCVideoRenderer.renderFrame` → `RTCCVPixelBuffer` (VideoToolbox NV12) → `CGImage` (CoreImage). PS5
  oturumu da `CGImage` verir; `PhoneModel.handle` değişmez.

### (b) Gizli WebView + xbox-xcloud-player

Windows'taki gibi: görünmeyen WebView (Android `WebView`, iOS `WKWebView`) `player.html`'i açar; kareler `canvas` →
`toDataURL('image/jpeg')` → JS köprüsü → base64 çözme → JPEG çözme → parlaklık/CGImage.

### Karşılaştırma

| | (a) Yerel WebRTC | (b) Gizli WebView |
| --- | --- | --- |
| Kare OCR'a | Android'de doğrudan Y düzlemi (sıfır kopya); iOS'ta CVPixelBuffer → CGImage | 5 kare/sn JPEG, base64 köprüsü, iki kez çözme; kayıplı |
| İşlemci ve pil | Donanım çözücü, ek iş yok | Tarayıcı + canvas + JPEG kodlama/çözme |
| Arka plan | Android ön plan hizmetinde çalışır (PS5 gibi) | WebView görünmezken ve arka planda kısılır, iOS'ta durur |
| Çalışırlık | Teklifin biçimi tarayıcıdan farklı olabilir (gerçek Xbox'ta denenmeli) | Windows'la aynı kod |
| Boyut | Android arm64 ~+9 MB, iOS ~+10 MB | Ek kütüphane yok |
| Bakım | Kanal ve paket mantığı Kotlin ve Swift'te iki kez | `player.html` üç platformda ortak |

**Öneri: (a) yerel WebRTC.** Android'deki OCR hattı zaten Y düzlemi bekliyor ve libwebrtc bunu kopyasız veriyor; telefonun
pil ve ısısı için tarayıcı + JPEG yolu fazla ağır, WebView arka planda da kısılıyor. Teklifin tarayıcıdan farkı (m-satırı
sırası, kodekler) en büyük risktir; libwebrtc Chrome'la aynı kod olduğu için SDP de aynı biçimdedir. Gerçek Xbox'ta
denenince fark çıkarsa yalnız teklif düzeltilir.

### Lisans

CouchSubs AGPL-3.0'dır. xal-node, xbox-webapi, xbox-xcloud-player ve Greenlight MIT'dir: sabitler ve protokol sırası
Kotlin/Swift'e aktarılır, telif bildirimleri `THIRD-PARTY-NOTICES.md`'de ve `windows/xbox-bridge/licenses/` altında
durur. libwebrtc (webrtc-sdk Android, stasel/WebRTC iOS) BSD-3 + patent izni; AGPL ile uyumlu. H.264 çözme işletim
sisteminin donanım çözücüsüyle yapılır (kütüphane kodek taşımaz). İki seçenek de lisans açısından uygundur.

## 3. Kod yerleşimi

Android (`couchsubs-android/app/src/main/java/com/couchsubs/mobile/xbox/`):
- `XboxTokens.kt`: jeton biçimleri ve ayrıştırma (kullanıcı jetonu, XSTS, yayın jetonu, cihaz kodu), süre hesabı.
- `XboxHttp.kt`: küçük HTTP arayüzü (testlerde sahte).
- `XboxAuth.kt`: giriş ve jeton zinciri.
- `XboxHome.kt`: konsol listesi ve ev yayını uçları (play, state, connect, sdp, ice, keepalive, stop).
- `Teredo.kt`: Teredo adresinden IPv4 adayı.
- `XboxSessionMachine.kt`: durum makinesi (saf; birim testli).
- `XboxChannels.kt`: veri kanalı iletileri (Handshake, yapılandırma, ClientMetadata paketi).
- `XboxStreamSession.kt`: `FrameSource`; WebRTC, kare sayacı ve günlük.

iPhone ve Mac (ortak Swift kodu): protokol katmanı `core/Sources/CouchSubsCore/Xbox/` içinde aynı adlarla Swift dosyaları; WebRTC oturumu `remoteplay/Sources/XboxStream/XboxStreamSession.swift`. Uygulamalar `XboxStreamSession`'ı kendi `StreamControlling` protokollerine uydurur.

## 4. Oturum durum makinesi

```
Idle --start--> Starting --play ok--> Provisioning
Provisioning --state=Provisioning/Queued/...--> Provisioning (1 sn sonra yeniden sor; 90 denemede zaman aşımı)
Provisioning --state=ReadyToConnect--> Connecting (connect gönderilir, sonra yine sorulur)
Connecting/Provisioning --state=Provisioned--> Negotiating (SDP, ICE)
Negotiating --ilk kare--> Streaming
herhangi --state=Failed / hata--> Failed(neden) --5 sn--> Starting (yeniden dener; Windows'la aynı)
herhangi --stop--> Stopped
```

Hatalar kullanıcıya anlaşılır ileti olarak gider: giriş gerekli (yenileme jetonu geçersiz), konsol kapalı ya da uzaktan
oynatma kapalı, Xbox meşgul, zaman aşımı, ağ. Teknik ayrıntı günlüğe yazılır.

## 5. Arayüz

- Kurulumun ilk adımı: "Konsolunuz" — PlayStation (varsayılan) ya da Xbox (Beta).
- Xbox seçilince: Microsoft girişi (cihaz kodu, `microsoft.com/link` tarayıcıda açılır, kod kopyalanır) → Xbox listesi
  (yalnız uzaktan oynatması açık olanlar seçilebilir; kapalıysa nasıl açılacağı yazılır) → altyazı nerede.
- "İkinci hesap" (PSN) adımı Xbox'ta yoktur: Xbox yayını kendi hesabınla çalışır, konsoldaki oyun kesilmez.
- Ayarlar/Profil: konsol türü değiştirilebilir; Xbox hesabından çıkış.
- Ana ekranda konsol adı ve "Beta" etiketi; durumda kare sayacı (tanı).
- Metinler Türkçe (siz) ve İngilizce. Ücretsiz.

## 6. Test

- Birim: jeton ayrıştırma ve süre, cihaz kodu yanıtları (`authorization_pending`, `expired_token`), konsol listesi
  ayrıştırma, oturum durum makinesi, Teredo, ClientMetadata paketi, SDP düzeltmesi, sessionPath ayrıştırma.
- Derleme: Android CI (`android-app.yml`), iOS `xcodebuild build`.
- Gerçek Xbox gerekli: giriş → liste → yayın → ilk kare; ICE'nin ev ağında (aynı Wi-Fi) ve dışarıda kurulması.
