# Focus Todo · Mac 客户端

原生 AppKit 窗口 + WKWebView，界面与网页版共用一份代码：编译时直接打包仓库根目录的 `index.html`、`fonts/`、`icons/`。

- **系统通知**：到点提醒走通知中心，App 关着也会弹出；通知上可以直接点「完成」或「10 分钟后提醒」
- **天气**：系统定位 + Open-Meteo（免费，无需 Key），显示在「今天」右上角
- **Dock 角标**：显示今天未完成的待办数
- **菜单与快捷键**：⌘N 新建、⌘1/2/3 切换视图、⇧⌘D 深色/浅色、⌘R 立即同步
- **窗口**：透明标题栏、毛玻璃背景，关闭窗口后 App 留在后台继续同步和提醒
- **同步**：和网页版一样，用 GitHub Token 同步到私密 Gist

## 编译

只需要 Xcode 命令行工具（`xcode-select --install`），不需要完整的 Xcode。

```bash
./build.sh            # 编译到 build/ 并打开
./build.sh install    # 编译并安装到「应用程序」
```

## 以后上架 Mac App Store 需要

- Apple 开发者账号，用正式证书签名
- 开启 App Sandbox（网络、定位权限）
- 天气可换成苹果的 WeatherKit
