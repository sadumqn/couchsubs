// SPDX-License-Identifier: AGPL-3.0-only
// Telefondan TV kurulumunun gerektirdiği kadar büyük tam sayı: adb'nin açık anahtar biçimi (R² mod n) ve SPAKE2'nin
// edwards25519 aritmetiği (Android'deki java.math.BigInteger'ın karşılığı; hız gerekmez).

import Foundation

/// İşaretsiz büyük tam sayı; 32 bitlik parçalar, en düşük parça başta. Sondaki sıfır parçalar tutulmaz.
struct BigUInt: Equatable, Comparable, CustomStringConvertible {
    private(set) var limbs: [UInt32]

    init(_ value: UInt64 = 0) {
        limbs = [UInt32(truncatingIfNeeded: value), UInt32(truncatingIfNeeded: value >> 32)]
        normalize()
    }

    init(limbs: [UInt32]) {
        self.limbs = limbs
        normalize()
    }

    /// Büyük-endian baytlardan.
    init(bigEndian bytes: [UInt8]) {
        var result = [UInt32](repeating: 0, count: (bytes.count + 3) / 4)
        for (index, byte) in bytes.reversed().enumerated() {
            result[index / 4] |= UInt32(byte) << (8 * UInt32(index % 4))
        }
        self.init(limbs: result)
    }

    init(littleEndian bytes: [UInt8]) { self.init(bigEndian: bytes.reversed()) }

    /// Onaltılık metinden (boşluksuz).
    init(hex: String) {
        var bytes: [UInt8] = []
        var text = Array(hex)
        if text.count % 2 == 1 { text.insert("0", at: 0) }
        var index = 0
        while index < text.count {
            bytes.append(UInt8(String(text[index...index + 1]), radix: 16) ?? 0)
            index += 2
        }
        self.init(bigEndian: bytes)
    }

    /// Onluk metinden.
    init(decimal: String) {
        var value = BigUInt()
        for character in decimal {
            guard let digit = character.wholeNumberValue else { continue }
            value = value * BigUInt(10) + BigUInt(UInt64(digit))
        }
        self = value
    }

    private mutating func normalize() {
        while let last = limbs.last, last == 0 { limbs.removeLast() }
    }

    var isZero: Bool { limbs.isEmpty }
    var bitWidth: Int {
        guard let last = limbs.last else { return 0 }
        return (limbs.count - 1) * 32 + (32 - last.leadingZeroBitCount)
    }

    func bit(_ index: Int) -> Bool {
        let limb = index / 32
        guard limb < limbs.count else { return false }
        return (limbs[limb] >> UInt32(index % 32)) & 1 == 1
    }

    var low32: UInt32 { limbs.first ?? 0 }

