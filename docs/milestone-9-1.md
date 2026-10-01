# M9.1 浅色界面与 Windows 预发布

日期：2026-10-01。App 0.9.1-beta.1；Parser 0.9.0；Binary Container 1；Map Converter / Classifier 不变。

本次按用户追加要求，优先完成浅色界面和可下载安装的应用交付。保留 M9 已完成的按需轨迹读取与后台预取，没有宣称事件流式加载或全部产品路线完成。

## 用户可见变化

统一浅色主题应用于首页、设置、加载、错误、时间轴和回放工具。场景默认浅蓝灰，在设置最上方提供三种背景选项，兼容既有设置文件。地图结构及屋顶/高度剖切规则保持原语义。观察侧栏随窗口高度调整，支持收起；打开 Demo 入口也可从回放工具栏访问。

## 分发

`tools/package_windows.ps1` 调用 Windows 构建、收集实际链接依赖的许可声明，使用 Inno Setup 7 编译安装器，并生成免安装 ZIP 与 SHA256SUMS.txt。`installer/windows.iss` 使用固定 AppId、当前用户安装和可选桌面快捷方式；卸载不删除独立用户数据。安装包不是代码签名版本。

[Inno Setup 权限文档](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm)说明 `lowest` 为不申请管理员权限的安装模式；[命令行文档](https://jrsoftware.org/ishelp/topic_setupcmdline.htm)用于自动化安装验收。Source2Viewer 本地版本为 20.0.6980+a06886f7；其 MIT 许可证随工具提供，另附上游维护的综合第三方声明（包含未打包的 GUI 组件条目）。Godot 许可与第三方文字直接从打包引擎导出。

构建前准备 README 中的 Go、Godot 4.5.1、导出模板、Source2Viewer 工具，并安装 Inno Setup 7。可显式传入 `-Godot` 与 `-ISCC`；默认编译器位于 `.tools/inno/compiler/ISCC.exe`。本次使用官方签名验证成功的 Inno Setup 7.1.0。

## 验收

- `release_ui_tests.gd`：16 项通过，检查偏好持久化、三种窗口尺寸（960×640、1280×800、1440×900）、侧栏边界、切换设置暂停、关闭会话。首页、设置、回放截图经人工视觉检查。
- `run_tests.gd`：84 项通过。
- `go -C parser test ./...`：通过。
- `tools/test_windows_installer.ps1`：12 项安装检查与实际安装 EXE 的 11 项真实 Demo/缓存检查通过；包含安装、重复安装、中文与空格路径、八个关键运行文件 hash、缓存新建/复用/损坏恢复、旧 JSON、卸载移除程序及注册项、保留独立数据。
- M9 已有 Ancient/Mirage 一致性、损坏和预取专项验收见 `milestone-9.md`。本次未修改底层回放事实或轨迹解码。

本地证据：`artifacts/m91/ui.log`、`ui-report.json`、截图、`mock.log`、`package.log`、`installer-check/report.json` 与 `installer-check/installed-app*.log`。验收使用本机图形环境和已有 prepared maps；不是干净 Windows 虚拟机矩阵测试。

## 保留限制

应用界面以英文为主，安装向导/发布说明为中英文。事件和投掷物仍整体加载、冷跳转可能同步等待；密集玩家姓名仍可重叠。地图兼容范围与 M8.1/M9 一致，不将几何检查等同于所有地图完整验证。无自动更新、无代码签名，后续仍需扩展事件流式加载、观察体验和跨机器兼容测试。
