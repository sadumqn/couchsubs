#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# libchiaki'nin görüntü alıcısını paket kaybı benzetiminde iki kez çalıştırır ve yan yana yazar:
#   ONCE:  chiaki-stream-recovery.patch olmadan (16 paketlik gönderme tamponu, 8 sn'lik görüntü bekçisi)
#   SONRA: third-party/patches altındaki bütün yamalarla (yamadaki tampon boyu, 15 sn'lik bekçi)
# Yama değiştiğinde çalıştırılır; SONRA'da "kopma" ve temiz ağda "kuyr-at" sıfır kalmalı (-c ile denetlenir).
# Sütunlar (saat başına): FEC-hata, IDR isteği, gelen IDR, bozuk kare bildirimi, tampon taşması; IDR beklerken
# toparlanma süresi (ortalama, en uzun); 250 ms'den uzun donma sayısı ve en uzunu; bekçinin oturumu kapatması;
# görüntülü geçen süre; ulaştığı halde sıralama kuyruğunun attığı paket.
#
# Kullanım: tools/chiaki-sim/run.sh [-n koşu] [-m dakika] [-s senaryo] [-v]
# Gerekenler: cc, patch; third-party/chiaki-ng (git submodule update --init third-party/chiaki-ng).
set -e
cd "$(dirname "$0")/../.."
SRC=third-party/chiaki-ng
[ -f "$SRC/lib/src/videoreceiver.c" ] || { echo "chiaki-ng kaynağı yok: git submodule update --init $SRC" >&2; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
for tree in once sonra; do
  mkdir "$WORK/$tree"
  cp -R "$SRC/lib" "$WORK/$tree/lib"
done
for p in third-party/patches/chiaki-*.patch; do
  case "$p" in
    *stream-recovery*) trees="sonra" ;;
    *) trees="once sonra" ;;
  esac
  for tree in $trees; do
    patch -d "$WORK/$tree" -p1 -s -f < "$p"
  done
done
SIZE=$(sed -n 's/^#define TAKION_SEND_BUFFER_SIZE //p' "$WORK/sonra/lib/src/takion.c")
build() { # ad, ağaç, tampon, ek bayrak
  cc -O2 -Wall -I "$WORK/$2/lib/include" -DVARIANT="\"$1\"" -DSEND_BUFFER_SIZE="$3" $4 tools/chiaki-sim/sim.c \
    "$WORK/$2/lib/src/videoreceiver.c" "$WORK/$2/lib/src/reorderqueue.c" -o "$WORK/sim-$2" -lm
}
build "ONCE (stream-recovery yamasi yok)" once 16 ""
build "SONRA (butun yamalar)" sonra "$SIZE" "-DAPP_NEW"
"$WORK/sim-once" "$@"
echo
"$WORK/sim-sonra" -c "$@"