    /// `size` baytlık küçük-endian gösterim (uzunsa kesilir).
    func littleEndianBytes(_ size: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: size)
        for index in 0..<size {
            let limb = index / 4
            guard limb < limbs.count else { break }
            result[index] = UInt8(truncatingIfNeeded: limbs[limb] >> (8 * UInt32(index % 4)))
        }
        return result
    }

    func bigEndianBytes(_ size: Int) -> [UInt8] { littleEndianBytes(size).reversed() }

    var description: String { limbs.reversed().map { String(format: "%08x", $0) }.joined() }

    static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.limbs.count != rhs.limbs.count { return lhs.limbs.count < rhs.limbs.count }
        for index in stride(from: lhs.limbs.count - 1, through: 0, by: -1) where lhs.limbs[index] != rhs.limbs[index] {
            return lhs.limbs[index] < rhs.limbs[index]
        }
        return false
    }

    static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        let count = max(lhs.limbs.count, rhs.limbs.count)
        var result = [UInt32](repeating: 0, count: count + 1)
        var carry: UInt64 = 0
        for index in 0..<count {
            let sum = UInt64(index < lhs.limbs.count ? lhs.limbs[index] : 0) + UInt64(index < rhs.limbs.count ? rhs.limbs[index] : 0) + carry
            result[index] = UInt32(truncatingIfNeeded: sum)
            carry = sum >> 32
        }
        result[count] = UInt32(carry)
        return BigUInt(limbs: result)
    }

    /// lhs ≥ rhs olmalıdır.
    static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        precondition(lhs >= rhs, "BigUInt: negatif sonuç")
        var result = lhs.limbs
        var borrow: Int64 = 0
        for index in 0..<result.count {
            var difference = Int64(result[index]) - Int64(index < rhs.limbs.count ? rhs.limbs[index] : 0) - borrow
            if difference < 0 {
                difference += 1 << 32
                borrow = 1
            } else {
                borrow = 0
            }
            result[index] = UInt32(difference)
        }
        return BigUInt(limbs: result)
    }

    static func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        if lhs.isZero || rhs.isZero { return BigUInt() }
        var result = [UInt32](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
        for i in 0..<lhs.limbs.count {
            var carry: UInt64 = 0
            let a = UInt64(lhs.limbs[i])
            for j in 0..<rhs.limbs.count {
                let value = a * UInt64(rhs.limbs[j]) + UInt64(result[i + j]) + carry
                result[i + j] = UInt32(truncatingIfNeeded: value)
                carry = value >> 32
            }
            var k = i + rhs.limbs.count
            while carry > 0 {
                let value = UInt64(result[k]) + carry
                result[k] = UInt32(truncatingIfNeeded: value)
                carry = value >> 32
                k += 1
            }
        }
        return BigUInt(limbs: result)
    }

    static func << (lhs: BigUInt, bits: Int) -> BigUInt {
        if lhs.isZero || bits == 0 { return lhs }
        let words = bits / 32
        let shift = UInt32(bits % 32)
        var result = [UInt32](repeating: 0, count: lhs.limbs.count + words + 1)
        for (index, limb) in lhs.limbs.enumerated() {
            result[index + words] |= limb << shift
            if shift > 0 { result[index + words + 1] |= limb >> (32 - shift) }
        }
        return BigUInt(limbs: result)
    }

    static func >> (lhs: BigUInt, bits: Int) -> BigUInt {
        let words = bits / 32
        guard words < lhs.limbs.count else { return BigUInt() }
        let shift = UInt32(bits % 32)
        var result = [UInt32](repeating: 0, count: lhs.limbs.count - words)
        for index in 0..<result.count {
            let source = index + words
            result[index] = lhs.limbs[source] >> shift
            if shift > 0, source + 1 < lhs.limbs.count { result[index] |= lhs.limbs[source + 1] << (32 - shift) }
        }
        return BigUInt(limbs: result)
    }

    /// Alttaki `bits` bit.
    func truncated(bits: Int) -> BigUInt {
        let words = bits / 32
        var result = Array(limbs.prefix(words + 1))
        if words < result.count {
            let keep = UInt32(bits % 32)
            result[words] &= keep == 0 ? 0 : (UInt32.max >> (32 - keep))
        }
        return BigUInt(limbs: result)
    }

    /// Kalan (bit bit uzun bölme; yalnız birkaç yüz bitlik sayılarda ve seyrek kullanılır).
    static func % (lhs: BigUInt, modulus: BigUInt) -> BigUInt {
        precondition(!modulus.isZero)
        if lhs < modulus { return lhs }
        var remainder = BigUInt()
        for index in stride(from: lhs.bitWidth - 1, through: 0, by: -1) {
            remainder = remainder << 1
            if lhs.bit(index) { remainder = remainder + BigUInt(1) }
            if remainder >= modulus { remainder = remainder - modulus }
        }
        return remainder
    }

    func power(_ exponent: BigUInt, modulus: BigUInt) -> BigUInt {
        var result = BigUInt(1) % modulus
        var base = self % modulus
        for index in 0..<exponent.bitWidth {
            if exponent.bit(index) { result = (result * base) % modulus }
            base = (base * base) % modulus
        }
        return result
    }
}
