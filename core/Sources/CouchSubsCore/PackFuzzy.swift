// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Paketteki satırın bulanık imzası: OCR'ın bozduğu satırı (harf hatası, birleşmiş sözcük) bulmak için.
/// canon metnin boşlukları atılır, OCR'ın karıştırdığı harfler birleştirilir (l/1/ı/j → i, 0 → o, 5 → s), kalan dizinin
/// her farklı üçlüsü FNV-1a 64 ile özetlenip m bitten birine düşer (Bloom kümesi; m uzunlukla büyür: 64/128/256).
/// Her bit onlarca farklı üçlünün ortak izidir ve sıra tutulmaz: İngilizce metin geri çıkarılamaz.
/// Windows'taki CouchSubs.Core/PackFuzzy.cs ve paket betiği (augment.py, common.py) ile birebir aynı; ortak deneme verisi
/// Tests/CouchSubsCoreTests/Fixtures/fuzzy-vectors.json.
public enum PackFuzzy {
    /// Bundan kısa satırda bulanık arama yok.
    public static let minLength = 16
    /// Bloom kümesinin en büyük boyu (32 bayt).
    static let maxBits = 256
    /// Üçlü başına bit.
    static let bitsPerGram = 3
    /// OCR izi olmayan satır neredeyse aynı olmalı: (uzunluk sınırı, en düşük benzerlik).
    static let cleanMinimum: [(limit: Int, value: Double)] = [(24, 90), (256, 80)]
    /// OCR izi olan satır: (uzunluk sınırı, en düşük benzerlik).
    static let damagedMinimum: [(limit: Int, value: Double)] = [(24, 70), (40, 60), (256, 55)]
    /// Türkçesi farklı en yakın ikinci aday en az bu kadar geride olmalı.
    static let margin = 5.0

    private static let fold: [Unicode.Scalar: Unicode.Scalar] = [
        "l": "i", "1": "i", "ı": "i", "j": "i", "0": "o", "5": "s", "æ": "a", "ø": "o", "œ": "o", "ß": "s",
    ]

    /// canon metin, boşluksuz ve OCR'ın karıştırdığı harfler birleşmiş.
    static func folded(_ text: String) -> [Unicode.Scalar] {
        PackKey.canon(text).unicodeScalars.compactMap { $0 == " " ? nil : (fold[$0] ?? $0) }
    }

    /// Uzunluğa göre Bloom boyu (bit).
    static func bits(forLength length: Int) -> Int {
        var bits = 64
        while bits < maxBits, length * bitsPerGram > bits { bits *= 2 }
        return bits
    }

    static func trigramHashes(_ scalars: [Unicode.Scalar]) -> [UInt64] {
        guard scalars.count >= 3 else { return [] }
        var hashes = Set<UInt64>()
        for index in 0...(scalars.count - 3) {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for scalar in scalars[index..<(index + 3)] {
                for byte in String(scalar).utf8 {
                    hash ^= UInt64(byte)
                    hash = hash &* 0x0000_0100_0000_01b3
                }
            }
            hashes.insert(hash)
        }
        return Array(hashes)
    }

    static func bloom(_ hashes: [UInt64], bits: Int) -> [UInt64] {
        var words = [UInt64](repeating: 0, count: bits / 64)
        for hash in hashes {
            let bit = Int(hash & UInt64(bits - 1))
            words[bit >> 6] |= 1 << UInt64(bit & 63)
        }
        return words
    }

    /// İki yönlü, rastlantıdan arındırılmış kapsama (0-100): min(sorgunun üçlülerinin adayda olanı, adayınkinin sorguda
    /// olanı). `entry`: dizindeki kelimeler, `offset`ten başlayarak `bits / 64` tane.
    static func similarity(_ query: [UInt64], _ entry: [UInt64], offset: Int, bits: Int) -> Double {
        var both = 0, inQuery = 0, inEntry = 0
        for index in 0..<(bits / 64) {
            let q = query[index], e = entry[offset + index]
            both += (q & e).nonzeroBitCount
            inQuery += q.nonzeroBitCount
            inEntry += e.nonzeroBitCount
        }
        return score(both: both, inQuery: inQuery, inEntry: inEntry, bits: bits)
    }

    /// Benzerlik, bit sayılarından (ortak, sorgudaki, adaydaki).
    @inline(__always)
    static func score(both: Int, inQuery: Int, inEntry: Int, bits: Int) -> Double {
        guard inQuery > 0, inEntry > 0 else { return 0 }
        let fillQuery = Double(inQuery) / Double(bits), fillEntry = Double(inEntry) / Double(bits)
        guard fillQuery < 1, fillEntry < 1 else { return 0 }
        let queryCovered = (Double(both) / Double(inQuery) - fillEntry) / (1 - fillEntry)
        let entryCovered = (Double(both) / Double(inEntry) - fillQuery) / (1 - fillQuery)
        return 100.0 * min(queryCovered, entryCovered)
    }

