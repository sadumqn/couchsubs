// SPDX-License-Identifier: AGPL-3.0-only
// "Geçmiş" ekranı ve Ayarlar'daki altyazı bölgesi karosu.

import CouchSubsCore
import SwiftUI
import UIKit

/// Bu ve önceki oturumlarda çevrilen son satırlar (en yenisi üstte); satırlar ve liste kopyalanabilir.
struct HistoryScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @State private var confirmClear = false
    @State private var copiedAll = false

    var body: some View {
        MobileScreen {
            BackHeader(title: "History")
        } content: {
            Text(String(format: String(localized: "The last %lld translated lines are kept on this phone."), SubtitleHistory.defaultLimit))
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            if model.history.entries.isEmpty {
                Text("No subtitles yet. Lines translated in this and earlier sessions appear here.")
                    .font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Tile(spacing: 0) {
                    ForEach(Array(model.history.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider() }
                        HistoryRow(entry: entry)
                    }
                }
            }
        } bottom: {
            if !model.history.entries.isEmpty {
                HStack(spacing: Mobile.Space.gap) {
                    Button {
                        UIPasteboard.general.string = SubtitleHistory.plainText(model.history.entries)
                        copiedAll = true
                    } label: {
                        Label(copiedAll ? "Copied" : "Copy", systemImage: copiedAll ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.mobileSecondary)
                    .resetsAfterDelay($copiedAll)
                    Button(role: .destructive) { confirmClear = true } label: { Label("Clear", systemImage: "trash") }
                        .buttonStyle(.mobileDestructive)
                }
            }
        }
        .confirmationDialog("Clear the history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { model.clearHistory() }
        } message: {
            Text("All saved lines are removed from this phone.")
        }
    }
}

