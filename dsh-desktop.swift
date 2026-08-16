// DeepSeek Harness 轻量桌面端 (macOS 原生, Swift + WKWebView)
// 架构: spawn dsh server 子进程 -> 轮询 3080 端口 -> 系统 WebKit 加载官方 Web UI
// 编译: swiftc -O dsh-desktop.swift -o dsh-desktop -framework Cocoa -framework WebKit
import Cocoa
import WebKit

// WKWebView 子类: 在最底层拦截 ⌘V — performKeyEquivalent 先于菜单被调用,
// 绕开 WKWebView 剪贴板安全模型的限制 (该限制下菜单/响应链的 paste: 均无效)
final class PasteWKWebView: WKWebView {
    var onPaste: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            onPaste?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var serverProc: Process?
    var didSpawnServer = false
    var killServerOnExit = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let rect = NSRect(x: 0, y: 0, width: 1180, height: 780)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "DeepSeek Harness"
        window.center()
        window.setFrameAutosaveName("dsh-main-window")
        window.minSize = NSSize(width: 800, height: 560)

        // WKWebView 配置: 注入 CSS 强制文本可选中/可复制 (DSH UI 可能设了 user-select:none)
        let config = WKWebViewConfiguration()
        // 注入 CSS: ①强制文本可选中 ②输入框文字强制可见 (覆盖 -webkit-text-fill-color:transparent 类透明字,
        // 用 currentColor 跟随 DSH 主题, 深色/浅色界面都不会出现"白字看不见")
        let css = """
        * { -webkit-user-select: text !important; user-select: text !important; }
        textarea, input, [contenteditable] {
          color: inherit !important;
          -webkit-text-fill-color: currentColor !important;
          caret-color: currentColor !important;
          opacity: 1 !important;
        }
        """
        let script = WKUserScript(source: css, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        let pasteWV = PasteWKWebView(frame: rect, configuration: config)
        pasteWV.onPaste = { [weak self] in self?.pasteViaJS() }
        webView = pasteWV
        window.contentView = webView
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 确保 WebView 拿到焦点 (复制/粘贴/输入法/听写依赖 first responder)
        window.makeFirstResponder(webView)
        webView.becomeFirstResponder()
        // 挂主菜单 (App/Edit/File) — ⌘C/⌘V/⌘X/⌘A 依赖 Edit 菜单存在才会路由
        setupMenu()

        if isServerUp() {
            loadUI()          // 复用已在运行的 dsh server
        } else {
            startServer()     // 没有则用本地缓存包拉起, 零网络
        }
    }

    // 窗口重新激活时也把焦点还给 WebView
    func windowDidBecomeKey(_ notification: Notification) {
        if webView != nil { window?.makeFirstResponder(webView) }
    }

