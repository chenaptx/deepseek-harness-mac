# DeepSeek Harness Mac

**132KB native macOS shell for DeepSeek Harness. Swift + WKWebView. No Electron.**

Reuses your local `dsh server` — double-click to launch, no terminal needed.

## Install (one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/chenaptx/deepseek-harness-mac/main/install.sh | bash
```

Requires **Node.js ≥ 22**. Script: downloads → clears quarantine → installs to `/Applications` → launches.

Or [download v0.1.2 zip](https://github.com/chenaptx/deepseek-harness-mac/releases/tag/v0.1.2) (30KB), unzip, double-click.

## Features

- **1000× smaller** than Electron alternatives (132KB vs 142MB+)
- **Reuses local dsh** — connects to existing `:3080` server, or spawns one automatically
- **Quit dialog** — keep or kill server when closing
- **⌘C/⌘V fixed** — WKWebView clipboard quirks patched via native menu + JS injection
- **Full-width layout** — overrides the upstream 748px fixed-width CSS so chat fills the window
- **Fallback** — menu bar → Open in Browser (⌘O) if WKWebView misbehaves

## Architecture

```
DeepSeek Harness.app (Swift, ~130KB)
 ├─ :3080 server already running? → connect directly
 ├─ No → spawn: local cache (node) → fallback npx
 ├─ WKWebView loads http://127.0.0.1:3080 (official web UI, untouched)
 └─ CSS injection: clipboard fix + full-width override
```

## Changelog

- **v0.1.2** — Full-width fix: overrides `--dsh-chat-content-width` from 748px to 100%
- **v0.1.1** — Fix ⌘C copy: wire up native Edit menu via `setupMenu()`
- **v0.1.0** — Initial release

## Build

```bash
xcrun swiftc -O dsh-desktop.swift -o dsh-desktop \
  -framework Cocoa -framework WebKit

mkdir -p "DeepSeek Harness.app/Contents/MacOS"
cp dsh-desktop "DeepSeek Harness.app/Contents/MacOS/dsh-desktop"
codesign --force --sign - "DeepSeek Harness.app"
```

## Known limitations

- No tray icon (quit = close window)
- Paste is JS-based: text only, no images
- Not notarized (ad-hoc signing; fine for personal use)

## See also

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (official, MIT)
- Electron alternatives: RZX00/deepseek-harness-desktop, anywhere-labs/deepseek-harness-desktop
