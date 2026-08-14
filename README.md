# DeepSeek Harness Mac (deepseekharness-mac)

> **A tiny native macOS shell for DeepSeek Harness — 132KB vs Electron's 142MB+.**
> 极轻量 macOS 原生壳：Swift + WKWebView，复用你本地的 dsh server，零捆绑。

DeepSeek Harness 官方通过命令行启动本地 Web UI（`npx @deepseek-ai/dsh web` → http://127.0.0.1:3080）。
本项目给它套一个 **macOS 原生轻壳**：双击即用，自动管理本地 server，窗口即官方 Web UI。

## 为什么轻（对比）

| | Electron 壳（社区版） | **本版（Swift 原生）** |
|---|---|---|
| 安装包 | 142–193 MB | **~132 KB** |
| 渲染 | 捆绑整个 Chromium | **系统 WebKit（WKWebView）** |
| Node runtime | 捆绑 | **复用你已有的 Node** |
| 技术栈 | Electron (JS) | **Swift + AppKit + WebKit** |

不捆绑任何东西：渲染用 macOS 自带的 WebKit，server 用你本地的 Node 跑官方 dsh 包。**磁盘占用小 1000 倍**。

## 特性

- ✅ **复用本地 dsh**：若 3080 端口已有 server 在跑（你手动启动的），直接连；没有则自动用本地缓存包拉起（零网络），最后才 `npx` 在线
- ✅ **双击即用**：双击 `.app` 即开，无需命令行
- ✅ **退出弹框**：关闭窗口时选择「关闭 server 并退出 / 保留 server 仅退出 / 取消」，外部 server 永不误杀
- ✅ **server 日志**：`~/.dsh-desktop/dsh.log`
- ✅ **卡顿兜底**：菜单栏 File → Open in Browser（⌘O）一键切 Chrome
- ✅ **复制粘贴可用**：WKWebView 的剪贴板通道在 macOS 有已知平台限制（右键可用、⌘C/⌘V 失效）——本壳通过 **WKWebView 子类拦截 ⌘V + JS 直写 textarea** 解决（支持 React 受控组件）

## 构建

```bash
xcrun swiftc -O dsh-desktop.swift -o dsh-desktop \
  -framework Cocoa -framework WebKit

# 打成 .app
mkdir -p "DeepSeek Harness.app/Contents/MacOS"
cp dsh-desktop "DeepSeek Harness.app/Contents/MacOS/dsh-desktop"
# 手写 Info.plist（见源码注释），然后：
codesign --force --sign - "DeepSeek Harness.app"
```

## 架构

```
DeepSeek Harness.app (Swift, ~130KB)
 ├─ 检查 :3080 是否已有 dsh server → 有则直接连
 ├─ 无 → spawn: 本地缓存包(node) → 兜底 npx 在线
 ├─ WKWebView 加载 http://127.0.0.1:3080（官方 Web UI，零改动）
 └─ 退出弹框：server 去留选择（自己起的才可能被杀）
```

复用 server 是行业标准做法（Hermes Desktop / Codex app-server / OpenClaw Companion 同款架构）。

## 已知限制

- 无托盘驻留（关窗即退，可加）
- 粘贴为 JS 方案：支持文本；图片粘贴未处理
- 未打 dmg / 未公证（本地 ad-hoc 签名，自己用没问题；分发需开发者证书）

## 相关

- [DeepSeek Harness 官方](https://github.com/deepseek-ai/deepseek-harness)（MIT）
- 社区 Electron 版（对比参考）：RZX00/deepseek-harness-desktop、anywhere-labs/deepseek-harness-desktop
