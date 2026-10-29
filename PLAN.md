# LingTip — Implementation Plan

## Context
Build a background macOS menu-bar app that, on a global shortcut, translates the currently selected text (in any browser or desktop app) and shows the result in a floating hover tooltip near the cursor.
- **Default language pair: English → Hebrew**, but the source/target pair is configurable (any language supported by the backend).
- **Backend v1: Claude API** (raw HTTPS via `URLSession`, model `claude-opus-5-5`), behind a `Translator` protocol so other backends can be added later.
  - *Decision log (2026-10-27):* Apple Translation was the first choice, but a spike (`Spike/spike.swift`) showed its 38 supported languages **do not include Hebrew** (`en→he` = `.unsupported`), so it cannot serve the default pair. An `AppleTranslator` may be added later as an offline option for the languages it does support.
- **Location:** `~/Documents/LingTip` (currently empty). Machine: macOS 26.6, only Command Line Tools installed (no Xcode).
- Distribution: personal use, signed locally, **not sandboxed** (needed for Accessibility + synthetic key events); not for the Mac App Store.

## Architecture
```
Hotkey ──► SelectionReader ──► TranslationService ──► TooltipController
(global)   (AX → Cmd+C fallback)  (protocol; Apple impl)  (floating NSPanel + SwiftUI RTL-aware view)
                                         ▲
                       Settings (languages, shortcut, launch at login) ◄── MenuBar UI
```

## Components & files (Swift Package + app bundle script, or Xcode project)
| File | Responsibility |
|---|---|
| `App/LingTipApp.swift` | `@main`, `LSUIElement` menu-bar app (`MenuBarExtra`), wires components |
| `Hotkey/HotkeyManager.swift` | Global shortcut via Carbon `RegisterEventHotKey` (default ⌥⌘T), `KeyCombo` persistence, and a `ShortcutRecorder` view |
| `Selection/SelectionReader.swift` | 1) `AXUIElement` focused element → `kAXSelectedTextAttribute`; 2) fallback: save pasteboard, post Cmd+C via `CGEvent`, poll `changeCount`, read, restore pasteboard |
| `Selection/Permissions.swift` | `AXIsProcessTrustedWithOptions` check + onboarding prompt/deep link to System Settings |
| `Translation/Translator.swift` | `protocol Translator { func translate(_ text: String, from: Locale.Language?, to: Locale.Language) async throws -> Translation }` |
| `Translation/AppleTranslator.swift` | Apple `Translation` framework impl (see risk #1) |
| `Translation/LanguageStore.swift` | Persisted source/target (default `en`→`he`), auto-detect source via `NLLanguageRecognizer`, language-pack availability (`LanguageAvailability`) |
| `UI/TooltipPanel.swift` | Borderless non-activating `NSPanel`, level `.floating`, positioned at mouse (`NSEvent.mouseLocation`), clamped to screen, fade in/out |
| `UI/TooltipView.swift` | SwiftUI: original word, translation (RTL layout when target is he/ar/fa/ur), copy button, loading/error states |
| `UI/SettingsView.swift` | Language pickers, shortcut recorder, launch-at-login (`SMAppService`), "download language pack" button |
| `Support/Info.plist` | `LSUIElement=true`, `NSAccessibilityUsageDescription` |
| `Scripts/build_app.sh` | `swift build -c release`, assemble `.app`, ad-hoc/local codesign |

## Milestones
1. **Skeleton** — menu-bar app, no Dock icon, Quit/Settings items, build script producing a runnable `.app`.
2. **Hotkey + selection** — global shortcut logs selected text from Safari, Chrome, Notes, Slack/Teams (Electron), VS Code, Preview/PDF. Implement AX path, then Cmd+C fallback; permission onboarding.
3. **Translation** — `Translator` protocol + `AppleTranslator`; en→he working end to end; language-pack download flow; source auto-detect; language pair from settings.
4. **Tooltip UI** — floating panel near cursor, RTL rendering, dismiss on Esc / outside click / timeout / new hotkey press; no focus stealing.
5. **Settings & polish** — shortcut recorder, language pickers, launch at login, small LRU cache, graceful errors (no selection, pack missing, unsupported pair, offline).
6. **Hardening** — multi-monitor/Spaces/full-screen apps, clipboard restoration edge cases (images/files on pasteboard), password fields (skip secure input), rapid repeated presses.

## Risks / open technical points
1. **Apple Translation API shape.** On macOS 15 a `TranslationSession` is only obtainable via SwiftUI `.translationTask`; macOS 26 adds a programmatic session initializer. Since this machine is on macOS 26, target macOS 26 and use the programmatic API if available; otherwise host a hidden SwiftUI view that supplies the session. **First task: a 30-line spike to confirm en→he works and which API to use.** Hebrew availability must be verified with `LanguageAvailability`; if unsupported or poor, fall back to the pluggable backend (Claude/DeepL) without UI changes.
2. **Toolchain.** Only Command Line Tools are installed. *Resolved 2026-10-27:* SwiftPM works, but the macOS 26 SDK's SwiftUI macros (`@State`, `#Preview`) need Xcode's macro plugins, which CLT lacks. Decision: build macro-free — view state in `ObservableObject`s, and a Carbon `RegisterEventHotKey` manager + custom recorder instead of the `KeyboardShortcuts` package. Zero dependencies; still compiles if Xcode is installed later. Also: `~/Documents` is a symlink into OneDrive, so both LingTip folders are the same directory.
3. **Selection reliability.** AX fails in Chrome/Electron unless accessibility is enabled for them → the Cmd+C fallback is required, not optional.
4. **Permissions.** Accessibility grant is tied to the binary signature; re-signing may reset it. Use a stable local signing identity.
5. **Secure input fields** block key events; detect `IsSecureEventInputEnabled()` and show a hint.

## Verification
- Unit checks (`./Scripts/test.sh` → `swift run LingTipChecks`; XCTest/Swift Testing need Xcode): settings defaults (auto→he) and reverse-pair resolution, pasteboard save/restore, RTL/script detection, Claude response parsing (incl. refusal/truncation/error), request body shape, LRU cache, KeyCombo. *Status 2026-10-27: 53 passing.*
- Manual matrix (select a word → press shortcut → tooltip with Hebrew appears near cursor, RTL correct): Safari, Chrome, Notes, TextEdit, VS Code, Slack/Teams, Preview PDF, Terminal.
- Confirm clipboard content is unchanged after a Cmd+C-fallback lookup.
- Confirm no Dock icon, app survives relaunch/login, tooltip never steals focus.
- Switch pair in Settings (e.g., en→es, he→en) and confirm it works.

## Deliverables
- `~/Documents/LingTip/PLAN.md` (this plan, copied there once plan mode ends)
- Source tree as above, `README.md` with build/permission instructions.
