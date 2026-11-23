// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.samsung

import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.math.BigInteger
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.cert.X509Certificate
import java.util.Date
import javax.security.auth.x500.X500Principal

/** Testlerde Samsung'un yerine sertifika veren küçük bir CA (BouncyCastle; yalnız testlerde). */
object TestCertificates {
    val caKey: KeyPair = rsa()
    val ca: X509Certificate = issue("CN=Test CA", caKey.public, "CN=Test CA", caKey.private, Date(System.currentTimeMillis() - DAY), Date(System.currentTimeMillis() + 365 * DAY))

    private const val DAY = 24L * 60 * 60 * 1000

    fun rsa(): KeyPair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()

    fun issue(subject: String, key: PublicKey, issuer: String = "CN=Test CA", signer: PrivateKey = caKey.private,
              notBefore: Date = Date(System.currentTimeMillis() - DAY), notAfter: Date = Date(System.currentTimeMillis() + 365 * DAY)): X509Certificate =
        issue(subject, key, X500Name(issuer), signer, notBefore, notAfter)

    /** Vereni bir sertifikanın adıyla birebir (aynı DER kodlamasıyla), ör. Samsung'un ara sertifikası. */
    fun issue(subject: String, key: PublicKey, issuer: X500Principal): X509Certificate =
        issue(subject, key, X500Name.getInstance(issuer.encoded), caKey.private,
            Date(System.currentTimeMillis() - DAY), Date(System.currentTimeMillis() + 365 * DAY))

    private fun issue(subject: String, key: PublicKey, issuer: X500Name, signer: PrivateKey, notBefore: Date, notAfter: Date): X509Certificate {
        val builder = JcaX509v3CertificateBuilder(issuer, BigInteger.valueOf(System.nanoTime()), notBefore, notAfter, X500Name(subject), key)
        val holder = builder.build(JcaContentSignerBuilder("SHA256withRSA").build(signer))
        return JcaX509CertificateConverter().getCertificate(holder)
    }
}
