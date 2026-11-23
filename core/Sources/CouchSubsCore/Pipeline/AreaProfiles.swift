// SPDX-License-Identifier: AGPL-3.0-only

import Combine
import Foundation

/// Alanların ölçüldüğü görüntü: konsolun kendi akışı (PS5/Xbox) ya da yakalanan pencere (Remote Play).
public enum AreaSource: Sendable { case stream, window }

/// Bir oyunun alanları: altyazı alanı, hazır seçimi ve ek alanlar.
public struct AreaSet: Codable, Equatable, Sendable {
    public var region: CropRegion
    public var areaPreset: AreaPreset
    public var extraAreas: [ExtraArea]

    public init(region: CropRegion, areaPreset: AreaPreset, extraAreas: [ExtraArea]) {
        self.region = region
        self.areaPreset = areaPreset
        self.extraAreas = extraAreas
    }
}

/// Oyuna göre kaydedilmiş alanlar. `key`: `AreaProfiles.key`; `game`: gösterilen ad.
public struct AreaProfile: Codable, Equatable, Sendable {
    public var key: String
    public var game: String
    public var areas: AreaSet

    public init(key: String, game: String, areas: AreaSet) {
        self.key = key
        self.game = game
        self.areas = areas
    }
}

/// Oyuna göre okuma alanları: kullanıcı bir oyunun altyazı alanını ve ek alanlarını kaydeder; o oyun yeniden oynanınca
/// alanlar kendiliğinden gelir. Profil oyun adıyla (`GameName.key`) ve görüntünün kaynağıyla anılır. Windows'taki
/// CouchSubs.Core/AreaProfiles.cs ve Android'deki AreaProfiles.kt ile aynı kurallar.
public enum AreaProfiles {
    /// En çok bu kadar profil saklanır; fazlasında en uzun süredir kullanılmayan silinir.
    public static let maxCount = 50

    /// Profilin anahtarı ("far cry 3|stream"); oyun adı boşsa nil.
    public static func key(_ game: String?, source: AreaSource) -> String? {
        let name = GameName.key(game ?? "")
        return name.isEmpty ? nil : name + "|" + (source == .window ? "window" : "stream")
    }

    /// Anahtarın görüntü kaynağı ("…|window" → pencere, gerisi akış).
    public static func source(ofKey key: String) -> AreaSource { key.hasSuffix("|window") ? .window : .stream }

    /// Profil listesinde ad değişikliği ya da çoğaltmanın sonucu.
    public enum Edit: Equatable, Sendable {
        case done
        /// Ad boş (ya da yalnız noktalama).
        case empty
        /// Bu adla başka bir oyunun profili var; üzerine yazılmaz.
        case exists
        /// Profil bulunamadı.
        case missing
    }

    /// Profilin adı `game` olur (aynı kaynakta). Yeni adın anahtarı başka bir profilinse değişmez (`exists`).
    public static func renamed(_ profiles: [AreaProfile], key: String, to game: String) -> (profiles: [AreaProfile], key: String?, edit: Edit) {
        let name = game.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = profiles.firstIndex(where: { $0.key == key }) else { return (profiles, nil, .missing) }
        guard let next = Self.key(name, source: source(ofKey: key)) else { return (profiles, nil, .empty) }
        if next != key, profiles.contains(where: { $0.key == next }) { return (profiles, nil, .exists) }
        var result = profiles
        result[index] = AreaProfile(key: next, game: name, areas: profiles[index].areas)
        return (result, next, .done)
    }

    /// Profilin alanları `game` adıyla yeni bir profile kopyalanır (aynı kaynakta); o adın profili varsa `exists`.
    public static func duplicated(_ profiles: [AreaProfile], key: String, as game: String) -> (profiles: [AreaProfile], key: String?, edit: Edit) {
        let name = game.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = profiles.first(where: { $0.key == key }) else { return (profiles, nil, .missing) }
        guard let next = Self.key(name, source: source(ofKey: key)) else { return (profiles, nil, .empty) }
        if profiles.contains(where: { $0.key == next }) { return (profiles, nil, .exists) }
        return (saved(profiles, AreaProfile(key: next, game: name, areas: profile.areas)) { $0.key }, next, .done)
    }

