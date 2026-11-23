// SPDX-License-Identifier: AGPL-3.0-only
// Android'deki Spake2.kt'nin (ve masaüstündeki Spake2.cs'in) Swift karşılığı.

import CryptoKit
import Foundation
import Security

/// 2^255 − 19 cismi: değerler hep [0, p) aralığında tutulur; çarpım p'nin özel biçimiyle indirgenir.
enum Field25519 {
    static let p = (BigUInt(1) << 255) - BigUInt(19)
    private static let nineteen = BigUInt(19)

    static func reduce(_ value: BigUInt) -> BigUInt {
        var x = value
        while x.bitWidth > 255 { x = x.truncated(bits: 255) + (x >> 255) * nineteen }
        if x >= p { x = x - p }
        return x
    }

    static func add(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
        let sum = a + b
        return sum >= p ? sum - p : sum
    }

    static func sub(_ a: BigUInt, _ b: BigUInt) -> BigUInt { a >= b ? a - b : a + p - b }
    static func mul(_ a: BigUInt, _ b: BigUInt) -> BigUInt { reduce(a * b) }
    static func negate(_ a: BigUInt) -> BigUInt { a.isZero ? a : p - a }

    static func power(_ base: BigUInt, _ exponent: BigUInt) -> BigUInt {
        var result = BigUInt(1)
        var square = base
        for index in 0..<exponent.bitWidth {
            if exponent.bit(index) { result = mul(result, square) }
            square = mul(square, square)
        }
        return result
    }

    static func inverse(_ a: BigUInt) -> BigUInt { power(a, p - BigUInt(2)) }
}

/// edwards25519 noktası (RFC 8032), genişletilmiş koordinatlar (X:Y:Z:T); yalnız SPAKE2 için.
struct EdPoint {
    let x: BigUInt, y: BigUInt, z: BigUInt, t: BigUInt
    typealias F = Field25519

    static let d = F.mul(F.sub(BigUInt(), BigUInt(121665)), F.inverse(BigUInt(121666)))
    /// Asal mertebeli alt grubun mertebesi.
    static let l = (BigUInt(1) << 252) + BigUInt(decimal: "27742317777372353535851937790883648493")
    private static let sqrtMinusOne = F.power(BigUInt(2), (F.p - BigUInt(1)) >> 2)
    static let identity = EdPoint(x: BigUInt(), y: BigUInt(1), z: BigUInt(1), t: BigUInt())
    static let base: EdPoint = {
        let y = F.mul(BigUInt(4), F.inverse(BigUInt(5)))
        return fromAffine(recoverX(y, sign: false)!, y)
    }()

    static func fromAffine(_ x: BigUInt, _ y: BigUInt) -> EdPoint { EdPoint(x: x, y: y, z: BigUInt(1), t: F.mul(x, y)) }

    /// 32 baytlık kodlamadan nokta; eğri üstünde değilse nil.
    static func decode(_ encoded: [UInt8]) -> EdPoint? {
        guard encoded.count == 32 else { return nil }
        var bytes = encoded
        let sign = bytes[31] & 0x80 != 0
        bytes[31] &= 0x7f
        let y = BigUInt(littleEndian: bytes)
        guard y < F.p, let x = recoverX(y, sign: sign) else { return nil }
        return fromAffine(x, y)
    }

    private static func recoverX(_ y: BigUInt, sign: Bool) -> BigUInt? {
        let y2 = F.mul(y, y)
        let u = F.sub(y2, BigUInt(1))
        let v = F.add(F.mul(d, y2), BigUInt(1))
        let x2 = F.mul(u, F.inverse(v))
        if x2.isZero { return sign ? nil : BigUInt() }
        var candidate = F.power(x2, (F.p + BigUInt(3)) >> 3)
        if F.mul(candidate, candidate) != x2 { candidate = F.mul(candidate, sqrtMinusOne) }
        if F.mul(candidate, candidate) != x2 { return nil }
        if candidate.bit(0) != sign { candidate = F.negate(candidate) }
        return candidate
    }

