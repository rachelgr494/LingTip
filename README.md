# LingTip

A macOS menu-bar app: select text in any app (browser, editor, Slack, PDF…), press a shortcut, and a tooltip near the cursor shows the translation. Default pair is **English → Hebrew**; any pair works, and Hebrew selections are translated back to English automatically.

Translation is done by the Claude API. No third-party dependencies; builds with just the Command Line Tools.

## Build & run

```bash
./Scripts/install.sh      # builds, installs to /Applications, launches
./Scripts/run.sh          # dev loop: builds build/LingTip.app, (re)launches it in place
./Scripts/test.sh         # unit checks (swift run LingTipChecks)
```

LingTip is a **menu-bar app**: it has no Dock icon and no main window. After launching, look for the speech-bubble icon at the right of the menu bar. Until an API key is saved and Accessibility is granted, launching (or double-clicking the app again) opens the Settings window. On a MacBook with a notch, if the menu bar is crowded the icon can be hidden behind the notch; quit some other menu-bar apps or use a tool like Bartender/Ice.

Requires macOS 14+ and Swift 6. The Command Line Tools are enough: the package deliberately avoids SwiftUI's `@State`, `#Preview`, XCTest and Swift Testing, whose macro plugins ship only with Xcode. Tests are a plain executable (`Sources/LingTipChecks`) that `@testable import`s `LingTipCore`.

## First-run setup

1. **Accessibility permission.** On first launch macOS asks to allow LingTip to control the computer. Enable it under *System Settings → Privacy & Security → Accessibility*. LingTip uses it to read the selected text and, for apps that don't expose their selection, to send ⌘C.
2. **Claude API key.** Open the menu-bar icon → *Settings…* → paste an API key from <https://console.anthropic.com/> and click *Save to Keychain*. (A claude.ai / Claude Code subscription does not include API access; the API is billed separately per token. A single-word lookup costs a fraction of a cent.)
   Alternatively, launch with `ANTHROPIC_API_KEY` set in the environment.
3. Click *Test connection*. You should see `OK — hello → שָׁלוֹם`.

## Use

Select a word or phrase anywhere, press **⌥⌘T** (changeable in Settings). The tooltip shows the translation, transliteration, part of speech, up to three alternative senses, and a copy button. Long results grow up to 60% of the screen height and then scroll (scroll with the pointer over the tooltip). It dismisses on click, scroll or keypress in another app, Esc, or after a timeout (it waits while the pointer is over it).

## How it works

```
⌥⌘T ──► SelectionReader ──► ClaudeTranslator ──► TooltipController
         AX API, then ⌘C      /v1/messages,         non-activating NSPanel,
         with clipboard       structured JSON        RTL-aware SwiftUI
         save/restore         output
```

- `Sources/LingTip/` — the thin app target: `@main`, app delegate, menu-bar menu.
- `Sources/LingTipCore/Selection/` — Accessibility (`kAXSelectedTextAttribute`) first; falls back to a synthesized ⌘C that snapshots and restores the clipboard. Skips the fallback in secure (password) fields.
- `Sources/LingTipCore/Translation/` — `Translator` protocol; `ClaudeTranslator` is the only backend today. Model and effort are in `ClaudeTranslator.body`. Results are cached (LRU, 200 entries).
- `Sources/LingTipCore/Hotkey/` — Carbon `RegisterEventHotKey` plus a click-to-record shortcut field.
- `Sources/LingTipCore/UI/` — tooltip panel, settings window, `Brand` palette.
- `Support/Icons/` — app icon, menu-bar template icon and settings logo, all generated from `LingTip Translation Logo.png` by `Scripts/make_icons.swift` (re-run it if the logo changes: see the usage line at the top of that file, then `iconutil -c icns Support/Icons/AppIcon.iconset -o Support/Icons/AppIcon.icns`).

## Known limitations

- **Ad-hoc signature.** Each rebuild changes the binary's code hash, so macOS may ask you to re-enable Accessibility and re-approve Keychain access after rebuilding. For a stable identity, create a self-signed *Code Signing* certificate in Keychain Access and build with `CODESIGN_IDENTITY="Your Cert Name" ./Scripts/run.sh`.
- Some canvas-based apps (Google Docs, Figma) may return nothing via Accessibility and rely on the ⌘C fallback, which needs the app to honor ⌘C for the selection.
- Apple's on-device Translation framework was evaluated (`Spike/`) but does not support Hebrew, so there is no offline mode yet.
