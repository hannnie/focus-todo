// Focus Todo — Mac 客户端
// 原生 AppKit 窗口 + WKWebView 承载界面；提醒走系统通知中心，天气走系统定位 + Open-Meteo，
// Dock 角标显示今天未完成的数量。界面代码与网页版共用一份（Resources/web）。
import AppKit
import WebKit
import UserNotifications
import CoreLocation
import SwiftUI

// MARK: - 本地资源：focus://app/... 从 App 包里读取网页文件
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root.standardizedFileURL }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.path), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript", "css": "text/css",
                     "woff2": "font/woff2", "png": "image/png", "json": "application/json",
                     "webmanifest": "application/manifest+json", "svg": "image/svg+xml"]
        let mime = types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"])!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - 标题栏拖拽区：透明标题栏下，让顶部一条区域可以拖动窗口、双击缩放
final class DragStrip: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - 菜单栏面板：列出今天的待办，快速新增
struct TodayItem: Identifiable, Equatable {
    let id: String
    let title: String
    let done: Bool
    let pri: Int
}

final class TodayModel: ObservableObject {
    @Published var items: [TodayItem] = []
    var onToggle: (String) -> Void = { _ in }
    var onAdd: (String) -> Void = { _ in }
    var onOpen: () -> Void = {}
}

