// SPDX-License-Identifier: AGPL-3.0-only
// "Paketleri şimdi güncelle"nin sonucu ve ekrandaki metni: Mac ve iPhone uygulamalarında ortak (Windows'taki karşılığı
// CouchSubs.Core/PackUpdateSummary.cs, Android'deki packs/PackUpdateSummary.kt).

import CouchSubsCore
import Foundation

/// Elle güncellemenin sonucu (ekranda uyarı olarak gösterilir).
enum PackUpdateOutcome: Equatable {
    case upToDate
    case updated(PackUpdateSummary)
    /// Neden ve hataya rağmen inen paketler.
    case failed(String, PackUpdateSummary)
}

/// Güncellemenin sonucu: başlık, metin ve (hatada) "Yeniden dene".
struct PackUpdateAlert {
    let title: String
    let message: String
    let retry: Bool

    /// `stillUsed`: hatada eklenen "Bu telefondaki / bilgisayardaki paketler kullanılmaya devam ediyor." cümlesi.
    init(_ outcome: PackUpdateOutcome, stillUsed: String) {
        switch outcome {
        case .upToDate:
            title = String(localized: "Packs are up to date")
            message = String(localized: "The packs are already up to date.")
            retry = false
        case let .updated(summary):
            title = String(localized: "Packs updated")
            message = Self.describe(summary)
            retry = false
        case let .failed(reason, summary):
            title = String(localized: "The packs could not be updated")
            message = ([reason, stillUsed] + (summary.isEmpty ? [] : [Self.describe(summary)])).joined(separator: "\n\n")
            retry = true
        }
    }

    /// "2 paket güncellendi: Grand Theft Auto VI (+12.300 satır), Red Dead Redemption 2 (+800 satır)."
    static func describe(_ summary: PackUpdateSummary) -> String {
        var parts: [String] = []
        let updated = summary.updated, added = summary.added
        if !updated.isEmpty {
            let list = updated.map(Self.updatedItem).joined(separator: ", ")
            parts.append(updated.count == 1 ? String(format: String(localized: "1 pack updated: %@."), list)
                         : String(format: String(localized: "%lld packs updated: %@."), updated.count, list))
        }
        if !added.isEmpty {
            let list = added.map { String(format: String(localized: "%1$@ (%2$@ lines)"), $0.title, $0.lines.formatted()) }
                .joined(separator: ", ")
            parts.append(added.count == 1 ? String(format: String(localized: "1 pack added: %@."), list)
                         : String(format: String(localized: "%lld packs added: %@."), added.count, list))
        }
        if summary.newLines > 0 {
            parts.append(String(format: String(localized: "%@ new lines in total."), summary.newLines.formatted()))
        }
        return parts.joined(separator: "\n")
    }

    private static func updatedItem(_ change: PackUpdateSummary.Change) -> String {
        if change.lineDelta > 0 {
            return String(format: String(localized: "%1$@ (+%2$@ lines)"), change.title, change.lineDelta.formatted())
        }
        if change.lineDelta < 0 {
            return String(format: String(localized: "%1$@ (%2$@ fewer lines)"), change.title, (-change.lineDelta).formatted())
        }
        return String(format: String(localized: "%@ (translations revised)"), change.title)
    }
}
