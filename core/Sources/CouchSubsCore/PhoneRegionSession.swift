// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Tek telefon açılışının son karesi, okunmuş balonları ve birebir çevirileri. Ana altyazı ve
/// elle seçilen bölgeler kendi saatlerinde kalır. Telefon kapanınca bu oturum tekrar kullanılmaz.
@MainActor
final class PhoneRegionSession {
    private struct Capture: Sendable {
        let frame: CGImage
        let pose: GamePhoneGeometry.Pose
        var region: CropRegion { pose.bounds }

        func isPresent() -> Bool {
            guard let found = GamePhoneGeometry.locate(frame) else { return false }
            return region.isClose(to: found.bounds, tolerance: 0.035)
        }
    }

    private struct Bubble: Sendable {
        var group: ScreenTranslation.Group
        let style: PhoneTextStyle
    }

    private struct Page: Sendable {
        let region: CropRegion
        let signature: [UInt8]
        let pixels: GamePhonePage
        let bubbles: [Bubble]
    }

    private let reader: TextReader
    private let translator: TextTranslator
    private let server: RegionSending
    private var latest: Capture?
    private var lastPass: Int?
    private var task: Task<Void, Never>?
    private var page: Page?
    private var rendered: [ScreenTranslation.Item] = []
    private var translations: [String: String] = [:]
    private var keys: [String] = []
    private var nextBubble = 0
    private var anchors: [(prefix: String, x: Double, y: Double)] = []
    private var needsWork = false
    private var emptyOnce = false
    /// Soluk satır kurtarmasının hafızası (`GamePhoneReader.readMessages`).
    private let retry = GamePhoneRetry()
    /// Son tam yayımlanan okuma: tek turluk OCR atlamasını gerçek değişiklikten ayırmak için.
    private var shownPage: Page?
    /// Bu okuma kaç turdur bekletiliyor (en çok `PhoneSteady.holdTurns`); sonra okuma her durumda ilerler.
    private var holds = 0
    /// Telefonun art arda bulunamadığı tur sayısı (`missed`).
    private var absences = 0
    /// Telefonun boyu (bölgenin yüksekliği): gerçek yakınlaşmada balonların görünüşü hemen yenilenir.
    private var scale = 0.0
    /// Kare boyu (piksel): yarım piksellik kutu oynaması yeniden gönderilmez.
    private var frameSize = (width: 1920, height: 1080)

    /// "GTA 6 Telefon Mesajları" ayarı: Yanda Panel (mesajlar telefonun yanındaki sohbet panelinde, `ScreenPhoneCard.layout`)
    /// ya da Balonların Üstünde; panelin yazı çarpanı altyazı boyutundan. Her gönderide yeniden okunur.
    var panel: () -> PhonePanelOptions = { PhonePanelOptions() }
    /// Son gönderinin ayarı: ayar değişince aynı mesajlar yeni düzende yeniden gönderilir.
    private var sentOptions: PhonePanelOptions?
    /// Son gönderilen düzen ve Yanda Panel'in dayandığı telefon yeri (`PhoneSteady.steadyPose`, `samePicture`).
    private var sentShown: [ScreenTranslation.Item] = []
    private var anchor: GamePhoneGeometry.Pose?
    /// Boş okumanın art arda kaç turdur sürdüğü: `PhoneSteady.missTurns` tur (~1,35 sn) sürmeden ekran silinmez.
    private var empties = 0

    init(reader: TextReader, translator: TextTranslator, server: RegionSending) {
        self.reader = reader
        self.translator = translator
        self.server = server
    }

    func observe(_ frame: CGImage, pose: GamePhoneGeometry.Pose) {
        latest = Capture(frame: frame, pose: pose)
    }

    func beginIfDue(_ time: Int) -> Bool {
        guard latest != nil, lastPass.map({ time - $0 >= 450 }) ?? true else { return false }
        lastPass = time
        return true
    }

    func close() {
        latest = nil
        shownPage = nil
        absences = 0
        task?.cancel()
        publish([])
    }

    func visit(packLookup: ((String) -> PackMatch?)?, skipsTurkish: Bool, english: Bool) async {
        guard latest != nil else { return }
        let work = Task {
            await update(packLookup: packLookup, skipsTurkish: skipsTurkish, english: english)
        }
        task = work
        await work.value
        task = nil
    }

