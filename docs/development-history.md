# CS2 Tactical Replay Viewer

当前增量版本 **0.8.1-dev / M8 地图可视性补完**：扩展通用斜屋顶分类；所有真实回放默认启用可关闭的高度剖切（View → Height cutaway），隐藏最高存活玩家轨迹上方 2 个场景单位以上的模型部分，可拖动滑块查看下层。真实楼层和未知结构保留在地图资产中。旧地图缓存（包括 Legacy Ancient）会独立失效并后台重建，Replay Cache 不受影响。已对本机 16 张非 vanity 地图进行转换、导航支撑和图形检查；这些地图不等同于全部完成真实长 Demo 验收。完整范围和限制见 [M8.1 验收报告](milestone-8-1.md)。Windows 入口为 `dist/windows/CS2TacticalReplay.exe`。

下面保留 M8 及更早版本的历史说明；当前行为以 M8.1 报告为准。

## 从 GitHub 获取源码

仓库包含 Godot Viewer、Go Parser/地图转换器、测试、格式规范和文档。历史说明中提到的便携引擎、Windows EXE、真实 Demo、Valve 地图、测试截图和本机缓存均为本地验收文件，不随源码上传。合成的 `app/data/mock_replay.json` 保留用于基础测试。

开发需要 Go 1.25+、Godot 4.5.1 Standard 和 PowerShell。将 Godot 放到 `.tools/godot/`，或通过 `tools/run.ps1` 使用 PATH 中的 `godot`/`godot4`。编译 Parser 使用 `tools/parser.ps1`；打开 Mock 使用 `Start Viewer.cmd`；基础测试使用 `Run Tests.cmd`。地图自动准备需要用户本机合法安装的 CS2，以及本地放置的 Source2Viewer CLI 及依赖。Windows 完整打包还需 `.tools/godot/` 下的 Windows export templates 和 `.tools/vrf/` 工具，详细文件要求见 `tools/build_windows.ps1`。

真实 Demo 测试需自行提供样本，来源记录在 `test_data/`。地图缺失不会阻止回放。源代码上传不等于已经发布可下载的 Windows 安装包。

当前版本 **0.8-dev**：新设置默认 Auto。地图缺失或过期时先使用 Plane 播放，后台准备并自动切换 Tactical Map，保留时间、播放状态、相机、玩家选择和图层。已实际准备并验证 Dust2、Vertigo、Inferno，兼容 Ancient、Mirage。验收范围、截图和限制见 [M8 报告](milestone-8.md)。

Milestone 7 已完成：**真实 Demo → Replay；缺地图自动使用 Plane → 后台准备战术地图 → 保留时间 Reload Map**。加入透明状态图标、携带 Bomb 时只显示红名，以及 CS2 安装发现和地图设置。完整文件清单、三张真实 Demo 验收、性能数据和限制见 [Milestone 7 报告](milestone-7.md)。

Viewer 使用 Godot 4.5.1 Standard / GDScript；Parser 使用 Go 1.25 和固定版本 demoinfocs v5.2.0。原有 ReplayClock、Timeline、玩家插值保持不变，兼容 V1 和 Mock。新增真实 Smoke、Fire、HE、Flash、弹体轨迹、Shot 与 Kill；新增真实 Bomb 状态、地图资产缓存和后台 Replay 加载；未实现经济、音频或网络服务。

## 普通用户启动

双击 `dist/windows/CS2TacticalReplay.exe`，在首页选择 **Open Demo** 或拖入 `.dem`。程序自动处理 Parser 和缓存，无需命令行、Go、Godot 或手动 JSON。请保留整个发行目录，包括 PCK、cs2parser.exe、cs2maptool.exe 和 map-tools。

缺少地图时自动进入 **Debug Plane**，不会因为地图缺失进入错误页。Settings 的 MAPS 可发现或浏览本机 CS2，选择 Ask / Auto / Never（新设置默认 Auto，保留旧用户选择）。Auto 会自动加载准备结果；Ask 可使用 **Prepare Tactical Map → Load Map**。Settings 支持 Prepare / Rebuild / Delete Cache / View Log。包内不含 Valve 模型；Ancient 原缓存可复用，Mirage 已验证本机自动准备。顶部 Home 返回首页，Settings 和 Recent Replays 重启后保留。详见 [Windows 快速开始](windows-quick-start.txt)。

