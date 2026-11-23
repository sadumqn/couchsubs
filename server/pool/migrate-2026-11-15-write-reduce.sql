-- Geçiş (2026-11-15): D1 yazma kotasını azaltmak için lines ve sightings WITHOUT ROWID olarak yeniden kurulur.
-- Öncesinde `npx wrangler d1 export couchsubs-pool --remote --output yedek.sql` ile yedek alınır.
--
--   * sightings: yalnız en az iki kurulumun gördüğü satırların ve 14 Kasım'dan beri görülen satırların kayıtları taşınır
--     (eski tek-kurulumluk satırların kaydı atılır; ikinci kurulum onları artık doğrulayamaz, kabul edilen kayıp).
--   * lines: yalnız installs>=2 satırlar; tek kurulumlular sightings'te kalır. lines_installs dizini kalkar,
--     lines_title kısmi olur.
-- Yeni kod eski ve yeni tablolarla da çalışır. Yazma maliyeti ≈ taşınan satır sayısı (≈ 53.000).
--
--   cd server/pool && npx wrangler d1 execute couchsubs-pool --remote --file=migrate-2026-11-15-write-reduce.sql

DROP TABLE IF EXISTS lines_new;
DROP TABLE IF EXISTS sightings_new;

CREATE TABLE lines_new (
  key TEXT PRIMARY KEY,
  text TEXT NOT NULL,
  installs INTEGER NOT NULL DEFAULT 0,
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL,
  exported INTEGER NOT NULL DEFAULT 0,
  title_id TEXT,
  game TEXT
) WITHOUT ROWID;

CREATE TABLE sightings_new (
  key TEXT NOT NULL,
  install TEXT NOT NULL,
  PRIMARY KEY (key, install)
) WITHOUT ROWID;

INSERT INTO lines_new(key,text,installs,first_seen,last_seen,exported,title_id,game)
  SELECT key,text,installs,first_seen,last_seen,exported,title_id,game FROM lines WHERE installs>=2;

INSERT INTO sightings_new(key,install)
  SELECT key,install FROM sightings
  WHERE key IN (SELECT key FROM lines WHERE installs>=2 OR substr(last_seen,1,10)>='2026-11-14');

DROP TABLE lines;
DROP TABLE sightings;
ALTER TABLE lines_new RENAME TO lines;
ALTER TABLE sightings_new RENAME TO sightings;
CREATE INDEX lines_title ON lines(title_id) WHERE title_id IS NOT NULL;
