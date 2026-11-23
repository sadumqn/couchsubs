// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.samsung

import org.bouncycastle.asn1.DERIA5String
import org.bouncycastle.asn1.pkcs.PKCSObjectIdentifiers
import org.bouncycastle.asn1.x500.style.BCStyle
import org.bouncycastle.asn1.x509.Extension
import org.bouncycastle.asn1.x509.Extensions
import org.bouncycastle.asn1.x509.GeneralName
import org.bouncycastle.asn1.x509.GeneralNames
import org.bouncycastle.openssl.PEMParser
import org.bouncycastle.operator.jcajce.JcaContentVerifierProviderBuilder
import org.bouncycastle.pkcs.PKCS10CertificationRequest
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.io.IOException
import java.io.StringReader
import java.nio.file.Files
import java.util.Date

/** Samsung sertifika istekleri (CSR), istek gövdesi ve imza dosyalarının saklanması (Samsung'a gitmeden). */
class SamsungCertificatesTest {
    private val account = SamsungAccount("tok-123", "user-9", "a@b.c")
    private val duid = "QJCDF4ABCDEFG"

    private fun parse(pem: ByteArray): PKCS10CertificationRequest {
        val text = String(pem, Charsets.US_ASCII)
        assertTrue(text.startsWith("-----BEGIN CERTIFICATE REQUEST-----\n"))
        assertTrue(text.endsWith("\n-----END CERTIFICATE REQUEST-----"))
        return PEMParser(StringReader(text)).readObject() as PKCS10CertificationRequest
    }

    @Test
    fun authorRequestIsSignedAndNamedCouchSubs() {
        val key = TestCertificates.rsa()
        val request = parse(SamsungCsr.author(key))
        assertTrue(request.isSignatureValid(JcaContentVerifierProviderBuilder().build(request.subjectPublicKeyInfo)))
        assertEquals("1.2.840.113549.1.1.11", request.signatureAlgorithm.algorithm.id)
        assertEquals("CouchSubs", request.subject.getRDNs(BCStyle.CN)[0].first.value.toString())
        assertArrayEquals(key.public.encoded, JcaPKCS10CertificationRequest(request).publicKey.encoded)
        assertEquals(0, request.attributes.size)
    }

    @Test
    fun distributorRequestCarriesTheTvsDuidInUpperCaseUrn() {
        val key = TestCertificates.rsa()
        val request = parse(SamsungCsr.distributor(key, duid, account.email))
        assertTrue(request.isSignatureValid(JcaContentVerifierProviderBuilder().build(request.subjectPublicKeyInfo)))
        assertEquals("TizenSDK", request.subject.getRDNs(BCStyle.CN)[0].first.value.toString())
        assertEquals("a@b.c", request.subject.getRDNs(BCStyle.EmailAddress)[0].first.value.toString())
        val attribute = request.getAttributes(PKCSObjectIdentifiers.pkcs_9_at_extensionRequest).single()
        val extensions = Extensions.getInstance(attribute.attrValues.getObjectAt(0))
        val san = extensions.getExtension(Extension.subjectAlternativeName)
        assertFalse(san.isCritical)
        val names = GeneralNames.getInstance(san.parsedValue).names
        assertEquals(listOf(GeneralName.uniformResourceIdentifier, GeneralName.uniformResourceIdentifier), names.map { it.tagNo })
        assertEquals(listOf("URN:tizen:packageid=", "URN:tizen:deviceid=$duid"), names.map { DERIA5String.getInstance(it.name).string })
        // Aynı anahtar her iki istekte.
        assertArrayEquals(key.public.encoded, JcaPKCS10CertificationRequest(request).publicKey.encoded)
    }

    @Test
    fun distributorRequestWithoutEmailHasOnlyCommonName() {
        val request = parse(SamsungCsr.distributor(TestCertificates.rsa(), duid, ""))
        assertEquals(1, request.subject.rdNs.size)
    }

    @Test
    fun derLengthsAboveOneTwentySevenUseLongForm() {
        assertArrayEquals(byteArrayOf(0x04, 0x81.toByte(), 200.toByte()), Der.tlv(0x04, ByteArray(200)).copyOf(3))
        assertArrayEquals(byteArrayOf(0x04, 0x82.toByte(), 0x01, 0x2C), Der.tlv(0x04, ByteArray(300)).copyOf(4))
        assertArrayEquals(byteArrayOf(0x06, 0x03, 0x55, 0x1D, 0x11), Der.oid("2.5.29.17"))
        assertArrayEquals(byteArrayOf(0x06, 0x09, 0x2A, 0x86.toByte(), 0x48, 0x86.toByte(), 0xF7.toByte(), 0x0D, 0x01, 0x09, 0x0E),
            Der.oid("1.2.840.113549.1.9.14"))
    }