    private func read(_ capture: Capture, signature: [UInt8]) async throws -> Page {
        let reader = self.reader, retry = self.retry
        return try await ReadQueue.shared.run(priority: .background, detail: ReadQueue.detail("telefon", capture.frame)) {
            let region = capture.region
            let reading = GamePhoneText.forTranslation(try GamePhoneReader.read(capture.frame, region: region,
                                                                                pose: capture.pose, reader: reader, retry: retry))
            let crop = RegionCropper.crop(capture.frame, to: region)
            let place = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
            let bubbles = ScreenTranslation.withImages(GamePhoneText.groups(reading), from: crop).map { group in
                let style = GamePhonePalette.sample(crop, box: group.box)
                var placed = group
                placed.box = group.box.placed(in: place)
                placed.lineHeight *= region.bottom - region.top
                return Bubble(group: placed, style: style)
            }
            return Page(region: region, signature: signature,
                        pixels: GamePhonePage(frame: capture.frame, region: region, reading: reading), bubbles: bubbles)
        }
    }

    private func update(packLookup: ((String) -> PackMatch?)?, skipsTurkish: Bool, english: Bool) async {
        guard let start = latest, start.isPresent() else { missed(); return }
        absences = 0
        frameSize = (start.frame.width, start.frame.height)
        let signature = RegionCropper.signature(of: RegionCropper.crop(start.frame, to: start.region))
        let changed = page.map {
            !$0.region.isClose(to: start.region, tolerance: 0.01)
                || ReadScheduler.changed($0.signature, signature, threshold: ReadScheduler.defaultChangeThreshold)
                || $0.pixels.changed(start.frame, region: start.region)
        } ?? true
        var fresh = false
        if changed || emptyOnce {
            do { page = try await read(start, signature: signature) }
            catch { page = nil; return }
            fresh = true
        } else if !needsWork && !emptyOnce {
            // "GTA 6 Telefon Mesajları" ayarı değişti: aynı sayfa yeni düzende hemen gösterilir.
            if sentOptions != panel(), let current = page, !rendered.isEmpty {
                publish(items(current, translations: availableTranslations(current.bubbles.map(\.group), packLookup: packLookup,
                                                                          skipsTurkish: skipsTurkish)))
            }
            return
        }
        guard !Task.isCancelled, var current = page, var verified = latest else { return }
        // Okuma sürerken farklı bir sayfa gelmişse eski sayfadan yeni çeviri isteği çıkarma.
        if start.frame !== verified.frame, !matches(current, verified) {
            guard let fresh = await reread(verified) else { missed(); return }
            current = fresh
        }
        guard latest != nil, !Task.isCancelled else { return }
        // Yerinde duran iki komşu arasından düşen balon ya da uzun mesajdaki yan yana birkaç bozuk harf tek okumada
        // ekrandan silinmesin, yeniden çevrilmesin: okuma bir tur bekletilir, sonraki tur mutlaka yeniden okur. Aynı
        // görünen gerçek değişiklik o turda ilerler (Windows ile aynı).
        if fresh, holds < PhoneSteady.holdTurns, let shown = shownPage, !rendered.isEmpty,
           Self.missingInteriorBubble(shown, current)
            || (Self.sameLayout(shown, current, frameSize) && GamePhoneText.hasAdjacentOcrEdits(Self.text(shown), Self.text(current))) {
            holds += 1
            page = nil
            return
        }
        holds = 0
        if current.bubbles.isEmpty {
            // Boş okuma aynı karede bir kez daha okunur: ilk okumada kaçan mesaj gizlenmesin. Ekranda çeviri varsa
            // `PhoneSteady.missTurns` tur boş kalmadan silinmez: telefonun ekranı kısa süre okunamayınca (kare geçişi,
            // bulanıklık) panel kaybolup geri geliyordu (X, 22 Kas).
            empties += 1
            if empties >= (rendered.isEmpty ? 2 : PhoneSteady.missTurns) {
                publish([])
                shownPage = nil
                emptyOnce = false
                empties = 0
            } else { emptyOnce = true }
            needsWork = false
            return
        }
        emptyOnce = false
        empties = 0
        let groups = current.bubbles.map(\.group)
        let paragraphs = groups.flatMap(\.paragraphs)
        var available = availableTranslations(groups, packLookup: packLookup, skipsTurkish: skipsTurkish)
        // Önce yalnız güncel sayfayla eşleşen balonlar kalır. Örneğin yeni WhatUp yanıtı ağdayken
        // önceki yanıtın üstü kendi özgün yazısıyla görünür, bitmiş komşu balonlar okunabilir.
        publish(items(current, translations: available))
        var missing = paragraphs.filter { available[$0] == nil }
        guard !missing.isEmpty else {
            needsWork = false
            shownPage = current
            return
        }
        if !translator.translatesTogether {
            followPage(current)
            for offset in groups.indices {
                let index = (nextBubble + offset) % groups.count
                let lead = groups[index].paragraphs.filter { available[$0] == nil }
                if lead.contains(where: GamePhoneText.isMessagePreview) {
                    missing = lead
                    nextBubble = (index + 1) % groups.count
                    break
                }
            }
        }
        var unique: Set<String> = []
        missing = missing.filter { unique.insert($0).inserted }
        let inputs = missing.map {
            let text = IconText.protect($0).text
            return english ? GamePhoneText.englishModelInput(text) : text
        }
        do {
            let result = try await translator.translateAll(inputs)
            guard !Task.isCancelled, latest != nil else { return }
            guard result.count == inputs.count else { needsWork = true; return }
            for (source, translated) in zip(missing, result) where !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                remember(source, translated)
                available[source] = translated
            }
        } catch { needsWork = true; return }

