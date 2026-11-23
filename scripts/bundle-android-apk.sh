#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Android TV APK'sını masaüstü uygulamalarına gömülecek adla dist/tv-app altına kopyalar:
# couchsubs-androidtv_<sürüm>.apk (sürüm tv-android/app/build.gradle'daki versionName).
# Kullanım: bundle-android-apk.sh <apk>
set -e
# Resolve the input against the caller's cwd before switching to the repository.
[ -f "$1" ] || { echo "APK yok: $1"; exit 1; }
APK="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")/.."
# Gradle allows either quote style. An empty version creates an unusable
# couchsubs-androidtv_.apk that the release validator cannot identify.
VERSION=$(sed -n -e "s/.*versionName '\([0-9.]*\)'.*/\1/p" -e 's/.*versionName "\([0-9.]*\)".*/\1/p' tv-android/app/build.gradle | head -1)
[ -n "$VERSION" ] || { echo "Android TV versionName bulunamadı" >&2; exit 1; }
mkdir -p dist/tv-app
TARGET="dist/tv-app/couchsubs-androidtv_$VERSION.apk"
# Copy first, then atomically replace. The caller can pass an existing APK
# inside dist/tv-app; deleting all *.apk before copying would delete its source.
STAGED=$(mktemp dist/tv-app/.androidtv-XXXXXX)
trap 'rm -f "$STAGED"' EXIT
cp "$APK" "$STAGED"
mv -f "$STAGED" "$TARGET"
trap - EXIT
for old in dist/tv-app/couchsubs-androidtv_*.apk; do
  [ "$old" = "$TARGET" ] || rm -f "$old"
done
echo "Gömülecek APK: $TARGET"