    public enum Step: Equatable, Sendable {
        /// Bir şey değişmez.
        case none
        /// Oyun kesin biliniyor (PS5 bildirdi ya da kullanıcı seçti): profil hemen uygulanır.
        case apply(String)
        /// Oyun yalnız paketten tanındı ya da seçim önceki oturumdan kaldı: alanlar sessizce değişmez, kullanıcıya sorulur.
        case offer(String)
        /// Başka bir oyuna geçildi ve onun profili yok: genel alanlara dönülür.
        case useGeneral
    }

    /// Oyun değişince ne yapılır. `active`: uygulanan profilin anahtarı (genel alanlarda nil). `declined`: bu oturumda
    /// geri alınan ya da istenmeyen profiller. Oyun bilinmez olursa son uygulanan profil kalır.
    public static func decide(active: String?, game: String?, source: GameSense.Source?, areaSource: AreaSource,
                              exists: (String) -> Bool, declined: (String) -> Bool) -> Step {
        guard let source, let key = key(game, source: areaSource), key != active else { return .none }
        if exists(key), !declined(key) { return source == .pack || source == .remembered ? .offer(key) : .apply(key) }
        return active == nil ? .none : .useGeneral
    }

    /// Profil eklendi ya da kullanıldı: aynı anahtarlı eskisi çıkar, yenisi sona eklenir (sıra son kullanımdır);
    /// `maxCount`'u aşınca baştan, en uzun süredir kullanılmayan silinir.
    public static func saved<T>(_ profiles: [T], _ profile: T, key: (T) -> String) -> [T] {
        let id = key(profile)
        let next = profiles.filter { key($0) != id } + [profile]
        return Array(next.suffix(maxCount))
    }
}

extension UserSettings {
    /// Alanların ölçüldüğü görüntü.
    public var areaSource: AreaSource { frameSource == .ps5 ? .stream : .window }

    /// Şu an okunan alanlar.
    public var areas: AreaSet {
        get { AreaSet(region: region, areaPreset: areaPreset, extraAreas: extraAreas) }
        set {
            region = newValue.region
            areaPreset = newValue.areaPreset
            extraAreas = newValue.extraAreas
        }
    }

    public func areaProfile(_ key: String?) -> AreaProfile? {
        key.flatMap { key in areaProfiles.first { $0.key == key } }
    }

    /// Profil uygulanır: genel alanlar (henüz kenarda değilse) saklanır, okunan alanlar profilinki olur.
    public mutating func useAreaProfile(_ profile: AreaProfile) {
        if generalAreas == nil { generalAreas = areas }
        areas = profile.areas
        activeAreaProfile = profile.key
        areaProfiles = AreaProfiles.saved(areaProfiles, profile) { $0.key }
    }

    /// Profil bırakılır, genel alanlar geri gelir (profilde kaydedilmemiş değişiklikler bırakılır).
    public mutating func useGeneralAreas() {
        if let generalAreas { areas = generalAreas }
        generalAreas = nil
        activeAreaProfile = nil
    }

    /// Okunan alanlar `game` için kaydedilir ve o profil etkin olur.
    public mutating func saveAreaProfile(for game: String) {
        guard let key = AreaProfiles.key(game, source: areaSource) else { return }
        areaProfiles = AreaProfiles.saved(areaProfiles, AreaProfile(key: key, game: game, areas: areas)) { $0.key }
        activeAreaProfile = key
        if generalAreas == nil { generalAreas = areas }
    }

    /// Okunan alanlar yeni bir oyun profili olur ve etkinleşir (listede olmayan oyun da adıyla). O adın profili varsa
    /// hiçbir şey değişmez (`exists`): başka oyunun alanlarının üzerine yazılmaz.
    @discardableResult
    public mutating func createAreaProfile(for game: String) -> AreaProfiles.Edit {
        let name = game.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = AreaProfiles.key(name, source: areaSource) else { return .empty }
        guard areaProfile(key) == nil else { return .exists }
        saveAreaProfile(for: name)
        return .done
    }

    /// Profilin adı değişir; etkinse etkin kalır.
    @discardableResult
    public mutating func renameAreaProfile(_ key: String, to game: String) -> AreaProfiles.Edit {
        let result = AreaProfiles.renamed(areaProfiles, key: key, to: game)
        guard result.edit == .done, let next = result.key else { return result.edit }
        areaProfiles = result.profiles
        if activeAreaProfile == key { activeAreaProfile = next }
        return .done
    }

