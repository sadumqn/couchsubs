// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

private func fixture(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent(name)
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("packs-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class PackKeyTests: XCTestCase {
    /// Windows ve paket hazırlayan Python betiği (canon.py) ile aynı sonuç: Fixtures/golden-vectors.json.
    func testGoldenVectors() throws {
        struct Vector: Decodable { let input: String; let canon: String; let key: String }
        let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: fixture("golden-vectors.json")))
        XCTAssertEqual(vectors.count, 15)
        for vector in vectors {
            XCTAssertEqual(PackKey.canon(vector.input), vector.canon, vector.input)
            XCTAssertEqual(PackKey.key(vector.input) ?? "", vector.key, vector.input)
        }
    }

    func testTagsLongerThanFortyCharactersStay() {
        XCTAssertEqual(PackKey.stripTags("a <b> c"), "a   c")
        let long = "<" + String(repeating: "x", count: 41) + ">"
        XCTAssertEqual(PackKey.stripTags(long), long)
        XCTAssertEqual(PackKey.stripTags("<" + String(repeating: "x", count: 40) + ">"), " ")
        XCTAssertEqual(PackKey.stripTags("a < b <i> c"), "a < b   c")
        XCTAssertEqual(PackKey.stripTags("<<b>>"), "< >")
    }
}

final class GamePackTests: XCTestCase {
    func testWrappedAndBareFormatsLoad() throws {
        let wrapped = try GamePack.decode(Data(contentsOf: fixture("pack-wrapped.json.gz")), name: "pack-wrapped")
        XCTAssertEqual(wrapped.id, "test-game")
        XCTAssertEqual(wrapped.title, "Test Game")
        XCTAssertEqual(wrapped.entries.count, 5)
        let bare = try GamePack.decode(Data(contentsOf: fixture("pack-bare.json.gz")), name: "pack-bare")
        XCTAssertEqual(bare.id, "pack-bare")
        XCTAssertEqual(bare.title, "pack-bare")
        XCTAssertEqual(bare.entries.count, 2)
    }

    func testPlainJSONIsAccepted() throws {
        let key = PackKey.key("Get back!")!
        let pack = try GamePack.decode(Data("{\"\(key)\": \"Geri çekil!\"}".utf8), name: "plain")
        XCTAssertEqual(pack.entries[PackKey.number(key)!], "Geri çekil!")
    }

    func testBrokenFilesAreRejected() {
        XCTAssertThrowsError(try GamePack.decode(Data("not json".utf8), name: "x"))
        XCTAssertThrowsError(try GamePack.decode(Data([0x1f, 0x8b, 8, 0] + [UInt8](repeating: 7, count: 30)), name: "x"))
        XCTAssertThrowsError(try GamePack.decode(Data("{\"format\":2,\"entries\":{\"0123456789abcdef\":\"x\"}}".utf8), name: "x"))
        XCTAssertThrowsError(try GamePack.decode(Data("{\"bad\":\"x\"}".utf8), name: "x"))
    }

    /// Paketteki Türkçede kalan biçim etiketleri TV'ye gitmez.
    func testTagsAreRemovedFromTurkish() throws {
        let pack = try GamePack.decode(Data(contentsOf: fixture("pack-wrapped.json.gz")), name: "x")
        let key = PackKey.number(PackKey.key("<b><h>SCANNATURI SPECIALE</></> KNIFE")!)!
        XCTAssertEqual(pack.entries[key], "SCANNATURI SPECIALE BIÇAĞI")
    }

    func testLibraryMergesBundledAndUserPacks() throws {
        let bundled = temporaryDirectory()
        let user = temporaryDirectory()
        try FileManager.default.copyItem(at: fixture("pack-bare.json.gz"), to: bundled.appendingPathComponent("a.json.gz"))
        try FileManager.default.copyItem(at: fixture("pack-wrapped.json.gz"), to: bundled.appendingPathComponent("b.json.gz"))
        try Data("bozuk".utf8).write(to: bundled.appendingPathComponent("c.json.gz"))
        let library = GamePackLibrary(bundled: bundled, user: user)
        XCTAssertEqual(library.packs.map(\.title), ["a", "Test Game"])
        XCTAssertEqual(library.packs.map(\.entries), [2, 5])
        // Aynı anahtarda sonraki paket kazanır.
        XCTAssertEqual(library.match("Get Down!")?.text, "Yere yat!")
        XCTAssertEqual(library.match("Get back!")?.text, "Geri çekil!")

        // Kullanıcının klasöründeki aynı kimlikli paket uygulamanınkinin yerine geçer ve sonra okunur.
        let key = PackKey.key("Get Down!")!
        let override = "{\"format\":1,\"id\":\"test-game\",\"title\":\"Test Game 2\",\"entries\":{\"\(key)\":\"Yat yere!\"}}"
        try Data(override.utf8).write(to: user.appendingPathComponent("test.json"))
        library.reload()
        XCTAssertEqual(library.packs.map(\.title), ["a", "Test Game 2"])
        XCTAssertEqual(library.packs.map(\.builtIn), [true, false])
        XCTAssertEqual(library.match("Get Down!")?.text, "Yat yere!")
        XCTAssertNil(library.match("Who is that?"))
    }

