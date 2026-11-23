# Community pack import implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let desktop users import local JSON, TXT, and bilingual SRT community translations as CouchSubs game packs.

**Architecture:** Parse and validate files in the Swift and .NET cores, producing matching preview counters and CouchSubs format-1 hashed entries. Native Mac and Windows settings flows select files, show a preview, confirm replacement, atomically install into the existing user pack directory, and refresh their libraries.

**Tech Stack:** Swift 6 package / XCTest; C# .NET 10 / xUnit; SwiftUI; WPF.

**Spec:** `docs/superpowers/specs/2026-11-15-community-pack-import-design.md`

## Global Constraints

- Support `.json`, `.txt`, and `.srt` local imports on macOS and Windows desktop.
- A bilingual SRT cue has exactly two non-empty text lines, English first and Turkish second; other shapes are reported invalid.
- Readable source text is converted with the existing `PackKey` algorithm; generated packs store hash keys and Turkish values, not English source lines.
- Do not bundle, remotely fetch, or publish imported community content.
- Write to the existing user pack directory and reload the installed pack list after success.
- Mobile and TV app import is out of scope.

## Review Focus

- UTF-8 BOM and CRLF input must parse consistently on both platforms; pin with parser tests in Tasks 1 and 2.
- SRT cue separators, invalid timestamps or reversed time ranges, and cues with one or three text lines must be reported invalid without shifting neighboring cues; pin in Tasks 1 and 2.
- Repeated canonical source keys with the same target collapse; conflicting targets exclude that key, even if a later line repeats one target; pin in Tasks 1 and 2.
- Hashed CouchSubs entries must validate 16 hexadecimal characters, normalize keys, and reject non-string/empty targets; pin in Tasks 1 and 2.
- IDs must be stable and path-safe with an 80-character maximum ASCII slug, and installation must not replace an existing user pack without `replacing: true`; pin in Tasks 1 and 2 and verify cancel in Tasks 3 and 4.

---

### Task 1: Swift importer core

**Files:**
- Create: `core/Sources/CouchSubsCore/GamePackImporter.swift`
- Create: `core/Tests/CouchSubsCoreTests/GamePackImporterTests.swift`

**Interfaces:**
- `GamePackImportPreview` contains an optional suggested title, `[String: String]` lowercase hexadecimal-keyed entries, and invalid, duplicate, and conflict counts.
- `GamePackImporter.parse(_:fileName:) throws -> GamePackImportPreview`, `makeID(title:) -> String`, and `install(_:title:directory:replacing:sourceURL:) throws -> URL` are public static APIs; `sourceURL` is optional.
- `install` emits format-1 `{format,id,title,entries}` JSON atomically, rejects a blank title, refuses an existing destination unless `replacing` is true, and refuses a destination equal to `sourceURL`.

- [x] **Step 1: Add failing importer tests** for flat/enveloped JSON, exact duplicate JSON member values/conflicts, malformed format-marked envelopes, format-1 hashed JSON, TXT delimiter precedence (exactly one tab wins; multiple tabs reject; otherwise first ` = `), bilingual SRT and invalid/reversed timestamps/cue shapes, UTF-8 BOM/CRLF, invalid records, duplicate/conflict counters, exact key generation, safe IDs, atomic install/replacement guard, and same-source-path refusal that preserves source bytes.
- [x] **Step 2: Run the importer XCTest filter and verify failures are from the missing API.** Run: `swift test --package-path core --filter GamePackImporterTests`. Expected: compilation fails because `GamePackImportPreview` and `GamePackImporter` do not exist.
- [x] **Step 3: Implement the importer** in `GamePackImporter.swift`. Strip a UTF-8 BOM; parse by extension while preserving JSON object member order; recognize numeric `format` markers before flat pairs and reject malformed/unsupported pack envelopes; read `game`/`title` metadata; hash readable English with `PackKey.key`; parse numeric SRT cue index, strict SRT timestamp with end later than start, and exactly two text lines; and omit conflicted keys. Generate stable `community-<slug>` IDs from lowercase ASCII alphanumeric groups joined by hyphens, capped at 80 characters with `game` as the empty-slug fallback. Use a same-directory temporary file and atomic replacement only when requested; reject an install whose standardized/resolved `sourceURL` equals the destination.
- [x] **Step 4: Run the full isolated Swift importer harness and attempt the package suite.** Run: `docker run --rm --mount "type=bind,source=D:/github/couchsubs-feature-pack-import,target=/repo,readonly" -w /repo swift:6.2 bash /repo/.superpowers/sdd/2026-11-15-community-pack-import/task-1-swift-harness.sh` and `swift test --package-path core`. Expected: importer plus `PackKey` harness tests pass; on Linux the full package may stop before tests because Apple `Combine` is unavailable, which must be recorded as Not Run rather than passed. The design's full native suite remains a Mac verification item.
- [x] **Step 5: Review and commit** with message `feat: add Swift community pack importer`.

