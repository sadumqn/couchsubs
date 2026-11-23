// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public extension String {
    /// Cihazdan, TV'den ya da ağdan gelen çok satırlı yanıtı satırlara böler; LF, CRLF ve tek CR aynı sayılır.
    /// Swift'te "\r\n" tek bir Character olduğundan `split(separator: "\n")` CRLF'li metni hiç bölmez
    /// (Samsung `getduid`, eski Android `pm list` böyle yanıt verir). Boş satırlar korunur; atmak çağıranın işi.
    var deviceLines: [String] {
        split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }
}
