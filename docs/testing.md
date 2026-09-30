# 项目测试

## M7 当前验收

运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-milestone7.ps1`。测试使用正式 Windows EXE/PCK、独立数据目录和三份真实 Demo；Mirage 的地图准备需要本机有效 CS2 和随包 map-tools。结果为 `artifacts/milestone-7-report.json`：52 检查、0 失败。覆盖自动 Plane、准备失败恢复、实际 Mirage 导出与保留时间 Reload、三 HE / 三 Burning、透明像素、红名、真实轨迹对齐、三地图切换与播放。

本次 M1–M6 回归分别为 88 / 362 / 117 / 653 / 285 / 1200，通过日志为 `artifacts/m7-m1-console.log` 至 `m7-m6-console.log`。M6 的缺地图断言已改为自动 Replay；旧报告中的 1203 是当时阻塞提示流程的计数。Go 15 个顶层测试通过、2 个可选诊断跳过，go vet 通过。最终 EXE 另经普通启动和文件选择器打开 Mirage，状态与八处对齐截图逐张视觉复核。详见 [M7 报告](milestone-7.md)。以下为历史阶段说明。

## M6 当前验收

执行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Milestone6 -VisualTest`，使用工作区真实 damage-source.dem 和隔离数据目录。覆盖 1,203 项状态、Seek、缓存、设置、错误与多 Session 检查。正式 Windows EXE 另外经过两次进程、共 17 项检查以及实际界面启动和截图检查。

Go 真实伤害测试使用 `tools/parser.ps1 -Test -Demo .\test_data\s2\s2.dem -DamageDemo .\test_data\damage-source.dem`。264 条原生 PlayerHurt 逐字段比对。M1–M5 本次回归分别为 88/362/117/653/285 检查通过。完整数值、日志位置、截图与限制见 [M6 报告](milestone-6.md)。历史 FullRound 报告不代表本阶段重新运行。


新增 `tools/run.ps1 -Milestone5 -VisualTest -FullRound -Replay test_data/public-s2-m5.replay.json`，覆盖 Bomb 真实事件、任意 Seek、颜色/效果/显示层、损坏缓存修复、地图回退、异步 UI 帧更新与完整回合。沿用下列 M2/M3/M4 回归；结果见 milestone-5.md。

# Milestone 4 测试（保留 Milestone 2 / 3 回归）

`tools/run.ps1 -CombatTest -VisualTest -FullRound -Replay test_data/public-s2-v2.replay.json` 执行 M4 事件数量、Smoke/Fire/HE/Flash 生灭、120 次随机 Seek 与独立全量扫描对照、Projectile 区间、Shot 寿命/批量节点、历史阵营色、图层开关、Kill Feed Seek 和 V1 reload；另做截图、交火性能和完整真实回合播放。去掉 `-FullRound` 跳过约 52 秒的实际回合；去掉 `-VisualTest` 可运行 headless 逻辑测试。报告为 `artifacts/milestone-4-report.json`。

Go 的 `TestCombatPublicDemo` 对真实源消息进行第二次独立解析，核对 12 个 Shot 源快照、火/闪/击杀计数和弹体历史归属；并 DeepEqual V1/V2 players、tracks、metadata。真实 source 诊断可设置 `CS2_PROBE=<demo path>` 后运行 `go test ./internal/demo -run TestSourceProbe -v`。更多结果与限制见 `milestone-4.md`。

新增 `tools/run.ps1 -MapTest -VisualTest -Replay test_data/public-s2.replay.json`：验证 Rig 层级、预设、投影、鼠标 Orbit、Pitch/Zoom 限制、模式、透明度、标签 billboard、带旋转偏移的坐标转换、实际地图三角形下的 1,393 个轨迹射线、Normal/X-Ray 遮挡截图及 3 秒播放 FPS。结果位于 `artifacts/milestone-3-report.json`。详见 `milestone-3.md`。