    @Test
    fun requestBodyHasSamsungsFieldsInOrder() {
        val csr = "-----BEGIN CERTIFICATE REQUEST-----\nAAAA\n-----END CERTIFICATE REQUEST-----".toByteArray()
        val author = String(SamsungCertificates.requestBody(account, csr, "author.csr", false, Multipart("B")).build())
        assertEquals(
            "--B\r\nContent-Disposition: form-data; name=\"access_token\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\ntok-123\r\n" +
                "--B\r\nContent-Disposition: form-data; name=\"user_id\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nuser-9\r\n" +
                "--B\r\nContent-Disposition: form-data; name=\"platform\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nVD\r\n" +
                "--B\r\nContent-Disposition: form-data; name=\"csr\"; filename=\"author.csr\"\r\nContent-Type: application/octet-stream\r\n\r\n" +
                String(csr) + "\r\n--B--\r\n",
            author)
        val distributor = String(SamsungCertificates.requestBody(account, csr, "distributor.csr", true, Multipart("B")).build())
        val names = Regex("name=\"([a-z_]+)\"").findAll(distributor).map { it.groupValues[1] }.toList()
        assertEquals(listOf("access_token", "user_id", "platform", "privilege_level", "developer_type", "csr"), names)
        assertTrue(distributor.contains("name=\"privilege_level\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\npublic\r\n"))
        assertTrue(distributor.contains("name=\"developer_type\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nIndividual\r\n"))
        assertEquals("multipart/form-data; boundary=B", Multipart("B").contentType)
    }

    /** Sahte Samsung: CSR'yi okuyup test CA'sıyla sertifika verir; cihaz profili için XML döner. */
    private class FakeSamsung(val fail: Pair<String, HttpReply>? = null) : HttpPost {
        val calls = ArrayList<String>()
        override fun post(url: String, contentType: String, body: ByteArray): HttpReply {
            calls.add(url)
            fail?.let { (failing, reply) -> if (url == failing) return reply }
            if (url == SamsungCertificates.DISTRIBUTOR_PROFILE_URL) return HttpReply(200, "OK", "<profile/>".toByteArray())
            val text = String(body, Charsets.ISO_8859_1)
            val pem = text.substring(text.indexOf("-----BEGIN CERTIFICATE REQUEST-----"), text.indexOf("-----END CERTIFICATE REQUEST-----") + 33)
            val request = JcaPKCS10CertificationRequest(PEMParser(StringReader(pem)).readObject() as PKCS10CertificationRequest)
            val cn = if (url == SamsungCertificates.AUTHOR_URL) "CN=CouchSubs" else "CN=TizenSDK"
            val certificate = TestCertificates.issue(cn, request.publicKey)
            return HttpReply(200, "OK", SamsungCsr.pem(certificate.encoded, "CERTIFICATE"))
        }
    }

    @Test
    fun certificatesAreRequestedAndStoredForTheTv() {
        val directory = File(Files.createTempDirectory("samsung").toFile(), duid)
        val samsung = FakeSamsung()
        val profile = SamsungCertificates(samsung).create(duid, account, SigningProfile(directory))
        assertEquals(listOf(SamsungCertificates.AUTHOR_URL, SamsungCertificates.DISTRIBUTOR_PROFILE_URL, SamsungCertificates.DISTRIBUTOR_URL), samsung.calls)
        assertTrue(profile.exists)
        assertTrue(profile.isValid())
        assertTrue(profile.isFor(duid))
        assertFalse(profile.isFor("BASKADUID1234"))
        assertEquals("<profile/>", profile.deviceProfileFile.readText())
        assertEquals("CN=CouchSubs", profile.author().subjectX500Principal.name)
        // Anahtar sertifikayla eşleşir.
        val signature = java.security.Signature.getInstance("SHA256withRSA")
        signature.initSign(profile.privateKey()); signature.update(byteArrayOf(1))
        val value = signature.sign()
        signature.initVerify(profile.distributor().publicKey); signature.update(byteArrayOf(1))
        assertTrue(signature.verify(value))
        assertTrue(profile.describe(Date(), duid).startsWith("geçerli"))
        assertTrue(profile.describe(Date(), "BASKADUID1234").startsWith("başka TV'nin"))
    }