### Task 2: .NET importer parity

**Files:**
- Create: `windows/src/CouchSubs.Core/GamePackImporter.cs`
- Create: `windows/tests/CouchSubs.Core.Tests/GamePackImporterTests.cs`

**Interfaces:**
- Matching `GamePackImportPreview` properties and `GamePackImporter.Parse(byte[], string)`, `MakeId(string)`, and `Install(preview, title, directory, replacing, sourcePath = null)` behavior from Task 1.
- Uses `PackKey.Key` and emits the same lowercase hexadecimal keys and format-1 JSON envelope as Swift.

- [x] **Step 1: Add failing xUnit parity tests** for Task 1's inputs/counters, including the golden key `e7f18c8f6d1083ab` for `You fucked up now, boy!`, raw duplicate JSON conflict handling, malformed format-marked envelopes, delimiter precedence, extra-tab rejection, reversed SRT times, and same-source refusal through a parent directory link when file IDs are unavailable.
- [x] **Step 2: Run the focused test and verify failure is from the missing API.** Run: `docker run --rm --mount "type=bind,source=D:/github/couchsubs-feature-pack-import,target=/repo" -w /repo mcr.microsoft.com/dotnet/sdk:10.0-alpine dotnet test windows/tests/CouchSubs.Core.Tests/CouchSubs.Core.Tests.csproj --filter FullyQualifiedName~GamePackImporterTests`. Expected: compile failure for the missing importer API.
- [x] **Step 3: Implement the .NET parser and installer** with behavior matching Task 1 while preserving JSON object member order and rejecting malformed format-marked envelopes; write to a same-directory temporary file, atomically move/replace, and clean up the temporary file on failure.
- [x] **Step 4: Run focused importer tests and the full Core test project** with the same Docker SDK command as Step 2, first with `--filter FullyQualifiedName~GamePackImporterTests`, then without a filter. Expected: focused importer tests and the Core suite pass.
- [x] **Step 5: Review and commit** with message `feat: add .NET community pack importer`.

### Task 3: macOS settings import flow

**Files:**
- Modify: `mac/CouchSubs/UI/SettingsView.swift`
- Modify: `mac/CouchSubs/Resources/Localizable.xcstrings`
- Modify: `mac/project.yml` to grant the sandboxed App Store target read access to user-selected files.

**Interfaces:**
- `GamePacksPage` uses Task 1's parser and installer, passing the selected source URL to `install`. After install it reloads `model.packs` and assigns `model.installedPacks`.
- Keep title edits, preview counts, cancel, and replacement confirmation in the existing SwiftUI settings page; do not add a separate import service to `AppModel`.

