# M9.3 — 界面清晰度 / Visual readability

版本：0.9.3-beta.2。未签名测试版本。

## 修改

- 文件选择器完整适配浅色主题，包括窗口边框、文件列表、选中项、文字和文件夹图标。默认列表视图，从最近打开 Demo 的有效目录开始；没有历史时使用文档目录。
- 小窗口保持字号，播放操作和时间/倍速分组自动换行；侧栏避让底部播放区。
- 根据用户反馈，取消姓名底牌和连接线，保留玩家位置上方的直接姓名显示。普通模式采用深度测试，X-Ray / Tactical 模式允许透视姓名。
- 真实地图默认镜头从 1.9 倍边界留白调整为 1.35 倍，通常显示大小增加约 41%。使用镜头缩放，不改变地图和玩家的坐标比例。滚轮可继续缩放，Home 恢复新的默认视角。
- 应用打开 Demo 时默认收起右侧面板；通过 Panels 可重新展开。
- 死亡玩家姓名默认隐藏，可通过图层开关或设置恢复；尸体和真实回放数据保留。
- 地图使用中性环境光和较柔和的定向光，浅色预设提高地图与背景的层次；玩家使用稳定队伍色，增强遮挡时的可辨识度。

## Validation

Real Ancient and Mirage replays are rendered at 960×640, 1280×800 and 1440×900. Checks cover recorded deaths, direct player labels, layer switches, view-mode depth, zoom, Home reset and unchanged replay facts. Screenshots and reports are written to `artifacts/m93/`; final beta.2 map screenshots use `*-larger-map-*.png`.

- `readability_tests.gd`: 53 checks passed in both source and exported application builds.
- `run_tests.gd`: 84 checks passed with actual viewport input after camera changes.
- The earlier beta.1 validation also covered playback navigation (50), palette states (52), shell integration (16), and binary/JSON scene parity and corruption (241). Nameplate-specific checks from beta.1 are superseded by the direct-label checks.

No parser, player position, round fact or ReplayClock behavior changes. The closer view prioritizes detail; map edges may be outside the view. Pan with right-drag or zoom out with the wheel when needed.

## Local build

`powershell -File tools/package_windows.ps1 -AllowUnsignedPreview`

Outputs are under `dist/previews/0.9.3-beta.2/`. This is an unsigned preview; the publisher certificate issue is unchanged. The installed user application is not overwritten during testing. Release artifacts and bilingual notes are available through the v0.9.3-beta.2 GitHub prerelease.