当前工作区的 `test_data/damage-source.dem` 是真实 Mirage 验收样本，包含 264 条伤害，其中 HE 15、Inferno 38；`test_data/third-map.dem` 是真实 Vertigo 样本，已验证自动准备和真实地图回放。Flash、Burning、HE Hit、In Smoke 使用透明图标，Bomb Carrier 仅改变姓名颜色。View 可打开 Debug；Events 的 player_hurt 过滤与 Inspect victim at +0.2s 用于复核真实伤害。

## 开发者旧入口与 Mock

当前工作目录已包含便携 Godot、已编译 `parser/bin/cs2parser.exe`、公开 Demo、解析结果和本机提取的 Ancient 战术模型。可直接运行。

- 双击 **Open Combat Replay.cmd**：打开真实 `de_ancient` M5 回放（兼容 V2，含 Bomb）。
- 双击 **Open Real Replay.cmd**：打开保留的 V1 玩家轨迹回放。
- 双击 **Start Viewer.cmd**：打开原有两个玩家的 Mock 回放。
- Viewer 左侧 **Open Replay JSON** 可以选择其他 V1 / V2 JSON；也支持将单个 JSON 拖入窗口。
- 初始暂停在 0 秒；真实 Demo 前几帧可能还没有有效玩家，点击 Play 后开始显示。

运行回放不需要 Go 或 .NET。重新编译 Parser 才需要 Go 1.25 或更新兼容版本。

## Demo 到 Replay

以下命令在项目根目录执行：

```powershell
# 可选：下载并校验公开样本；当前目录已经准备好了
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\fetch-test-demo.ps1

# 编译独立解析器
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1

# .dem -> JSON，父输出目录须存在
.\parser\bin\cs2parser.exe .\test_data\s2\s2.dem .\test_data\public-s2-m5.replay.json

# 可选：输出旧 V1
.\parser\bin\cs2parser.exe --v1 .\test_data\s2\s2.dem .\artifacts\v1-regression.replay.json

# JSON -> Godot
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Replay .\test_data\public-s2-m5.replay.json
```

CLI 成功退出码为 0；输入/解析/校验/写入失败为 1；参数错误为 2。失败有明确 stderr 消息。验证成功后通过临时文件提交 JSON，失败不破坏已有输出。命令不会启动 CS2，也不需要 CS2 安装或运行。

在 Godot 编辑器中打开：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Editor
```

或者导入 `app/project.godot` 后按 F5。只复制源码到新机器时，需要安装 [Godot 4.5.1 Standard](https://godotengine.org/download/archive/4.5.1-stable/)，将引擎放入 `.tools/godot/` 或把 `godot` / `godot4` 加入 PATH。依赖安装和测试样本下载需要联网；构建完成后的 Parser / Viewer 本地运行不需要联网。

## 操作

| 操作 | 效果 |
|---|---|
| Play / Pause、空格 | 播放 / 暂停 |
| Restart | 回到 0 秒，保留播放状态 |
| 点击 / 拖动 Timeline | 立即 Seek 并更新位置、朝向与离散状态 |
| 0.5x / 1x / 2x | 切换速度 |
| 场景滚轮 | 缩放 |
| 场景右键拖动 | 平移 |
| 中键拖动 / Alt + 左键拖动 | 围绕 Pivot 旋转 |
| 1 / 2 / 3 | Top / 45° / Free Perspective |
| P / 投影按钮 | 正交 / 透视切换 |
| 右侧模式 / 透明度下拉框 | Normal / X-Ray / Tactical；100 / 75 / 50 / 25% |
| Home / Reset camera | 恢复适合本次回放的构图 |
| Inspect player 下拉框 | 查看玩家原始与转换坐标、yaw、health、alive |
| 右侧 Layers Tab | 开关 Players / Names / Smoke / Fire / Grenades / Trajectories / Shots / Kill Feed |
| 右侧 Events Tab | 按类型检查真实事件及 Seek 至事件发生时间 |
| Kill Feed 行 | 显示最近 8 次 Kill，点击回到该 Kill 前 2.5 秒；列表内部可滚动 |

播放时拖动会临时暂停，释放后恢复；原本暂停时拖动仍保持暂停。结束后停在末帧，再按 Replay 从头开始。阵营从当前帧读取，因此换边后会变色。死亡 Capsule 变灰并压低，无有效 pawn 的玩家隐藏。

## 架构和文件

```text
PROJECT_SPEC.md                          从原始 project_spec.docx 提取的完整 100 节规范
parser/
  go.mod / go.sum                        固定依赖与校验和
  cmd/cs2parser/main.go                  CLI、错误码、安全输出与统计
  cmd/cs2parser/main_test.go             CLI 失败与文件保护测试
  internal/demo/parser.go               demoinfocs 适配、玩家身份、原始状态
  internal/demo/sampling.go              16 Hz 采样门限
  internal/demo/parser_test.go           采样、身份、损坏输入、真实源数据比对
  internal/replay/replay.go              V1 类型与输出校验
  internal/replay/replay_test.go         校验器测试
  bin/cs2parser.exe                      已编译程序（本地忽略）