人工追加验收：切换 1/2/3/P、滚轮/右拖/中拖/Alt+左拖/Home；选玩家检查相机和地图参数；从 Normal 切到 X-Ray 确认墙后玩家出现；切换四档透明度和 Tactical 模式。真实地图缺失时应显示明确提示并回退 Plane，Mock 始终保持 Plane。

运行入口和完整命令见根目录 README。测试使用真实 Go 工具链与 Godot，不依赖第三方测试框架。

## Go

`tools/parser.ps1 -Test -Demo <本机dem路径>` 执行 `go test -v ./...` 和 `go vet ./...`。只运行 `go test ./...` 时，真实 Demo 集成测试会明确 skip；设置 CS2_TEST_DEMO 才执行。

覆盖 CLI 参数/文件错误、损坏 Demo、失败时保留已有输出、同输入输出保护、16 Hz 采样与数据缺口、无 SteamID 身份、晚到 SteamID、V1 校验错误。真实测试独立重新解码源 Demo，对照 30 个已导出 tick 的 XYZ、yaw、health、alive、team，不只检查 JSON 自洽性。

## Godot Mock

原来的 69 个逻辑/输入检查继续执行；新增 10 个 V1 非法数据案例和 5 个离散状态/瞬移边界案例，共 84 项无界面检查。图形模式增加 4 项截图与窗口检查，共 88 项。

Mock 已迁移到正式 V1；原有两个 Capsule 的 Godot 路径、Seek 结果、三档速度、暂停、终点、摄像机与时间轴交互预期保留。ReplayClock 源码未修改。

## Godot Real Replay

`-RealTest -Replay <JSON>` 覆盖动态人数、全部玩家在多个时点的转换位置与 yaw、可用/存活状态、真实移动段中点、反向 Seek 恢复存活、换边颜色、真实 Slider 输入、Play/Pause/三档速度、真实帧循环、Overlay、真实时长刻度及 Real -> Mock 切换和失败恢复。

公开样本的无界面模式为 359 项；图形模式为 362 项。输入测试通过 Godot Viewport 派发，实际触发引擎控件，不是仅直接调用时钟。

## 人工验收

1. 双击 Open Real Replay.cmd，确认地图 de_ancient、10 名玩家、32:56.203、Sample 16 Hz。
2. 点击 Play。文件起点可能仍在玩家实体初始化，时间推进后会出现玩家。
3. 拖到约 10 分钟，暂停，左右拖动观察玩家移动；暂停状态应保留。
4. 依次切换 0.5x、1x、2x 并播放；时间推进速度正确。
5. 下拉选择玩家，检查 raw / Godot XYZ 满足 scale 0.01 的轴映射；检查 yaw、health、alive。
6. 观察死亡玩家的灰色压低显示；反向 Seek 到生前应恢复原阵营颜色和体型。
7. 在比赛后段检查换边后颜色与 Alive T/CT；名单初始 team 不应覆盖当前帧 team。
8. 滚轮缩放、右键平移、Home 重置；窗口缩到 960×640，底栏和检查面板可见。
9. 用 Open Replay JSON 切换到内置 Mock，再测试原有播放操作。

## 日志与产物

- `artifacts/parser-public.log`：实际解析统计与库警告。
- `artifacts/go-tests.log`：Go 测试记录。
- `artifacts/tests.log`：Mock 结果。
- `artifacts/real-tests.log`：真实回放结果。
- `artifacts/real-viewer-report.json`：实际人数、时长、加载时间与验证标记。
- `artifacts/real-replay-120s.png`、`real-replay-600s.png`、`real-replay-960.png`：实际渲染截图。

验收在 Windows、Go 1.25.1、Godot 4.5.1 Standard、RTX 5070 Ti Laptop GPU / OpenGL Compatibility 上完成。FPS 数字为 Godot 当前计数，不是跨硬件性能保证。