struct TodayPanel: View {
    @ObservedObject var model: TodayModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var openItems: [TodayItem] { model.items.filter { !$0.done } }
    private var doneItems: [TodayItem] { model.items.filter { $0.done } }
    private let sun = Color(red: 0.95, green: 0.64, blue: 0.05)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "sun.horizon.fill").foregroundColor(sun)
                Text("今天").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(openItems.isEmpty ? "全部完成" : "\(openItems.count) 件待办")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                TextField("添加到今天，回车确认", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit {
                        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { model.onAdd(t); draft = "" }
                    }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)

            Divider().padding(.top, 10)

            if model.items.isEmpty {
                Spacer()
                Text("今天还没有待办").font(.system(size: 12)).foregroundColor(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(openItems) { row($0) }
                        if !doneItems.isEmpty {
                            HStack {
                                Text("已完成 \(doneItems.count) 件").font(.system(size: 11)).foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                            ForEach(doneItems) { row($0) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Divider()
            Button(action: model.onOpen) {
                HStack {
                    Text("打开 Focus Todo").font(.system(size: 12))
                    Spacer()
                    Text("⌘0").font(.system(size: 11)).foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 320, height: 420)
        .onAppear { focused = true }
    }

    private func row(_ it: TodayItem) -> some View {
        HStack(spacing: 10) {
            Button { model.onToggle(it.id) } label: {
                Image(systemName: it.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundColor(it.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            Text(it.title)
                .font(.system(size: 13))
                .strikethrough(it.done)
                .foregroundColor(it.done ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if it.pri >= 0 {
                Text("P\(it.pri)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(priColor(it.pri))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func priColor(_ p: Int) -> Color {
        let colors: [Color] = [.red, .orange, .yellow, .blue, .gray]
        return colors[min(max(p, 0), 4)]
    }
}

// MARK: - App
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate,
                         UNUserNotificationCenterDelegate, CLLocationManagerDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var pageReady = false
    var pendingJS: [String] = []
    let location = CLLocationManager()
    var weatherTimer: Timer?
    var lastWeather: [String: Any] = [:]
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let today = TodayModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        setupStatusItem()
        setupNotifications()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
        weatherTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.refreshWeather()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // 关掉窗口后 App 继续在后台运行（保持同步和提醒），点 Dock 图标重新打开
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        send(["type": "sync"])
    }

    // MARK: 窗口
    func buildWindow() {
        let config = WKWebViewConfiguration()
        let root = Bundle.main.resourceURL!.appendingPathComponent("web")
        config.setURLSchemeHandler(AppSchemeHandler(root: root), forURLScheme: "focus")
        config.websiteDataStore = .default()
        let content = WKUserContentController()
        content.add(self, name: "native")
        config.userContentController = content

        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground") // 让窗口的毛玻璃底透出来
        web.allowsBackForwardNavigationGestures = false
        web.translatesAutoresizingMaskIntoConstraints = false

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Focus Todo"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 560)
        window.delegate = self
        window.tabbingMode = .disallowed

        let glass = NSVisualEffectView()
        glass.material = .underWindowBackground
        glass.blendingMode = .behindWindow
        glass.state = .followsWindowActiveState
        window.contentView = glass

        let strip = DragStrip()
        strip.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(web)
        glass.addSubview(strip)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            web.topAnchor.constraint(equalTo: glass.topAnchor),
            web.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 80),
            strip.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            strip.topAnchor.constraint(equalTo: glass.topAnchor),
            strip.heightAnchor.constraint(equalToConstant: 40),
        ])

        if !window.setFrameUsingName("FocusTodoMain") { window.center() }
        window.setFrameAutosaveName("FocusTodoMain")
        window.makeKeyAndOrderFront(nil)
        web.load(URLRequest(url: URL(string: "focus://app/index.html")!))
    }

    // MARK: 菜单栏图标
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: "Focus Todo")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        today.onToggle = { [weak self] id in self?.send(["type": "toggle", "id": id]) }
        today.onAdd = { [weak self] title in self?.send(["type": "addToday", "title": title]) }
        today.onOpen = { [weak self] in
            self?.popover.performClose(nil)
            self?.showMain()
        }
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: TodayPanel(model: today))
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: 菜单
    func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Focus Todo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Focus Todo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Focus Todo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(main, title: "Focus Todo", menu: appMenu)

        let file = NSMenu(title: "文件")
        file.addItem(item("新建待办", #selector(newTodo), "n"))
        file.addItem(.separator())
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(main, title: "文件", menu: file)

        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(main, title: "编辑", menu: edit)

        let view = NSMenu(title: "视图")
        view.addItem(item("今天", #selector(showToday), "1"))
        view.addItem(item("本周", #selector(showWeek), "2"))
        view.addItem(item("计划", #selector(showPlan), "3"))
        view.addItem(.separator())
        let theme = item("切换深色 / 浅色", #selector(toggleTheme), "d")
        theme.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(theme)
        view.addItem(item("立即同步", #selector(syncNow), "r"))
        view.addItem(item("刷新天气", #selector(menuWeather), ""))
        addSubmenu(main, title: "视图", menu: view)

        let win = NSMenu(title: "窗口")
        win.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(.separator())
        win.addItem(item("显示主窗口", #selector(showMain), "0"))
        addSubmenu(main, title: "窗口", menu: win)
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }
    private func addSubmenu(_ main: NSMenu, title: String, menu: NSMenu) {
        menu.title = title
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }

    @objc func newTodo() { showMain(); send(["type": "new"]) }
    @objc func showToday() { showMain(); send(["type": "view", "view": "today"]) }
    @objc func showWeek() { showMain(); send(["type": "view", "view": "week"]) }
    @objc func showPlan() { showMain(); send(["type": "view", "view": "plan"]) }
    @objc func toggleTheme() { send(["type": "theme"]) }
    @objc func syncNow() { send(["type": "sync"]) }
    @objc func menuWeather() { refreshWeather() }
    @objc func showMain() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    // MARK: 网页 ↔ 原生
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            pageReady = true
            pendingJS.forEach { web.evaluateJavaScript($0) }
            pendingJS.removeAll()
            if !lastWeather.isEmpty { send(lastWeather) }
            refreshWeather()
        case "reminders":
            scheduleReminders(body["items"] as? [[String: Any]] ?? [])
        case "badge":
            let n = (body["count"] as? Int) ?? 0
            NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
        case "weather":
            refreshWeather()
        case "today":
            let list = body["items"] as? [[String: Any]] ?? []
            today.items = list.compactMap { d in
                guard let id = d["id"] as? String, let title = d["title"] as? String else { return nil }
                return TodayItem(id: id, title: title, done: (d["done"] as? Bool) ?? false, pri: (d["pri"] as? Int) ?? -1)
            }
        default:
            break
        }
    }

    func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.focusNative&&window.focusNative(\(json))"
        DispatchQueue.main.async {
            if self.pageReady { self.web.evaluateJavaScript(js) } else { self.pendingJS.append(js) }
        }
    }

    // 外部链接（创建 GitHub Token 等）用默认浏览器打开
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, url.scheme != "focus", url.scheme != "about" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        webView.reload()
    }

    // MARK: 系统通知
    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "DONE", title: "完成", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "10 分钟后提醒", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "TODO", actions: [done, snooze],
                                                                 intentIdentifiers: [], options: [])])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, error in
            self.send(["type": "notifyAuth", "ok": ok, "error": error?.localizedDescription ?? ""])
        }
    }

    func scheduleReminders(_ items: [[String: Any]]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date().timeIntervalSince1970 * 1000
        for it in items.prefix(60) {
            guard let id = it["id"] as? String, let title = it["title"] as? String,
                  let at = it["at"] as? Double, at > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = (it["body"] as? String) ?? "到时间了"
            content.sound = .default
            content.categoryIdentifier = "TODO"
            content.userInfo = ["id": id]
            let date = Date(timeIntervalSince1970: at / 1000)
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: "todo-" + id, content: content, trigger: trigger))
        }
    }

    // App 在前台时也弹出横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["id"] as? String ?? ""
        switch response.actionIdentifier {
        case "DONE": send(["type": "complete", "id": id])
        case "SNOOZE": send(["type": "snooze", "id": id, "minutes": 10])
        default:
            DispatchQueue.main.async { self.showMain() }
            send(["type": "open", "id": id])
        }
        completionHandler()
    }

    // MARK: 天气：系统定位 → Open-Meteo（免费、无需 Key）
    func refreshWeather() {
        switch location.authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()
        case .denied, .restricted:
            pushWeather(["error": "定位权限未开启，可在「系统设置 → 隐私与安全性 → 定位服务」里打开"])
        default:
            location.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: pushWeather(["error": "定位权限未开启"])
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pushWeather(["error": "暂时无法获取位置"])
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = String(format: "%.3f", loc.coordinate.latitude)
        let lon = String(format: "%.3f", loc.coordinate.longitude)
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&timezone=auto")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = json["current"] as? [String: Any],
                  let temp = cur["temperature_2m"] as? Double else {
                self.pushWeather(["error": "天气服务暂时不可用"])
                return
            }
            let code = (cur["weather_code"] as? Int) ?? 3
            CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "zh_CN")) { marks, _ in
                let p = marks?.first
                let city = p?.locality ?? p?.subAdministrativeArea ?? p?.administrativeArea ?? ""
                self.pushWeather(["temp": temp, "code": code, "city": city])
            }
        }.resume()
    }

    private func pushWeather(_ w: [String: Any]) {
        var msg = w
        msg["type"] = "weather"
        DispatchQueue.main.async { self.lastWeather = msg }
        send(msg)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
