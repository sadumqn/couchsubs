-- Geçiş (2026-11-15): oyun adı oyları. Uygulamalar oyunu kendileri tanıyınca (paket eşleşmesi ya da kullanıcının
-- seçimi) satırlar kimliksiz, yalnız oyun adıyla gelir; gece paketi aynı adı en az iki kurulum bildirdiyse o oyuna ayrı
-- paket açar (pool-<ad>). Geriye uyumlu: tablo yoksa Worker oy yazmaz, gece paketi yalnız kimlikle ve ortak paketle çalışır.
--
--   cd server/pool && npx wrangler d1 execute couchsubs-pool --remote --file=migrate-2026-11-15-game-votes.sql

CREATE TABLE IF NOT EXISTS game_votes (
  game_key TEXT NOT NULL,
  install TEXT NOT NULL,
  PRIMARY KEY (game_key, install)
);