/// Bir satır: saat ve kaynak, Türkçe, altında İngilizcesi. Basılı tutunca kopyalanır.
private struct HistoryRow: View {
    let entry: SubtitleHistory.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.hair) {
            Text(verbatim: "\(entry.date.formatted(date: .omitted, time: .standard)) · \(origin)")
                .font(Mobile.TypeScale.caption.monospacedDigit())
                .foregroundStyle(entry.origin == .pack ? Mobile.Palette.pro : Mobile.Palette.tertiary)
            Text(verbatim: entry.translation)
                .font(Mobile.TypeScale.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: entry.source)
                .font(Mobile.TypeScale.caption)
                .foregroundStyle(Mobile.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Mobile.Space.gap)
        .contentShape(Rectangle())
        .contextMenu {
            Button { UIPasteboard.general.string = "\(entry.translation)\n\(entry.source)" } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    private var origin: String {
        entry.origin == .pack ? String(localized: "Pack") : String(localized: "Translation engine")
    }
}

/// Ayarlar › Bu oyunun alanları: alanlar oynanan oyuna kaydedilir, o oyun yeniden oynanınca kendiliğinden gelir (Mac'teki
/// AreaProfileCard, Windows ve Android ile aynı).
struct AreaProfileTile: View {
    @ObservedObject var areas: GameAreas
    @EnvironmentObject private var model: PhoneModel
    @State private var confirmDelete = false

    var body: some View {
        let active = model.settings.activeAreaProfile == nil ? nil : areas.activeGame
        let target = areas.target
        let unsaved = model.settings.areasDifferFromProfile
        Tile {
            Text("Areas for this game").font(Mobile.TypeScale.headline)
            if let active {
                Text(verbatim: String(format: String(localized: "These areas are saved for %@."), active)).font(Mobile.TypeScale.body)
                hint(String(localized: unsaved ? "Your changes are not saved yet; they are dropped when translating stops."
                                               : "They come back by themselves whenever you play this game."))
            } else if let target {
                Text("These are your general areas.").font(Mobile.TypeScale.body)
                hint(String(format: String(localized: "Save them for %@ and they come back by themselves the next time you play it."), target))
            } else {
                Text("Areas can be saved for a game while translating, once the game being played is known.").font(Mobile.TypeScale.body)
                hint(String(localized: "The played game is shown on the home screen; you can choose it there."))
            }
            if let target, areas.targetHasOtherProfile {
                // Oynanan oyunun kayıtlı alanları uygulanmadı: üzerine yazılmaz, istenirse kullanılır.
                Button(String(format: String(localized: "Use the saved areas for %@"), target)) {
                    if let key = AreaProfiles.key(target, source: model.settings.areaSource) { areas.use(key) }
                }
                .buttonStyle(.mobileSecondary)
            } else if let target, active == nil || unsaved {
                Button(active == nil ? String(format: String(localized: "Save for %@"), target) : String(localized: "Save to profile")) {
                    areas.save()
                }
                .buttonStyle(.mobileSecondary)
            }
            if active != nil {
                Button("Delete profile") { confirmDelete = true }.buttonStyle(.mobileDestructive)
            }
        }
        .confirmationDialog(String(format: String(localized: "Delete the saved areas for %@?"), active ?? ""), isPresented: $confirmDelete) {
            Button("Delete profile", role: .destructive) { areas.delete() }
        }
    }

    private func hint(_ value: String) -> some View {
        Text(verbatim: value).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Ayarlar › Oyun profilleri: her oyunun kendi alanları. Listede olmayan oyun adı yazılarak eklenir; profil seçilir,
/// yeniden adlandırılır, çoğaltılır, silinir. Profil seçmek oynanan oyunu da o yapar (Mac, Windows ve Android ile aynı).
struct GameProfilesTile: View {
    @ObservedObject var areas: GameAreas
    @EnvironmentObject private var model: PhoneModel
    @State private var editing: Editing?
    @State private var name = ""
    @State private var problem: String?
    @State private var deleting: AreaProfile?

    private enum Editing: Equatable { case new, rename(String), duplicate(String) }

    var body: some View {
        Tile {
            Text("Game profiles").font(Mobile.TypeScale.headline)
            Text("Each game keeps its own subtitle area and extra areas. A game that isn't in the list can be added by typing its name; one profile never overwrites another.")
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.settings.gameProfiles, id: \.key) { profile in
                if editing == .rename(profile.key) || editing == .duplicate(profile.key) {
                    editor
                } else {
                    row(profile)
                }
                RowDivider()
            }
            if editing == .new {
                editor
            } else {
                Button("New game profile") { begin(.new, name: model.gameChoice.game?.name ?? "") }.buttonStyle(.mobileSecondary)
            }
        }
        .confirmationDialog(String(format: String(localized: "Delete the saved areas for %@?"), deleting?.game ?? ""),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete profile", role: .destructive) { if let deleting { areas.delete(deleting.key) } }
        }
    }

    private func row(_ profile: AreaProfile) -> some View {
        HStack(spacing: Mobile.Space.inline) {
            VStack(alignment: .leading, spacing: Mobile.Space.micro) {
                Text(verbatim: profile.game).font(Mobile.TypeScale.body).lineLimit(1)
                if model.settings.activeAreaProfile == profile.key {
                    Text("In use").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                }
            }
            Spacer(minLength: Mobile.Space.inline)
            if model.settings.activeAreaProfile != profile.key {
                Button("Use") { areas.use(profile.key) }
                    .font(Mobile.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(Mobile.Palette.accentText)
            }
            Menu {
                Button("Rename") { begin(.rename(profile.key), name: profile.game) }
                Button("Duplicate") { begin(.duplicate(profile.key), name: "") }
                Button("Delete profile", role: .destructive) { deleting = profile }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: Mobile.Control.icon, height: Mobile.Control.icon)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("More"))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.inline) {
            TextField("Game name", text: $name)
                .textFieldStyle(MobileFieldStyle())
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(commit)
            if let problem {
                Text(verbatim: problem).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Mobile.Space.inline) {
                Button(commitTitle) { commit() }
                    .buttonStyle(.mobileSecondary)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { editing = nil }
                    .font(Mobile.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(Mobile.Palette.secondary)
            }
        }
    }

    private var commitTitle: LocalizedStringKey {
        switch editing {
        case .rename?: "Rename"
        case .duplicate?: "Duplicate"
        case .new?, nil: "Save current areas"
        }
    }

    private func begin(_ mode: Editing, name: String) {
        editing = mode
        self.name = name
        problem = nil
    }

    private func commit() {
        guard let editing else { return }
        let edit: AreaProfiles.Edit = switch editing {
        case .new: areas.saveAs(name)
        case .rename(let key): areas.rename(key, to: name)
        case .duplicate(let key): areas.duplicate(key, as: name)
        }
        switch edit {
        case .done: self.editing = nil
        case .exists: problem = String(format: String(localized: "There is already a profile for %@."), name.trimmingCharacters(in: .whitespacesAndNewlines))
        case .empty, .missing: problem = String(localized: "Type the game's name.")
        }
    }
}

/// Ayarlar › Altyazı alanı: hazır seçimler, son kareyle canlı önizleme (çerçeve sürüklenir), Özel'de kaydırıcılar.
struct AreaTile: View {
    @EnvironmentObject private var model: PhoneModel
    var resetTitle: LocalizedStringKey?

    var body: some View {
        Tile {
            Text("Subtitle area").font(Mobile.TypeScale.headline)
            SegmentedTabs(options: [AreaPreset.bottom: "Bottom area", .top: "Top area", .full: "Full screen", .custom: "Custom"],
                          selection: Binding(get: { model.settings.areaPreset }, set: { model.settings.selectAreaPreset($0) }))
            PhoneRegionPreview(settings: $model.settings, preview: model.framePreview)
            if model.settings.areaPreset == .custom {
                let percent = model.settings.region.verticalPercent
                sliderRow("Vertical position", value: percent.position, range: 0...max(1, 100 - percent.height)) {
                    model.settings.setCustomRegion(model.settings.region.withVertical(position: $0, height: percent.height))
                }
                sliderRow("Height", value: percent.height, range: CropRegion.minimumSize * 100...100) {
                    model.settings.setCustomRegion(model.settings.region.withVertical(position: percent.position, height: $0))
                }
            }
            Toggle(isOn: $model.settings.keepAreaCentered) {
                Text("Keep centered").font(Mobile.TypeScale.headline)
            }
            .tint(Mobile.Palette.accent)
            // "Ortalı kalır" yalnız Ortada tut açıkken yazılır.
            Group {
                if model.settings.keepAreaCentered {
                    Text("Drag the frame to move it, or drag an edge or corner to resize it; the subtitle area stays centered.")
                } else {
                    Text("Drag the frame to move it, or drag an edge or corner to resize it.")
                }
            }
            .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            // Mac'teki Alanları Sıfırla: altyazı alanı Alt hazır seçimine döner (başlık Ayarlar › Altyazı Alanı'ndan gelir).
            if let resetTitle {
                Button(resetTitle) { model.settings.selectAreaPreset(.bottom) }
                    .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true))
            }
        }
    }

    private func sliderRow(_ title: LocalizedStringKey, value: Double, range: ClosedRange<Double>,
                           set: @escaping (Double) -> Void) -> some View {
        DSSliderRow(title: title, valueText: percentText(value), value: Binding(get: { value }, set: set), range: range)
    }
}

/// Ayarlar › Ek alanlar: altyazının yanında sürekli okunan küçük alanlar (görev, bildirim, telefon mesajı; en çok
/// `ExtraArea.maxCount`, Mac ile aynı sınır). Her biri adlandırılır, açılıp kapatılır; çerçevesi canlı önizlemede sürüklenir
/// (Mac'teki ExtraAreasCard ile aynı).
struct ExtraAreasTile: View {
    @EnvironmentObject private var model: PhoneModel

    var body: some View {
        Tile {
            Text("Extra areas").font(Mobile.TypeScale.headline)
            Text("Also reads small text next to the subtitle, such as objectives, phone messages or notifications. Each area is read once a second and translated again when the text changes; the translation appears on the TV next to that text.")
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Tam ekranda ek alanlar okunmaz (bkz. activeExtraAreas); ayarları korunur, düzenlenebilir.
            if model.settings.extraAreasPausedByFullScreen, !model.settings.extraAreas.isEmpty {
                Text("Extra areas aren't read while the subtitle area is Full screen, because the whole screen is already read. They're read again when you pick another area.")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.settings.extraAreas) { area in
                ExtraAreaEditor(id: area.id, settings: $model.settings, preview: model.framePreview)
                    .opacity(model.settings.extraAreasPausedByFullScreen ? 0.5 : 1)
            }
            if model.settings.canAddExtraArea {
                Menu {
                    ForEach(ExtraAreaPreset.allCases, id: \.self) { preset in
                        Button(preset.title) { model.settings.addExtraArea(preset, name: preset.defaultName) }
                    }
                } label: {
                    Label("Add Extra Area", systemImage: "plus")
                }
                .buttonStyle(.mobileSecondary)
            }
        }
    }
}

private struct ExtraAreaEditor: View {
    let id: String
    @Binding var settings: UserSettings
    /// Önizleme ayrı görünümde izlenir: her yeni karede yalnız önizleme yeniden çizilir, ad alanı ve seçimler değil.
    let preview: PhoneFramePreview

    var body: some View {
        if let area = settings.extraAreas.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: Mobile.Space.inline) {
                HStack(spacing: Mobile.Space.inline) {
                    TextField("Area name", text: Binding(get: { area.name }, set: { name in settings.updateExtraArea(id: id) { $0.name = name } }))
                        .textFieldStyle(DSTextFieldStyle())
                    // Yalnız anahtar (adı yanındaki alan); yeni dildeki anahtar, kendi düğmesiyle.
                    Button { settings.updateExtraArea(id: id) { $0.enabled.toggle() } } label: {
                        DSSwitch(isOn: .constant(area.enabled)).frame(minWidth: Mobile.Control.icon, minHeight: Mobile.Control.icon)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Read this area"))
                    .accessibilityValue(Text(area.enabled ? "On" : "Off"))
                    Button { settings.removeExtraArea(id: id) } label: {
                        Image(systemName: "trash")
                            .frame(width: Mobile.Control.icon, height: Mobile.Control.icon)
                            .contentShape(Rectangle())
                    }
                        .foregroundStyle(Mobile.Palette.secondary)
                        .accessibilityLabel(Text("Remove"))
                }
                SegmentedTabs(options: [ExtraAreaPreset.quest: "Quest", .notification: "Notification", .phone: "Phone"],
                              selection: Binding(get: { ExtraAreaPreset.matching(area.region) ?? .quest },
                                                 set: { preset in settings.updateExtraArea(id: id) { $0.region = preset.region } }))
                ExtraAreaPreview(region: area.region, preview: preview) { region in
                    settings.updateExtraArea(id: id) { $0.region = region }
                }
                .opacity(area.enabled ? 1 : 0.5)
            }
            .padding(Mobile.Space.gap)
            .background(Mobile.Palette.bg, in: RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous).strokeBorder(Mobile.Palette.border))
        }
    }
}

