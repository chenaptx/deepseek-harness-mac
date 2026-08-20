# DeepSeek Harness Mac

**132KB native macOS shell for DeepSeek Harness. Swift + WKWebView. No Electron.**

Also works as a **cordis plugin** — install via `dsh plugin add` and the native shell launches automatically when DSH starts.

## Install

**As a DSH plugin** (auto-launches with `dsh web`):
```bash
dsh plugin add chenaptx/deepseek-harness-mac
```

**As a standalone app** (double-click to launch):
```bash
curl -fsSL https://raw.githubusercontent.com/chenaptx/deepseek-harness-mac/main/install.sh | bash
```
Or [download v0.1.2 zip](https://github.com/chenaptx/deepseek-harness-mac/releases/tag/v0.1.2) (30KB), unzip, double-click.

Requires **Node.js ≥ 22**.

## Features

- **1000× smaller** than Electron alternatives (132KB vs 142MB+)
- **Dual mode** — standalone app + cordis plugin in one repo
- **Reuses local dsh** — connects to existing `:3080` server, or spawns one automatically
- **Quit dialog** — keep or kill server when closing
- **⌘C/⌘V fixed** — WKWebView clipboard quirks patched via native menu + JS injection
- **Full-width layout** — overrides the upstream 748px fixed-width CSS so chat fills the window
- **Fallback** — menu bar → Open in Browser (⌘O) if WKWebView misbehaves

## Architecture

```
Mode 1: dsh plugin add → DSH loads lib/index.js → spawns bin/dsh-desktop → native window

Mode 2: double-click DeepSeek Harness.app → spawns DSH server → WKWebView → native window

Both modes use the same Swift binary (132KB, arm64).
```

## Changelog

- **v0.1.2** — Full-width fix + cordis plugin bridge (`dsh plugin add` support)
- **v0.1.1** — Fix ⌘C copy: wire up native Edit menu via `setupMenu()`
- **v0.1.0** — Initial release

## Build

```bash
xcrun swiftc -O dsh-desktop.swift -o dsh-desktop \
  -framework Cocoa -framework WebKit
```

## See also

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (official, MIT)
- Electron alternatives: RZX00/deepseek-harness-desktop, anywhere-labs/deepseek-harness-desktop
