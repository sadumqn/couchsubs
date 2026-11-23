// SPDX-License-Identifier: AGPL-3.0-only
import XCTest
@testable import CouchSubsCore

#if canImport(CoreGraphics)
import CoreGraphics

/// Kullanıcı bildirimi (GTA 6): oyun altta "x yere git" gibi bir görev yazısı gösterirken o sırada gelen altyazıların hiçbiri
/// çevrilmiyordu. Görev satırı sabit dururken üstünde ya da altında değişen altyazıların hepsi çevrilmeli, görev hiçbir
/// altyazıya karışmamalı (Windows: ObjectiveWithDialogueTests.cs, Android: ObjectiveWithDialogueTest.kt).
private final class SequenceReader: TextReader, @unchecked Sendable {
    var readings: [Reading]
    init(_ readings: [Reading]) { self.readings = readings }
    func read(_ image: CGImage) throws -> String { try readLines(image, deep: false).text }
    func readLines(_ image: CGImage, deep: Bool) throws -> Reading { readings.isEmpty ? Reading.empty : readings.removeFirst() }
}
private final class ObjectiveSender: SubtitleSending {
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) {}
    func clear() {}
}
private final class ObjectiveTranslator: TextTranslator {
    var requested: [String] = []
    func translate(_ text: String) async throws -> String {
        requested.append(text)
        return "TR: " + text
    }
}

@MainActor
final class ObjectiveWithDialogueTests: XCTestCase {
    static let objective = "Go to the bank."
    static let dialogue: [[String]] = [
        ["We have to move before the cops show up."],
        ["I told you this was a bad idea,", "but you never listen to me."],
        ["Lucia: Just drive the car and stay calm."],
        ["Where did they take all the money?"],
        ["Nobody saw us leave the place.", "Keep your head down for a while."],
    ]
    static let line = 0.08

    static func row(_ text: String, _ top: Double, width: Double = 0.6) -> TextLine {
        TextLine(text, box: TextBox(left: 0.5 - width / 2, top: top, right: 0.5 + width / 2, bottom: top + line), confidence: 0.95)
    }

    /// Görev önce tek başına (`objectiveFirst` kare), sonra her altyazı 4 kare (2 sn) görevle birlikte.
    static func frames(below: Bool, gap: Double, objectiveFirst: Int) -> [Reading] {
        let alone = Reading(lines: [row(objective, below ? 0.8 : 0.2, width: 0.3)])
        var frames = Array(repeating: alone, count: objectiveFirst)
        for lines in dialogue {
            let height = Double(lines.count) * line
            var rows: [TextLine] = []
            if below {
                let top = 0.8 - gap * line - height
                rows += lines.enumerated().map { row($1, top + Double($0) * line) }
                rows.append(row(objective, 0.8, width: 0.3))
            } else {
                rows.append(row(objective, 0.2, width: 0.3))
                let top = 0.2 + line + gap * line
                rows += lines.enumerated().map { row($1, top + Double($0) * line) }
            }
            frames += Array(repeating: Reading(lines: rows), count: 4)
        }
        return frames + Array(repeating: alone, count: 4)
    }

    func run(below: Bool, gap: Double, objectiveFirst: Int) async {
        let frames = Self.frames(below: below, gap: gap, objectiveFirst: objectiveFirst)
        var time = 0
        let translator = ObjectiveTranslator()
        let pipeline = SubtitlePipeline(reader: SequenceReader(frames), translator: translator, server: ObjectiveSender(), clock: { time })
        pipeline.packWait = 0; pipeline.cleanWait = 0
        let image = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        for _ in frames.indices {
            await pipeline.process(image, region: CropRegion(top: 0, bottom: 1, left: 0, right: 1))
            await pipeline.waitForTranslations()
            time += 500
        }
        let label = "below: \(below) gap: \(gap) first: \(objectiveFirst) — istekler: \(translator.requested)"
        // Görev ilk altyazıyla aynı anda belirince de ilk altyazı çevrilir (kısa görev satırı altyazının altında; beta.69).
        let missing = Self.dialogue.flatMap { $0 }.map { $0.replacingOccurrences(of: "Lucia: ", with: "") }
            .filter { line in !translator.requested.contains { $0.contains(line) } }
        XCTAssertEqual(missing, [], "çevrilmedi — \(label)")
        let mixed = translator.requested.filter { $0.contains("Go to the bank") && $0.trimmingCharacters(in: .whitespaces) != Self.objective }
            .filter { objectiveFirst != 0 || !$0.contains(Self.dialogue[0][0]) }
        XCTAssertEqual(mixed, [], "görev karıştı — \(label)")
    }

