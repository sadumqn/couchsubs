// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.samsung

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import javax.xml.parsers.DocumentBuilderFactory
import org.apache.xml.security.Init
import org.apache.xml.security.signature.XMLSignature
import org.apache.xml.security.signature.XMLSignatureInput
import org.apache.xml.security.utils.resolver.ResourceResolverContext
import org.apache.xml.security.utils.resolver.ResourceResolverSpi

/**
 * Paket imzası: Apache Santuario'nun XML imza doğrulayıcısı (yalnız testlerde) imzayı, bütün dosya özetlerini ve
 * `#prop` nesnesinin C14N 1.1 özetini kabul etmeli. Böylece elle üretilen kanonik biçim bağımsız olarak denetlenir.
 */
class WgtSignerTest {
    private val files = linkedMapOf(
        "config.xml" to "<?xml version=\"1.0\"?>\n<widget id=\"x\"><name>CouchSubs</name></widget>\n".toByteArray(),
        "index.html" to "<!doctype html><script src=\"\$WEBAPIS/webapis/webapis.js\"></script>".toByteArray(),
        "app.js" to "var a = 1 & 2 < 3;\r\n".toByteArray(),
        "icon.png" to ByteArray(3000) { (it * 7).toByte() },
    )

    private fun wgt(extra: Map<String, ByteArray> = emptyMap()): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            for ((name, data) in files + extra) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(data)
                zip.closeEntry()
            }
        }
        return out.toByteArray()
    }

    private val authorKey = TestCertificates.rsa()
    private val author = TestCertificates.issue("CN=CouchSubs", authorKey.public)
    private val distributor = TestCertificates.issue("CN=TizenSDK", authorKey.public)

    /** İmzalı paketin bütün dosyaları, sırasıyla (readEntries imza dosyalarını atladığı için zip baştan okunur). */
    private fun signed(input: ByteArray = wgt(), digest: WgtSigner.Digest = WgtSigner.Digest.SHA512): List<WgtSigner.Entry> {
        val output = WgtSigner.sign(input,
            WgtSigner.Signer(authorKey.private, listOf(author, TestCertificates.ca)),
            WgtSigner.Signer(authorKey.private, listOf(distributor, TestCertificates.ca)), digest)
        val all = ArrayList<WgtSigner.Entry>()
        java.util.zip.ZipInputStream(ByteArrayInputStream(output)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                all.add(WgtSigner.Entry(entry.name, zip.readBytes()))
            }
        }
        return all
    }

    @Test
    fun signaturesComeFirstAndOriginalOrderIsKept() {
        val names = signed().map { it.name }
        assertEquals(listOf("author-signature.xml", "signature1.xml") + files.keys, names)
    }

    @Test
    fun authorAndDistributorSignaturesValidate() {
        val entries = signed().associate { it.name to it.data }
        val authorRefs = validate(entries.getValue("author-signature.xml"), author, entries)
        assertEquals(files.keys.toList() + "#prop", authorRefs)
        val distributorRefs = validate(entries.getValue("signature1.xml"), distributor, entries)
        assertEquals(listOf("author-signature.xml") + files.keys + "#prop", distributorRefs)
    }

    /** Tizen 2.x TV'ler (2016) için SHA-256 (#638): imza ve bütün özetler Santuario ile doğrulanır. */
    @Test
    fun sha256SignaturesValidateAndNameTheirAlgorithms() {
        val entries = signed(digest = WgtSigner.Digest.SHA256).associate { it.name to it.data }
        assertEquals(files.keys.toList() + "#prop", validate(entries.getValue("author-signature.xml"), author, entries))
        assertEquals(listOf("author-signature.xml") + files.keys + "#prop", validate(entries.getValue("signature1.xml"), distributor, entries))
        for (name in listOf("author-signature.xml", "signature1.xml")) {
            val xml = String(entries.getValue(name), Charsets.UTF_8)
            assertTrue(xml.contains("<SignatureMethod Algorithm=\"http://www.w3.org/2001/04/xmldsig-more#rsa-sha256\">"))
            assertTrue(xml.contains("<DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\">"))
            assertTrue(xml.contains("<CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\">"))
            assertFalse(xml.contains("sha512"))
        }
    }

    @Test
    fun defaultStaysSha512() {
        val xml = String(signed().first { it.name == "author-signature.xml" }.data, Charsets.UTF_8)
        assertTrue(xml.contains("xmldsig-more#rsa-sha512"))
        assertTrue(xml.contains("xmlenc#sha512"))
        assertFalse(xml.contains("sha256"))
    }

    /** Bilinen girdi, bilinen özet: Windows'taki WgtSignerTests ve iPhone'daki WgtSignerTests ile aynı değerler. */
    @Test
    fun knownInputGivesKnownDigests() {
        val known = listOf(WgtSigner.Entry("config.xml", "<widget/>".toByteArray()), WgtSigner.Entry("index.html", "<p>merhaba</p>".toByteArray()))
        fun prop(id: String, digest: WgtSigner.Digest) = WgtSigner.digest(WgtSigner.propObject(id, canonical = true).toByteArray(), digest)
        fun signedInfoHash(digest: WgtSigner.Digest): String {
            val canonical = WgtSigner.canonicalSignedInfo(WgtSigner.signedInfo(known, prop("AuthorSignature", digest), digest))
            return java.security.MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray()).joinToString("") { "%02x".format(it) }
        }
        val sha256 = WgtSigner.Digest.SHA256
        assertEquals("EY7MvyaBrTJqCTlmhv1sr4UMN5v2uF5KXyQLW3VbiAA=", WgtSigner.digest(known[0].data, sha256))
        assertEquals("6KF08mjdP2RJgT9dsGq+QSvYwK9Gf1evjAdB8iPWFUM=", WgtSigner.digest(known[1].data, sha256))
        assertEquals("lpo8tUDs054eLlBQXiDPVDVKfw30ZZdtkRs1jd7H5K8=", prop("AuthorSignature", sha256))
        assertEquals("u/jU3U4Zm5ihTMSjKGlGYbWzDfRkGphPPHx3gJIYEJ4=", prop("DistributorSignature", sha256))
        assertEquals("fd26f785814408973737073c499f19c6fce194dad6ec3f3cf3205a640ff5d975", signedInfoHash(sha256))
        val sha512 = WgtSigner.Digest.SHA512
        assertEquals("hSUufNpfpXKCyTwglfu2Zrqtt8W2nXG1K6Vfy7fwYUMDL5lpBwC0EgpxeKlzb9I40BrzBklgo31V7Pl1ZqoOTQ==", WgtSigner.digest(known[0].data, sha512))
        assertEquals("aXbSAVgmAz0GsBUeZ1UmNDRrxkWhDUVGb45dZcNRq429wX3X+x6kaXT3NdNDTSNVTU+ypkysPMGvQY10fG1EWQ==", prop("AuthorSignature", sha512))
        assertEquals("844e74e1b6dd5518e71f58ee694827115d657d623d35bb6711216ac8c74c6e27", signedInfoHash(sha512))
    }

    @Test
    fun oldSignaturesAreReplaced() {
        val stale = mapOf("author-signature.xml" to "eski".toByteArray(), "signature1.xml" to "eski".toByteArray())
        val entries = signed(wgt(stale))
        assertEquals(2, entries.count { it.name.endsWith(".xml") && it.name != "config.xml" })
        val map = entries.associate { it.name to it.data }
        validate(map.getValue("signature1.xml"), distributor, map)
    }

    @Test
    fun signatureXmlHasTizenRolesAndChainWithoutRoot() {
        val entries = signed().associate { it.name to String(it.data, Charsets.UTF_8) }
        val authorXml = entries.getValue("author-signature.xml")
        val distributorXml = entries.getValue("signature1.xml")
        assertTrue(authorXml.startsWith("<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\" Id=\"AuthorSignature\">"))
        assertTrue(authorXml.contains("<dsp:Role URI=\"http://www.w3.org/ns/widgets-digsig#role-author\"></dsp:Role>"))
        assertTrue(distributorXml.contains("Id=\"DistributorSignature\""))
        assertTrue(distributorXml.contains("#role-distributor"))
        assertFalse(authorXml.startsWith("<?xml"))
        // Zincir verildiği gibi yazılır (yaprak önce); çağıran kökü koymaz (SamsungCertificates.chain).
        val document = parse(authorXml.toByteArray())
        val certificates = document.getElementsByTagNameNS("http://www.w3.org/2000/09/xmldsig#", "X509Certificate")
        assertEquals(2, certificates.length)
        val first = CertificateFactory.getInstance("X.509").generateCertificate(
            ByteArrayInputStream(Base64.getMimeDecoder().decode(certificates.item(0).textContent.trim()))) as X509Certificate
        assertEquals(author, first)
        assertTrue(certificates.item(0).textContent.startsWith("\n"))
    }

    @Test
    fun attributeEscapingFollowsCanonicalXml() {
        assertEquals("a&amp;b&lt;c&quot;d&#x9;&#xA;&#xD;>", WgtSigner.attr("a&b<c\"d\t\n\r>"))
    }

    /** İmzayı doğrular; doğrulanan referansların URI'leri döner. */
    private fun validate(xml: ByteArray, certificate: X509Certificate, entries: Map<String, ByteArray>): List<String> {
        val document = parse(xml)
        val root = document.documentElement
        val prop = root.getElementsByTagNameNS("http://www.w3.org/2000/09/xmldsig#", "Object").item(0) as Element
        prop.setIdAttributeNS(null, "Id", true)
        Init.init()
        val signature = XMLSignature(root, "", false)
        // Paketin dosyaları (URI = zip'teki ad) testteki haritadan okunur; "#prop" Santuario'nun kendi çözücüsüyle.
        signature.addResourceResolver(object : ResourceResolverSpi() {
            override fun engineCanResolveURI(context: ResourceResolverContext) =
                context.uriToResolve != null && !context.uriToResolve.startsWith("#") && context.uriToResolve in entries
            override fun engineResolveURI(context: ResourceResolverContext) =
                XMLSignatureInput(entries.getValue(context.uriToResolve))
        })
        val valid = signature.checkSignatureValue(certificate.publicKey)
        val info = signature.signedInfo
        val uris = (0 until info.length).map { info.item(it).uri }
        val broken = (0 until info.length).filter { runCatching { !info.getVerificationResult(it) }.getOrDefault(true) }.map { uris[it] }
        assertTrue("imza geçersiz; bozuk referanslar: $broken", valid)
        return uris
    }

    private fun parse(xml: ByteArray) = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        .newDocumentBuilder().parse(ByteArrayInputStream(xml))
}
