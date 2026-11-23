// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.samsung

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.math.BigInteger
import java.net.ServerSocket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.util.Base64
import kotlin.concurrent.thread

/** sdb çerçeve biçimi ve sahte bir TV'yle kabuk komutu, dosya gönderme (gerçek TV olmadan). */
class SdbTest {
    @Test
    fun frameHeaderIsLittleEndianWithChecksumAndMagic() {
        val bytes = SdbFrame.encode(SdbFrame(SdbFrame.OPEN, 98, 0, "shell:0 getduid\u0000".toByteArray()))
        val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals("OPEN", String(bytes, 0, 4, Charsets.US_ASCII))
        assertEquals(SdbFrame.OPEN, header.getInt(0))
        assertEquals(98, header.getInt(4))
        assertEquals(0, header.getInt(8))
        assertEquals(16, header.getInt(12))
        assertEquals("shell:0 getduid\u0000".toByteArray().sumOf { it.toInt() and 0xFF }, header.getInt(16))
        assertEquals(SdbFrame.OPEN xor -1, header.getInt(20))
        assertEquals(24 + 16, bytes.size)
    }

    @Test
    fun knownCnxnFrameMatchesTizenSdb() {
        // TizenSdb'nin ilk çerçevesi: CNXN, sürüm 0x01000000, maxData 4096, "host::sdb-net-client".
        val bytes = SdbFrame.encode(SdbFrame(SdbFrame.CNXN, 0x01000000, 4096, "host::sdb-net-client".toByteArray()))
        val hex = bytes.copyOfRange(0, 24).joinToString("") { "%02x".format(it) }
        assertEquals("434e584e" + "00000001" + "00100000" + "14000000" + "8b070000" + "bcb1a7b1", hex)
    }

    @Test
    fun frameRoundTripsAndRejectsCorruption() {
        val original = SdbFrame(SdbFrame.WRTE, 5, 7, byteArrayOf(1, 2, 3, (-1).toByte()))
        val bytes = SdbFrame.encode(original)
        val read = SdbFrame.read(ByteArrayInputStream(bytes))
        assertEquals(SdbFrame.WRTE, read.command)
        assertEquals(5, read.arg0)
        assertEquals(7, read.arg1)
        assertArrayEquals(original.payload, read.payload)

        val badMagic = bytes.copyOf().also { it[20] = 0 }
        expectIo { SdbFrame.read(ByteArrayInputStream(badMagic)) }
        val badSum = bytes.copyOf().also { it[24] = 9 }
        expectIo { SdbFrame.read(ByteArrayInputStream(badSum)) }
        expectIo { SdbFrame.read(ByteArrayInputStream(bytes.copyOf(10))) }
    }

    @Test
    fun syncPacketAndCapability() {
        val packet = SdbFrame.syncPacket("SEND", "/opt/usr/apps/tmp/a.wgt".toByteArray())
        assertEquals("SEND", String(packet, 0, 4))
        assertEquals(23, ByteBuffer.wrap(packet, 4, 4).order(ByteOrder.LITTLE_ENDIAN).int)
        assertEquals("/opt/usr/apps/tmp/a.wgt", String(packet, 8, 23))

        val capability = "8csecure_protocol:enabled\nplatform_version:6.5\nsdk_toolpath:/home/owner/share/tmp/sdk_tools\n".toByteArray()
        val parsed = SdbFrame.parseCapability(capability)
        assertEquals("6.5", parsed["platform_version"])
        assertEquals("/home/owner/share/tmp/sdk_tools", parsed["sdk_toolpath"])
        assertEquals(emptyMap<String, String>(), SdbFrame.parseCapability(byteArrayOf(1)))
    }

    @Test
    fun adbPublicKeyHasAndroidLayout() {
        val key = AdbKey.loadOrCreate(File(Files.createTempDirectory("sdb").toFile(), "adbkey"))
        val blob = AdbKey.encodePublicKey(key.publicKey)
        assertEquals(4 + 4 + 256 + 256 + 4, blob.size)
        val buffer = ByteBuffer.wrap(blob).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(64, buffer.getInt(0))
        // n0inv = -1/n mod 2^32
        val n0inv = BigInteger.valueOf(buffer.getInt(4).toLong() and 0xFFFFFFFFL)
        val r32 = BigInteger.ONE.shiftLeft(32)
        assertEquals(r32.subtract(BigInteger.ONE), key.publicKey.modulus.multiply(n0inv).mod(r32))
        val modulus = BigInteger(1, blob.copyOfRange(8, 264).reversedArray())
        assertEquals(key.publicKey.modulus, modulus)
        assertEquals(65537, buffer.getInt(520))
        val payload = String(key.publicKeyPayload(), Charsets.US_ASCII)
        assertTrue(payload.endsWith(" couchsubs@android\u0000"))
        assertArrayEquals(blob, Base64.getDecoder().decode(payload.substringBefore(' ')))
    }

    @Test
    fun keyIsReusedAcrossRuns() {
        val file = File(Files.createTempDirectory("sdb").toFile(), "adbkey")
        val first = AdbKey.loadOrCreate(file)
        val second = AdbKey.loadOrCreate(file)
        assertEquals(first.publicKey.modulus, second.publicKey.modulus)
    }