    @Test
    fun samsungErrorIsACertificateErrorWithItsWords() {
        val reply = HttpReply(401, "Unauthorized", "{\"code\":\"AUTH_FAIL\",\"message\":\"Invalid access token\"}".toByteArray())
        val directory = File(Files.createTempDirectory("samsung").toFile(), duid)
        try {
            SamsungCertificates(FakeSamsung(SamsungCertificates.AUTHOR_URL to reply)).create(duid, account, SigningProfile(directory))
            fail()
        } catch (error: SamsungInstallException) {
            assertEquals(SamsungInstallError.CERTIFICATE_FAILED, error.error)
            assertEquals("Samsung sertifika sunucusu /apis/v3/authors: 401 Unauthorized code=AUTH_FAIL, message=Invalid access token", error.detail)
        }
        assertFalse(SigningProfile(directory).exists)
    }

    @Test
    fun successfulAnswerThatIsNotACertificateIsACertificateError() {
        val reply = HttpReply(200, "OK", "{\"errorMessage\":\"Not a developer\"}".toByteArray())
        try {
            SamsungCertificates(FakeSamsung(SamsungCertificates.DISTRIBUTOR_URL to reply))
                .create(duid, account, SigningProfile(File(Files.createTempDirectory("samsung").toFile(), duid)))
            fail()
        } catch (error: SamsungInstallException) {
            assertEquals(SamsungInstallError.CERTIFICATE_FAILED, error.error)
            assertEquals("Samsung dağıtıcı sertifikası vermedi: errorMessage=Not a developer", error.detail)
        }
    }

    @Test
    fun unreachableServerIsACertificateError() {
        val offline = HttpPost { _, _, _ -> throw IOException("Unable to resolve host") }
        try {
            SamsungCertificates(offline).create(duid, account, SigningProfile(File(Files.createTempDirectory("samsung").toFile(), duid)))
            fail()
        } catch (error: SamsungInstallException) {
            assertEquals(SamsungInstallError.CERTIFICATE_FAILED, error.error)
            assertTrue(error.detail!!.contains("svdca.samsungqbe.com"))
        }
    }

    @Test
    fun serverErrorIsReadable() {
        assertEquals("code=AUTH_FAIL, message=Invalid access token",
            SamsungCertificates.serverError("{\"code\":\"AUTH_FAIL\",\"message\":\"Invalid access token\"}".toByteArray()))
        assertEquals("Service Unavailable", SamsungCertificates.serverError(" Service Unavailable ".toByteArray()))
    }

    @Test
    fun expiredOrFutureCertificatesNeedRenewal() {
        val directory = Files.createTempDirectory("samsung").toFile()
        val key = TestCertificates.rsa()
        val day = 24L * 60 * 60 * 1000
        val now = System.currentTimeMillis()
        // Birkaç dakika sonra başlayan sertifika (telefonun saati biraz geride) kullanılır.
        val soon = TestCertificates.issue("CN=CouchSubs", key.public, notBefore = Date(now + 10 * 60 * 1000), notAfter = Date(now + 365 * day))
        SigningProfile(directory).save(key.private, soon.encoded, soon.encoded, ByteArray(0), duid)
        assertTrue(SigningProfile(directory).isValid())
        assertFalse(SigningProfile(directory).isValid(Date(now + 2 * 365 * day)))
    }

    @Test
    fun rejectedProfileIsSetAside() {
        val parent = Files.createTempDirectory("samsung").toFile()
        val directory = File(parent, duid)
        val key = TestCertificates.rsa()
        val certificate = TestCertificates.issue("CN=CouchSubs", key.public)
        SigningProfile(directory).save(key.private, certificate.encoded, certificate.encoded, ByteArray(0), duid)
        SigningProfile(directory).discard()
        assertFalse(directory.exists())
        assertFalse(SigningProfile(directory).exists)
        assertEquals(1, parent.listFiles()!!.count { it.name.startsWith("$duid.rejected-") })
    }

    @Test
    fun samsungIntermediatesAreBundledAndChainSkipsUnknownIssuers() {
        assertEquals(4, SamsungCertificates.authorities.size)
        val leaf = TestCertificates.issue("CN=CouchSubs", TestCertificates.rsa().public)
        assertEquals(listOf(leaf), SamsungCertificates.chain(leaf))
        // Samsung'un yazar CA'sının verdiği bir sertifika, o ara sertifikayla zincirlenir.
        val samsungAuthor = SamsungCertificates.authorities.first { it.subjectX500Principal != it.issuerX500Principal }
        val issued = TestCertificates.issue("CN=CouchSubs", TestCertificates.rsa().public, issuer = samsungAuthor.subjectX500Principal)
        assertEquals(listOf(issued, samsungAuthor), SamsungCertificates.chain(issued))
        assertNull(SamsungCertificates.chain(issued).getOrNull(2))
    }
}
