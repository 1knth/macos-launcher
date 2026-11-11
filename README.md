# Prism

A native macOS launcher for Sequoia (macOS 14+): Raycast-style search with optional AI chat. It's AppKit and SwiftUI with system vibrancy, SF Symbols and system typography, and has no web views or dependencies.

## Build

```bash
make install    # build, copy to /Applications, launch
make run        # build to build/Prism.app and launch it
make test       # unit tests for PrismCore (calculator, ranking, parsers, transforms)
```

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌥Space (falls back to ⌘⇧Space if taken) | Open Prism |
| ⌥⌘V | Clipboard history |
| ⌃⇧T (falls back to ⌃⌥T while Clippy runs) | Capture text from screen (OCR) |
| ⌃⌥P | Pick color from screen |
| ⌃⌥⌘E | Emoji picker |
| ⌃⌥ ← → ↑ ↓ ↩ C ⌫ D F G | Window halves, maximize, center, restore, thirds |
| ⌃⌘ drag / ⌃⌥ drag (or ⌃⌘ right-drag) | Move / resize the active window, from anywhere on screen |

Open **Settings** with **⌘,** while the launcher is open, the footer gear, or the menu bar. Turn extensions (Window Dragging, Window Shortcuts, Clipboard History) on or off, record new global shortcuts with an optional secondary shortcut each (none by default), choose the window move and resize gestures, restore defaults, and check Accessibility and Screen Recording access. Shortcut changes apply immediately and persist across launches; unavailable shortcuts keep the previous binding.

Every open starts at the home search with an empty field. On an empty search, ↑ brings back your last search (keep pressing for older ones). Inside the launcher: ↑↓ to move, ↩ for the primary action, ⌘↩ for the secondary action, ⌘K for every action, Esc to go back, ⌘W to close. Window shortcuts can be turned off with `defaults write app.local.prism windowShortcuts -bool false`.

## Features

- **Search**: apps, commands and System Settings panes, with fuzzy matching ("vsc" finds Visual Studio Code) and frecency ranking. Root search also shows the top file hits. The empty search lists what you opened last under **Last Used**, then your most frequently opened items under **Most Used**.
- **Files**: Spotlight search with image, text and code previews, folder listings and Quick Look thumbnails. Filters: `kind:image|pdf|text|code|folder|video|audio|app|archive`, `ext:swift`, `.pdf`, and `in:contents` (or ⌘T) for content search.
- **Switch Windows**: every window on every Space, searchable by title or app. ↩ jumps to its Space. Window titles need Screen Recording access.
- **Search Menu Items**: run any menu command of the app you were in by name, shown with its shortcut. Needs Accessibility access.
- **Transform Clipboard Text**: change case (UPPER, lower, Title, camelCase, snake_case, kebab-case), trim, sort, dedupe or reverse lines, Base64 and URL encode or decode, format JSON, and count characters and words. ↩ pastes the result and ⌘↩ copies it.
- **Learned searches**: whatever you pick for a query becomes that query's top result, so after choosing Safari for "sfi" once, "sfi" always means Safari. Abbreviations that wouldn't normally match work as aliases too, like "web" for Safari. The learned result shows the query as a tag. Forget one with ⌃F in ⌘K, or clear them all with "Reset Learned Searches".
- **Selected text**: select text in any app before opening the launcher, and the empty search offers actions on it:
  - translate it into your language, on device (macOS 15)
  - transform it, replacing the selection
  - search Google, look it up in Dictionary, or search files
  - calculate it, or open it if it's a URL or path

  It's read through Accessibility without touching the clipboard.
- **Ask AI**: open “Ask AI” or type a question in search and choose “Ask Luna”. Return sends to GPT-6 Luna, and you can ask follow-up questions in the same chat. Chat runs through the Codex CLI (`codex`, installed and signed in with ChatGPT), so it uses your ChatGPT subscription rather than an API key. Luna can search the web. Paste (⌘V) or attach up to 4 screenshots per message. Only the conversation and its attached images are sent; files, search results, clipboard and selected text are not. Chats are saved to `~/Library/Application Support/Prism/chats.json`. ⌘N starts a new chat, ⌘⌫ deletes the current one and ⌘. stops a reply.
- **Claude & GPT usage limits**: search for “usage”, “Claude”, or “GPT” (or open Settings → AI Usage Limits) to view subscription usage bars and reset times. Uses existing Claude Code credentials (macOS Keychain, with a credentials-file fallback) and ChatGPT sign-in from `$CODEX_HOME/auth.json` or `~/.codex/auth.json`. GPT displays Codex limits, not ChatGPT chat limits or API billing. Refresh fetches both providers independently; missing or expired credentials show sign-in guidance. Prism does not store or renew tokens. Provider usage endpoints are undocumented and may change.
- **Calculator**: `2^10`, `50 + 10%`, `20% of 80`, `sqrt(2)`, `5!`, `10 km to mi`, `100 f to c`, `1 GB in MB`, `255 to hex`, `0xff`, `time in tokyo`.
- **Clipboard history**: text, links, images, files and colors with a preview pane. It supports paste, paste as plain text, pin and OCR on copied images. Password-manager copies are skipped. ⌘K lets you pause recording.
- **Color wheel and picker**: HEX, RGB, HSL, HSB and SwiftUI formats, harmonies, shades, WCAG contrast and saved colors.
- **OCR**: Clippy's capture pipeline (ScreenCaptureKit and Vision). It also runs on image files and clipboard images.
- **Window Dragging**: hold ⌃⌘ and drag anywhere on screen to move the active window. Hold ⌃⌘ and right-drag, or ⌃⌥ and drag (the default secondary gesture, for trackpads without right click), to resize it around its center, moving all four corners at once. The click never reaches the app underneath. Both gestures can be changed in Settings → Keyboard Shortcuts. Needs Accessibility access.
- **Extras**: window management, timers (`timer 25m tea`), Keep Awake, web search keywords (`g`, `ddg`, `yt`, `gh`, `wiki`, `maps`, `npm`, `so`, `r`), opening URLs directly, `quit <app>`, UUID and password generators, lorem ipsum, `roll 2d20`, coin flip, lock, sleep, empty trash, appearance toggle, hidden files, eject, and open at login.

## Code

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the code is organized, how data flows through the launcher, and how to add a route or command.

## Permissions

- **Accessibility** is needed for auto-paste, window management and window dragging.
- **Screen Recording** is needed for OCR.

Ad-hoc signed rebuilds can invalidate these permissions. To keep them stable, the build signs with a keychain identity named "Prism Local Signing" when one exists (a self-signed Code Signing certificate is enough), or with `PRISM_SIGNING_IDENTITY`. Clipboard history is stored in `~/Library/Application Support/Prism/` with owner-only permissions.
