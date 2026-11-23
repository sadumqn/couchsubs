// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

// Perde bileşen kataloğu (tuvaldeki DL-Bilesenler panosunun uygulamadaki karşılığı). Yalnız geliştirme ve ekran
// görüntüsü testleri içindir (ScreenshotTests / PerdeScreenshotTests); kullanıcıya gösterilmez. Mac ve iPhone aynı
// dosyayı derler: aynı bileşen, aynı API. Örnek metinler katalog anahtarı değildir (çevrilmez).

struct PerdeCatalog: View {
    /// Bir sütun (iPhone) ya da genişliğe göre çok sütun (Mac).
    var columns = 3
    @State private var pace = 1
    @State private var tab = 0
    @State private var motion = true
    @State private var original = false
    @State private var size = 28.0
    @State private var address = "192.168.1.24"
    @State private var engine = 1
    @State private var option = 0
    @State private var cover = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("l")) {
            VStack(alignment: .leading, spacing: DS.space("titleBody")) {
                Text(verbatim: "Perde · Bileşenler").font(.dsH2).foregroundStyle(Color.dsText)
                Text(verbatim: "Koyu tema birincil; amber yalnız ana eylemde, seçilide ve ışımada.").dsMutedSmall()
            }
            if columns == 1 {
                // Tek sütun (iPhone): tembel olmayan yığın; görüntüye çizilirken (ImageRenderer) de bütün kartlar kurulur.
                VStack(alignment: .leading, spacing: DS.space("l")) { items }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.space("l"), alignment: .top), count: columns),
                          alignment: .leading, spacing: DS.space("l")) { items }
            }
        }
        .padding(DS.space("l"))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Color.dsBackground
                DSProjectorLight()
                DSAmbientGlow(intensity: 0.6)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder private var items: some View {
        buttons
        chips
        selector
        switches
        slider
        inputs
        options
        accounts
        tvCards
        covers
        perde
        progress
        notices
        loaders
        success
        glass
        adBand
    }

    private func k(_ text: String) -> LocalizedStringKey { LocalizedStringKey(text) }

    private func section<Content: View>(_ title: String, _ note: String, @ViewBuilder content: () -> Content) -> some View {
        DSCard(spacing: DS.space("m"), scrolls: false) {
            DSSectionTitle(title: k(title), message: k(note))
            content()
        }
    }

    private var buttons: some View {
        section("Düğmeler", "Ana amber ışımalı (ekranda bir tane) · ikincil · hayalet · canlı · başarı · sürüyor · pasif.") {
            Button {} label: { Label { Text(verbatim: "Çeviriyi Başlat") } icon: { Image(systemName: "play.fill") } }
                .buttonStyle(DSButtonStyle(kind: .primary, fullWidth: true))
            HStack(spacing: DS.space("xs")) {
                Button {} label: { Text(verbatim: "Ekranı Çevir") }.buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: false))
                Button {} label: { Text(verbatim: "IP ile Ekle") }.buttonStyle(DSButtonStyle(kind: .ghost, fullWidth: false))
            }
            Button {} label: { Text(verbatim: "Çeviriyi Durdur") }.buttonStyle(DSButtonStyle(kind: .live, fullWidth: true))
            HStack(spacing: DS.space("xs")) {
                DSSuccessBadge(text: k("Eşleşti"))
                Button {} label: { Text(verbatim: "Aranıyor…") }.buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: false, busy: true))
                    .disabled(true)
            }
            HStack(spacing: DS.space("xs")) {
                Button {} label: { Text(verbatim: "Devam Et") }.buttonStyle(DSButtonStyle(kind: .primary, fullWidth: false)).disabled(true)
                Button {} label: { Label { Text(verbatim: "Kopyala") } icon: { Image(systemName: "doc.on.doc") } }
                    .buttonStyle(DSButtonStyle(kind: .compact, fullWidth: false))
            }
        }
    }

    private var chips: some View {
        section("Durum hapı ve rozet", "Renk + nokta ya da simge + yazı birlikte; canlı noktası nabız atar.") {
            HStack(spacing: DS.space("xs")) {
                DSStatusChip(k("Bağlı"), tone: .ok)
                DSStatusChip(k("Canlı"), tone: .live)
                DSStatusChip(k("Güncelleme Var"), tone: .amber, dot: false)
            }
            HStack(spacing: DS.space("xs")) {
                DSStatusChip(k("Yeni"), tone: .info, dot: false)
                DSStatusChip(k("Uykuda"), tone: .muted)
                DSCountBadge(count: 6)
                DSCountBadge(count: 12, neutral: true)
            }
            HStack(spacing: DS.space("xs")) {
                DSStatusPill(text: k("Çeviri Açık"), dot: .dsLiveDot, pulse: true)
                DSStatusPill(text: k("Hazır"), dot: .dsSuccess)
            }
        }
    }

    private var selector: some View {
        section("Tek seçici", "Bej iz + yükselmiş hap; hap 250 ms kayar. Bütün tek seçimler bu.") {
            DSTabs(selection: $pace, items: [(0, k("Hızlı")), (1, k("Dengeli")), (2, k("Doğru"))])
            DSTabs(selection: $tab, items: [(0, k("Ana Ekran")), (1, k("Geçmiş")), (2, k("Ayarlar"))])
        }
    }

    private var switches: some View {
        section("Anahtar satırı", "Anahtar başta; açık = amber + hafif ışıma; açıklama başlığın altında.") {
            DSSwitchRow(title: k("Geçiş Animasyonları"), subtitle: k("Kapalıyken arayüz durağan kalır."), isOn: $motion)
            DSSwitchRow(title: k("Orijinali de Göster"), isOn: $original)
        }
    }

    private var slider: some View {
        section("Kaydırıcı", "Başlık solda, değer sağda mono amber; uç etiketleri çubuğun gerçek uçlarında.") {
            DSSliderRow(title: k("Yazı Boyutu"), valueText: "\(Int(size))", value: $size, range: 16...50, step: 1,
                        hint: k("TV'de altyazının yüksekliği."), ends: ("16", "50"))
        }
    }

    private var inputs: some View {
        section("Girdi ve ayar birimi", "Tam yuvarlak 48; odakta amber halka; kopyala simgesi kutu içinde.") {
            DSUnit(title: k("TV adresi"), hint: k("TV ile bu cihaz aynı ağda olmalı.")) {
                TextField(text: $address) { Text(verbatim: "192.168.1.24") }.textFieldStyle(DSTextFieldStyle(mono: true))
            }
            DSCopyField(text: "http://192.168.1.5:8765/altyazi/obs")
            DSUnit(title: k("Çeviri motoru")) {
                DSSelect(selection: $engine, options: [(0, "Google"), (1, "DeepL"), (2, "Gemini")])
            }
        }
    }

    private var options: some View {
        section("Seçenek kartı", "Her zaman kıl çizgi; seçili 2 pt amber + amber dolgu + ışıma.") {
            ForEach(0..<2) { index in
                Button { option = index } label: {
                    VStack(alignment: .leading, spacing: DS.space("line")) {
                        Text(verbatim: index == 0 ? "Alt Bölge" : "Tam Ekran").font(.dsBodyStrong).foregroundStyle(Color.dsText)
                        Text(verbatim: index == 0 ? "Altyazının durduğu şerit okunur." : "Bütün görüntü okunur.").dsMutedSmall()
                    }
                }
                .buttonStyle(DSOptionStyle(selected: option == index))
            }
        }
    }

    private var accounts: some View {
        section("Hesap kartı", "Bağlı: yükselmiş + amber halkalı rozet. Bağlı değil: düz + tek eylem.") {
            DSAccountCard(badge: "EO", title: k("PlayStation"), signedIn: true, detail: "enmera_oyuncu", signIn: {}) { EmptyView() }
            DSAccountCard(badge: "MS", title: k("Microsoft"), signedIn: false, signIn: {}) { EmptyView() }
        }
    }

    private var tvCards: some View {
        section("TV kartı", "Seçili kart amber kenar + ışıma; kartta durum hapı.") {
            DSTVCard(name: "Salon TV", detail: "LG webOS · 192.168.1.24", status: k("Hazır"), statusTone: .ok, selected: true) {}
            DSTVCard(name: "Yatak Odası", detail: "Samsung Tizen · 192.168.1.31", status: k("Ön Koşul Var"), statusTone: .amber) {}
        }
    }

    private var covers: some View {
        section("Oyun kapağı rafı", "3:4 kapak + alt scrim + cam durum hapı; seçilide amber halka ve kapak ışıması.") {
            DSCoverShelf(title: k("Bu oyun için hazır"), showAll: {}) {
                ForEach(Array(["GTA V", "Mafia", "Red Dead", "Cyberpunk", "The Witcher"].enumerated()), id: \.offset) { index, title in
                    Button { cover = index } label: {
                        DSGameCover(title: title, status: index == 1 ? k("Kurulu") : nil, selected: cover == index)
                    }
                    .buttonStyle(DSFocusPlainStyle(cornerRadius: DS.radius("cover")))
                }
            }
        }
    }

    private var perde: some View {
        section("Perde önizlemesi", "Sahne üstünde gerçek ayarlarla altyazı plakası; okunan alan kesikli amber.") {
            DSPerdePreview(showArea: true, speaker: "Lamar:", line: "Bunu sana söylemem lazım.",
                           speakerColor: Color(red: 0.361, green: 0.761, blue: 0.718), textSize: 14) {
                DSStatusChip(k("Canlı"), tone: .glass, dot: false)
            }
            HStack {
                Spacer()
                DSSubtitlePlate(speaker: "Franklin:", line: "Dinliyor musun?", size: 15)
                Spacer()
            }
            .padding(.vertical, DS.space("s"))
            .background(DSPerdeScene().clipShape(RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous)))
        }
    }

    private var progress: some View {
        section("İlerleme ve adım çizelgesi", "Amber dolgu + kayan ışık (yalnız sürerken). Biten adım amber, şimdiki halkalı.") {
            DSProgressRow(title: k("İndiriliyor…"), value: 0.64)
            DSStepTimeline(steps: [
                .init(title: k("Konsol bağlandı"), state: .done),
                .init(title: k("TV seçiliyor"), detail: k("Listeden TV'nizi seçin."), state: .current),
                .init(title: k("Deneme"), state: .todo),
            ])
        }
    }

    private var notices: some View {
        section("Bilgi, uyarı ve hata kutusu", "Tonlu zemin, komple saran ince renkli kenarlık, simge; hata kutusunda düğmeler.") {
            DSNoticeBox(tone: .info, text: k("Altyazı TV'de ve bu cihazda aynı anda görünebilir."))
            DSCallout(text: k("**Düşük kontrast:** zemini koyulaştırın."))
            DSNoticeBox(tone: .error, title: k("TV bağlantıyı reddetti"),
                        text: k("1. TV'de \"İzin Ver\"i seçin.  2. TV ile bu cihaz aynı ağda olsun.")) {
                Button {} label: { Text(verbatim: "Tekrar Dene") }.buttonStyle(DSButtonStyle(kind: .compact, fullWidth: false))
            }
        }
    }

    private var loaders: some View {
        section("Arama ve yükleme", "Arama halkası dalgası ve logodaki çubuklardan yükleyici; boşta, çeviri sürerken durur.") {
            HStack(spacing: DS.space("l")) {
                DSSearchRings()
                VStack(alignment: .leading, spacing: DS.space("xxs")) {
                    Text(verbatim: "Ağ taranıyor…").font(.dsBodyStrong).foregroundStyle(Color.dsText)
                    Text(verbatim: "PS5 ve TV'ler kart kart belirir.").dsMutedSmall()
                }
                Spacer(minLength: 0)
                DSBarsLoader(scale: 1.8)
            }
        }
    }

    private var success: some View {
        section("Başarı anı", "Işın bir kez döner, tik yayla oturur (≤ 1 sn); hareket azaltılmışsa yalnız tik.") {
            DSSuccessMoment(title: k("Paket Kuruldu"), message: k("Altyazılar bu oyunda hazır çeviriyle gelir."))
        }
    }

    private var glass: some View {
        section("Cam yüzey ve odak halkası", "Cam yalnız katmanlarda (sekme çubuğu, sheet, perde hapları); odak amber halka.") {
            ZStack {
                DSPerdeScene()
                HStack(spacing: 0) {
                    ForEach(Array(["house.fill", "clock", "slider.horizontal.3"].enumerated()), id: \.offset) { index, symbol in
                        VStack(spacing: DS.space("line")) {
                            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                            Text(verbatim: ["Ana Ekran", "Geçmiş", "Ayarlar"][index]).font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(index == 0 ? Color.dsAmberText : Color.dsMuted)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(index == 0 ? Color.dsAmberSoft : .clear, in: Capsule(style: .circular))
                    }
                }
                .padding(.horizontal, DS.space("xxs"))
                .frame(height: DS.size("tabBarHeight"))
                .dsGlass(in: Capsule(style: .circular))
                .padding(.horizontal, DS.space("m"))
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous))
            HStack(spacing: DS.space("m")) {
                Button {} label: { Text(verbatim: "Bağlan") }.buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: false))
                    .dsFocusRing(true, in: Capsule(style: .circular))
                Button {} label: { Text(verbatim: "Yeniden Ara") }.buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: false))
            }
            .padding(.vertical, DS.space("xxs"))
        }
    }

    private var adBand: some View {
        section("Reklam bandı", "64 pt, REKLAM etiketi, simge + başlık + açıklama + mağaza düğmeleri.") {
            DSAdBand()
        }
    }
}
