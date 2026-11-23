// SPDX-License-Identifier: AGPL-3.0-only

import CryptoKit
import Security
import XCTest
@testable import CouchSubs

/// Tizen 2.x TV'ler (2016) için SHA-256 imza (#638). Bilinen girdinin özetleri Android'deki WgtSignerTest ve Windows'taki
/// WgtSignerTests ile aynıdır: üç imzalayıcı aynı metni üretir; o metnin imzası Android'de Apache Santuario, Windows'ta
/// .NET'in XML kanonikleştiricisiyle bağımsız doğrulanır.
final class WgtSignerTests: XCTestCase {
    private let files = [StoredZip.Entry(name: "config.xml", data: Array("<widget/>".utf8)),
                         StoredZip.Entry(name: "index.html", data: Array("<p>merhaba</p>".utf8))]

    private func prop(_ id: String, _ digest: WgtSigner.Digest) -> String {
        WgtSigner.digest(Array(WgtSigner.propObject(id, canonical: true).utf8), digest)
    }

    private func signedInfoHash(_ digest: WgtSigner.Digest) -> String {
        let info = WgtSigner.signedInfo(files, propDigest: prop("AuthorSignature", digest), digest)
        return SHA256.hash(data: Data(WgtSigner.canonicalSignedInfo(info).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func testKnownInputGivesKnownSha256Digests() {
        XCTAssertEqual(WgtSigner.digest(files[0].data, .sha256), "EY7MvyaBrTJqCTlmhv1sr4UMN5v2uF5KXyQLW3VbiAA=")
        XCTAssertEqual(WgtSigner.digest(files[1].data, .sha256), "6KF08mjdP2RJgT9dsGq+QSvYwK9Gf1evjAdB8iPWFUM=")
        XCTAssertEqual(prop("AuthorSignature", .sha256), "lpo8tUDs054eLlBQXiDPVDVKfw30ZZdtkRs1jd7H5K8=")
        XCTAssertEqual(prop("DistributorSignature", .sha256), "u/jU3U4Zm5ihTMSjKGlGYbWzDfRkGphPPHx3gJIYEJ4=")
        XCTAssertEqual(signedInfoHash(.sha256), "fd26f785814408973737073c499f19c6fce194dad6ec3f3cf3205a640ff5d975")
    }

    func testKnownInputGivesKnownSha512Digests() {
        XCTAssertEqual(WgtSigner.digest(files[0].data, .sha512),
                       "hSUufNpfpXKCyTwglfu2Zrqtt8W2nXG1K6Vfy7fwYUMDL5lpBwC0EgpxeKlzb9I40BrzBklgo31V7Pl1ZqoOTQ==")
        XCTAssertEqual(prop("AuthorSignature", .sha512),
                       "aXbSAVgmAz0GsBUeZ1UmNDRrxkWhDUVGb45dZcNRq429wX3X+x6kaXT3NdNDTSNVTU+ypkysPMGvQY10fG1EWQ==")
        XCTAssertEqual(signedInfoHash(.sha512), "844e74e1b6dd5518e71f58ee694827115d657d623d35bb6711216ac8c74c6e27")
        // Varsayılan (Tizen 3.0 ve üstü) SHA-512 olarak kalır.
        XCTAssertEqual(WgtSigner.digest(files[0].data), WgtSigner.digest(files[0].data, .sha512))
        XCTAssertTrue(WgtSigner.signedInfo(files, propDigest: "x").contains("xmldsig-more#rsa-sha512"))
    }

    func testSha256SignatureNamesItsAlgorithmsAndVerifies() throws {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let signer = WgtSigner.Signer(key: RsaKey(privateKey: privateKey), chain: [])

        let xml = String(decoding: try WgtSigner.signature("AuthorSignature", files, signer, .sha256), as: UTF8.self)
        XCTAssertTrue(xml.hasPrefix("<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\" Id=\"AuthorSignature\">"))
        XCTAssertTrue(xml.contains("<CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\">"))
        XCTAssertTrue(xml.contains("<SignatureMethod Algorithm=\"http://www.w3.org/2001/04/xmldsig-more#rsa-sha256\">"))
        XCTAssertTrue(xml.contains("<DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\">"))
        XCTAssertFalse(xml.contains("sha512"))
        XCTAssertTrue(xml.contains("<Reference URI=\"config.xml\"><DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"></DigestMethod><DigestValue>EY7MvyaBrTJqCTlmhv1sr4UMN5v2uF5KXyQLW3VbiAA=</DigestValue>"))
        XCTAssertTrue(xml.contains("<DigestValue>lpo8tUDs054eLlBQXiDPVDVKfw30ZZdtkRs1jd7H5K8=</DigestValue></Reference></SignedInfo>"))

        // İmza, dosyadaki SignedInfo'nun kanonik biçimi üzerinde RSA-SHA256 olmalı.
        let start = try XCTUnwrap(xml.range(of: "<SignedInfo>")), end = try XCTUnwrap(xml.range(of: "</SignedInfo>"))
        let canonical = WgtSigner.canonicalSignedInfo(String(xml[start.lowerBound..<end.upperBound]))
        let valueStart = try XCTUnwrap(xml.range(of: "<SignatureValue>")), valueEnd = try XCTUnwrap(xml.range(of: "</SignatureValue>"))
        let value = try XCTUnwrap(Data(base64Encoded: String(xml[valueStart.upperBound..<valueEnd.lowerBound])))
        XCTAssertTrue(SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data(canonical.utf8) as CFData, value as CFData, nil))
        XCTAssertFalse(SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA512, Data(canonical.utf8) as CFData, value as CFData, nil))
    }

    func testAlternativePackageIsTriedOnlyAfterTwoBareFailures() {
        XCTAssertTrue(SamsungDiagnostics.alternativeMayHelp(.other, .other))
        XCTAssertFalse(SamsungDiagnostics.alternativeMayHelp(.certificateMismatch, .other))
        XCTAssertFalse(SamsungDiagnostics.alternativeMayHelp(.other, .packageBlocked))
        XCTAssertEqual(SamsungDiagnostics.classify("app_id[CouchSubsT.CouchSubs] install failed[118]"), .other)
    }
}