    /// (uzunluk, Bloom baytları) — paket betiğinin yazdığıyla aynı; satır çok kısaysa nil.
    static func signature(_ text: String) -> (length: Int, bytes: [UInt8])? {
        let scalars = folded(text)
        guard scalars.count >= minLength else { return nil }
        let length = min(scalars.count, 255)
        let words = bloom(trigramHashes(scalars), bits: bits(forLength: length))
        return (length, words.flatMap { word in (0..<8).map { UInt8(truncatingIfNeeded: word >> UInt64($0 * 8)) } })
    }

    /// Kabul için en düşük benzerlik (0-100), OCR izine ve uzunluğa göre.
    static func required(length: Int, damaged: Bool) -> Double {
        let table = damaged ? damagedMinimum : cleanMinimum
        return table.first { length < $0.limit }?.value ?? table[table.count - 1].value
    }

    private static let edge = Set(".,!?;:'\"()[]-…“”’‘".unicodeScalars)
    private static let typographic = Set("’‘“”—–…".unicodeScalars)

    static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }

    static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.numericType == .decimal || scalar.properties.numericType == .digit
    }

    /// OCR izi: İngilizce satırda ASCII dışı harf ya da işaret, sözcük içinde harf olmayan işaret ya da rakam, tek harfli
    /// garip sözcük, çok uzun (birleşmiş) sözcük. İzi olmayan satırın neredeyse aynı olması gerekir: temiz ama pakette
    /// olmayan satır büyük olasılıkla başka bir satırdır.
    static func damaged(_ text: String) -> Bool {
        if text.unicodeScalars.contains(where: { $0.value > 127 && !typographic.contains($0) }) { return true }
        for word in text.split(whereSeparator: \.isWhitespace) {
            var core = Array(word.unicodeScalars)
            while let first = core.first, edge.contains(first) { core.removeFirst() }
            while let last = core.last, edge.contains(last) { core.removeLast() }
            guard !core.isEmpty else { continue }
            if core.count >= 3 {
                for index in 1..<(core.count - 1)
                    where isLetter(core[index - 1]) && isLetter(core[index + 1]) && !isLetter(core[index])
                    && !"'’-".unicodeScalars.contains(core[index]) {
                    return true
                }
            }
            for index in core.indices.dropFirst() {
                let previous = core[index - 1], current = core[index]
                if (isLetter(previous) && isDigit(current)) || (isDigit(previous) && isLetter(current)) { return true }
            }
            if core.count == 1, isLetter(core[0]), !"aAIoO".unicodeScalars.contains(core[0]) { return true }
            if core.count > 14 { return true }
        }
        return false
    }
}


/// Bir paketin bulanık dizini: imzalı satırlar uzunluğa göre sıralı (aynı uzunlukta anahtar sırasıyla), Bloom
/// kelimeleri ardışık, her satırın bit sayısı önceden sayılmış.
struct PackFuzzyIndex: Sendable {
    private let lengths: [UInt8]
    private let keys: [UInt64]
    private let offsets: [Int32]
    private let ones: [UInt16]
    private let words: [UInt64]
    /// `start[n]`: uzunluğu n olan ilk satırın sırası.
    private let start: [Int]

    var count: Int { keys.count }

