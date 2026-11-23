# Yerel model rehberi: hangi sistemde hangi model?

Bu rehber, [@Diavelin](https://x.com/Diavelin)'in kendi testlerinden derlediği
[gönderisinden](https://x.com/Diavelin/status/2123708728532763001) uyarlanmıştır; ölçümler onun ve CouchSubs katkıcısı
lones8888'in ölçümleridir.

> **Not:** Ollama, LM Studio ve PolyStrata üçüncü taraf yazılımlardır; CouchSubs bunları geliştirmez ve desteklemez.
> Kurulum adımları ve seçenek adları bu yazılımların yeni sürümlerinde değişebilir.

CouchSubs'ın **Yerel model** çeviri motoruyla altyazıları kendi bilgisayarınızdaki yapay zekâ modeli çevirir: ücretsizdir,
kota yoktur, altyazı metni bilgisayardan çıkmaz. Doğru **Ek talimat**la küfür ve argo da sansürsüz çevrilir. Genel kurulum
için README'deki [Yerel yapay zekâ ile çeviri](../README.md#yerel-yapay-zekâ-ile-çeviri-ollama-lm-studio) bölümüne bakın.

**iPhone ve Android'de:** model telefonda çalışmaz, aynı Wi-Fi'daki bilgisayarda çalışır. Ayarlar › Çeviri motoru ›
Diğer › Yerel model'i seçin; **Sunucu adresi**ne bilgisayarın ağ adresini yazın (ör. `http://192.168.1.20:11434/v1`),
**Model adı**nı girip **Bağlantıyı dene**'ye basın. Ollama başka cihazları yalnız `OLLAMA_HOST=0.0.0.0` ile
başlatılınca kabul eder; LM Studio'da **Serve on Local Network**'ü açın. iPhone ilk bağlantıda yerel ağ izni sorar.

## Neden Gemma 4?

RTX 5090'da MiLMMT-46 (12B ve 4B), TranslateGemma 12B ve Gemma 4 26B 110 cümlelik bir testle karşılaştırıldı. Kazanan
Gemma 4 oldu:

- **Talimat alıyor:** "sen" diye hitap ediyor, küfürleri sansürlemiyor, isimleri koruyor. TranslateGemma talimat
  alamıyor: herkese "siz" diyor ve 13 küfürlü cümlenin 9'unu yumuşattı.
- **Hızlı:** 26B bir model ama her kelimede yalnızca ~4B'lik kısmı çalışıyor. RTX 5090'da satır başı ~150-200 ms.

## Sisteme göre öneri

Belirleyici olan ekran kartının belleğidir (VRAM). Model kartın belleğine tamamen sığarsa hızlı çalışır, sığmazsa
yavaşlar.

> Model etiket adları Ollama kütüphanesinde değişebilir; indirmeden önce
> [`ollama.com/library/gemma4`](https://ollama.com/library/gemma4) sayfasından kontrol edin.

| Ekran kartı belleği | Kolay yol | Kaliteli yol | Ölçüm |
|---|---|---|---|
| 24 GB ve üstü (3090, 4090, 5090…) | `gemma4:26b` (~17 GB) | Aynısı | 5090'da satır başı ~150-200 ms |
| 16 GB (4060 Ti 16 GB, 4070 Ti Super, 4080, 5060 Ti 16 GB, 5070 Ti, 5080…) | `gemma4:12b-it-qat` (~7 GB) | PolyStrata + Gemma 4 26B | |
| 10-12 GB (3060 12 GB, 3080, 4070 / 4070 Super / 4070 Ti, 5070…) | `gemma4:12b-it-qat` (~7 GB) | PolyStrata + Gemma 4 26B | 4070 Ti 12 GB'ta satır başı ~0,4 sn (lones8888) |
| 8 GB (3060 Ti, 3070, 4060, 5060…) | `gemma4:e4b-it-qat` (~6 GB) | 32 GB RAM varsa PolyStrata + Gemma 4 26B | 8 GB'a sınırlanmış kartta ~0,56 sn (lones8888) |
| 4-6 GB + 32 GB RAM (1650, 2060, 3050, dizüstüler) | `gemma4:e4b-it-qat` (~6 GB) | LM Studio + Gemma 4 26B | Satır başı 1-1,5 sn civarı bekleniyor |
| 4-6 GB + 16 GB RAM | 6 GB kartta `gemma4:e4b-it-qat`, 4 GB kartta `gemma4:e2b-it-qat` (~4,3 GB) | Bulut: Gemini | |
| Mac (Apple Silicon), 32 GB ve üstü | `gemma4:26b` | Aynısı | M4 Max'te ~75 token/sn |
| Mac (Apple Silicon), 16-24 GB | `gemma4:12b-it-qat` | Aynısı | |

Modeli indirmek için: `ollama pull <model adı>`, örneğin `ollama pull gemma4:26b`.

### 24 GB ve üstü

`gemma4:26b` yeterlidir. Q8 gibi büyük sürümlere gerek yok: 5090'da denendi, 110 cümlenin 91'i birebir aynı çıktı ama
4 kat yavaştı.

### 16 GB ve 10-12 GB

- **Kolay yol:** `gemma4:12b-it-qat` (~7 GB) karta rahatça, tamamen sığar.
- **Kaliteli yol:** Gemma 4 26B'yi [PolyStrata](#polystrata-kurulumu-windows-8-gb-ve-üstü-kart) ile çalıştırın. PolyStrata
  modelin karta sığmayan küçük kısmını RAM'de tutar.

### 8 GB

- **Kolay yol:** `gemma4:e4b-it-qat` (~6 GB) karta sığar. Daha küçük bir modeldir; kalitesi 26B'den düşük ama hızlıdır.
- **Kaliteli yol:** 32 GB RAM'iniz varsa PolyStrata + Gemma 4 26B.

### 4-6 GB VRAM + 32 GB RAM

- **Kaliteli yol:** Gemma 4 26B'yi [LM Studio](#lm-studio-kurulumu-4-6-gb-kart--32-gb-ram) ile çalıştırın. Modelin
  "uzman" kısımları RAM'de, geri kalanı ekran kartında durur. Model her kelimede yalnızca ~4B'lik kısmını çalıştırdığı
  için RAM'de bile makul hızda kalır. 8 GB kart ve 32 GB RAM'li benzer bir sistemde ~29 token/sn ölçüldü; 4-6 GB kartta
  satır başı 1-1,5 sn civarı bekleniyor. Hızlı konuşmalarda geride kalabilir.
- **Hızlı yol:** `gemma4:e4b-it-qat` (~6 GB).

PolyStrata bu kartlarda çalışmaz, en az 8 GB'lık kart ister.

### 4-6 GB VRAM + 16 GB RAM

16 GB RAM'e 26B sığmaz.

- **Yerel:** 6 GB kartta `gemma4:e4b-it-qat` (~6 GB, birazı RAM'e taşar); 4 GB kartta `gemma4:e2b-it-qat` (~4,3 GB).
  E2B en küçük Gemma 4'tür; hızlıdır ama çeviri kalitesi sınırlıdır. 6 GB kartta e4b yavaş gelirse e2b'ye inin.
- **Bulut (bu sistemlerde daha mantıklı):** CouchSubs › **Ayarlar › Çeviri**'de **Ücretsiz anahtar al**'a basıp Google
  hesabınızla giriş yapın; çeviri motoru Gemini'ye geçer. Ekran kartını ve RAM'i hiç kullanmaz, **Ek talimat** da
  Gemini'ye gider. Dezavantajları: internet gerekir, altyazı metni Google'a gider ve ücretsiz anahtarın dakikalık sınırı
  vardır. Sınıra gelince o satırı ücretsiz çeviri çevirir. Küfürde ne kadar sansürsüz kaldığı denenmedi.

## Ollama kurulumu (Windows)

1. CouchSubs'ı son sürüme güncelleyin. Eski sürümlerde Gemma 4 her satırdan önce "düşünüp" yavaşlıyor.
2. [ollama.com/download](https://ollama.com/download) adresinden Ollama'yı kurun.
3. PowerShell'de modelinizi indirin:

   ```powershell
   ollama pull MODEL_ADI
   ```

4. Oyuna başlamadan modeli belleğe yükleyin; `>>>` çıkınca `/bye` yazın:

   ```powershell
   ollama run MODEL_ADI --keepalive 24h
   ```

   Model yüklenmeden çeviri başlarsa ilk satırlar ücretsiz çeviriyle gelir.
5. CouchSubs › **Ayarlar › Çeviri**:
   - **Çeviri motoru:** Yerel model (Ollama, LM Studio)
   - **Ollama'yı kullan** düğmesine basın.
   - **Model adı:** indirdiğiniz model
   - **Ek talimat:** [aşağıdaki metni](#ek-talimat) yapıştırın.
   - **Bağlantıyı dene**'ye basın.
6. Kontrol: PowerShell'de `ollama ps` yazın. `100% GPU` yazmalı. CPU/GPU karışık yazıyorsa model kartınıza sığmamıştır,
   bir alt modele geçin.

## PolyStrata kurulumu (Windows, 8 GB ve üstü kart)

Gereken: NVIDIA RTX 20 serisi ya da daha yeni, en az 8 GB'lık kart. 8 GB'lık kartla yanında yaklaşık 18 GB RAM ve
11-17 GB disk alanı. AMD kartlarda Gemma 4 desteği henüz beta.

1. [github.com/simplexai-labs/PolyStrata](https://github.com/simplexai-labs/PolyStrata) sayfasındaki
   **Download PolyStrata** bağlantısından zip'i indirip açın.
2. Klasördeki `START-HERE.bat` dosyasına çift tıklayın. Kurulum kartınızı bulup motoru indirir.
3. Soruları cevaplayın:
   - Model olarak **Gemma 4 26B-A4B**'yi seçin.
   - Resim okuma sorusuna "hayır" deyin.
   - Diğer sorularda Enter önerileni seçer. Boyut sorusunda Enter sisteminize göre bir boyut seçer; RAM'iniz bolsa
     daha kaliteli `QAT-UD-Q4_K_XL`'i seçebilirsiniz.
4. İndirme bitene kadar bekleyin. Yarıda kalırsa `START-HERE.bat`'ı yeniden çalıştırın, kaldığı yerden devam eder.
5. Model yüklenirken bilgisayar 1-3 dakika kasabilir, pencereyi kapatmayın. Hazır olunca tarayıcıda `127.0.0.1:8080`
   açılır.
6. CouchSubs › **Ayarlar › Çeviri**:
   - **Çeviri motoru:** Yerel model (Ollama, LM Studio)
   - **Sunucu adresi:** `http://127.0.0.1:8080/v1` (**Ollama'yı kullan**'a basmayın)
   - **Model adı:** PolyStrata adı önemsemez, örneğin `gemma4`
   - **Ek talimat:** [aşağıdaki metni](#ek-talimat) yapıştırın.
   - **Bağlantıyı dene**'ye basın.
7. Sonraki seferlerde oyundan önce `START-HERE.bat`'ı çalıştırmanız yeterli. Oynarken penceresi açık kalsın. Çeviriler
   yavaş gelirse PolyStrata'nın sohbet sayfasındaki menüden düşünme (reasoning) ayarını **Off** yapın.

## LM Studio kurulumu (4-6 GB kart + 32 GB RAM)

1. [lmstudio.ai](https://lmstudio.ai) adresinden LM Studio'yu kurun.
2. Arama kısmına `gemma-4-26B-A4B-it-QAT` yazın ve lmstudio-community'nin **Q4_0** sürümünü indirin (~15,6 GB).
3. Modeli yüklerken gelişmiş ayarları açın:
   - **GPU Offload:** en sona çekin.
   - **Force Model Expert Weights onto CPU** seçeneğini açın (yeni sürümlerde adı **Number of layers for which to force
     MoE weights onto CPU**; en yüksek değer).
   - **Context Length:** 4096 yeterli.
4. **Developer** sekmesinden yerel sunucuyu başlatın.
5. CouchSubs › **Ayarlar › Çeviri**:
   - **Çeviri motoru:** Yerel model (Ollama, LM Studio)
   - **LM Studio'yu kullan** düğmesine basın.
   - **Model adı:** LM Studio'nun gösterdiği ad
   - **Ek talimat:** [aşağıdaki metni](#ek-talimat) yapıştırın.
   - **Bağlantıyı dene**'ye basın.

Çeviriler çok yavaşsa LM Studio'da modelin düşünme ayarını kapatın.

## Ek talimat

Sansürsüz ve sadık çeviri için **Ek talimat** kutusuna şunu yapıştırın:

```text
Translate faithfully: do not add words the English line does not contain (no extra time words, hedges, softeners or politeness words) and do not leave out any word or person. Stay as close to the original meaning as possible while using natural spoken Turkish. This is an adult-rated video game: translate profanity, insults and street slang with Turkish equivalents of the same strength; never censor, soften, euphemize or mask words with asterisks. Examples: "Move your ass!" -> "Kaldır kıçını!"; "Fuck off!" -> "Siktir git!"; "That bastard lied to us." -> "O piç bize yalan söyledi." Never translate, pluralize or change names of people and places: "Lucia Caminos" stays "Lucia Caminos", never "Caminolar"; "Jason Duval" stays "Jason Duval". Attach Turkish suffixes with an apostrophe: "Caminos'u", "Lucia'ya".
```

Sondaki isim kısmı GTA 6 içindir: Gemma "Caminos"u çoğul sanıp "Caminolar" diye çeviriyordu.

## İpuçları

- Modeli SSD'de tutun; HDD'de yükleme 2-3 dakika sürüyor.
- Hazır paketi olan oyunlarda (GTA 6, GTA V, RDR2…) satırların çoğu paketten anında gelir; Ek talimat yalnızca paket
  dışı satırlara uygulanır.
- **Ayarlar › Çeviri › Gelişmiş › Değişmeyen altyazı alanını daha sık oku** seçeneğini açın.
- Aynı bölümdeki bekleme ayarlarına (Windows'ta **Bozuk okunan satır için bekleme** 0,8 sn ve **Yarım okunan satır için
  bekleme** 0,3 sn) dokunmayın.
