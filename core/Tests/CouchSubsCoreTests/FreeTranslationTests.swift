// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Terim ekleri ünlü uyumu, kaynaştırma ve ünsüz benzeşmesiyle kurulur (Windows: TurkishSuffixTests, aynı örnekler).
final class TurkishSuffixTests: XCTestCase {
    private func check(_ cases: [(String, String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (term, suffix, expected) in cases {
            XCTAssertEqual(TurkishSuffix.attach(term, suffix: suffix), expected, "\(term) + \(suffix)", file: file, line: line)
        }
    }

    func testProperNounsTakeHarmonizedSuffixWithApostrophe() {
        check([
            ("Kratos", "u", "Kratos'u"), ("Kratos", "un", "Kratos'un"), ("Kratos", "a", "Kratos'a"), ("Kratos", "da", "Kratos'ta"),
            ("Kratos", "dan", "Kratos'tan"), ("Kratos", "la", "Kratos'la"), ("Kratos", "dur", "Kratos'tur"),
            ("Atreus", "un", "Atreus'un"), ("Atreus", "a", "Atreus'a"),
            ("Midgard", "a", "Midgard'a"), ("Midgard", "da", "Midgard'da"), ("Midgard", "u", "Midgard'ı"),
            ("Midgard", "un", "Midgard'ın"), ("Midgard", "daki", "Midgard'daki"),
            ("Freya", "u", "Freya'yı"), ("Freya", "a", "Freya'ya"), ("Freya", "un", "Freya'nın"), ("Freya", "la", "Freya'yla"),
            ("Freya", "da", "Freya'da"),
            ("Mimir", "a", "Mimir'e"), ("Mimir", "u", "Mimir'i"), ("Mimir", "un", "Mimir'in"), ("Mimir", "dan", "Mimir'den"),
            ("Brok", "da", "Brok'ta"), ("Brok", "u", "Brok'u"),
            ("Jötunheim", "a", "Jötunheim'e"), ("Jötunheim", "da", "Jötunheim'de"),
            ("Thor", "un", "Thor'un"), ("Baldur", "u", "Baldur'u"), ("Sindri", "un", "Sindri'nin"), ("Sindri", "u", "Sindri'yi"),
            ("Odin", "a", "Odin'e"), ("Odin", "ya", "Odin'e"), ("Freya", "nın", "Freya'nın"), ("Kratos", "nın", "Kratos'un"),
            ("Kratos", "", "Kratos"),
        ])
    }

    func testCompoundNamesTakeTheBufferN() {
        check([
            ("Leviathan Baltası", "u", "Leviathan Baltası'nı"), ("Leviathan Baltası", "a", "Leviathan Baltası'na"),
            ("Leviathan Baltası", "da", "Leviathan Baltası'nda"), ("Leviathan Baltası", "dan", "Leviathan Baltası'ndan"),
            ("Leviathan Baltası", "un", "Leviathan Baltası'nın"), ("Leviathan Baltası", "la", "Leviathan Baltası'yla"),
            ("Dünya Ağacı", "a", "Dünya Ağacı'na"), ("Kaos Bıçakları", "u", "Kaos Bıçakları'nı"),
        ])
    }

    func testCommonNounsAreWrittenTogether() {
        check([
            ("can iksiri", "u", "can iksirini"), ("kontrol noktası", "a", "kontrol noktasına"),
            ("bekleme süresi", "da", "bekleme süresinde"), ("envanter", "a", "envantere"), ("envanter", "da", "envanterde"),
            ("kılıç", "u", "kılıcı"), ("kitap", "u", "kitabı"), ("bıçak", "u", "bıçağı"), ("renk", "u", "rengi"), ("top", "u", "topu"),
            ("balta", "u", "baltayı"), ("balta", "lar", "baltalar"), ("kalkan", "lar", "kalkanlar"), ("kalkan", "dan", "kalkandan"),
            ("kalkan", "la", "kalkanla"),
        ])
    }

    func testApostropheAbbreviationsAndCapitals() {
        XCTAssertEqual(TurkishSuffix.attach("Kratos", suffix: "un", apostrophe: "’"), "Kratos’un")
        XCTAssertEqual(TurkishSuffix.attach("XP", suffix: "u"), "XP'yi")
        XCTAssertEqual(TurkishSuffix.attach("Midgard", suffix: "A"), "Midgard'a")
    }
}

/// Terim sözlüğü (Windows: GlossaryTests).
final class GlossaryTests: XCTestCase {
    static let godOfWar = """
        { "game": "God of War",
          "terms": { "Leviathan Axe": "Leviathan Baltası", "Axe": "Balta", "Midgard": "Midgard", "World Serpent": "Dünya Yılanı" },
          "keep": ["Kratos", "Atreus"] }
        """

    private var gow: Glossary { try! Glossary.parse(Self.godOfWar) }

    func testParsesTermsAndKeepNames() {
        XCTAssertEqual(gow.count, 6)
        XCTAssertEqual(gow.turkish("leviathan  axe"), "Leviathan Baltası")
        XCTAssertEqual(gow.turkish("KRATOS"), "Kratos")
        XCTAssertNil(gow.turkish("Freya"))
    }

    func testFindsWholeWordsCaseInsensitiveLongestFirst() {
        let found = gow.find("THROW THE LEVIATHAN AXE, then the axe. Kratos's axes. Midgardian.")
        XCTAssertEqual(found.map(\.english), ["Leviathan Axe", "Axe", "Kratos"])
        XCTAssertEqual(found[0].start, 10)
    }

    func testCapitalizedTermsAndKeepNamesAreCapitalWords() {
        XCTAssertEqual(gow.capitalWords.sorted(), ["atreus", "axe", "kratos", "leviathan", "midgard", "serpent", "world"])
        XCTAssertFalse(Glossary.builtIn.capitalWords.contains("health"))
    }

    func testBuiltInGlossaryHasGeneralGameTerms() {
        XCTAssertGreaterThanOrEqual(Glossary.builtIn.count, 10)
        XCTAssertEqual(Glossary.builtIn.turkish("Health Potion"), "can iksiri")
        XCTAssertEqual(Glossary.builtIn.turkish("skill tree"), "yetenek ağacı")
    }

    // Phantom Blade Zero: kahramanın adı "Soul" çevrilmez, sıradan "soul" çevrilir (Emir, 2026-11-13).
    func testKeepExactNamesMatchOnlyAsWritten() throws {
        let found = Glossary.builtIn.find("Soul, you sold your soul. SOUL!")
        XCTAssertEqual(found.map(\.english), ["Soul"])
        XCTAssertEqual(found.first?.start, 0)
        XCTAssertFalse(Glossary.builtIn.capitalWords.contains("soul"))
        let exact = try Glossary.parse(#"{ "keepExact": ["Soul"] }"#)
        let loose = try Glossary.parse(#"{ "keep": ["Soul"] }"#)
        XCTAssertNotEqual(exact.fingerprint, loose.fingerprint)
    }

    func testLaterGlossaryWinsAndFingerprintFollowsContent() throws {
        let user = try Glossary.parse(#"{ "terms": { "skill tree": "beceri ağacı" } }"#)
        let merged = Glossary.merge([.builtIn, user])
        XCTAssertEqual(merged.turkish("skill tree"), "beceri ağacı")
        XCTAssertNotEqual(merged.fingerprint, Glossary.builtIn.fingerprint)
        XCTAssertEqual(merged.fingerprint, Glossary.merge([.builtIn, user]).fingerprint)
    }

    func testIgnoresEntriesWithoutLetters() throws {
        XCTAssertEqual(try Glossary.parse(#"{ "terms": { "...": "x", "Odin": "Odin", "": "y" }, "keep": [3] }"#).count, 1)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("couchsubs-glossary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testLoadsUserFolderAndSkipsBrokenFiles() throws {
        let directory = try temporaryDirectory()
        try Self.godOfWar.write(to: directory.appendingPathComponent("gow.json"), atomically: true, encoding: .utf8)
        try "{ not json".write(to: directory.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
        try #"{ "keep": ["Ignored"] }"#.write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let glossary = Glossary.load(directory: directory)
        XCTAssertEqual(glossary.turkish("Leviathan Axe"), "Leviathan Baltası")
        XCTAssertEqual(glossary.turkish("health potion"), "can iksiri")
        XCTAssertNil(glossary.turkish("Ignored"))
        XCTAssertEqual(Glossary.load(directory: directory.appendingPathComponent("missing")).count, Glossary.builtIn.count)
    }

    func testStoreReloadsWhenAFileChanges() throws {
        let directory = try temporaryDirectory()
        var now = Date(timeIntervalSince1970: 0)
        let store = GlossaryStore(directory: directory, clock: { now })
        XCTAssertNil(store.glossary.turkish("Kratos"))
        try Self.godOfWar.write(to: directory.appendingPathComponent("gow.json"), atomically: true, encoding: .utf8)
        // Klasöre birkaç saniyede bir bakılır.
        XCTAssertNil(store.glossary.turkish("Kratos"))
        now += 6
        XCTAssertEqual(store.glossary.turkish("Kratos"), "Kratos")
    }
}

/// Yer tutucuyla terim koruma (Windows: TermProtectionTests).
final class TermProtectionTests: XCTestCase {
    private let gow = try! Glossary.parse("""
        { "terms": { "Leviathan Axe": "Leviathan Baltası", "Midgard": "Midgard", "health potion": "can iksiri" },
          "keep": ["Kratos", "Atreus"] }
        """)

    func testReplacesTermsWithPlaceholderNames() {
        let protector = TermProtector(glossary: gow, sources: [""])
        let (text, slots) = protector.protect("Kratos, take the Leviathan Axe to Midgard. Kratos!")
        XCTAssertEqual(text, "Zarmon, take the Velkor to Dorvan. Zarmon!")
        XCTAssertEqual(slots.map(\.english), ["Kratos", "Leviathan Axe", "Midgard"])
    }

    func testRestoresTermsWithSuffixesDespiteCaseAndSpacing() {
        let cases = [
            ("Zarmon, Velkor'u Dorvan'a götür. Zarmon!", "Kratos, Leviathan Baltası'nı Midgard'a götür. Kratos!"),
            ("ZARMON, VELKOR'U DORVAN'A GÖTÜR. ZARMON!", "Kratos, Leviathan Baltası'nı Midgard'a GÖTÜR. Kratos!"),
            ("Zarmon, Velkor ’u Dorvana götür. Zarmon!", "Kratos, Leviathan Baltası'nı Midgard'a götür. Kratos!"),
        ]
        for (output, expected) in cases {
            let protector = TermProtector(glossary: gow, sources: [""])
            let slots = protector.protect("Kratos, take the Leviathan Axe to Midgard. Kratos!").slots
            XCTAssertEqual(TermProtector.restore(output, expected: slots, all: protector.allSlots), expected)
        }
    }

    func testMissingPlaceholderMeansUnreliable() {
        let protector = TermProtector(glossary: gow, sources: [""])
        let slots = protector.protect("Take the Leviathan Axe to Midgard.").slots
        XCTAssertNil(TermProtector.restore("Baltayı Dorvan'a götür.", expected: slots, all: protector.allSlots))
    }

    func testPlaceholderFromAnotherPartMeansUnreliable() {
        let protector = TermProtector(glossary: gow, sources: [""])
        _ = protector.protect("Kratos!")
        let slots = protector.protect("Go to Midgard.").slots
        XCTAssertNil(TermProtector.restore("Zarmon Velkor'a git.", expected: slots, all: protector.allSlots))
        XCTAssertEqual(TermProtector.restore("Velkor'a git.", expected: slots, all: protector.allSlots), "Midgard'a git.")
    }

    func testCommonNounAtSentenceStartIsCapitalized() {
        let protector = TermProtector(glossary: gow, sources: [""])
        let slots = protector.protect("Drink the health potion. Health potion first!").slots
        XCTAssertEqual(TermProtector.restore("Zarmon'u iç. Önce Zarmon!", expected: slots), "Can iksirini iç. Önce can iksiri!")
    }

    func testQuotedPlaceholderIsNotASuffix() {
        let protector = TermProtector(glossary: gow, sources: [""])
        let slots = protector.protect("He said 'Midgard' again.").slots
        XCTAssertEqual(TermProtector.restore("Yine 'Zarmon' dedi.", expected: slots), "Yine 'Midgard' dedi.")
    }

    func testPlaceholderAlreadyInTheSourceIsSkipped() {
        let protector = TermProtector(glossary: gow, sources: ["Zarmon met Kratos."])
        XCTAssertEqual(protector.protect("Zarmon met Kratos.").text, "Zarmon met Velkor.")
    }

    func testTextWithoutTermsIsUnchanged() {
        let protector = TermProtector(glossary: gow, sources: [""])
        let (text, slots) = protector.protect("We go now.")
        XCTAssertEqual(text, "We go now.")
        XCTAssertTrue(slots.isEmpty)
        XCTAssertEqual(TermProtector.restore("Şimdi gidiyoruz.", expected: slots, all: protector.allSlots), "Şimdi gidiyoruz.")
    }
}

/// Türkçe düzeltmeler (Windows: TurkishPostEditTests).
final class TurkishPostEditTests: XCTestCase {
    func testSourceEndingIsKept() {
        let cases = [
            ("Run!", "Koş.", "Koş!"), ("Run!", "Koş", "Koş!"), ("What?!", "Ne?", "Ne?!"), ("Wait…", "Bekle.", "Bekle…"),
            ("Wait...", "Bekle.", "Bekle..."), ("Where is he?", "O nerede.", "O nerede?"),
            ("He said \"Run!\"", "\"Koş.\" dedi.", "\"Koş.\" dedi."), ("He said \"Run!\"", "\"Koş\" dedi", "\"Koş\" dedi"),
            ("\"Run!\"", "\"Koş.\"", "\"Koş!\""), ("We go.", "Gidiyoruz!", "Gidiyoruz!"), ("We go.", "Gidiyoruz", "Gidiyoruz"),
            ("Boy!", "Evlat!", "Evlat!"),
        ]
        for (source, translation, expected) in cases {
            XCTAssertEqual(TurkishPostEdit.apply(source: source, translation: translation), expected, source)
        }
    }

    func testSpaceBeforePunctuationIsRemoved() {
        for (translation, expected) in [("Dur , bekle !", "Dur, bekle!"), ("Ne  oldu ?", "Ne oldu?"), ("Peki ... gidelim .", "Peki... gidelim.")] {
            XCTAssertEqual(TurkishPostEdit.apply(source: "Okay. Go.", translation: translation), expected)
        }
    }

    func testQuotesFollowTheSource() {
        XCTAssertEqual(TurkishPostEdit.apply(source: "He said \"run\", Kratos's son.", translation: "“Koş” dedi, Kratos’un oğlu."),
                       "\"Koş\" dedi, Kratos'un oğlu.")
        XCTAssertEqual(TurkishPostEdit.apply(source: "He said “run”, Kratos’s son.", translation: "\"Koş\" dedi, Kratos'un oğlu."),
                       "“Koş” dedi, Kratos’un oğlu.")
    }

    func testImperativesFollowAnInformalLine() {
        XCTAssertEqual(TurkishPostEdit.register(["Sana söyledim.", "Bekleyin!", "Dikkat edin, evlat."]),
                       ["Sana söyledim.", "Bekle!", "Dikkat et, evlat."])
        XCTAssertEqual(TurkishPostEdit.register(["Seni gördüm. Hemen gelin!"]), ["Seni gördüm. Hemen gel!"])
    }

    func testOtherLinesKeepTheirRegister() {
        // "Sen" yoksa hitap belirsiz; "siz" varsa bilerek seçilmiş; emir yerinde değilse başka anlam olabilir.
        for sentence in ["Bekleyin!", "Siz bekleyin, sana sonra bakarım!", "Sen gelin misin?"] {
            XCTAssertEqual(TurkishPostEdit.register([sentence]), [sentence])
        }
    }

    func testNilPiecesStayNil() {
        XCTAssertEqual(TurkishPostEdit.register([nil, "Sana söyledim.", nil, "Durun!"]), [nil, "Sana söyledim.", nil, "Dur!"])
    }
}

/// Ücretsiz çevirinin metin hattı (Windows: FreeTranslationTests).
final class FreeTranslationTests: XCTestCase {
    private let gow = try! Glossary.parse(#"{ "terms": { "Leviathan Axe": "Leviathan Baltası" }, "keep": ["Kratos", "Atreus"] }"#)

    func testPipelineVersionIsBumped() { XCTAssertGreaterThanOrEqual(FreeTranslation.pipelineVersion, 2) }

    func testShortLinesHaveFewerThanFourWords() {
        for (sentence, expected) in [("Boy!", true), ("Do it.", true), ("Not you, boy.", true), ("We go to the mountain.", false), ("...", false)] {
            XCTAssertEqual(FreeTranslation.isShort(sentence), expected, sentence)
        }
    }

    func testPartAfterTheSeparatorOnlyWhenUnambiguous() {
        let cases: [(String, String?)] = [
            ("Annen nerede? *** Sen değil.", "Sen değil."), ("Annen nerede?***Sen değil.", "Sen değil."),
            ("ANNEN NEREDE? *** SEN DEĞİL.", "SEN DEĞİL."), ("Annen nerede? Sen değil.", nil),
            ("Annen *** nerede? *** Sen değil.", nil), ("Annen nerede? **** Sen değil.", nil), ("*** Sen değil.", nil),
            ("Annen nerede? ***", nil),
            ("Annen nerede? *** Sen değil, sen değil, sen değil, sen değil, sen değil, sen değil, sen değil.", nil),
        ]
        for (output, expected) in cases {
            XCTAssertEqual(FreeTranslation.afterSeparator(output, source: "Not you."), expected, output)
        }
    }

    func testCacheKeyCarriesContextAndGlossary() {
        XCTAssertEqual(FreeTranslation.cacheKey("We go.", context: nil, glossary: gow), "We go.")
        XCTAssertEqual(FreeTranslation.cacheKey("We go.", context: "Where?", glossary: gow), "Where?\u{1F}We go.")
        XCTAssertEqual(FreeTranslation.cacheKey("Kratos, go.", context: nil, glossary: gow), gow.fingerprint + "\u{1F}Kratos, go.")
        XCTAssertTrue(FreeTranslation.cacheKey("Go.", context: "Kratos!", glossary: gow).hasPrefix(gow.fingerprint))
    }

    /// Çağrıları kaydeden sahte motor.
    private final class Engine: @unchecked Sendable {
        var calls: [String] = []
        let map: (String) -> String
        init(_ map: @escaping (String) -> String) { self.map = map }
        func run(_ input: String) -> String { calls.append(input); return map(input) }
    }

    private func translate(_ sentence: String, context: String?, normalize: (String) -> String = { $0 },
                           _ engine: Engine) async -> String {
        await FreeTranslation.translate(sentence, context: context, glossary: gow, normalize: normalize, engine: { engine.run($0) })
    }

    func testTermsAreProtectedAndRestored() async {
        let engine = Engine { _ in "Zarmon, Velkor'u fırlat." }
        let result = await translate("Kratos, throw the Leviathan Axe!", context: nil, engine)
        XCTAssertEqual(engine.calls, ["Zarmon, throw the Velkor!"])
        XCTAssertEqual(result, "Kratos, Leviathan Baltası'nı fırlat!")
    }

    func testLostPlaceholderFallsBackToPlainTranslation() async {
        let engine = Engine { $0.contains("Zarmon") ? "Baltayı fırlat!" : "Leviathan Baltasını fırlat!" }
        let result = await translate("Throw the Leviathan Axe!", context: nil, engine)
        XCTAssertEqual(engine.calls, ["Throw the Zarmon!", "Throw the Leviathan Axe!"])
        XCTAssertEqual(result, "Leviathan Baltasını fırlat!")
    }

    func testShortLineIsTranslatedWithItsContext() async {
        let engine = Engine { _ in "Annen nerede? *** Sen değil." }
        let result = await translate("Not you.", context: "Where is your mother?", engine)
        XCTAssertEqual(engine.calls, ["Where is your mother? *** Not you."])
        XCTAssertEqual(result, "Sen değil.")
    }

    func testAmbiguousContextFallsBackToTheLineAlone() async {
        let engine = Engine { $0.contains("***") ? "Annen nerede, sen değil." : "Sen değil." }
        let result = await translate("Not you.", context: "Where is your mother?", engine)
        XCTAssertEqual(engine.calls, ["Where is your mother? *** Not you.", "Not you."])
        XCTAssertEqual(result, "Sen değil.")
    }

    func testContextTermsDoNotLeakIntoTheLine() async {
        // Bağlamdaki terimin yer tutucusu satıra kaydıysa ayrım güvenilmez; satır tek başına çevrilir.
        let engine = Engine { $0.contains("***") ? "Burada. *** Git, Zarmon Velkor!" : "Git, Zarmon!" }
        let result = await translate("Go, Atreus!", context: "Kratos is here.", engine)
        XCTAssertEqual(result, "Git, Atreus!")
    }

    func testContextualLineKeepsTermsOfItsOwn() async {
        let engine = Engine { _ in "Zarmon burada. *** Git, Velkor!" }
        let result = await translate("Go, Atreus!", context: "Kratos is here.", engine)
        XCTAssertEqual(engine.calls, ["Zarmon is here. *** Go, Velkor!"])
        XCTAssertEqual(result, "Git, Atreus!")
    }

    func testNormalizeAndGameEnglishRunBeforeProtection() async {
        let engine = Engine { _ in "Dikkat et, Zarmon!" }
        _ = await translate("HEADS UP, KRATOS!", context: nil, normalize: { $0 == "HEADS UP, KRATOS!" ? "Heads up, kratos!" : $0 }, engine)
        XCTAssertEqual(engine.calls, ["Watch out, Zarmon!"])
    }
}

/// Kısa satırın bağlamı (Windows: RecentLinesTests).
final class RecentLinesTests: XCTestCase {
    func testPreviousLineIsTheContextAndRereadsKeepIt() {
        var now = Date(timeIntervalSince1970: 0)
        let recent = RecentLines(clock: { now })
        XCTAssertNil(recent.shown("Where is your mother?"))
        XCTAssertEqual(recent.shown("Not you."), "Where is your mother?")
        now += 300
        // Aynı satır uzun süre ekranda kaldı; bağlamı değişmez, çevirisi de değişmez.
        XCTAssertEqual(recent.shown("Not you."), "Where is your mother?")
        XCTAssertEqual(recent.shown("Go."), "Not you.")
    }

    func testOldLineIsNotContext() {
        var now = Date(timeIntervalSince1970: 0)
        let recent = RecentLines(clock: { now })
        _ = recent.shown("Where is your mother?")
        now += 25
        XCTAssertNil(recent.shown("Not you."))
    }
}

/// Satır düzeyi akış (Windows: MarianTranslatorTests'teki aynı senaryolar).
final class FreeLineTranslatorTests: XCTestCase {
    private final class Engine: @unchecked Sendable {
        var calls: [String] = []
        let map: ((String) -> String)?
        init(_ map: ((String) -> String)? = nil) { self.map = map }
        func run(_ input: String) -> String { calls.append(input); return map?(input) ?? input.uppercased() }
    }

    func testShortSentenceUsesThePreviousSentenceOfTheLine() async throws {
        let engine = Engine()
        let translator = FreeLineTranslator()
        let result = try await translator.translate("ATREUS: Father, look!\nKRATOS: Stay.") { engine.run($0) }
        XCTAssertEqual(result, "ATREUS: FATHER, LOOK!\nKRATOS: STAY.")
        XCTAssertEqual(engine.calls, ["Father, look!", "Father, look! *** Stay."])
        XCTAssertEqual(translator.spokenLines(for: "ATREUS: Father, look!\nKRATOS: Stay.").map(\.speaker), ["ATREUS", "KRATOS"])
    }

    func testShortLineIsTranslatedWithThePreviousLine() async throws {
        let engine = Engine {
            switch $0 {
            case "Where is your mother?": "Annen nerede?"
            case "Where is your mother? *** Not you.": "Annen nerede? *** Sen değil."
            default: "?"
            }
        }
        let translator = FreeLineTranslator()
        _ = try await translator.translate("Where is your mother?") { engine.run($0) }
        let first = try await translator.translate("Not you.") { engine.run($0) }
        XCTAssertEqual(first, "Sen değil.")
        // Yeniden okunan satır aynı bağlamla önbellekten gelir.
        let again = try await translator.translate("Not you.") { engine.run($0) }
        XCTAssertEqual(again, "Sen değil.")
        XCTAssertEqual(engine.calls.count, 2)
    }

    func testShortLineAfterALongPauseHasNoContext() async throws {
        var now = Date(timeIntervalSince1970: 0)
        let engine = Engine()
        let translator = FreeLineTranslator(clock: { now })
        _ = try await translator.translate("Where is your mother?") { engine.run($0) }
        now += 60
        _ = try await translator.translate("Not you.") { engine.run($0) }
        XCTAssertEqual(engine.calls, ["Where is your mother?", "Not you."])
    }

    func testGlossaryTermsGetTheirTurkishAndSuffix() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("couchsubs-glossary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"{ "game": "God of War", "terms": { "Leviathan Axe": "Leviathan Baltası" }, "keep": ["Kratos"] }"#
            .write(to: directory.appendingPathComponent("gow.json"), atomically: true, encoding: .utf8)
        let engine = Engine { $0 == "Zarmon, throw the Velkor!" ? "Zarmon, Velkor'u fırlat." : "?" }
        let translator = FreeLineTranslator(glossary: GlossaryStore(directory: directory))
        let result = try await translator.translate("KRATOS, THROW THE LEVIATHAN AXE!") { engine.run($0) }
        XCTAssertEqual(result, "Kratos, Leviathan Baltası'nı fırlat!")
        XCTAssertEqual(engine.calls, ["Zarmon, throw the Velkor!"])
    }

    /// #287: "PRICE:" etiketinden öğrenilen ad sonraki cümlelerin içinde de çeviriden korunur ("Fiyat" olmasın); küçük
    /// harfle geçen ya da sözcüğün parçası olan "price"/"Pricey" korunmaz, görev etiketleri ("SOLDIER:") ad sayılmaz.
    func testLearnedSpeakerNameIsKeptInsideSentences() async throws {
        let engine = Engine {
            switch $0 {
            case "Move.": "Hareket et."
            case "Zarmon, get down right now!": "Zarmon, hemen yere yat!"
            case "The price is Pricey.": "Fiyat pahalı."
            case "Soldier, get down right now!": "Asker, hemen yere yat!"
            default: "?"
            }
        }
        let translator = FreeLineTranslator()
        _ = try await translator.translate("PRICE: Move.") { engine.run($0) }
        let result = try await translator.translate("Price, get down right now!") { engine.run($0) }
        XCTAssertEqual(result, "Price, hemen yere yat!")
        let common = try await translator.translate("The price is Pricey.") { engine.run($0) }
        XCTAssertEqual(common, "Fiyat pahalı.")
        _ = try await translator.translate("SOLDIER: Move.") { engine.run($0) }
        let role = try await translator.translate("Soldier, get down right now!") { engine.run($0) }
        XCTAssertEqual(role, "Asker, hemen yere yat!")
        XCTAssertEqual(engine.calls, ["Move.", "Zarmon, get down right now!", "The price is Pricey.",
            "The price is Pricey. *** Move.", "Move.", "Soldier, get down right now!"])

        // Hat satır başındaki adı ayırıp yalnız cümleyi verir ("Price: Get down right now!"); ad ayrıca bildirilir.
        let separated = FreeLineTranslator()
        separated.noteSpeaker("Price")
        let noted = try await separated.translate("Price, get down right now!") { engine.run($0) }
        XCTAssertEqual(noted, "Price, hemen yere yat!")
    }

    func testInformalLineGetsInformalImperatives() async throws {
        let engine = Engine {
            switch $0 {
            case "I told you to wait for me.": "Sana beni beklemeni söyledim."
            case "I told you to wait for me. *** Stay here!": "Sana beni beklemeni söyledim. *** Burada bekleyin!"
            default: "?"
            }
        }
        let translator = FreeLineTranslator()
        let result = try await translator.translate("I told you to wait for me. Stay here!") { engine.run($0) }
        XCTAssertEqual(result, "Sana beni beklemeni söyledim. Burada bekle!")
        XCTAssertEqual(translator.spokenLines(for: "I told you to wait for me. Stay here!").last?.turkish, "Burada bekle!")
    }

    func testPersistentCacheSkipsTheEngineInTheNextSession() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("couchsubs-free-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let firstEngine = Engine()
        _ = try await FreeLineTranslator(cache: TranslationCache(file: file)).translate("KRATOS: We go now. Stay close.") { firstEngine.run($0) }
        let engine = Engine()
        let translator = FreeLineTranslator(cache: TranslationCache(file: file))
        let result = try await translator.translate("KRATOS: We go now. Stay close.") { engine.run($0) }
        XCTAssertEqual(result, "KRATOS: WE GO NOW. STAY CLOSE.")
        XCTAssertEqual(engine.calls, [])
    }
}

/// Oyun terimleri örnek seti (Windows: GameTermsTests, Android: GameTermsTest; aynı satırlar). Kullanıcı şikâyetleri:
/// "Toss a smoke" → "sigara at", ünlem satırları ve büyük harfli satırlar sözcük sözcük çevriliyordu.
/// Gerçek motor (Apple Translation / ML Kit / OPUS-MT) burada çağrılmaz: motora giden metin ve hazır satırlar sınanır.
final class GameTermsTests: XCTestCase {
    private final class Engine: @unchecked Sendable {
        var calls: [String] = []
        let map: (String) -> String
        init(_ map: @escaping (String) -> String) { self.map = map }
        func run(_ input: String) -> String { calls.append(input); return map(input) }
    }

    private func translate(_ sentence: String, _ engine: Engine) async -> String {
        await FreeTranslation.translate(sentence, context: nil, glossary: .builtIn,
                                        normalize: { SubtitleSegmenter.normalizeCase($0, names: Glossary.builtIn.capitalWords) },
                                        engine: { engine.run($0) })
    }

    /// Ünlem satırları motora gitmeden hazır Türkçesini alır; büyük harf, noktalama ve kıvrık kesme fark etmez.
    func testCalloutsUseTheirTurkishLine() async {
        let samples = [
            ("Toss a smoke!", "Sis bombası at!"),
            ("Reloading!", "Şarjör değiştiriyorum!"),
            ("RELOADING!", "Şarjör değiştiriyorum!"),
            ("Frag out!", "Bomba atıyorum!"),
            ("Cover me, I’m reloading!", "Şarjör değiştiriyorum, koru beni!"),
            ("Man down!", "Yaralı var!"),
            ("Get down!", "Yere yat!"),
            ("Move up.", "İlerleyin."),
            ("- Contact!", "Düşman var!"),
        ]
        for (english, turkish) in samples {
            let engine = Engine { _ in "?" }
            let result = await translate(english, engine)
            XCTAssertEqual(result, turkish, english)
            XCTAssertEqual(engine.calls, [], english)
        }
    }

    /// Uzun cümlede argo düz İngilizceye, silah adı yer tutucuya döner; Türkçe terim ekiyle geri konur.
    func testSlangAndWeaponTermsInLongerLines() async {
        let samples: [(english: String, sent: String, engineSays: String, turkish: String)] = [
            ("Toss a smoke and move up.", "Throw a Zarmon and move up.", "Bir Zarmon at ve ilerle.", "Bir sis bombası at ve ilerle."),
            ("THROW A FLASHBANG IN THERE!", "Throw a Zarmon in there!", "Oraya bir Zarmon at!", "Oraya bir flaş bombası at!"),
            ("Pop smoke, we're leaving.", "Throw a Zarmon, we're leaving.", "Bir Zarmon at, gidiyoruz.", "Bir sis bombası at, gidiyoruz."),
            ("Hostiles on the bridge.", "Enemies on the bridge.", "Köprüde düşmanlar.", "Köprüde düşmanlar."),
            ("Grab the medkit before you go.", "Grab the Zarmon before you go.", "Gitmeden Zarmon'u al.", "Gitmeden ilk yardım çantasını al."),
        ]
        for sample in samples {
            let engine = Engine { _ in sample.engineSays }
            let result = await translate(sample.english, engine)
            XCTAssertEqual(engine.calls.first, sample.sent, sample.english)
            XCTAssertEqual(result, sample.turkish, sample.english)
        }
    }

    /// Sıradan cümlelere dokunulmaz: "smoke" tek başına sis bombası değildir, "flashlight" flaş değildir.
    func testOrdinarySentencesAreUnchanged() async {
        for english in ["I smell smoke.", "Turn on your flashlight.", "Where is the grenade launcher?", "I'm covering you."] {
            let engine = Engine { $0 }
            _ = await translate(english, engine)
            XCTAssertEqual(engine.calls, [english], english)
        }
    }

    func testUserGlossaryCanAddLinesAndPhrases() throws {
        let user = try Glossary.parse(#"{ "phrases": { "nerf": "weaken" }, "lines": { "GG!": "İyi oyundu" } }"#)
        let merged = Glossary.merge([.builtIn, user])
        XCTAssertEqual(merged.line("gg"), "İyi oyundu")
        XCTAssertEqual(merged.plain("Nerf the boss"), "Weaken the boss")
        XCTAssertNotEqual(merged.fingerprint, Glossary.builtIn.fingerprint)
        XCTAssertTrue(merged.rewrites("They nerf it."))
        XCTAssertFalse(merged.rewrites("Nerfed."))
        // Bozuk düzenli ifade alınmaz.
        XCTAssertEqual(try Glossary.parse(#"{ "phrases": { "(": "x" } }"#).plain("( a"), "( a")
    }

    func testCacheKeyFollowsLinesAndPhrases() {
        let glossary = Glossary.builtIn
        XCTAssertTrue(FreeTranslation.cacheKey("Reloading!", context: nil, glossary: glossary).hasPrefix(glossary.fingerprint))
        XCTAssertTrue(FreeTranslation.cacheKey("Toss a smoke and go.", context: nil, glossary: glossary).hasPrefix(glossary.fingerprint))
        XCTAssertEqual(FreeTranslation.cacheKey("I smell it.", context: nil, glossary: glossary), "I smell it.")
    }

    /// Windows ve Android'le aynı iz: üç platformun önbellek anahtarları aynı kalır.
    func testFingerprintMatchesTheOtherPlatforms() {
        XCTAssertEqual(Glossary.builtIn.fingerprint, "g978a414e")
    }
}
