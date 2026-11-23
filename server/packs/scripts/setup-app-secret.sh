#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# Paket isteklerinin imza sırrını (PACKS_APP_SECRET) kurar; değer hiçbir yere yazdırılmaz:
#   1. ~/.config/couchsubs/packs.env (chmod 600) içinde yoksa rastgele 32 bayt (hex) üretir, varsa olanı kullanır.
#   2. Worker sırrı: npx wrangler secret put APP_SECRET (stdin'den).
#   3. GitHub Actions sırrı: gh secret set PACKS_APP_SECRET (stdin'den).
#   4. packs.env'i iCloud Drive/CouchSubs-anahtarlar klasörüne yedekler.
# Kullanım (sahibin oturumlarıyla): server/packs/scripts/setup-app-secret.sh [--no-worker] [--no-github]
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ENV_FILE="${PACKS_ENV:-$HOME/.config/couchsubs/packs.env}"
BACKUP="$HOME/Library/Mobile Documents/com~apple~CloudDocs/CouchSubs-anahtarlar"
REPO="${PACKS_REPO:-yorulmazsinan/couchsubs}"
WORKER=1
GITHUB=1
for arg in "$@"; do
  case "$arg" in
    --no-worker) WORKER=0 ;;
    --no-github) GITHUB=0 ;;
    *) echo "bilinmeyen seçenek: $arg" >&2; exit 64 ;;
  esac
done

mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"
if ! grep -q '^PACKS_APP_SECRET=.\+' "$ENV_FILE"; then
  SECRET="$(openssl rand -hex 32)"
  grep -v '^PACKS_APP_SECRET=' "$ENV_FILE" > "$ENV_FILE.tmp" || true
  printf 'PACKS_APP_SECRET=%s\n' "$SECRET" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  unset SECRET
  echo "✓ Yeni uygulama sırrı üretildi: $ENV_FILE"
else
  echo "✓ Var olan uygulama sırrı kullanılıyor: $ENV_FILE"
fi
value() { grep '^PACKS_APP_SECRET=' "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '\n'; }

if [ "$WORKER" = 1 ]; then
  (cd "$ROOT/server/packs" && value | npx wrangler secret put APP_SECRET >/dev/null)
  echo "✓ Worker sırrı (APP_SECRET) konuldu"
fi
if [ "$GITHUB" = 1 ]; then
  value | gh secret set PACKS_APP_SECRET -R "$REPO" >/dev/null
  echo "✓ GitHub sırrı (PACKS_APP_SECRET) konuldu"
fi
if [ -d "$BACKUP" ]; then
  cp "$ENV_FILE" "$BACKUP/packs.env"
  chmod 600 "$BACKUP/packs.env"
  echo "✓ Yedek: $BACKUP/packs.env"
else
  echo "! Yedek klasörü yok: $BACKUP" >&2
fi