    @Test
    fun shellCapabilityAndPushAgainstAFakeTv() {
        val tv = FakeSdbTv()
        val key = AdbKey.loadOrCreate(File(Files.createTempDirectory("sdb").toFile(), "adbkey"))
        SdbConnection.connect("127.0.0.1", key, tv.port).use { device ->
            assertEquals("device::fake", device.banner)
            assertEquals("A1B2C3D4E5F6G\n", device.shell("0 getduid"))
            assertEquals("6.5", device.capability()["platform_version"])
            val data = ByteArray(150_000) { (it % 251).toByte() }
            device.push(data, "/opt/usr/apps/tmp/x.wgt")
            assertEquals("/opt/usr/apps/tmp/x.wgt", tv.pushedPath)
            assertArrayEquals(data, tv.pushed)
            // Kanallar sırayla açılıp kapanır; bağlantı ayakta kalır.
            assertEquals("A1B2C3D4E5F6G\n", device.shell("0 getduid"))
        }
        tv.join()
        assertEquals(null, tv.error)
        assertTrue("TV kimlik doğrulama istedi, imza ve açık anahtar geldi", tv.authenticated)
    }

    @Test
    fun tvThatClosesDuringHandshakeIsUnreachable() {
        val server = ServerSocket(0)
        val accepter = thread { repeat(3) { runCatching { server.accept().close() } } }
        val key = AdbKey.loadOrCreate(File(Files.createTempDirectory("sdb").toFile(), "adbkey"))
        expectIo { SdbConnection.connect("127.0.0.1", key, server.localPort) }
        accepter.join(5000)
        server.close()
    }

    private fun expectIo(block: () -> Unit) {
        try {
            block()
            fail("IOException bekleniyordu")
        } catch (expected: IOException) {
        }
    }
}

/**
 * Tek bağlantılık sahte Samsung sdbd'si: önce AUTH ister, sonra `shell:`, `capability:` ve `sync:` (SEND/DATA/DONE)
 * kanallarını yanıtlar. Gerçek sdbd gibi her WRTE'yi OKAY ile onaylar ve kendi WRTE'leri için OKAY bekler.
 */
class FakeSdbTv {
    private val server = ServerSocket(0)
    val port get() = server.localPort
    var error: Throwable? = null
    var authenticated = false
    var pushedPath: String? = null
    var pushed: ByteArray? = null
    private val worker = thread { runCatching { serve() }.onFailure { if (it !is java.io.EOFException) error = it } }

    fun join() {
        worker.join(10_000)
        server.close()
    }

    private fun serve() {
        server.accept().use { socket ->
            val input = socket.getInputStream().buffered()
            val output = socket.getOutputStream()
            fun send(frame: SdbFrame) = output.write(SdbFrame.encode(frame)).also { output.flush() }
            fun next() = SdbFrame.read(input)

            check(next().command == SdbFrame.CNXN)
            send(SdbFrame(SdbFrame.AUTH, 1, 0, ByteArray(20) { it.toByte() }))
            check(next().let { it.command == SdbFrame.AUTH && it.arg0 == 2 && it.payload.size == 256 })
            // TizenSdb gibi: TV açık anahtarı AUTH türü 3 ile ister.
            send(SdbFrame(SdbFrame.AUTH, 3, 0, ByteArray(0)))
            check(next().let { it.command == SdbFrame.AUTH && it.arg0 == 3 })
            authenticated = true
            send(SdbFrame(SdbFrame.CNXN, 0x01000000, 2048, "device::fake".toByteArray()))
            var remoteId = 100
            while (true) {
                val open = next()
                check(open.command == SdbFrame.OPEN) { "OPEN bekleniyordu" }
                val service = String(open.payload).trimEnd('\u0000')
                val local = open.arg0
                val mine = ++remoteId
                send(SdbFrame(SdbFrame.OKAY, mine, local))
                fun write(data: ByteArray) {
                    send(SdbFrame(SdbFrame.WRTE, mine, local, data))
                    val ack = next()
                    check(ack.command == SdbFrame.OKAY && ack.arg0 == local) { "OKAY bekleniyordu" }
                }
                when {
                    service == "shell:0 getduid" -> write("A1B2C3D4E5F6G\n".toByteArray())
                    service == "capability:" -> write("xxplatform_version:6.5\nsdk_toolpath:/opt/usr/apps/tmp\n".toByteArray())
                    service == "sync:" -> {
                        val stream = ByteArrayOutputStream()
                        // İstemcinin yazdıklarını (en çok 2048 baytlık parçalar) birleştir, DONE gelince OKAY dön.
                        while (true) {
                            val frame = next()
                            check(frame.command == SdbFrame.WRTE && frame.payload.size <= 2048)
                            send(SdbFrame(SdbFrame.OKAY, mine, local))
                            stream.write(frame.payload)
                            val all = stream.toByteArray()
                            if (all.size >= 16 && String(all, all.size - 12, 4) == "DONE") {
                                parseSync(all)
                                break
                            }
                        }
                        write(SdbFrame.syncPacket("OKAY", ByteArray(0)))
                    }
                    else -> error("bilinmeyen hizmet $service")
                }
                send(SdbFrame(SdbFrame.CLSE, mine, local))
                val close = next()
                check(close.command == SdbFrame.CLSE)
                if (service == "shell:0 getduid" && pushed != null) return
            }
        }
    }

    private fun parseSync(all: ByteArray) {
        val buffer = ByteBuffer.wrap(all).order(ByteOrder.LITTLE_ENDIAN)
        val data = ByteArrayOutputStream()
        while (buffer.remaining() >= 8) {
            val id = ByteArray(4).also { buffer.get(it) }.toString(Charsets.US_ASCII)
            val length = buffer.int
            // TizenSdb, DONE'un ardından zamanı 4 baytlık veri olarak gönderir.
            val payload = ByteArray(length).also { buffer.get(it) }
            when (id) {
                "SEND" -> pushedPath = String(payload)
                "DATA" -> data.write(payload)
                "DONE" -> { pushed = data.toByteArray(); return }
            }
        }
    }
}