    func testEveryDialogueIsTranslatedWhileObjectiveStays() async {
        for (below, gap, first) in [(true, 0.1, 4), (true, 1.5, 4), (false, 0.1, 4), (false, 1.5, 4),
                                    (true, 0.1, 20), (true, 1.5, 20), (false, 0.1, 20), (true, 0.1, 0), (true, 1.5, 0)] {
            await run(below: below, gap: gap, objectiveFirst: first)
        }
    }

    /// Kullanıcı bildirimi (X, beta.69, GTA 6): konuşma sürerken altta "Follow John" görevi belirdi, o konuşma çevrilmedi.
    /// Görev konuşmayla aynı anda ya da konuşma başladıktan 0,5–2 sn sonra gelir; görev altyazıdan ayrı blok ya da bitişik.
    /// Konuşma çevrilir, görev altyazının yerine geçmez, görev kendi yerinde gösterilir.
    func testObjectiveArrivingDuringDialogueDoesNotReplaceIt() async {
        let objective = "Follow John"
        let dialogue = ["I can't believe he's still alive after all that.", "We need to keep moving before they find us."]
        let objectiveTop = 0.8
        let image = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        for (after, gap) in [(0, 1.5), (1, 1.5), (2, 1.5), (4, 1.5), (0, 0.1), (2, 0.1), (4, 0.1)] {
            let dialogueTop = objectiveTop - gap * Self.line - Self.line
            var frames: [Reading] = (0..<8).map { i in
                Reading(lines: i < after ? [Self.row(dialogue[0], dialogueTop)]
                                         : [Self.row(dialogue[0], dialogueTop), Self.row(objective, objectiveTop, width: 0.25)])
            }
            frames += Array(repeating: Reading(lines: [Self.row(dialogue[1], dialogueTop),
                                                       Self.row(objective, objectiveTop, width: 0.25)]), count: 8)
            var time = 0
            let translator = ObjectiveTranslator()
            let pipeline = SubtitlePipeline(reader: SequenceReader(frames), translator: translator, server: ObjectiveSender(),
                                            clock: { time })
            pipeline.packWait = 0; pipeline.cleanWait = 0
            var regions: [CropRegion?] = []
            pipeline.onMissionChanged = { regions.append($0) }
            for _ in frames.indices {
                await pipeline.process(image, region: CropRegion(top: 0, bottom: 1, left: 0, right: 1))
                await pipeline.waitForTranslations()
                time += 500
            }
            let label = "after: \(after) gap: \(gap) — istekler: \(translator.requested)"
            for line in dialogue {
                XCTAssertTrue(translator.requested.contains { $0.contains(line) }, "çevrilmedi: \(line) — \(label)")
            }
            // Görev tek başına altyazı olarak çevrilmedi (konuşmanın yerine geçmedi).
            XCTAssertFalse(translator.requested.contains { $0.trimmingCharacters(in: .whitespaces) == objective }, label)
            // Görev kendi yerinde.
            XCTAssertTrue(regions.contains { region in
                guard let region else { return false }
                return region.top <= objectiveTop && region.bottom >= objectiveTop + Self.line
            }, "görev alanı yok — \(label)")
        }
    }
}
#endif
