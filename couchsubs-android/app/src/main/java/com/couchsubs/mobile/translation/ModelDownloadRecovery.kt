// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import com.google.mlkit.common.MlKitException
import java.net.SocketTimeoutException
import java.util.concurrent.TimeoutException

/** Diagnose the ML Kit download cause rather than treating every failure as lost internet. */
internal enum class ModelDownloadProblem { NETWORK, STORAGE, UNAVAILABLE, TIMEOUT, UNKNOWN }

internal object ModelDownloadRecovery {
    /** ML Kit failures are commonly wrapped in ExecutionException and IOException. */
    fun classify(error: Throwable): ModelDownloadProblem {
        var cause: Throwable? = error
        while (cause != null) {
            when (cause) {
                is TimeoutException, is SocketTimeoutException -> return ModelDownloadProblem.TIMEOUT
                is MlKitException -> return when (cause.errorCode) {
                    MlKitException.NETWORK_ISSUE -> ModelDownloadProblem.NETWORK
                    MlKitException.NOT_ENOUGH_SPACE -> ModelDownloadProblem.STORAGE
                    MlKitException.UNAVAILABLE -> ModelDownloadProblem.UNAVAILABLE
                    else -> ModelDownloadProblem.UNKNOWN
                }
            }
            cause = cause.cause
        }
        return ModelDownloadProblem.UNKNOWN
    }

    /** One bounded retry for transient ML Kit network/service errors; never retry storage/unknown failures. */
    fun <T> retryOnce(wait: (Long) -> Unit = Thread::sleep, action: () -> T): T {
        try {
            return action()
        } catch (error: Exception) {
            if (classify(error) !in setOf(ModelDownloadProblem.NETWORK, ModelDownloadProblem.UNAVAILABLE)) throw error
            wait(1_500)
            return action()
        }
    }
}