    func startServer() {
        // 复用优先级: DSH_CMD 环境变量 > npx 缓存包(本地, 不联网) > npx 在线拉取
        let shell = """
        if [ -n "$DSH_CMD" ]; then
          eval "$DSH_CMD"
        else
          CACHE=$(find "$HOME/.npm/_npx" -maxdepth 4 -type d -path "*/@deepseek-ai/dsh" 2>/dev/null | head -1)
          if [ -n "$CACHE" ] && [ -f "$CACHE/lib/bin.js" ]; then
            node "$CACHE/lib/bin.js" web
          else
            npx -y @deepseek-ai/dsh web
          fi
        fi
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", shell]
        // server 输出落盘, 方便排查 (卡顿/错误)
        let logPath = NSHomeDirectory() + "/.dsh-desktop/dsh.log"
        try? FileManager.default.createDirectory(
            atPath: (logPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let log = FileHandle(forWritingAtPath: logPath) {
            p.standardOutput = log
            p.standardError = log
        } else {
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }
        do { try p.run() } catch {
            showError("无法启动 dsh server: \(error.localizedDescription)")
            return
        }
        serverProc = p
        didSpawnServer = true
        // 首次可能需建索引, 最多等 120s
        pollPort(attempt: 0, maxAttempts: 120)
    }

    func pollPort(attempt: Int, maxAttempts: Int) {
        if attempt > maxAttempts {
            showError("dsh 启动超时 (\(maxAttempts)s)。请检查网络 / Node 环境后重开。")
            return
        }
        if isServerUp() { loadUI(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.pollPort(attempt: attempt + 1, maxAttempts: maxAttempts)
        }
    }

    func isServerUp() -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var up = false
        var req = URLRequest(url: URL(string: "http://127.0.0.1:3080/")!)
        req.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode < 500 { up = true }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 2.5)
        return up
    }

    func loadUI() {
        webView.load(URLRequest(url: URL(string: "http://127.0.0.1:3080/")!))
    }

    // 菜单栏: File -> Open in Browser (卡顿时一键切 Chrome)
    func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DeepSeek Harness",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Edit 菜单: 强制启用 + 手动沿响应链转发 (WKWebView 本身无 paste: 公开方法,
        // 处理者是其内部 WKContentView — 右键菜单能用的原因; 这里 ⌘V 走同一条链)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.autoenablesItems = false
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        let cutItem = NSMenuItem(title: "Cut", action: #selector(cutForward(_:)), keyEquivalent: "x")
        cutItem.target = self
        editMenu.addItem(cutItem)
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyForward(_:)), keyEquivalent: "c")
        copyItem.target = self
        editMenu.addItem(copyItem)
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteForward(_:)), keyEquivalent: "v")
        pasteItem.target = self
        editMenu.addItem(pasteItem)
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAllForward(_:)), keyEquivalent: "a")
        selectAllItem.target = self
        editMenu.addItem(selectAllItem)
        editItem.submenu = editMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open in Browser",
                                  action: #selector(openInBrowser), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        fileItem.submenu = fileMenu
        NSApp.mainMenu = mainMenu
    }

    @objc func openInBrowser() {
        if let url = URL(string: "http://127.0.0.1:3080/") {
            NSWorkspace.shared.open(url)
        }
    }

    // 沿响应链转发编辑命令 (first responder = WKWebView 内部输入视图时, 与右键同路径)
    func sendEditCommand(_ sel: Selector, _ sender: Any?) -> Bool {
        var responder: NSResponder? = webView.window?.firstResponder
        while let r = responder {
            if r.tryToPerform(sel, with: sender) { return true }
            responder = r.nextResponder
        }
        // 兜底: 尝试从 webView 自己开始
        var r2: NSResponder? = webView
        while let r = r2 {
            if r.tryToPerform(sel, with: sender) { return true }
            r2 = r.nextResponder
        }
        return false
    }

    @objc func copyForward(_ sender: Any?) { _ = sendEditCommand(Selector(("copy:")), sender) }
    @objc func cutForward(_ sender: Any?) { _ = sendEditCommand(Selector(("cut:")), sender) }
    @objc func selectAllForward(_ sender: Any?) { _ = sendEditCommand(Selector(("selectAll:")), sender) }

    @objc func pasteForward(_ sender: Any?) {
        if sendEditCommand(Selector(("paste:")), sender) { return }
        pasteViaJS()
    }

    // 读系统剪贴板 → JS 直改 textarea (DSH composer 是 <textarea>): 改 value + input 事件
    // 完全绕开 WKWebView 剪贴板通道 (该通道是已知平台限制, 见 GitHub hotjamwot/juju-swift)
    func pasteViaJS() {
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        let esc = str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        let js = """
        (function(){
          var el = document.activeElement;
          if (!el) { el = document.querySelector('[contenteditable="true"]') || document.querySelector('textarea'); }
          if (!el) return false;
          el.focus();
          if (el.isContentEditable) {
            document.execCommand('insertText', false, "\(esc)");
            return true;
          }
          if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
            var s = el.selectionStart != null ? el.selectionStart : el.value.length;
            var t = el.selectionEnd != null ? el.selectionEnd : s;
            var newVal = el.value.slice(0, s) + "\(esc)" + el.value.slice(t);
            // React 受控组件: 必须用原生 setter 触发 onChange, 否则界面不刷新(白字/不可见)
            var proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
            setter.call(el, newVal);
            el.selectionStart = el.selectionEnd = s + \(str.count);
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return true;
          }
          return false;
        })()
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func showError(_ msg: String) {
        let html = "<html><body style='font-family:-apple-system,sans-serif;padding:48px;font-size:16px;color:#333'>"
            + "<h2>DeepSeek Harness</h2><p>\(msg)</p></body></html>"
        webView.loadHTMLString(html, baseURL: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // 关窗弹框: server 状态 + 去留选择 (无论谁启动都可选择关闭)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let st = serverStatus()
        let alert = NSAlert()
        alert.messageText = "退出 DeepSeek Harness？"
        if st.running {
            var info = "dsh server 运行中（PID \(st.pid)，\(st.owner)）。\n活动状态：\(st.active)"
            if !didSpawnServer {
                info += "\n注意：该 server 由外部启动，关闭会中断其正在运行的任务。"
            }
            alert.informativeText = info
        } else {
            alert.informativeText = "dsh server 未运行。"
        }
        alert.addButton(withTitle: "关闭 server 并退出")
        alert.addButton(withTitle: "保留 server，仅退出 App")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            killServerOnExit = true
            NSApp.terminate(nil)
            return true
        case .alertSecondButtonReturn:
            killServerOnExit = false
            NSApp.terminate(nil)
            return true
        default:
            return false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard killServerOnExit else { return }
        if didSpawnServer {
            serverProc?.terminate()
            let k = Process()
            k.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            k.arguments = ["-f", "@deepseek-ai/dsh"]
            try? k.run()
        } else {
            // 关闭外部启动的 server: 按监听 3080 的 PID 终止
            let pid = runCmd("/usr/sbin/lsof", ["-nP", "-i", ":3080", "-sTCP:LISTEN", "-t"])
            let trimmed = pid.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { _ = runCmd("/bin/kill", ["-TERM", trimmed]) }
        }
    }

    // --- 状态探测 ---
    func serverStatus() -> (running: Bool, pid: String, owner: String, active: String) {
        let up = isServerUp()
        guard up else { return (false, "-", "-", "-") }
        let pid = runCmd("/usr/sbin/lsof", ["-nP", "-i", ":3080", "-sTCP:LISTEN", "-t"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = didSpawnServer ? "本 App 启动" : "外部启动"
        return (true, pid, owner, dshActivity())
    }

    func dshActivity() -> String {
        // 尽力而为: ~/.dsh 数据目录最近 60s 内有无写入 (排除 node_modules)
        let home = NSHomeDirectory()
        let out = runCmd("/usr/bin/find", [home + "/.dsh", "-type", "f", "-mmin", "-1", "-not", "-path", "*/node_modules/*"])
        let hits = out.split(separator: "\n").filter { !$0.isEmpty }
        return hits.isEmpty ? "空闲（近 60s 无数据写入）" : "有活动（近 60s 数据写入 \(hits.count) 处）"
    }

    func runCmd(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
