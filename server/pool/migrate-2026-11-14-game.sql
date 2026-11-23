-- Geçiş (2026-11-14): havuz satırlarına isteğe bağlı oyun bilgisi. Uygulamalar PS5'in keşif yanıtındaki çalışan oyunu
-- (running-app-titleid, running-app-name) satırla birlikte gönderir; GTA 6 gibi yeni bir oyun çıkınca o oyunun satırları
-- ayrı toplanıp hızlıca paket yapılabilir (tools/packs/poolpack.py).
-- ÇALIŞTIRILMADI. Geriye uyumlu: var olan satırlarda iki sütun NULL kalır; eski uygulamalar oyun göndermez.
-- Worker geçişten önce yayınlansa da çalışır (sütun yoksa eski biçimle yazar), ama oyun bilgisi geçişten sonra tutulur.
--
-- Sıra: önce bu dosya, sonra `npx wrangler deploy`.
--   cd server/pool && npx wrangler d1 execute couchsubs-pool --remote --file=migrate-2026-11-14-game.sql
-- Doğrulama (yalnız okur):
--   cd server/pool && npx wrangler d1 execute couchsubs-pool --remote --command "PRAGMA table_info(lines)"
--
-- D1 maliyeti: ALTER TABLE ve CREATE INDEX satırları tek tek yazmaz; dizin kurulurken var olan satırlar okunur.

ALTER TABLE lines ADD COLUMN title_id TEXT;
ALTER TABLE lines ADD COLUMN game TEXT;
CREATE INDEX IF NOT EXISTS lines_title ON lines(title_id, installs);
