# Architecture

Prism is a Swift package with two targets:

- **`PrismCore`**: pure logic that only uses Foundation: calculator, fuzzy ranking, learned queries, query parsers, text transforms, OCR line assembly and usage math. It has no AppKit and no global state, and everything in it is unit-tested in `Tests/PrismCoreTests`.
- **`Prism`**: the app, made of AppKit and SwiftUI on top of `PrismCore`.

## Layers

Each folder in `Sources/Prism` has one job:

| Folder | Responsibility | Uses |
|---|---|---|
| `App/` | Launch, the composition root (`AppServices`), global shortcuts, the menu bar item and snapshot renders | everything |
| `UI/` | The launcher's SwiftUI views, shared components and Settings | Launcher, Features, Services, Platform |
| `Launcher/` | The vocabulary shared by every route (`Route`, `ResultItem`, `ResultProvider`), the state machine that composes the providers (`LauncherState`), the window, and the ranking stores | Results, feature models, Services, Platform |
| `Results/` | One `ResultProvider` per list route, which turns services into rows | Launcher's types, Services, Platform |
| `Features/` | Self-contained screens with their own model and view: Chat, Usage and Color Wheel | Services, Platform |
| `Services/` | System integrations and data stores: apps, files, clipboard, windows, OCR, timers and more. They don't know about the launcher | Platform, PrismCore |
| `Platform/` | Thin wrappers over macOS: Accessibility, paste, hotkeys, toast, shell and `DefaultsKey` | nothing in the app |

The hard rule is that **`Services/` and `Platform/` never depend on the launcher**. When a service has to affect it, for example hiding the launcher before a screen capture, the service exposes a callback such as `OCRController.willCapture` or `Toast.inlinePresenter`, and `AppServices` or `LauncherController` wires it up.

## The launcher's data flow

```
key press / typing / data change
        │
        ▼
LauncherState ── refresh() ──▶ provider(for: route).items(for: query)
        │                                │
        │◀────────── [ResultItem] ───────┘
        ▼
LauncherView renders rows ──▶ Return, a shortcut, a click or ⌘K
        │
        ▼
LauncherState.perform(action, on: item)
   records frecency and learned queries, hides if `action.dismiss`, runs `action.run`
```

- **`Route`** is a screen. Routes stack: `push` covers the current route, and Esc or ⌫ on an empty field pops back. `Route.layout` says whether the route shows a list, a list with a detail pane, or a custom view (chat, usage, color wheel).
- **`ResultItem`** is an immutable row value that is rebuilt on every refresh. Everything a row can do is an `ItemAction`. The first action runs on Return; the others run from their shortcut or the ⌘K panel.
- **`ResultProvider`** builds the rows for one route. It owns that route's state, such as a Spotlight query, the window snapshot taken in `activate()`, or the text being transformed, and it stops live work in `deactivate()`. Providers reach the launcher only through the narrow `LauncherNavigator` protocol (`push`, `flash`, `refresh`, `query`).
- A provider subscribes to its own data sources when it's created. For example, `ClipboardResults` refreshes the list when the clipboard changes, but only while its route is showing.
- **`LauncherState`** coordinates and holds no route logic. Key handling is in `LauncherState+Keys.swift`, tried in a fixed priority order.

## Principles

1. **Only `PrismCore` holds pure logic.** If something can be written with Foundation alone, such as a parser, a scorer or a formatter, it goes in `PrismCore` with tests.
2. **Each route has one owner.** A route's rows and the state behind them live in one `Results/` file.
3. **Rows are values, behavior is actions.** Views never decide what an item does; they call `perform`.
4. **Inject dependencies and wire them at the root.** Providers receive `AppServices` and a `LauncherNavigator` in their initializers. Singletons (`AppServices.shared`, `PrismSettings.shared`) are touched only at the edges: `App/`, views and settings.
5. **Name the magic values.** UserDefaults keys live in `DefaultsKey`, and they're persisted on users' Macs, so never rename one without a migration. Key codes live in `KeyCode`.

## Recipes

**Add a command** (a root-search entry that runs one thing): add a `Command` to `CommandCatalog.all()`. Give it a stable `id`, because frecency and learned queries are stored under it.

**Add a list route:**
1. Add a case to `Route`, with its `title`, `placeholder` and `icon`, plus a `layout` if it isn't a plain list.
2. Create `Results/FooResults.swift` with a class conforming to `ResultProvider`.
3. Add a provider property and a case in `LauncherState.provider(for:)`.
4. Add a command that does `navigator.push(.foo)` so people can open the route.

**Add a custom-view route:** give it `layout: .custom`, put its model and view in `Features/Foo/`, store the model on `LauncherState`, and show the view in `LauncherView.content`.

**Check UI changes:** `Prism --snapshot out.png <route> [query] [selection] [--actions] [--light]` renders the launcher offscreen. Routes are `root`, `files`, `clipboard`, `emoji`, `wheel`, `colors`, `chat`, `usage`, `google`, and `settings <pane>`.