    /// Paketteki "fuzzy" nesnesi. `order`: paketteki bütün anahtarlar (entries + segments) sayı sırasıyla.
    /// Biçim tutmazsa nil (paket yine de tam eşleşmeyle çalışır).
    init?(json: [String: Any], order: [UInt64]) {
        guard json["version"] as? Int == 1, json["count"] as? Int == order.count,
              let mask = (json["mask"] as? String).flatMap({ Data(base64Encoded: $0) }).map([UInt8].init),
              let lengthBytes = (json["lengths"] as? String).flatMap({ Data(base64Encoded: $0) }).map([UInt8].init),
              let blooms = (json["blooms"] as? String).flatMap({ Data(base64Encoded: $0) }),
              mask.count == (order.count + 7) / 8 else { return nil }
        // Dosyadaki sıra: imzalı anahtarlar sayı sırasıyla, Bloom'ları ardışık.
        let total = lengthBytes.count
        var fileKeys = [UInt64](repeating: 0, count: total)
        var fileOffsets = [Int](repeating: 0, count: total)
        var signed = 0, byteOffset = 0
        for index in order.indices where mask[index >> 3] >> UInt8(index & 7) & 1 == 1 {
            guard signed < total else { return nil }
            fileKeys[signed] = order[index]
            fileOffsets[signed] = byteOffset
            byteOffset += PackFuzzy.bits(forLength: Int(lengthBytes[signed])) / 8
            signed += 1
        }
        guard signed == total, byteOffset == blooms.count else { return nil }
        // Uzunluğa göre sayarak sırala (aynı uzunlukta anahtar sırası korunur).
        var start = [Int](repeating: 0, count: 257)
        for length in lengthBytes { start[Int(length) + 1] += 1 }
        for length in 1...256 { start[length] += start[length - 1] }
        var next = start
        var lengths = [UInt8](repeating: 0, count: total)
        var keys = [UInt64](repeating: 0, count: total)
        var offsets = [Int32](repeating: 0, count: total)
        var ones = [UInt16](repeating: 0, count: total)
        var words = [UInt64](repeating: 0, count: blooms.count / 8)
        // source[yeni sıra] = dosyadaki sıra
        var source = [Int](repeating: 0, count: total)
        for item in 0..<total {
            let length = Int(lengthBytes[item])
            source[next[length]] = item
            next[length] += 1
        }
        var wordOffset = 0
        blooms.withUnsafeBytes { raw in
            for position in 0..<total {
                let item = source[position]
                let length = lengthBytes[item]
                let count = PackFuzzy.bits(forLength: Int(length)) / 64
                lengths[position] = length
                keys[position] = fileKeys[item]
                offsets[position] = Int32(wordOffset)
                var bits = 0
                for word in 0..<count {
                    let value = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: fileOffsets[item] + word * 8, as: UInt64.self))
                    words[wordOffset + word] = value
                    bits += value.nonzeroBitCount
                }
                ones[position] = UInt16(bits)
                wordOffset += count
            }
        }
        self.lengths = lengths
        self.keys = keys
        self.offsets = offsets
        self.ones = ones
        self.words = words
        self.start = start
    }

    /// Eşik, uzunluk ve ikinci aday şartlarını sağlayan en benzer satırın anahtarı; yoksa nil.
    /// `translation`: anahtarın Türkçesi (aynı Türkçeli iki aday birbirinin rakibi sayılmaz).
    func nearest(_ text: String, translation: (UInt64) -> String?) -> UInt64? {
        let scalars = PackFuzzy.folded(text)
        guard scalars.count >= PackFuzzy.minLength, !keys.isEmpty else { return nil }
        let length = min(scalars.count, 255)
        let floor = PackFuzzy.required(length: length, damaged: PackFuzzy.damaged(text)) - PackFuzzy.margin
        let need = floor + PackFuzzy.margin
        let hashes = PackFuzzy.trigramHashes(scalars)
        // Sorgunun üç boydaki Bloom'u yan yana: 64 bit [0], 128 bit [1, 2], 256 bit [3...6].
        let query = PackFuzzy.bloom(hashes, bits: 64) + PackFuzzy.bloom(hashes, bits: 128) + PackFuzzy.bloom(hashes, bits: 256)
        let queryOnes = [query[0].nonzeroBitCount, query[1].nonzeroBitCount + query[2].nonzeroBitCount,
                         query[3...6].reduce(0) { $0 + $1.nonzeroBitCount }]
        // Aday uzunluğu en çok ±%25 farklı: |aday - satır| * 4 <= satır.
        let lower = length - length / 4
        let upper = min(255, length + length / 4)
        var found: [(score: Double, key: UInt64)] = []
        query.withUnsafeBufferPointer { q in
            words.withUnsafeBufferPointer { w in
                for index in start[lower]..<start[upper + 1] {
                    let bits = PackFuzzy.bits(forLength: Int(lengths[index]))
                    let tier = bits == 64 ? 0 : bits == 128 ? 1 : 2
                    let base = Int(offsets[index])
                    var both = (q[tier == 0 ? 0 : tier == 1 ? 1 : 3] & w[base]).nonzeroBitCount
                    if tier >= 1 { both += (q[tier == 1 ? 2 : 4] & w[base + 1]).nonzeroBitCount }
                    if tier == 2 { both += (q[5] & w[base + 2]).nonzeroBitCount + (q[6] & w[base + 3]).nonzeroBitCount }
                    let score = PackFuzzy.score(both: both, inQuery: queryOnes[tier], inEntry: Int(ones[index]), bits: bits)
                    if score >= floor { found.append((score, keys[index])) }
                }
            }
        }
        guard let best = found.max(by: { ($0.score, $0.key) < ($1.score, $1.key) }), best.score >= need else { return nil }
        let turkish = translation(best.key)
        for other in found where other.key != best.key && other.score > best.score - PackFuzzy.margin
            && translation(other.key) != turkish {
            return nil
        }
        return best.key
    }
}
