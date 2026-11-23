# GTA 6 için başlangıç terim ve hitap sözlüğü: GTA V paketindeki (core/.../Resources/packs/gta-v.json.gz) çevirilerden,
# API'siz üretilir. Paket İngilizceyi taşımaz, yalnız anahtarı (canon SHA-256) taşır; burada bilinen İngilizce ifadelerin
# anahtarı hesaplanıp paketteki Türkçesi okunur. Tek sözcüklük girişler bağlamsız olabileceğinden ("club" = "Sopa")
# her terim için paketteki karşılık kanıt olarak yazılır, seçilen karşılık elle belirlenir (CHOICES).
# Kullanım: gta6glossary.py [gta-v.json.gz] [çıktı.json]   (varsayılan: glossary/gta6.json)
import collections, gzip, json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as c

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "core/Sources/CouchSubsCore/Resources/packs/gta-v.json.gz"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent / "glossary/gta6.json"

# (İngilizce, seçilen Türkçe, not). Türkçe None ise paketteki karşılık olduğu gibi alınır (noktalama atılır).
CHOICES = {
    "address": [
        ("dude", "ahbap", None), ("man", "dostum", "cümle sonunda 'adamım' da olur (GTA V'te ikisi de sık)"),
        ("bro", "kardeş", None), ("homie", "kardeşim", None), ("buddy", "dostum", None),
        ("my friend", "dostum", None), ("nigga", "kanka", "küfür değil hitap; GTA V'te de 'kanka'"),
        ("sir", "efendim", "resmî; polisler ve görevliler"), ("ma'am", "hanımefendi", None), ("boss", "patron", None),
        ("honey", "canım", None), ("baby", "bebeğim", "sevgililer arası hitapta"), ("partner", "ortak", None),
        ("kid", "evlat", None), ("son", "evlat", None),
    ],
    "insults": [
        ("fuck", "siktir", None), ("shit", "siktir", "ünlem; nesne olarak 'bok'"), ("damn", "lanet olsun", None),
        ("what the fuck", "bu da ne amına koyayım", None), ("holy shit", "ha siktir", None),
        ("son of a bitch", "orospunun evladı", None), ("fuck you", "siktir git", None), ("fuck off", "siktir git", None),
        ("motherfucker", "orospu çocuğu", None), ("asshole", "orospu çocuğu", "hafif bağlamda 'pislik'"),
        ("bitch", "orospu", "erkeğe hakarette 'kaltak/ibne' değil, bağlama göre 'pislik'"), ("pussy", "korkak", None),
        ("idiot", "geri zekalı", None), ("fool", "salak", None), ("jerk", "lavuk", None), ("punk", "serseri", None),
        ("snitch", "muhbir", None), ("rat", "sıçan", "ihbarcı anlamında"),
    ],
    "crime": [
        ("cops", "polisler", "argoda 'aynasızlar'"), ("pigs", "domuzlar", None), ("feds", "federaller", None),
        ("heist", "soygun", None), ("crew", "ekip", None), ("gang", "çete", None), ("job", "iş", None),
        ("score", "vurgun", "soygun bağlamında; GTA V'te arayüzde 'SKOR'"), ("getaway car", "kaçış aracı", None),
        ("stash", "zula", None), ("weed", "ot", None), ("meth", "met", "GTA V'te 'uyuşturucu' da kullanılmış"),
        ("coke", "kokain", None), ("dealer", "satıcı", None), ("armored truck", "zırhlı araç", None),
        ("safehouse", "sığınak", "GTA V'te bazen 'ev'"), ("ammo", "mühimmat", None), ("shotgun", "pompalı tüfek", None),
        ("pistol", "tabanca", None), ("rifle", "tüfek", None), ("lawyer", "avukat", None), ("prison", "hapishane", None),
        ("bail", "kefalet", None), ("parole", "şartlı tahliye", None), ("cartel", "kartel", None),
    ],
    "game_ui": [
        ("wasted", "ÖLDÜN", None), ("busted", "YAKALANDIN", None), ("mission passed", "Görev Başarılı", None),
        ("mission failed", "Görev Başarısız", None), ("wanted level", "Aranma Seviyesi", None),
        ("lose the cops", "Polislerden kurtul.", None), ("get in the car", "Arabaya bin.", None),
        ("checkpoint", "Kontrol Noktası", None), ("destination", "Varış Yeri", None), ("waypoint", "Varış Noktası", None),
        ("objective", "Hedef", None),
    ],
    "phrases": [
        ("come on", "hadi", None), ("let's go", "gidelim", None), ("hurry up", "acele et", None),
        ("watch out", "dikkat", None), ("shut up", "kapa çeneni", None), ("calm down", "sakinleş", None),
        ("take it easy", "ağır ol", None), ("get down", "yere yat", None), ("freeze", "olduğun yerde kal", None),
        ("copy that", "anlaşıldı", None), ("you got it", "tamamdır", "GTA V'teki 'Artık senin!' bağlama uymaz"),
        ("see ya", "görüşürüz", None), ("follow me", "beni takip et", None),
    ],
    "places": [
        ("strip club", "striptiz kulübü", None), ("gas station", "benzinci", None), ("liquor store", "içki dükkânı",
        "GTA V'te 'Likör Dükkanı' (yanlış çeviri)"), ("downtown", "şehir merkezi", None), ("docks", "rıhtım", None),
        ("swamp", "bataklık", None), ("marina", "marina", None), ("yacht", "yat", None), ("mansion", "malikâne", None),
    ],
}

