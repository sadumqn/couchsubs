// SPDX-License-Identifier: AGPL-3.0-only
// Oyun adının karşılaştırma anahtarı. PS5 çalışan oyunu bildirmediği için oyun çoğu zaman uygulamanın kendi tanıdığı
// ya da kullanıcının seçtiği addan gelir; aynı oyun farklı yazılır ("Grand Theft Auto VI", "GTA 6", "gta vi"). Anahtar:
// küçük harf, aksansız, noktalama yok, Roma rakamı sayıya, bilinen uzun adlar kısaltmaya. Uygulamalardaki arama da
// aynı kuralı kullanır (core/.../GameSense.swift GameName.key, GameSense.kt, GameSense.cs).

// Uzun ad → kısaltma (anahtar düzeyinde, sözcük sınırında).
const ALIASES = [
  ["grand theft auto", "gta"],
  ["call of duty", "cod"],
  ["red dead redemption", "rdr"],
  ["ea sports fc", "fc"],
  ["ea sports", ""],
];
const ROMAN = { ii: "2", iii: "3", iv: "4", v: "5", vi: "6", vii: "7", viii: "8", ix: "9", x: "10", xi: "11", xii: "12",
  xiii: "13", xiv: "14", xv: "15", xvi: "16" };
const MAX = 80;

/** Asıl paketi olan oyunun otomatik (havuz) paketinin adına eklenen ek (autopack.js packTitle). Paketten tanınan oyunun
 *  adı uygulamalardan havuza bu ekle dönebilir; havuz adı kaydederken eki atar (index.js gameName). */
export const EXTRA_SUFFIX = " (ek satırlar)";

/** "Grand Theft Auto VI™" → "gta 6"; boşsa "". */
export function gameKey(value) {
  if (typeof value !== "string") return "";
  // Marka işaretleri önce atılır (NFKD "™"yi "TM" yapar).
  let t = value.replace(/[™®©]/g, " ").normalize("NFKD").toLowerCase().replace(/\p{M}/gu, "");
  t = t.replace(/['’`]/g, "").replace(/&/g, " and ").replace(/ı/g, "i");
  t = t.replace(/[^\p{L}\p{N}]+/gu, " ");
  // "gta6" → "gta 6" (harf ve rakam ayrılır).
  t = t.replace(/(\p{L})(\p{N})/gu, "$1 $2").replace(/(\p{N})(\p{L})/gu, "$1 $2");
  const rawWords = t.split(" ").filter(Boolean);
  // Preserve literal franchise letters without changing established sequel keys
  // (e.g. GTA V Premium Edition and Final Fantasy X HD).
  const megaManX = rawWords[0] === "mega" && rawWords[1] === "man" && rawWords[2] === "x";
  let words = rawWords.map((w, i) => {
    const literal = (w === "x" && ((megaManX && i === 2) || rawWords[i + 1] === "men"))
      || (w === "v" && rawWords[i + 1] === "rally");
    return literal ? w : (ROMAN[w] ?? w);
  });
  if (words[0] === "the" && words.length > 1) words = words.slice(1);
  let joined = ` ${words.join(" ")} `;
  for (const [long, short] of ALIASES) joined = joined.split(` ${long} `).join(short ? ` ${short} ` : " ");
  return joined.replace(/\s+/g, " ").trim().slice(0, MAX).trim();
}

/** Paket kimliğinde kullanılan biçim: "gta 6" → "gta-6". */
export function gameSlug(key) {
  return String(key).replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60);
}
