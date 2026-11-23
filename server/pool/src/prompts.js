// SPDX-License-Identifier: AGPL-3.0-only
// "Press/Hold/Tap/Use ... to ..." kumanda ipuçları. Tuş simgesi resimdir; yazı tanıma onu ya hiç okumaz ("Press  to
// open the map") ya da harf/simge kalıntısı olarak okur ("Press @ to", "Hold I LI to", "Press [RB] to take cover").
// Böyle satırlar konuşma değildir; çevrilince tuş kaybolur ve oyuncu hangi tuşa basacağını anlamaz (GTA 6). Uygulamadaki
// ButtonPrompts (core/Sources/CouchSubsCore/Reading.swift, windows/src/CouchSubs.Core/Reading.cs, Android Reading.kt)
// ile aynı kural.

const BUTTONS = new Set([
  "r1", "r2", "r3", "l1", "l2", "l3", "options", "touchpad",
  "✕", "×", "⨯", "✖", "○", "◯", "●", "□", "▢", "◻", "■", "△", "▲", "⨂",
]);
const LOOKALIKES = new Set(["X", "O"]);
const VERBS = new Set(["press", "hold", "tap", "push", "use", "mash", "release"]);
const CONNECTORS = new Set(["and", "or"]);
// Büyük harfle yazılmış kısa İngilizce sözcükler tuş kalıntısı sayılmaz ("HOLD ON TO IT").
const SHORT_WORDS = new Set(["on", "up", "it", "in", "at", "out", "off", "me", "us", "him", "her", "my", "an", "the", "you", "its"]);
// "to"dan sonra eylem yerine bunlar gelirse konuşmadır ("Hold to your course").
const OBJECTS = new Set(["the", "a", "an", "my", "your", "his", "her", "our", "their", "me", "you", "him", "them", "us", "it", "this", "that"]);
const BRACKETS = /^[()[\]{}<>「」]+|[()[\]{}<>「」]+$/gu;

const isButton = (t) => BUTTONS.has(t.toLowerCase());
const hasLetter = (t) => /\p{L}/u.test(t);

// Tuş simgesinin yazı tanımadaki kalıntısı: harfsiz ("@", "•", "9"), tek karakter ("D", "i"; "a" hariç), tuş adı,
// "and"/"or" ya da büyük harf içeren en çok üç karakter ("LI", "RE", "Rd", "RB").
function isIconRemnant(t) {
  if (!hasLetter(t) || isButton(t) || LOOKALIKES.has(t) || CONNECTORS.has(t.toLowerCase())) return true;
  if ([...t].length === 1) return t !== "a";
  return [...t].length <= 3 && /\p{Lu}/u.test(t) && !SHORT_WORDS.has(t.toLowerCase());
}

export function tokens(line) {
  return line.split(/[\s+/]+/u).map((t) => t.replace(BRACKETS, "")).filter(Boolean);
}

// Simgesi okunamamış ya da bozulmuş "Press ... to ..." ipucu.
export function isIconPrompt(line) {
  if (/[!?"“”:]/u.test(line)) return false;
  let all = tokens(line);
  while (all.length && !hasLetter(all[0])) all = all.slice(1);
  if (all.length < 3 || !VERBS.has(all[0].toLowerCase())) return false;
  const to = all.findIndex((t, i) => i > 0 && t.toLowerCase() === "to");
  if (to < 1 || to > 4 || !all.slice(1, to).every(isIconRemnant)) return false;
  const rest = all.slice(to + 1).filter(hasLetter);
  return rest.length >= 1 && all.length - to - 1 <= 10 && !OBJECTS.has(rest[0].toLowerCase());
}

// Kumanda ipucu: "Press ✕ to jump", "Hold R2 to aim" ya da simgesi bozulmuş biçimi (isIconPrompt).
export function isVerbPrompt(line) {
  const all = tokens(line);
  if (all.length >= 2 && all.length <= 10 && VERBS.has(all[0].toLowerCase()) && (isButton(all[1]) || LOOKALIKES.has(all[1]))) return true;
  return isIconPrompt(line);
}
