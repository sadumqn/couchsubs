# Community pack import design

**Status:** Implemented

**Date:** 2026-11-15

## Goal

Let a CouchSubs desktop user install a community translation file from their computer as a game pack. Convert readable English-to-Turkish pairs to CouchSubs' existing hashed pack format, so imported packs work with the existing lookup pipeline without storing the English source text.

## Scope

- Add an import action under **Settings → Game packs** on macOS and Windows.
- Support `.json`, `.txt`, and standard `.srt` files.
- Show a preview before writing anything: game title, usable entry count, invalid rows/cues, repeated pairs, and conflicting translations.
- Write a CouchSubs format-1 JSON pack into the existing per-user pack directory, then reload the library and refresh the installed-pack list.
- Keep the source file untouched. Do not bundle, publish, or remotely fetch community translations.
- Phones (follow-up): Android and iPhone add the same action under **Game packs**, with the same parsing rules, preview, replace prompt and 64 MB limit. See *Phones* below. TV apps keep their downloaded-pack flow.

## Accepted input formats

1. **JSON pairs:** a flat object mapping English source text to Turkish text, or the GameTranslator-style `{ "game": "Game title", "subtitles": { "English": "Türkçe" } }` envelope. Also accept an existing CouchSubs format-1 pack (`format`, `id`, `title`, and 16-character hexadecimal `entries`) so users can import a pack already built for CouchSubs.
2. **TXT pairs:** one pair per line. If a line contains exactly one tab, split on that tab; if it contains multiple tabs, reject it. Otherwise split on the first ` = `. Ignore blank lines and lines beginning with `#`.
3. **Bilingual SRT:** parse cue indices and timestamps according to SRT; each cue must have exactly two non-empty text lines after trimming, with English first and Turkish second, and its end timestamp must be later than its start. Report cues with any other shape or invalid timing as invalid. A mono-language SRT cannot provide translations and is not inferred or machine-translated.

For readable source/target pairs, hash the English side with the existing `PackKey` algorithm and store only the resulting key and Turkish value. For an already-hashed CouchSubs pack, validate and preserve its valid entries. Empty keys and translations are rejected. Identical duplicate keys and translations collapse to one entry; if the same key has different Turkish values, omit that key and report it as a conflict rather than choosing silently. Count each repeated identical pair after its first occurrence as a duplicate, even if that key is later conflicted; count each conflicted key once. Preserve repeated JSON object members in input order and pass them through the same duplicate/conflict handling.

A numeric `format` marker identifies a CouchSubs pack envelope. Require its `entries` property to be an object and reject unsupported format values; do not fall back to treating malformed pack metadata as flat subtitle pairs.

## User flow and storage

1. The user clicks **Import pack** and selects one supported file.
2. CouchSubs parses it locally and shows the preview. The user supplies or confirms a game title; JSON metadata may prefill it.
3. The user confirms installation. CouchSubs creates a stable `community-<slug>` ID (lowercase ASCII letters/digits joined with hyphens, at most 80 slug characters; use `game` when the title has no ASCII letters/digits) and writes `<id>.json` under the existing user pack directory using a temporary file and atomic replacement. If that community ID already exists, ask before replacing it; cancel leaves the installed pack untouched. If the selected source path equals the destination, refuse the install so the original file remains intact. The importer never overwrites a bundled pack.
4. Reload the pack library and show the imported pack in the existing installed-pack list. Invalid input or a failed write leaves existing files untouched and gives a localized error.

## Implementation shape

Keep parsing and pack construction in each platform's core (`CouchSubsCore` and `CouchSubs.Core`) so it can be tested without UI. Add small platform-native file-picker and preview/confirmation UI to the existing game-pack settings page. Keep macOS and Windows parsing rules and output envelopes aligned with shared fixtures/golden cases.

## Phones

- **Android:** *Game packs → Import pack* opens the system file picker (Storage Access Framework, `ACTION_OPEN_DOCUMENT`); no storage permission is requested. `core/GamePackImporter.kt` mirrors the Swift importer (same `PackKey` hashing, counts, IDs and envelope; `GamePackImporterTest` repeats the Swift cases). Packs are written to `filesDir/packs-imported`.
- **iPhone:** the same section uses `.fileImporter` (JSON, plain text, SRT) and the shared `CouchSubsCore.GamePackImporter`. Packs are written to `Application Support/CouchSubs/Packs/imported`.
- On both phones imported packs live in their own directory, separate from downloaded packs, so a server refresh never deletes them. `GamePackLibrary` reads that directory last, so an imported pack wins on a line that other packs also have. The section lists imported packs with a delete action. Files stay on the phone and are never sent to the server or the shared line pool.

## Non-goals

- Capture-card, OBS, or other video-input support.
- Downloading, sharing, or curating community packs from CouchSubs servers.
- Import on TV apps.
- Translating mono-language SRT files or guessing which cues are English/Turkish.
- Importing copyrighted translations into the repository or shipping them with CouchSubs.

## Verification plan

- Unit-test JSON/TXT/SRT parsing, timestamps, malformed input, empty values, duplicate/conflicting keys, and exact `PackKey` output.
- Unit-test validation of existing CouchSubs hashed packs, safe IDs/filenames, and replacement/cancel behavior.
- Verify both platform libraries load the generated pack and expose the expected title and entry count after reload.
- Build the macOS and Windows desktop projects and manually check import, preview, cancel, successful install, and reload in each settings screen.

The Windows WPF project cross-build passed in Docker, and the macOS settings file passed a Swift 6.2 syntax check. The native macOS build and interactive import checks on both desktops were not run.