/// Ek alanın önizlemesi, son PS5 karesiyle (kare değişince yalnız bu görünüm yeniden çizilir).
private struct ExtraAreaPreview: View {
    let region: CropRegion
    @ObservedObject var preview: PhoneFramePreview
    let onChange: (CropRegion) -> Void

    var body: some View {
        RegionPreview(region: region, frame: preview.image, onChange: onChange)
    }
}

extension ExtraAreaPreset {
    /// Seçimin ekrandaki adı.
    var title: LocalizedStringKey {
        switch self {
        case .quest: "Quest (top right)"
        case .notification: "Notification (bottom left)"
        case .phone: "Phone (bottom right)"
        }
    }

    /// Yeni alanın adı (kullanıcı değiştirebilir).
    var defaultName: String {
        switch self {
        case .quest: String(localized: "Quest")
        case .notification: String(localized: "Notification")
        case .phone: String(localized: "Phone")
        }
    }
}

/// Önizleme son kareyi izler; kare değişince yalnız bu görünüm yeniden çizilir.
private struct PhoneRegionPreview: View {
    @Binding var settings: UserSettings
    @ObservedObject var preview: PhoneFramePreview

    var body: some View {
        RegionPreview(region: settings.region, frame: preview.image, centered: settings.keepAreaCentered) { settings.setCustomRegion($0) }
    }
}