        guard let latest else { return }
        if latest.frame !== verified.frame, !matches(current, latest) {
            verified = latest
            guard let fresh = await reread(verified) else { missed(); return }
            current = fresh
            available = availableTranslations(current.bubbles.map(\.group), packLookup: packLookup, skipsTurkish: skipsTurkish)
        }
        guard !Task.isCancelled, self.latest != nil else { return }
        publish(items(current, translations: available))
        needsWork = current.bubbles.contains { $0.group.paragraphs.contains { available[$0] == nil } }
        shownPage = needsWork ? nil : current
    }

    private static func text(_ page: Page) -> String {
        page.bubbles.flatMap(\.group.paragraphs).joined(separator: "\n")
    }

    /// Yalnız tek iç balon eksilmiş: kalanların yazısı ve kutuları aynı sırada, aynı yerde. Kaydırma, yeni yazı ya da
    /// sayfanın kapanması bu denetime takılmaz.
    nonisolated static func missingInteriorBubble(_ shownBubbles: [(paragraphs: [String], box: TextBox)],
                                                  _ current: [(paragraphs: [String], box: TextBox)]) -> Bool {
        guard current.count >= 2, shownBubbles.count == current.count + 1 else { return false }
        var missing = false
        for (index, bubble) in current.enumerated() {
            var prior = shownBubbles[missing ? index + 1 : index]
            if prior.paragraphs != bubble.paragraphs {
                guard !missing, index > 0 else { return false }
                missing = true
                prior = shownBubbles[index + 1]
                guard prior.paragraphs == bubble.paragraphs else { return false }
            }
            let a = prior.box, b = bubble.box
            if abs(a.left - b.left) > 0.012 || abs(a.right - b.right) > 0.012 || abs(a.top - b.top) > 0.012
                || abs(a.bottom - b.bottom) > 0.012 { return false }
        }
        // Kalanlar yerinde, yalnız en alttaki balon düştü: yeni mesaj eklenir, silinmez; bu da bir OCR atlamasıdır.
        return true
    }

    private static func missingInteriorBubble(_ shown: Page, _ current: Page) -> Bool {
        missingInteriorBubble(shown.bubbles.map { ($0.group.paragraphs, $0.group.box) },
                              current.bubbles.map { ($0.group.paragraphs, $0.group.box) })
    }

    /// İki okumanın balonları aynı yerde (iki piksel içinde) ve aynı yüzeyde: telefon kıpırdamadı.
    private static func sameLayout(_ a: Page, _ b: Page, _ size: (width: Int, height: Int)) -> Bool {
        guard a.bubbles.count == b.bubbles.count else { return false }
        let dx = 2.0 / Double(size.width), dy = 2.0 / Double(size.height)
        return zip(a.bubbles, b.bubbles).allSatisfy { x, y in
            x.group.paragraphs.count == y.group.paragraphs.count && near(x.group.box, y.group.box, dx, dy)
                && abs(x.group.lineHeight - y.group.lineHeight) <= dy
                && nearColor(x.style.background, y.style.background) && nearColor(x.style.foreground, y.style.foreground)
        }
    }

    nonisolated static func near(_ a: TextBox, _ b: TextBox, _ dx: Double, _ dy: Double) -> Bool {
        abs(a.left - b.left) <= dx && abs(a.right - b.right) <= dx && abs(a.top - b.top) <= dy && abs(a.bottom - b.bottom) <= dy
    }

    /// İki renk her kanalda en çok `tolerance` farklı (palet kanalları sekizli basamaklara yuvarlar; bir basamak fark
    /// sıkıştırma titreşimidir).
    nonisolated static func nearColor(_ a: String, _ b: String, _ tolerance: Int = 8) -> Bool {
        if a == b { return true }
        func channels(_ hex: String) -> [Int]? {
            guard hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else { return nil }
            return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
        }
        guard let x = channels(a), let y = channels(b) else { return false }
        return zip(x, y).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// Aynı balon hareket ederken yeri her gönderide izlenir; küçük OCR kutu farkları yazı boyunu ve satır kırılımını,
    /// renk örneklemesi zemini sürekli değiştirmesin. Esas alınan, son çizilendir (Windows ile aynı). Aynı balon
    /// (`PhoneSteady.match`: aynı çeviri, OCR'la biraz farklı okunsa da aynı mesaj) ilk okunuşunu korur: yazının bir harfi
    /// oynadı diye gönderi yenilenmez.
    nonisolated static func stableBlocks(_ items: [ScreenTranslation.Item], previous: [ScreenTranslation.Item]) -> [ScreenTranslation.Item] {
        items.map { item in
            guard let match = PhoneSteady.match(item, in: previous) else { return item }
            var stable = item
            stable.source = match.source
            // Balonun tarafı (gelen/giden/not) da kimliğiyle kalır: hiza ya da renk okuması bir piksel oynadı diye balon
            // panelde sola sağa atlamaz.
            if let role = match.phone?.role, stable.phone != nil { stable.phone?.role = role }
            let width = item.box.right - item.box.left, height = item.box.bottom - item.box.top
            let oldWidth = match.box.right - match.box.left, oldHeight = match.box.bottom - match.box.top
            if oldWidth > 0, abs(width - oldWidth) <= oldWidth * 0.05 { stable.box.right = min(1, item.box.left + oldWidth) }
            if oldHeight > 0, abs(height - oldHeight) <= oldHeight * 0.10 { stable.box.bottom = min(1, item.box.top + oldHeight) }
            if abs(item.lineHeight - match.lineHeight) <= match.lineHeight * 0.15 { stable.lineHeight = match.lineHeight }
            if let style = item.style, let before = match.style {
                // Ön ve arka renk ayrı ayrı: seçimin gerçek yazı/zemin rengi değişimi korunur.
                // Yazı rengi zeminin aynı yanında kaldıysa (ikisi de zeminden koyu ya da ikisi de açık) eskisi kalır: yazı
                // örneği balonun kenar pikselinden bir koyu, bir gri okunuyor, TV'de yazı rengi titriyordu. Seçimde yazı
                // zeminin öbür yanına geçer (siyahtan beyaza): o değişim izlenir.
                let ink = nearColor(style.foreground, before.foreground, 16)
                    || PhoneSteady.sameInk(style.foreground, before.foreground, on: style.background)
                var kept = PhoneTextStyle(background: nearColor(style.background, before.background, 16) ? before.background : style.background,
                                          foreground: ink ? before.foreground : style.foreground)
                // İki okunabilir paletin karışımı kontrastı düşürebilir: o durumda güncel çift kullanılır.
                if kept != before, kept != style, TextStyleSampler.contrast(kept.background, kept.foreground) < 4.5 { kept = style }
                stable.style = kept
            }
            return stable
        }
    }

    private func matches(_ page: Page, _ capture: Capture) -> Bool {
        capture.isPresent() && page.region.isClose(to: capture.region, tolerance: 0.01)
            && !page.pixels.changed(capture.frame, region: capture.region)
    }

    private func reread(_ capture: Capture) async -> Page? {
        guard capture.isPresent(), !Task.isCancelled else { return nil }
        let signature = RegionCropper.signature(of: RegionCropper.crop(capture.frame, to: capture.region))
        guard let fresh = try? await read(capture, signature: signature), let last = latest, !Task.isCancelled,
              last.frame === capture.frame || matches(fresh, last) else { return nil }
        page = fresh
        return fresh
    }

    /// Telefon bu turda bulunamadı ya da okuma doğrulanamadı. Çeviriler hemen silinmez: tek karelik ıska çevirileri
    /// kaldırıp geri getiriyor, ekranda gidip geliyordu. Art arda `PhoneSteady.missTurns` turdan sonra silinir
    /// (telefon gerçekten kapanınca izleyici oturumu zaten kapatır).
    ///
    /// Ekran kalsa da okunan sayfa bırakılır: sonraki tur mutlaka yeniden okur. Eskiden sayfa kalıyordu; çeviri bu turda
    /// geldiyse ve telefon aynı görünüşe döndüyse sayfa "değişmedi" sayılıyor, hazır çeviri hiç gösterilmiyordu (GitHub
    /// #822, X: "çeviri ya hiç gelmiyor ya da geç geliyor"; Windows `Signature = null` ile zaten yeniden okuyordu).
    private func missed() {
        absences += 1
        if absences >= PhoneSteady.missTurns { clearMissing() } else { page = nil }
    }

    private func clearMissing() {
        absences = 0
        page = nil
        shownPage = nil
        emptyOnce = false
        empties = 0
        needsWork = false
        publish([])
    }

    private func remember(_ source: String, _ translation: String) {
        if translations[source] == nil {
            if keys.count >= 2 * ScreenTranslation.maxGroups { translations[keys.removeFirst()] = nil }
            keys.append(source)
        }
        translations[source] = translation
    }

    /// Paketten, hafızadan ya da zaten Türkçe olduğu için hazır çeviriler. Kişinin adı (sohbet başlığı) çevrilmez: "Rose"
    /// "Gül" olmasın; panelin başlığında aslıyla görünür.
    private func availableTranslations(_ groups: [ScreenTranslation.Group], packLookup: ((String) -> PackMatch?)?,
                                       skipsTurkish: Bool) -> [String: String] {
        var result: [String: String] = [:]
        for group in groups {
            for text in group.paragraphs {
                if group.phone?.role.keepsText == true {
                    result[text] = text
                    continue
                }
                let known = packLookup?(IconText.plain(text))?.text ?? PhoneSteady.translation(of: text, in: translations)
                result[text] = known ?? ((skipsTurkish && TurkishText.isSure(text)) ? text : nil)
            }
        }
        return result
    }

    /// Çevirisi hazır balonlar. Panelde çevirisi aslıyla aynı mesajlar ("ok", ad) da görünür (sohbet eksik kalmasın);
    /// balonların üstünde ise atılır, özgün yazı görünür kalır.
    private func items(_ page: Page, translations: [String: String]) -> [ScreenTranslation.Item] {
        let keepUnchanged = panel().enabled
        return page.bubbles.compactMap { bubble in
            let group = bubble.group
            let result = group.paragraphs.compactMap { GamePhoneText.keepIdentifiers($0, translation: translations[$0]) }
            guard result.count == group.paragraphs.count,
                  var item = ScreenTranslation.item(group, group.paragraphs.map(IconText.protect), result,
                                                    keepUnchanged: keepUnchanged) else { return nil }
            item.style = bubble.style
            return item
        }
    }

    private func publish(_ fresh: [ScreenTranslation.Item]) {
        var items = fresh
        if let region = latest?.region {
            let height = region.bottom - region.top
            // Telefon gerçekten yakınlaşıp uzaklaşınca yeni boyutlar hemen kullanılır.
            if abs(height - scale) > scale * 0.03 {
                scale = height
                anchor = nil
            } else if !rendered.isEmpty {
                items = PhoneSteady.steadyPositions(Self.stableBlocks(items, previous: rendered), previous: rendered,
                                                    aspect: Double(frameSize.width) / Double(max(1, frameSize.height)))
            }
        }
        let options = panel()
        let sameOptions = sentOptions == options
        guard rendered != items || (!sameOptions && !items.isEmpty) else { return }
        // Aynı yazı bir iki piksel oynadıysa (OCR kutusu, yüzey örneği) yeniden gönderilmez; gerçek hareket birikince gider.
        let dx = 2.0 / Double(frameSize.width), dy = 2.0 / Double(frameSize.height)
        if sameOptions, rendered.count == items.count, !items.isEmpty, zip(rendered, items).allSatisfy({ a, b in
            a.source == b.source && a.translation == b.translation && Self.near(a.box, b.box, dx, dy)
                && abs(a.lineHeight - b.lineHeight) <= dy && Self.sameSurface(a.style, b.style)
        }) { return }
        rendered = items
        sentOptions = options
        // Panel telefonun el titremesiyle kaymaz (`PhoneSteady.steadyPose`); TV'de aynı görünen gönderi yinelenmez.
        let pose = latest.map { PhoneSteady.steadyPose($0.pose, anchor: anchor) }
        anchor = pose ?? anchor
        let shown = Self.arranged(items, pose: pose, frameSize: frameSize, options: options)
        if sameOptions, PhoneSteady.samePicture(shown, sentShown) { return }
        sentShown = shown
        let boxes = shown.map(\.box)
        let box = boxes.dropFirst().reduce(boxes.first) { $0?.union($1) }
        let heights = shown.map(\.lineHeight).sorted()
        server.sendRegion(id: "game-phone", text: shown.filter { !ScreenPhoneCard.isBackdrop($0) }.map(\.translation)
                            .joined(separator: "\n"), box: box,
                          lineHeight: heights.isEmpty ? nil : heights[heights.count / 2], icons: nil,
                          blocks: shown.isEmpty ? nil : shown)
    }

    /// Gönderilecek düzen: Yanda Panel'de telefonun mesajları yanındaki sohbet panelinde (`ScreenPhoneCard.layout`; ana
    /// ekran yazıları yerinde kalır), Balonların Üstünde'de her çeviri kendi balonunun yerinde (çevirisi aslıyla aynı
    /// olanlar atılır). Telefonun yeri bilinmiyorsa balonlar yerinde kalır.
    nonisolated static func arranged(_ items: [ScreenTranslation.Item], pose: GamePhoneGeometry.Pose?,
                                     frameSize: (width: Int, height: Int), options: PhonePanelOptions) -> [ScreenTranslation.Item] {
        guard options.enabled, let pose, !items.isEmpty else { return items.filter { !$0.unchanged } }
        let handset = ScreenPhoneCard.Handset(pose: pose, aspect: Double(frameSize.width) / Double(max(1, frameSize.height)))
        return ScreenPhoneCard.layout(items, handset: handset, textScale: options.textScale).filter { !$0.unchanged }
    }

    private static func sameSurface(_ a: PhoneTextStyle?, _ b: PhoneTextStyle?) -> Bool {
        guard let a, let b else { return a == b }
        return nearColor(a.background, b.background) && nearColor(a.foreground, b.foreground)
    }

    private func followPage(_ page: Page) {
        let w = page.region.right - page.region.left, h = page.region.bottom - page.region.top
        let current: [(prefix: String, x: Double, y: Double)] = page.bubbles.compactMap { bubble in
            guard let first = bubble.group.paragraphs.first, GamePhoneText.isMessagePreview(first) else { return nil }
            return (TextMatch.normalize(first).split(separator: " ").prefix(3).joined(separator: " "),
                    (bubble.group.box.left - page.region.left) / w, (bubble.group.box.top - page.region.top) / h)
        }
        if !current.isEmpty {
            if !current.contains(where: { b in anchors.contains { a in
                a.prefix == b.prefix && abs(a.x - b.x) <= 0.10 && abs(a.y - b.y) <= 0.08
            } }) { nextBubble = 0 }
            anchors = current
        }
    }
}
