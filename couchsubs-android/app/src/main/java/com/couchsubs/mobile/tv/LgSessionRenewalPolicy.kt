// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import java.util.Locale

internal object LgSessionRenewalPolicy {
    private const val RENEW_INTERVAL_MS = 20 * 3600 * 1000L

    fun storageKey(host: String): String = "tvApp.lgSessionRenewed.${host.trim().lowercase(Locale.ROOT)}"

    fun renewIfDue(
        now: Long,
        lastRenewedAt: Long?,
        saveRenewedAt: (Long) -> Unit,
        renew: () -> Int?,
    ): Int? {
        if (lastRenewedAt != null && now - lastRenewedAt < RENEW_INTERVAL_MS) return null
        val hours = renew() ?: return null
        saveRenewedAt(now)
        return hours
    }
}
