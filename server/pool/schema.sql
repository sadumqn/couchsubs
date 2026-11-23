-- Subtitle pool: oyuncuların okuduğu, paketlerde olmayan İngilizce satırlar.
-- IP, kullanıcı adı ya da PSN bilgisi tutulmaz; yalnız rastgele kurulum kimliği.
--
-- D1 ücretsiz planda günde 100.000 satır yazma: tablo satırı ve her dizin girdisi ayrı sayılır. Bu yüzden iki büyük
-- tablo WITHOUT ROWID (birincil anahtar = tablo, ek dizin yazması yok) ve gereksiz dizin yok.
-- Yerel D1'de ölçülen rows_written (2026-11-18): rowid'li sightings'e yeni görülme 2, WITHOUT ROWID'e 1; rowid'li ve
-- iki dizinli lines'a ekleme 4, installs güncellemesi 3, WITHOUT ROWID'de ikisi de 1. Değişiklik yapmayan
-- INSERT OR IGNORE, koşulu tutmayan UPSERT ve CAS'ı tutmayan kota güncellemesi 0. Kod (src/index.js) ayrıca
-- installs>=SATURATED ya da exported=1 satırın yeni görülmesini yazmaz ve kotayı her istekte değil QUOTA_BLOCK'ta bir yazar.

-- Havuz: yalnız en az iki farklı kurulumun gördüğü satırlar. Tek kurulumun gördüğü satır yalnız sightings'te durur;
-- ikinci kurulum gelince buraya installs=2 ile girer (src/index.js UPSERT).
CREATE TABLE IF NOT EXISTS lines (
  key TEXT PRIMARY KEY,          -- canon(text) SHA-256 ilk 16 hex
  text TEXT NOT NULL,            -- havuza giren (ikinci) kurulumun okuması
  installs INTEGER NOT NULL DEFAULT 0,  -- kaç farklı kurulum gördü (en az 2)
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL,
  exported INTEGER NOT NULL DEFAULT 0,  -- çeviriye alındı mı
  title_id TEXT,                 -- PS5'te çalışan oyunun kimliği (ör. PPSA01234); eski sürümlerde ve bilinmezse NULL
  game TEXT                      -- PS5'in bildirdiği oyun adı; NULL olabilir
) WITHOUT ROWID;
-- Kısmi dizin: kimliksiz satırlar dizine hiç yazılmaz. Gece paketi ve dışa aktarım diğer sorguları tabloyu tarayarak
-- yapar (tablo küçük: yalnız doğrulanmış satırlar; D1 okuma sınırı günde 5 milyon satır).
CREATE INDEX IF NOT EXISTS lines_title ON lines(title_id) WHERE title_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS sightings (
  key TEXT NOT NULL,
  install TEXT NOT NULL,
  PRIMARY KEY (key, install)
) WITHOUT ROWID;

-- Kimliksiz gelen oyun adı (uygulamanın paketten tanıdığı ya da kullanıcının seçtiği): kurulum başına bir oy.
-- Gece paketi (src/autopack.js) bir adı en az iki kurulum oyladıysa ayrı paket yapar. game_key: src/games.js gameKey.
CREATE TABLE IF NOT EXISTS game_votes (
  game_key TEXT NOT NULL,
  install TEXT NOT NULL,
  PRIMARY KEY (game_key, install)
);

CREATE TABLE IF NOT EXISTS quota (
  install TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (install, day)
);