- [x] **Step 1: Implement the Mac file picker and preview sheet** in `GamePacksPage`: filter JSON/TXT/SRT, display editable game title and all preview counts, allow cancel, and request explicit confirmation before replacing a same-ID community file.
- [x] **Step 2: Install only after confirmation**, then reload the pack library and update `model.installedPacks`; show localized parse/write errors and retain the preview on failure.
- [x] **Step 3: Add English and Turkish catalog strings** and verify the strings catalog is valid JSON. Run: `python -m json.tool mac/CouchSubs/Resources/Localizable.xcstrings` with output redirected to null. Add the selected-file read entitlement to the App Store target and validate the project YAML.
- [x] **Step 4a: Parse-check `SettingsView.swift` with Swift 6.2.** The Linux Docker syntax check passed.
- [ ] **Step 4b: Build the Mac app with `xcodebuild` and manually check picker, preview, cancel, install, and replacement confirmation on macOS.** Native type-check, build, and UI checks are Not Run because this environment has no macOS toolchain.
- [x] **Step 5: Review and commit** with message `feat: add macOS community pack import UI`.

### Task 4: Windows settings import flow

**Files:**
- Modify: `windows/src/CouchSubs.App/Views/SettingsWindow.xaml`
- Modify: `windows/src/CouchSubs.App/Views/SettingsWindow.xaml.cs`
- Create: `windows/src/CouchSubs.App/Views/GamePackImportWindow.xaml`
- Create: `windows/src/CouchSubs.App/Views/GamePackImportWindow.xaml.cs`
- Modify: `windows/src/CouchSubs.Shell/AppController.cs`
- Modify: `mac/CouchSubs/Resources/Localizable.xcstrings`
- Modify: `docs/superpowers/specs/2026-11-15-community-pack-import-design.md`
- Modify: `docs/superpowers/plans/2026-11-15-community-pack-import.md`
- Test: `windows/tests/CouchSubs.Shell.Tests/AppControllerTests.cs`

**Interfaces:**
- `AppController.ReloadGamePacks()` calls `services.GamePacks.Reload()` and updates `InstalledPacks`.
- The settings window writes via Task 2's importer to `GamePackLibrary.UserDirectory`, passing the selected source path, then calls `ReloadGamePacks()`.
- `FakeServices.GamePacks` can be configured with a library using a temporary user directory for the controller regression test.

- [x] **Step 1: Add a failing controller test** that configures `FakeServices.GamePacks` with a library backed by a temporary directory, writes one valid pack there, calls `ReloadGamePacks()`, and asserts the installed title/count. Run: `dotnet test windows/tests/CouchSubs.Shell.Tests/CouchSubs.Shell.Tests.csproj --filter FullyQualifiedName~ReloadGamePacks`. Expected: compile failure because the method does not exist.
- [x] **Step 2: Implement `ReloadGamePacks()` and make the focused Shell test pass.**
- [x] **Step 3: Add the Game packs tab import button and `OpenFileDialog`** filtered to JSON/TXT/SRT; parse selected bytes and surface parse errors through localized UI.
- [x] **Step 4: Implement `GamePackImportWindow`** with editable title, entry/invalid/duplicate/conflict counts, cancel, install, and a second confirmation before replacement. On install success, call `ReloadGamePacks()`.
- [x] **Step 5: Add English and Turkish localization entries.**
- [x] **Step 6: Run the focused Shell test, full Core and Shell suites, and cross-build the Windows app** in the .NET 10 Docker SDK. Use `dotnet test windows/tests/CouchSubs.Shell.Tests/CouchSubs.Shell.Tests.csproj --filter FullyQualifiedName~ReloadGamePacks`; `dotnet test windows/tests/CouchSubs.Core.Tests/CouchSubs.Core.Tests.csproj`; `dotnet test windows/tests/CouchSubs.Shell.Tests/CouchSubs.Shell.Tests.csproj`; `dotnet build windows/src/CouchSubs.App/CouchSubs.App.csproj -p:EnableWindowsTargeting=true`. All passed. Interactive WPF checks were not run.
- [x] **Step 7: Mark the implementation tasks complete, set the design status to implemented, and run `git diff --check` plus JSON validation of the string catalog.** Native macOS verification remains open under Task 3.
- [x] **Step 8: Review and commit** with message `feat: add Windows community pack import UI`.