app/
  project.godot                          Godot 项目配置
  scenes/Main.tscn                       回退 Plane、Camera Rig、Controller、UI
  scenes/replay/Player.tscn              Capsule、方向标记、姓名
  data/mock_replay.json                  已迁移至同一 V1，2 人、20 秒、16 Hz
  scripts/Main.gd                       打开文件并连接地图、播放、UI 模块
  scripts/core/ReplayLoader.gd          文件读取与 JSON 解析
  scripts/core/ReplayValidator.gd       V1 校验、内存表示转换
  scripts/core/ReplayClock.gd           原有唯一时间源，未修改
  scripts/core/TrackSampler.gd          原有二分与插值，加离散状态和中断处理
  scripts/core/ReplayController.gd      采样、集中转换、动态玩家
  scripts/map/MapTransform.gd           唯一 CS2 -> Godot 坐标边界
  scripts/map/MapDefinition.gd          每张地图独立配置
  scripts/map/MapManager.gd             地图资源、材质、透明度和回退
  scripts/map/DebugMapTransform.gd      旧类名兼容入口
  maps/de_ancient/map.json / map.glb    配置 / 本地 Ancient 模型
  scripts/replay/PlayerView.gd          阵营、姓名、alive 状态与显示
  scripts/ui/TimelineUI.gd              原有控制流程，动态时长和重复加载支持
  scripts/ui/DebugOverlay.gd            统计与玩家检查
  scripts/camera/TacticalCamera.gd      Rig / Pivot / Camera3D，旋转和投影
  scripts/ui/ViewControls.gd           显示模式、透明度和相机预设
  scripts/world/WorldAxes.gd            原点与 XYZ 轴
  scripts/world/TestGrid.gd             Plane 网格
  tests/run_tests.gd                    Mock 回归及 V1 校验
  tests/real_replay_tests.gd             真实回放场景与输入测试
  tests/milestone_3_tests.gd             相机、地图对齐、X-Ray 和 FPS
shared/replay-format/
  README.md                            V1 字段、时间、采样和坐标约定
  replay-v1.schema.json                 JSON Schema
  example.replay.json                   短小的完整有效示例
Start Viewer.cmd / Open Real Replay.cmd / Run Tests.cmd
 tools/run.ps1 / tools/parser.ps1 / tools/fetch-test-demo.ps1
 docs/architecture.md / docs/testing.md / docs/milestone-2.md
 test_data/README.md / test_data/source.json
```

上表为既有播放与地图基础；M4 新增的 events / rendering / config 模块、Go serializer 和全部变更清单见 [M4 报告](milestone-4.md)。[V2 格式说明](../shared/replay-format/README-v2.md) 定义了事件归属、时间与区间语义。

二进制、地图 GLB、`.dem`、真实 Replay、下载归档、`.godot` 和测试产物不进入版本控制。`.gd.uid` 是 Godot 自动生成的稳定标识。原始 `project_spec.docx` 未修改。当前范围为 Milestone 6，完成后停止。地图来自本机 CS2；另一台机器可用 `tools/import-ancient.ps1 -CS2Path <安装目录> -Python python` 重建，需要 Python/pip/numpy，首次联网下载官方 Source2Viewer CLI。

## 自动测试

```powershell
# Go 单元测试、公开 Demo 的 30 个源快照比对、go vet
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1 -Test -Demo .\test_data\s2\s2.dem