# Olduğu gibi kalan adlar: GTA 6'nın fragmanlarda görünen kişi ve yer adları, markalar, GTA V'ten kalan kurumlar.
KEEP = ["Lucia", "Jason", "Vice City", "Leonida", "Leonida Keys", "Grassrivers", "Port Gellhorn", "Ambrosia",
        "Mount Kalaga", "Los Santos", "Liberty City", "San Andreas", "Rockstar", "FIB", "IAA", "LSPD", "VCPD",
        "Ammu-Nation", "Lifeinvader", "Pay 'n' Spray", "Cluckin' Bell", "Burger Shot", "Sprunk", "eCola"]

# Hitap sıklığı: oyunun ses tonunu gösterir (yalnız tam satırlarda sayılır).
ADDRESS_WORDS = ["dostum", "adamım", "kanka", "kardeşim", "lan", "ahbap", "evlat", "oğlum", "patron", "bebeğim",
                 "tatlım", "efendim", "hanımefendi", "birader", "moruk", "aynasızlar", "polisler"]


def main():
    pack = json.load(gzip.open(SRC))
    table = {**pack["segments"], **pack["entries"]}

    def evidence(en):
        k = c.key(en)
        return table.get(k) if k else None

    sections, found = {}, 0
    for section, items in CHOICES.items():
        rows = []
        for en, tr, note in items:
            seen = evidence(en)
            found += seen is not None
            row = {"en": en, "tr": tr or re.sub(r"[.!?,…]+$", "", seen or "").strip(), "gta_v": seen}
            if note:
                row["note"] = note
            rows.append(row)
        sections[section] = rows

    words = collections.Counter()
    for v in pack["entries"].values():
        words.update(re.findall(r"[a-zçğıöşüâî]+", v.lower()))
    freq = {w: words[w] for w in ADDRESS_WORDS}

    out = {
        "game": "Grand Theft Auto VI",
        "source": f"{pack['id']} paketi ({pack['source']}), {len(pack['entries'])} satır; API kullanılmadı",
        "register": "Varsayılan 'sen'; 'siz' yalnız resmî hitapta (polis, görevli, yabancı yetişkin). Küfür aynı "
                    "şiddette kalır. Arayüz yazıları (ÖLDÜN, YAKALANDIN) GTA V paketindeki gibi büyük harf.",
        "keep": KEEP,
        **sections,
        "address_frequency_gta_v": freq,
        "found_in_gta_v": found,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(OUT, "terimler", sum(len(v) for v in sections.values()), "GTA V'te bulunan", found)


def prompt_block(path):
    """translate/poolpack için: sözlüğü modelin okuyacağı kısa metne çevirir."""
    g = json.loads(Path(path).read_text(encoding="utf-8"))
    parts = [f"Game: {g['game']}. {g['register']}", "Keep these names as is: " + ", ".join(g["keep"]) + "."]
    for section in CHOICES:
        terms = "; ".join(f"{r['en']} = {r['tr']}" for r in g.get(section, []))
        if terms:
            parts.append(f"{section}: {terms}.")
    return "\n".join(parts)


if __name__ == "__main__":
    main()
