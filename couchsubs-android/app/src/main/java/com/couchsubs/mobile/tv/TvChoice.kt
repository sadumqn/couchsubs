// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

/**
 * Altyazı hedefi ekranında TV seçimi (iPhone TargetScreen ile aynı kural): ağda bulunan ya da elle yazılan TV seçilince
 * çeviride açılacak ve önde tutulacak TV o olur ([InstalledTv]; TvSessionLauncher onu kullanır). Eskiden Android'de TV'ler
 * yalnız listeleniyordu; TV uygulaması bu telefondan kurulmadıysa TV hiç açılmıyordu.
 */
object TvChoice {
    /** Seçilen TV; aynı TV yeniden seçildiyse bilinen ADB kapısı ve TV uygulaması sürümü korunur. */
    fun select(current: InstalledTv?, tv: FoundTv): InstalledTv =
        if (current != null && current.brand == tv.brand && current.host == tv.host) current
        else InstalledTv(tv.brand, tv.host)

    /** Gösterilecek liste: kayıtlı TV ağda görünmüyorsa (kapalı olabilir) yine en üstte durur. */
    fun list(found: List<FoundTv>, current: InstalledTv?, currentName: String?): List<FoundTv> {
        if (current == null || found.any { it.brand == current.brand && it.host == current.host }) return found
        return listOf(FoundTv(currentName ?: current.host, current.host, current.brand)) + found
    }

    fun isSelected(tv: FoundTv, current: InstalledTv?): Boolean = current?.brand == tv.brand && current.host == tv.host
}