# 原有 Mock 回归
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Test
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -VisualTest

# 真实回放，增加 -VisualTest 时打开实际图形窗口并截图
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -RealTest -Replay .\test_data\public-s2.replay.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -RealTest -VisualTest -Replay .\test_data\public-s2.replay.json

# Milestone 3 相机 / 实际几何对齐 / X-Ray 画面对比 / FPS
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -MapTest -VisualTest -Replay .\test_data\public-s2.replay.json

# Milestone 4 事件、连续 Seek、图层、截图、性能及完整真实回合
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -CombatTest -VisualTest -FullRound -Replay .\test_data\public-s2-v2.replay.json
```

测试成功为退出码 0，失败非 0。当前验收见 `docs/milestone-6.md`；历史地图 / Parser 验收见 `docs/milestone-3.md` 和 `docs/milestone-2.md`。

## 已知限制

- 两份公开 CS2 Demo 完成验收，不能据此保证所有新版本 / POV Demo 都兼容。旧 Ancient 样本没有 PlayerHurt；真实伤害验收使用第二份 Mirage 样本。
- JSON 未压缩，M5 V2 样本约 56.91 MiB；解码与准备约 4.3 秒在后台完成。主线程场景提交仍可能短暂卡顿，尚未流式加载。
- Smoke / Fire 为战术近似体积和区域；射击线无可信 impact 时按真实方向绘制固定长度，不是弹道物理。详见 M4 Known Issues。
- 16 Hz 状态会量化到采样时刻，不能复原两个样本之间的瞬时变化。超过 0.25 秒的数据缺口或相邻位置跳变超过 256 CS2 单位时保持前一状态，避免虚假的平滑移动。
- Ancient 使用原始碰撞几何的灰色战术模型，非原版视觉地图；透明模式可能出现重叠排序。未知地图回退到 Plane。
- 透视近距离缩放受保守地图高度上界限制；未实现室内漫游。当前地图与较早 Demo 不保证同一版本，实际 1,393 个轨迹抽样均命中地图，99% 高度差小于 50 Source 单位。
- 玩家密集时姓名可能重叠，可缩放或使用下拉框检查；UI 暂为英文。
- 当前原型 V1 取代上一阶段的临时格式。仓库内 Mock 已迁移，旧的外部 `godot_y_up` JSON 不再直接兼容。
- 已导出 Windows 便携程序；未制作安装器或自动更新。完成 M6 后没有继续下一阶段。

## M5 地图缓存与异步加载

地图准备一次存放于 `%LOCALAPPDATA%/CS2TacticalReplay/maps/`，与 Replay 文件分离。Ancient 首次由现有本地准备资产安装缓存，后续校验并复用；缺失地图可回退 Debug Plane，View 提供 Retry。所有打开/拖放操作使用后台 JSON 加载，节点在主线程创建。

右侧 Layers 可选择 Smoke Low / Tactical / Strong，以及 Flash Effects、Flashed Players、HE Effects、Bomb 等开关。Bomb Timer 表示距记录中的实际结束事件的时间，未知时不猜测。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Milestone5 -VisualTest -FullRound -Replay .\test_data\public-s2-m5.replay.json
```

M5 视觉对比图保存在 `artifacts/m5-*.png`，完整 24 项验收见 `docs/milestone-5.md`。

## M6 构建和测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1 -Test -Demo .\test_data\s2\s2.dem -DamageDemo .\test_data\damage-source.dem
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Milestone6 -VisualTest
```

构建需要 Go 和 Godot 4.5.1 Windows export templates，路径见 export_presets.cfg；当前工作区已准备。M6 场景测试 1,203 项、正式 EXE 两进程 17 项全部通过，M1–M5 回归继续通过。缓存首次/重启耗时及测量边界见报告。用户数据默认在 `%LOCALAPPDATA%/CS2TacticalReplay/`。