    func adding(_ q: EdPoint) -> EdPoint {
        let a = F.mul(F.sub(y, x), F.sub(q.y, q.x))
        let b = F.mul(F.add(y, x), F.add(q.y, q.x))
        let c = F.mul(F.mul(F.add(t, t), EdPoint.d), q.t)
        let dd = F.mul(F.add(z, z), q.z)
        let e = F.sub(b, a), f = F.sub(dd, c), g = F.add(dd, c), h = F.add(b, a)
        return EdPoint(x: F.mul(e, f), y: F.mul(g, h), z: F.mul(f, g), t: F.mul(e, h))
    }

    func negated() -> EdPoint { EdPoint(x: F.negate(x), y: y, z: z, t: F.negate(t)) }

    func multiplied(by scalar: BigUInt) -> EdPoint {
        var result = EdPoint.identity
        var addend = self
        for index in 0..<scalar.bitWidth {
            if scalar.bit(index) { result = result.adding(addend) }
            addend = addend.adding(addend)
        }
        return result
    }

    func encoded() -> [UInt8] {
        let inverse = F.inverse(z)
        let affineX = F.mul(x, inverse)
        var bytes = F.mul(y, inverse).littleEndianBytes(32)
        if affineX.bit(0) { bytes[31] |= 0x80 }
        return bytes
    }
}

/// BoringSSL'in SPAKE2'si, adb'nin kablosuz hata ayıklama eşleştirmesindeki biçimiyle (Spake2.kt ile aynı).
struct Spake2 {
    static let clientName = Array("adb pair client\u{0}".utf8)
    static let serverName = Array("adb pair server\u{0}".utf8)
    static let m = EdPoint.decode(hexBytes("5ada7e4bf6ddd9adb6626d32131c6b5c51a1e347a3478f53cfcf441b88eed12e"))!
    static let n = EdPoint.decode(hexBytes("10e3df0ae37d8e7a99b5fe74b44672103dbddcbd06af680d71329a11693bc778"))!

    static func hexBytes(_ text: String) -> [UInt8] {
        let characters = Array(text)
        return stride(from: 0, to: characters.count, by: 2).map { UInt8(String(characters[$0...$0 + 1]), radix: 16)! }
    }

    let alice: Bool
    private let passwordHash: [UInt8]
    private let privateKey: BigUInt
    private let passwordScalar: BigUInt
    let message: [UInt8]

    init(alice: Bool, password: [UInt8], random64: [UInt8]? = nil) {
        self.alice = alice
        passwordHash = Array(SHA512.hash(data: password))
        var random = random64 ?? [UInt8](repeating: 0, count: 64)
        if random64 == nil { _ = SecRandomCopyBytes(kSecRandomDefault, 64, &random) }
        privateKey = (BigUInt(littleEndian: random) % EdPoint.l) << 3
        var scalar = BigUInt(littleEndian: passwordHash) % EdPoint.l
        // BoringSSL'in "password scalar hack"i: alt üç bit sıfır olacak biçimde l, 2l, 4l eklenir.
        if scalar.bit(0) { scalar = scalar + EdPoint.l }
        if scalar.bit(1) { scalar = scalar + (EdPoint.l << 1) }
        if scalar.bit(2) { scalar = scalar + (EdPoint.l << 2) }
        passwordScalar = scalar
        message = EdPoint.base.multiplied(by: privateKey).adding((alice ? Spake2.m : Spake2.n).multiplied(by: scalar)).encoded()
    }

    /// Karşı tarafın mesajından 64 baytlık anahtar malzemesi; nokta geçersizse nil.
    func finish(_ theirMessage: [UInt8]) -> [UInt8]? {
        guard let theirs = EdPoint.decode(theirMessage) else { return nil }
        let unmasked = theirs.adding((alice ? Spake2.n : Spake2.m).multiplied(by: passwordScalar).negated())
        let shared = unmasked.multiplied(by: privateKey).encoded()
        var hash = SHA512()
        func update(_ data: [UInt8]) {
            var length = UInt64(data.count).littleEndian
            withUnsafeBytes(of: &length) { hash.update(bufferPointer: $0) }
            hash.update(data: data)
        }
        let myName = alice ? Spake2.clientName : Spake2.serverName
        let theirName = alice ? Spake2.serverName : Spake2.clientName
        if alice {
            update(myName); update(theirName); update(message); update(theirMessage)
        } else {
            update(theirName); update(myName); update(theirMessage); update(message)
        }
        update(shared)
        update(passwordHash)
        return Array(hash.finalize())
    }
}
