// Focus Todo — Mac 客户端
// 原生 AppKit 窗口 + WKWebView 承载界面；提醒走系统通知中心，天气走系统定位 + Open-Meteo，
// Dock 角标显示今天未完成的数量。界面代码与网页版共用一份（Resources/web）。
import AppKit
import WebKit
import UserNotifications
import CoreLocation

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
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
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
            strip.heightAnchor.constraint(equalToConstant: 28),
        ])

        if !window.setFrameUsingName("FocusTodoMain") { window.center() }
        window.setFrameAutosaveName("FocusTodoMain")
        window.makeKeyAndOrderFront(nil)
        web.load(URLRequest(url: URL(string: "focus://app/index.html")!))
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
