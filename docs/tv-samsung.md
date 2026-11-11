# Samsung TV (Tizen) uygulaması

Durum: gerçek Samsung TV'de (75" Neo QLED) kuruldu ve çalıştı. Kurulum
adımları: [tv-kurulum.md](tv-kurulum.md#samsung-tv).

## Yapı

Arayüz kodu LG ile ortaktır (`tv-webos/`). Samsung'a özgü olanlar `tv-tizen/` içindedir:

- `platform.js`: HDMI görüntüsü (`tizen.tvwindow`, `BEHIND`), kumanda tuşları, başlatma parametreleri
- `config.xml`: uygulama kimliği ve izinler

`./scripts/package-tizen.sh` bunları `dist/tv-tizen/app` altında toplar.

## Denenecekler

- HDMI görüntüsü altyazının arkasında görünüyor mu, ses geliyor mu?
- Tek bağlı HDMI otomatik seçiliyor mu?
- Sayı ve renk tuşu olmayan kumandada Tamam paneli açıyor, sol ve sağ HDMI girişini değiştiriyor mu?
- Bilgisayardan `ed.apps.launch` ile uygulama açılabiliyor mu? Yeni modellerde çalışmadığını bildirenler var.

## LG'den farkı

Samsung'da paket, TV'nin DUID'ini içeren distributor sertifikasıyla imzalanır. Bu yüzden tek bir paketi herkesin
TV'sine kurmak mümkün değildir. Mac ve Windows uygulamaları bunu kullanıcının yerine yapar
(`windows/src/CouchSubs.TvInstall/Samsung/`; Mac'te aynı kod gömülü `couchsubs-tv-helper` ile çalışır):

1. sdb (26101) ile TV'ye bağlanır, `0 vd_applist` ile TV'deki CouchSubs sürümüne bakar (güncelse burada durur),
   `0 getduid` ile DUID'i okur.
2. Bu TV için geçerli sertifika yoksa Samsung'un SignInGate sayfasını tarayıcıda açar; jeton `localhost:4794`'e POST
   edilir.
3. Yazar ve dağıtıcı CSR'lerini `svdca.samsungqbe.com`'a gönderir (dağıtıcı CSR'sinde `URN:tizen:deviceid=<DUID>`),
   gelen sertifikaları Samsung ara sertifikasıyla PKCS#12'ye yazar (Mac: `~/Library/Application Support/CouchSubs/samsung`,
   Windows: `%LOCALAPPDATA%\CouchSubs\samsung`).
4. Uygulamayla gelen imzasız `couchsubs-samsung_<sürüm>.wgt`'yi imzalar, `vd_appinstall` ile kurar ve `was_execute` ile açar.
   TV başka sertifikalı eski kopya ya da paket kimliği yüzünden reddederse (`[118, -12]`, `[118, -11]`, `[118, -22]`)
   eski kopyayı kaldırıp bir kez daha dener; TV sertifikayı reddederse kayıtlı sertifika bırakılır, bir sonraki
   denemede yenisi alınır. Hata kodlarının anlamı `SamsungInstallDiagnostics.cs`'te.

Her adım ve TV'nin, Samsung'un bütün yanıtları `tvinstall.log`'a yazılır (Mac: `~/Library/Logs/CouchSubs/`,
Windows: `%LOCALAPPDATA%\CouchSubs\`); hata iletisi bu dosyayı da söyler.

Uç noktalar belgesizdir ve Apps2Samsung'dan alınmıştır; Samsung değiştirirse burası güncellenir. Herkes için kalıcı
yol yine mağaza yayınıdır (`docs/magaza.md`).