    /// Profilin alanları başka bir oyun adıyla kopyalanır; etkin profil değişmez.
    @discardableResult
    public mutating func duplicateAreaProfile(_ key: String, as game: String) -> AreaProfiles.Edit {
        let result = AreaProfiles.duplicated(areaProfiles, key: key, as: game)
        guard result.edit == .done else { return result.edit }
        areaProfiles = result.profiles
        return .done
    }

    /// Şu anki görüntü kaynağının profilleri, ada göre sıralı (Ayarlar'daki oyun profilleri listesi).
    public var gameProfiles: [AreaProfile] {
        areaProfiles.filter { AreaProfiles.source(ofKey: $0.key) == areaSource }
            .sorted { $0.game.localizedCaseInsensitiveCompare($1.game) == .orderedAscending }
    }

    /// Profil silinir; etkinse genel alanlara dönülür.
    public mutating func deleteAreaProfile(_ key: String) {
        if activeAreaProfile == key { useGeneralAreas() }
        areaProfiles.removeAll { $0.key == key }
    }

    /// Etkin profil var ve okunan alanlar ondan farklı: "Profile kaydet" gösterilir.
    public var areasDifferFromProfile: Bool {
        guard let profile = areaProfile(activeAreaProfile) else { return false }
        return profile.areas != areas
    }
}

/// Mac ve iPhone uygulamasının oyuna göre alanları: oyun değişince profil uygulanır, önerilir ya da genel alanlara
/// dönülür; "Geri al", "Kullan/Hayır", kaydetme ve silme. Ayarlar uygulamanın modelindedir (`read`/`write`).
/// Windows'ta AppController, Android'de GameAreas.kt aynı kurallarla çalışır.
@MainActor
public final class GameAreas: ObservableObject {
    /// Paketten tanınan oyunun önerilen profili ("Kayıtlı alanlar kullanılsın mı?").
    @Published public private(set) var offered: String?
    /// Çeviri sürüyor (oturum yokken profil uygulanmaz, kaydedilemez).
    @Published public private(set) var running = false
    /// Oynanan oyun (kaydetme hedefi).
    @Published public private(set) var game: String?

    private var declined: Set<String> = []
    private let read: () -> UserSettings
    private let write: (UserSettings) -> Void

    public init(read: @escaping () -> UserSettings, write: @escaping (UserSettings) -> Void) {
        self.read = read
        self.write = write
    }

    /// Uygulanan profilin oyunu; genel alanlarda nil.
    public var activeGame: String? { let settings = read(); return settings.areaProfile(settings.activeAreaProfile)?.game }
    /// Önerilen profilin oyunu.
    public var offeredGame: String? { read().areaProfile(offered)?.game }
    /// Alanların kaydedilebileceği oyun (çeviri sürerken): oynanan oyun, bilinmiyorsa etkin profilin oyunu. Kaydetme
    /// düğmesi bu adı taşır; başka bir oyunun profiline sessizce yazılmaz.
    public var target: String? { running ? game ?? activeGame : nil }
    /// Hedef oyunun kayıtlı profili var ama uygulanmadı (öneri bekliyor ya da "Hayır" dendi): "X için kaydet" yerine
    /// "Kayıtlı alanları kullan" gösterilir; kayıtlı alanların üzerine yazılmaz.
    public var targetHasOtherProfile: Bool {
        guard let target else { return false }
        let settings = read()
        guard let key = AreaProfiles.key(target, source: settings.areaSource) else { return false }
        return key != settings.activeAreaProfile && settings.areaProfile(key) != nil
    }
    /// Etkin profil kaydedilmemiş değişiklik içeriyor.
    public var unsaved: Bool { read().areasDifferFromProfile }
    /// Profil seçilince ya da yeni profil açılınca oynanan oyun o olur (uygulama `GameChoice.choose`a bağlar).
    public var onChoose: (String) -> Void = { _ in }

    /// Uygulama açılırken: oturum sürerken kapandıysa açık kalan profil kapanır.
    public static func restored(_ settings: UserSettings) -> UserSettings {
        guard settings.activeAreaProfile != nil || settings.generalAreas != nil else { return settings }
        var next = settings
        next.useGeneralAreas()
        return next
    }

    /// Çeviri başladı.
    public func start() {
        running = true
        declined = []
    }