    func testMissingDirectoriesGiveAnEmptyLibrary() {
        let library = GamePackLibrary(bundled: nil, user: URL(fileURLWithPath: "/nonexistent/packs"))
        XCTAssertEqual(library.packs, [])
        XCTAssertNil(library.match("Get Down!"))
    }

    /// Yalnız tek bir gömülü paketle kitaplık: paketler birleşince ortak satırlarda ("Get down!") sonraki paket kazanır.
    private func bundledOnly(_ file: String) throws -> GamePackLibrary {
        let directory = temporaryDirectory()
        let source = try XCTUnwrap(GamePackLibrary.bundledDirectory).appendingPathComponent(file)
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(file))
        return GamePackLibrary(bundled: directory, user: nil)
    }

    /// Uygulamayla gelen paketler (Mafia, GTA V, RDR2) birlikte yüklenir ve hızlı aranır.
    func testBundledPacksLoad() throws {
        let all = GamePackLibrary(bundled: GamePackLibrary.bundledDirectory, user: nil)
        let start = Date()
        let ids = all.packs.map(\.id)
        let elapsed = Date().timeIntervalSince(start)
        print("paket yükleme: \(Int(elapsed * 1000)) ms, \(all.packs.reduce(0) { $0 + $1.entries }) satır")
        XCTAssertEqual(ids, ["gta-v", "mafia-the-old-country", "red-dead-redemption-2"])
        XCTAssertTrue(all.packs.allSatisfy(\.builtIn))
        XCTAssertLessThan(elapsed, 10)

        let library = try bundledOnly("mafia-the-old-country.json.gz")
        let mafia = library.packs.first { $0.id == "mafia-the-old-country" }
        XCTAssertEqual(mafia?.title, "Mafia: The Old Country")
        XCTAssertGreaterThan(mafia?.entries ?? 0, 18000)
        XCTAssertEqual(mafia?.builtIn, true)
        XCTAssertEqual(library.match("You fucked up now, boy!")?.text, "Şimdi ayvayı yedin, evlat!")
        XCTAssertEqual(library.match("It’s his mother, she passed.")?.text, "Annesi vefat etti.")
        XCTAssertEqual(library.match("MARIA: Get Down!")?.text, "MARIA: Yere yat!")
        XCTAssertEqual(library.match("Get Down!\nMinchia! You shouldn't be allowed to ride!")?.text,
                       "Yere yat!\nMinchia! Sana at sürmeyi yasaklamak lazım!")
        let lookups = Date()
        for _ in 0..<1000 { _ = library.match("You fucked up now, boy!") }
        print("1000 arama: \(Int(Date().timeIntervalSince(lookups) * 1000)) ms")
    }

    /// Her gömülü paket kendi başına açılır, en az beklenen satırı taşır ve bilinen satırlar (anahtarlar canon.py ile
    /// hesaplandı) boş olmayan Türkçeye çıkar.
    func testEachBundledPackHasItsLines() throws {
        let expected: [(file: String, id: String, title: String, minimum: Int, keys: [String])] = [
            ("mafia-the-old-country.json.gz", "mafia-the-old-country", "Mafia: The Old Country", 18000,
             ["e7f18c8f6d1083ab", "15014c246455f36c"]),
            // "Are you listening to me?", "Cool, I'll see you later.", "Take out the Lost."
            ("gta-v.json.gz", "gta-v", "Grand Theft Auto V", 150_000,
             ["e43b873bf7992f8f", "cc57fc6e0542ca05", "aaa1a152be96d47f"]),
            // "Can't see where I'm going.", "I'm not afraid to fight you.", "Burn the tobacco fields"
            ("red-dead-redemption-2.json.gz", "red-dead-redemption-2", "Red Dead Redemption 2", 150_000,
             ["7fab2b68b3726a28", "3484a8ef3d8c7fc7", "bc0c9435160e8723"]),
        ]
        let directory = try XCTUnwrap(GamePackLibrary.bundledDirectory)
        for pack in expected {
            let data = try Data(contentsOf: directory.appendingPathComponent(pack.file))
            let decoded = try GamePack.decode(data, name: GamePackLibrary.baseName(directory.appendingPathComponent(pack.file)))
            XCTAssertEqual(decoded.id, pack.id)
            XCTAssertEqual(decoded.title, pack.title)
            XCTAssertGreaterThan(decoded.entries.count, pack.minimum, pack.id)
            for key in pack.keys {
                let turkish = decoded.entries[try XCTUnwrap(PackKey.number(key))] ?? ""
                XCTAssertFalse(turkish.isEmpty, "\(pack.id) \(key)")
                XCTAssertFalse(turkish.contains("~"), "\(pack.id) \(key): \(turkish)")
            }
        }
    }

    /// Assassin's Creed Shadows, Death Stranding 2 ve Modern Warfare (2019) paketleri de uygulamayla gelir.
    func testMoreBundledPacksLoad() {
        let library = GamePackLibrary(bundled: GamePackLibrary.bundledDirectory, user: nil)
        let expected: [(id: String, title: String, minimum: Int)] = [
            ("assassins-creed-shadows", "Assassin's Creed Shadows", 39000),
            ("death-stranding-2", "Death Stranding 2: On the Beach", 23000),
            ("call-of-duty-modern-warfare-2019", "Call of Duty: Modern Warfare (2019)", 50000),
        ]
        for game in expected {
            let pack = library.packs.first { $0.id == game.id }
            XCTAssertEqual(pack?.title, game.title, game.id)
            XCTAssertGreaterThan(pack?.entries ?? 0, game.minimum, game.id)
            XCTAssertEqual(pack?.builtIn, true, game.id)
        }
        XCTAssertEqual(library.match("NAOE: Yagoro? What are you doing here?")?.text, "NAOE: Yagoro? Burada ne yapıyorsun?")
        // Sahne notu ("[laughs]") ekranda kalsa da kalmasa da aynı satır bulunur.
        let gnats = "Her yerdeler, biliyorsun, sinekler gibi! Ne arıyorsan bulacaksın. Naoe'me her zaman güvenebilirim."
        XCTAssertEqual(library.match("They are everywhere, you know, like gnats! Whatever it is, you will find it. I can always count on my Naoe.")?.text, gnats)
        XCTAssertEqual(library.match("They are everywhere, you know, like gnats! [laughs] Whatever it is, you will find it. I can always count on my Naoe.")?.text, gnats)
        XCTAssertEqual(library.match("Terminal Fort Knot is in danger. A voidout would kill them all!")?.text,
                       "Terminal Fort Knot tehlikede. Bir boşluk patlaması hepsini öldürür!")
        XCTAssertEqual(library.match("Requesting air drop on my position!")?.text, "Konumuma hava ikmali talep ediyorum!")
    }
}

