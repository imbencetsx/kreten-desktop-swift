# KRETÉN for macOS

A native SwiftUI rewrite of KRETÉN Desktop for macOS 26+, built around Liquid Glass.
No webview, Node or Rust runtime: KRÉTA OAuth, sync, change notifications and the
encrypted cache are all Swift.

## Run

Open `Kreten.xcodeproj` in Xcode 26+ and press ⌘R, or:

```sh
./build.sh          # → build/KRETEN.app (ad-hoc signed)
./test-core.sh      # core logic checks (OAuth/PKCE, diffing, parsing, calendar)
```

Launch arguments for development: `-demo` (sample data, no KRÉTA traffic) and
`-page grades` (open a specific page). Put `-page` before `-demo`.

## Layout

| Path | What |
| --- | --- |
| `Kreten/Core` | KRÉTA protocol: `KretaCore` actor (sessions, token rotation, sync, diffing), `KretaAPI`, `OAuth` (PKCE), `SecureStore` (AES-GCM file, key in Keychain), `JSON`, `Day` (Budapest time) |
| `Kreten/Model` | `AppModel` (observable app state, polling, notifications), typed diary views (`Diary.swift`), school calendar progress, preferences, demo data |
| `Kreten/UI` | SwiftUI: root split view, sidebar, pages, login, settings, menu bar panel, window backdrop |

Cards use native Liquid Glass surfaces, grouped per page for shared background sampling.

## Window transparency

*Settings → Megjelenés → Ablak* has three backdrops:

- **Átlátszó**: the desktop shows through, blurred and tinted. *Átlátszatlanság* sets
  the tint opacity, *Elmosás* sets the blur radius, and the tint can follow the
  accent color. The blur uses the private window-server call
  `CGSSetWindowBackgroundBlurRadius`, resolved at runtime, so the slider is
  disabled if a future macOS removes it.
- **Üveg**: the system material.
- **Színátmenet**: a slowly moving two-color mesh gradient.

## Notes

- The data store is new (`~/Library/Containers/app.kreten.desktop.mac`), so log in
  once again. The OAuth flow runs in an isolated, non-persistent `WKWebView`; the
  app never sees the password.
- Closing the window keeps KRETÉN syncing from the menu bar extra. *Kilépés* quits.
- UI is Hungarian only for now.