    /// Oyun ya da nereden bilindiği değişti (`GameChoice.onPublish`).
    public func follow(game current: RunningGame?, source: GameSense.Source?) {
        game = current?.name
        guard running else { return }
        let settings = read()
        let step = AreaProfiles.decide(active: settings.activeAreaProfile, game: current?.name, source: source,
                                       areaSource: settings.areaSource,
                                       exists: { settings.areaProfile($0) != nil }, declined: { self.declined.contains($0) })
        if case .offer(let key) = step { offered = key } else { offered = nil }
        switch step {
        case .apply(let key): if let profile = settings.areaProfile(key) { change { $0.useAreaProfile(profile) } }
        case .useGeneral: change { $0.useGeneralAreas() }
        case .none, .offer: break
        }
    }

    /// "Kullan".
    public func useOffered() {
        if let profile = read().areaProfile(offered) { change { $0.useAreaProfile(profile) } }
        offered = nil
    }

    /// "Hayır": bu oturumda bir daha sorulmaz.
    public func declineOffered() {
        if let offered { declined.insert(offered) }
        offered = nil
    }

    /// "Geri al": genel alanlara dönülür; bu oyunun profili bu oturumda yeniden uygulanmaz.
    public func undo() {
        guard let key = read().activeAreaProfile else { return }
        declined.insert(key)
        change { $0.useGeneralAreas() }
    }

    /// Okunan alanlar oynanan oyunun profiline (yoksa yeni), oyun bilinmiyorsa etkin profile kaydedilir. Oynanan oyunun
    /// başka kayıtlı alanları varsa ve uygulanmadıysa kaydedilmez (`targetHasOtherProfile`).
    public func save() {
        guard let target, !targetHasOtherProfile else { return }
        if let key = AreaProfiles.key(target, source: read().areaSource) { declined.remove(key) }
        change { $0.saveAreaProfile(for: target) }
    }

    /// Okunan alanlar adı yazılan oyunun yeni profili olur (listede olmayan oyun da) ve oynanan oyun o olur. Çeviri
    /// dururken de çalışır. O adın profili varsa `exists`.
    @discardableResult
    public func saveAs(_ game: String) -> AreaProfiles.Edit {
        var settings = read()
        let edit = settings.createAreaProfile(for: game)
        guard edit == .done else { return edit }
        if let key = settings.activeAreaProfile { declined.remove(key) }
        offered = nil
        objectWillChange.send()
        write(settings)
        onChoose(game.trimmingCharacters(in: .whitespacesAndNewlines))
        return .done
    }

    /// Listeden profil seçildi: alanları uygulanır, oynanan oyun o olur.
    public func use(_ key: String) {
        guard let profile = read().areaProfile(key) else { return }
        declined.remove(key)
        offered = nil
        change { $0.useAreaProfile(profile) }
        onChoose(profile.game)
    }

    /// Profil yeniden adlandırılır; etkin profilse oynanan oyun da yeni ad olur (yoksa oyun değişince profil bırakılırdı).
    @discardableResult
    public func rename(_ key: String, to game: String) -> AreaProfiles.Edit {
        var settings = read()
        let wasActive = settings.activeAreaProfile == key
        let edit = settings.renameAreaProfile(key, to: game)
        guard edit == .done else { return edit }
        objectWillChange.send()
        write(settings)
        if wasActive { onChoose(game.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return .done
    }

    /// Profilin alanları başka bir oyun adıyla kopyalanır.
    @discardableResult
    public func duplicate(_ key: String, as game: String) -> AreaProfiles.Edit {
        var settings = read()
        let edit = settings.duplicateAreaProfile(key, as: game)
        guard edit == .done else { return edit }
        objectWillChange.send()
        write(settings)
        return .done
    }

    /// Etkin profil silinir.
    public func delete() {
        guard let key = read().activeAreaProfile else { return }
        delete(key)
    }

    /// Profil silinir; etkinse genel alanlara dönülür.
    public func delete(_ key: String) {
        if offered == key { offered = nil }
        change { $0.deleteAreaProfile(key) }
    }

    /// Çeviri durdu: profil bırakılır (kaydedilmemiş alan değişiklikleri de).
    public func stop() {
        running = false
        offered = nil
        declined = []
        let settings = read()
        if settings.activeAreaProfile != nil || settings.generalAreas != nil { change { $0.useGeneralAreas() } }
    }

    private func change(_ edit: (inout UserSettings) -> Void) {
        var settings = read()
        edit(&settings)
        objectWillChange.send()
        write(settings)
    }
}
