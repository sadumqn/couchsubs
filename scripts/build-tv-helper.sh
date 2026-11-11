#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
# Mac uygulamasına gömülen Samsung ve Android TV kurulum yardımcısını (windows/src/CouchSubs.TvHelper) Native AOT ile
# derler: dist/tv-helper/couchsubs-tv-helper (Apple Silicon ve Intel dilimleri tek evrensel dosyada). Ardından XML
# imzasının AOT ile çalıştığını sınar. Yalnız bir mimari için: TV_HELPER_RIDS="osx-arm64".
set -e
setopt pipefail
cd "${0:A:h}/.."

OUT=dist/tv-helper
RIDS=(${=TV_HELPER_RIDS:-osx-arm64 osx-x64})
rm -rf "$OUT" "$OUT"-osx-*(N)
SLICES=()
for RID in $RIDS; do
  dotnet publish windows/src/CouchSubs.TvHelper -c Release -r "$RID" -o "$OUT-$RID" -nologo -v q
  [[ -x "$OUT-$RID/couchsubs-tv-helper" ]] || { echo "Yardımcı derlenemedi ($RID)."; exit 1; }
  SLICES+=("$OUT-$RID/couchsubs-tv-helper")
done
mkdir -p "$OUT"
lipo -create "${SLICES[@]}" -output "$OUT/couchsubs-tv-helper"
rm -rf "$OUT"-osx-*(N)
[[ -x "$OUT/couchsubs-tv-helper" ]] || { echo "Yardımcı derlenemedi."; exit 1; }
# Homebrew'un kaynaktan derlenmiş .NET'i Homebrew kitaplıklarına bağlar; öyle bir dosya başka Mac'te açılmaz.
# Yayın derlemesi Microsoft'un .NET'iyle (actions/setup-dotnet) yapılır. Yerel sınama için ALLOW_LOCAL_LIBS=1.
if otool -L "$OUT/couchsubs-tv-helper" | grep -q /opt/homebrew && [[ -z "$ALLOW_LOCAL_LIBS" ]]; then
  echo "Yardımcı Homebrew kitaplıklarına bağlı; Microsoft'un .NET SDK'sıyla derleyin."; exit 1
fi
# Sınama bu Mac'in işlemcisindeki dilimle çalışır.
"$OUT/couchsubs-tv-helper" self-test | grep -q '"event":"done"' || { echo "Yardımcı sınaması başarısız."; exit 1; }
echo "Hazır: $OUT/couchsubs-tv-helper ($(lipo -archs "$OUT/couchsubs-tv-helper"), $(du -h "$OUT/couchsubs-tv-helper" | cut -f1))"
