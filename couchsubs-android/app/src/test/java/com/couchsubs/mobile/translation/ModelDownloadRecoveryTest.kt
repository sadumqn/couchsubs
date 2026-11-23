// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import com.google.mlkit.common.MlKitException
import java.io.IOException
import java.util.concurrent.TimeoutException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Test

class ModelDownloadRecoveryTest {
    @Test fun classifiesWrappedMlKitErrorsAndTimeouts() {
        assertEquals(ModelDownloadProblem.STORAGE,
            ModelDownloadRecovery.classify(IOException("download", MlKitException("disk", MlKitException.NOT_ENOUGH_SPACE))))
        assertEquals(ModelDownloadProblem.NETWORK,
            ModelDownloadRecovery.classify(IOException("download", MlKitException("offline", MlKitException.NETWORK_ISSUE))))
        assertEquals(ModelDownloadProblem.UNAVAILABLE,
            ModelDownloadRecovery.classify(IOException("download", MlKitException("not ready", MlKitException.UNAVAILABLE))))
        assertEquals(ModelDownloadProblem.TIMEOUT,
            ModelDownloadRecovery.classify(IOException("download", TimeoutException("stalled"))))
        assertEquals(ModelDownloadProblem.UNKNOWN, ModelDownloadRecovery.classify(IOException("other")))
    }

    @Test fun retriesOneTransientDownloadAndPreservesSecondFailure() {
        val network = IOException("network", MlKitException("offline", MlKitException.NETWORK_ISSUE))
        var calls = 0
        val result = ModelDownloadRecovery.retryOnce(wait = { assertEquals(1500L, it) }) {
            calls++
            if (calls == 1) throw network
            "downloaded"
        }
        assertEquals("downloaded", result)
        assertEquals(2, calls)

        calls = 0
        val second = IOException("still offline", MlKitException("offline", MlKitException.UNAVAILABLE))
        assertSame(second, assertThrows(IOException::class.java) {
            ModelDownloadRecovery.retryOnce(wait = {}) {
                calls++
                if (calls == 1) throw network
                throw second
            }
        })
        assertEquals(2, calls)
    }

    @Test fun doesNotRetryStorageOrUnknownFailures() {
        for (cause in listOf(
            MlKitException("no space", MlKitException.NOT_ENOUGH_SPACE),
            IllegalStateException("unexpected"))) {
            val failure = IOException("download", cause)
            var calls = 0
            assertSame(failure, assertThrows(IOException::class.java) {
                ModelDownloadRecovery.retryOnce(wait = { throw AssertionError("unexpected wait") }) {
                    calls++
                    throw failure
                }
            })
            assertEquals(1, calls)
        }
    }
}