final class PackLookupTests: XCTestCase {
    private let pack: [String: String] = [
        PackKey.key("Get Down!")!: "Yere yat!",
        PackKey.key("Who is that?")!: "O da kim?",
        PackKey.key("Don Torrisi wants you.")!: "Don Torrisi seni istiyor.",
        PackKey.key("Get back!")!: "Geri çekil!",
    ]

    private func match(_ text: String) -> PackMatch? {
        PackLookup.match(text) { line in PackKey.key(line).flatMap { pack[$0] } }
    }

    func testWholeLineIgnoresCaseSpacingAndPunctuation() {
        XCTAssertEqual(match("GET DOWN!!")?.text, "Yere yat!")
        XCTAssertEqual(match("  Who   is\nthat?  ")?.text, "O da kim?")
        XCTAssertNil(match("Get out!"))
        XCTAssertNil(match(""))
    }

    func testSpeakerLabelIsKeptAndVoiced() {
        let found = match("ENZO: Don Torrisi wants you.")
        XCTAssertEqual(found?.text, "ENZO: Don Torrisi seni istiyor.")
        XCTAssertEqual(found?.spoken, [SpokenLine(speaker: "ENZO", english: "Don Torrisi wants you.", turkish: "Don Torrisi seni istiyor.")])
        XCTAssertEqual(match("Cesare: Get down!")?.text, "Cesare: Yere yat!")
        XCTAssertNil(match("ENZO: Get out!"))
    }

    func testEachLineIsLookedUpWhenTheWholeIsMissing() {
        XCTAssertEqual(match("ENZO: Get down!\nMARIA: Who is that?")?.text, "ENZO: Yere yat!\nMARIA: O da kim?")
        XCTAssertEqual(match("- Get down!\n- Who is that?")?.text, "- Yere yat!\n- O da kim?")
        // Bir satır bile eksikse paket kullanılmaz.
        XCTAssertNil(match("Get down!\nWho are you?"))
    }

    func testEachSentenceIsLookedUpWhenTheLineIsMissing() {
        let found = match("ENZO: Get down! Who is that?")
        XCTAssertEqual(found?.text, "ENZO: Yere yat! O da kim?")
        XCTAssertEqual(found?.spoken.map(\.speaker), ["ENZO", "ENZO"])
        XCTAssertEqual(match("Get down! Get back!")?.text, "Yere yat! Geri çekil!")
        XCTAssertNil(match("Get down! Who are you?"))
    }

    func testWholeLineWinsOverParts() {
        let custom = [PackKey.key("Get down! Get back!")!: "Eğil ve geri çekil!", PackKey.key("Get Down!")!: "Yere yat!"]
        let found = PackLookup.match("Get down! Get back!") { PackKey.key($0).flatMap { custom[$0] } }
        XCTAssertEqual(found?.text, "Eğil ve geri çekil!")
    }
}
