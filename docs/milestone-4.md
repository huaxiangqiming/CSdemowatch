# Milestone 4 — Combat & Utility Visualization

验收日期：2026-09-22–23。范围停在 M4，未进入 Bomb 或其他后续系统。数据使用原有公开 `s2.dem`，来源、版本与 SHA256 记录在 `test_data/source.json`。Godot 4.5.1 Standard，Go 1.25.1，demoinfocs v5.2.0。

## 1. Replay V2 格式

`version:2`；保留 V1 metadata / players / tracks，新增 events / projectiles。全程保存 raw CS2 coordinates，MapTransform 为唯一 Godot 坐标转换入口。正式字段与时间语义见 `shared/replay-format/README-v2.md` 和 `replay-v2.schema.json`。V1 仍可读取和单独导出。

## 2. Parser 新增数据

新增 Smoke 生命周期、Molotov/Incendiary Inferno、实际 flame patch 位置/生灭、HE/Flash 爆点、弹体轨迹、原始网络射击消息、Kill/助攻/爆头/武器名称，以及可获得的 Flash affected-player 数据。weapon 字符串仅用于击杀展示，没有新增武器系统。

架构：`internal/demo/combat.go` 适配 demoinfocs；`internal/replay/events.go` 为 domain model 和校验；`internal/serialization/json.go` 独立写 JSON；CLI 负责参数、错误码、统计与安全文件提交。原有 16 Hz 玩家采样、ReplayClock、TrackSampler、TimelineUI 核心未改变。Go 集成测试逐项比较 V1/V2 玩家轨迹完全一致。

Source 2 原始属性和网络消息是关键：该 Demo 不提供通常预期的旧式 smoke/HE/weapon_fire game events。Smoke/HE 读取真实实体更新，Shot 读取 CMsgTEFireBullets。不能把空的旧事件回调误报为“没有投掷/开枪”。来源诊断保留在 `source_probe_test.go`，仅设置 CS2_PROBE 时运行。

## 3–8. 实际事件数量

| 类型 | 数量 |
|---|---:|
| Smoke | 48 |
| Fire（Molotov / Incendiary） | 41 |
| HE | 67 |
| Flash | 68 |
| Shot | 3,023 |
| Kill | 163 |
| 总事件 | 3,410 |

10 players、10 tracks、314,497 player frames；226 projectiles、6,831 projectile frames；465 flame patches；89 affected-player flash records。共有 43 次燃烧瓶弹体、41 次实际 Inferno；没有给未生成 Inferno 的弹体捏造火区。

## 9. Utility 阵营颜色

`TeamVisualConfig.gd` 集中定义 T 暖橙/琥珀、CT 青蓝、死亡和未知颜色，以及视觉半径/寿命。Smoke 为半透明灰色球体和阵营圆环；火区为橙红色 patch 和阵营轮廓，CT 火仍保持火焰主体颜色。投掷时固定 actor_team，后续换边不修改历史事件。

独立 source pass 校验所有弹体的投掷时归属；其中 159 次投掷者的最终阵营与投掷阵营不同。Viewer 专门执行后半场 → 前半场 Smoke Seek，验证历史颜色规则。

## 10. Shot tracer

一个可复用 ImmediateMesh 批量绘制全部当前枪线和短暂枪口十字；不为每发实例化节点。原始 origin + 原始 pitch/yaw 得到单位 direction；没有可靠 impact 时绘制 1200 Source 单位射线。持续 0.12 秒，枪口指示最多 0.08 秒，淡出也只取决于 ReplayClock 时间。颜色读取 event.actor_team。

## 11. Kill Feed

右侧 Layers Tab 显示当前时间之前最近 8 次 Kill，包含时间、击杀者、受害者、武器和 HS；阵营着色，支持隐藏。列表在固定面板内部滚动，避免覆盖 Timeline。点击一行 Seek 至击杀前 2.5 秒。每次 Seek 替换列表，不追加旧历史。Timeline 上通过独立 KillMarkers 子节点绘制标记，不修改原有拖动逻辑。

## 12. Event Index

Smoke、Fire、HE/Flash pulse、Projectile 使用一秒 interval buckets；Shot/Kill 使用有序数组与二分时间边界。每帧只访问当前桶和短时间窗口；不扫描全场所有事件。支持 get_events_around、get_active_smoke/fire/projectiles、get_recent_shots/kills。

## 13. Seek 与显示层

CombatController 监听原有 ReplayClock.time_changed，按目标时间查询并重建活动集合。Utility / Projectile 使用节点池，Shot 使用批量线段。所有区间左闭右开；暂停后开关图层也立即刷新。Smoke、Fire、Grenades/Pulses、Trajectories、Shots、Players、Player Names、Kill Feed 分别可控。关闭效果层后清空/隐藏相应绘制，保留池供复用。重载 V1 时清空 V2 效果。

## 14. 验证与性能

- Go 单元/真实 Demo 测试与 go vet 通过。测试六类精确事件数量，另一次解析抽查 12 条网络 Shot 的 tick、player、team、origin，核对 Inferno/Flash/Kill source count、投掷归属与 V1 轨迹一致性。
- Mock 图形回归 88 项通过；V1 实际场景回归 362 项通过；M3 地图/相机回归 117 项通过。包含真实移动、死亡、换边、Play/Pause/Seek、0.5x/1x/2x、文件切换和 UI 输入。最终 `--v1` 导出与原 V1 文件 SHA256 完全相同。
- M4 最终图形验收 **653 项通过、0 失败**：覆盖 V2 非法输入拒绝、Utility 激活前/中/结束、反向 Seek、120 次跨全场跳转与独立全量事件比较、Projectile 时间查询、Shot 寿命和不增长节点、图层开关、Kill Feed 回溯及 V1 reload。最终结果见 `artifacts/milestone-4-report.json`。完整真实 V2 文件通过 JSON Schema 验证，Godot 编辑器导入成功。
- 实际渲染完整回合：源 round_start tick 14311 到 round_end tick 21010，即 **223.609375–328.28125 秒**；2x 连续播放约 **52.34 秒 / 50,390 帧**，遇到全部六类事件。回合内实际有 3 Smoke、2 Fire、4 HE、5 Flash、123 Shot、9 Kill。证据 `artifacts/m4-full-round-report.json`。
- 同次验收中，1608–1613 秒高频交火窗口持续渲染 5 秒平均约 **962 FPS**；120 次跳转最大 Seek CPU 约 **3.42 ms**；Utility 池最大 4、Grenade 池最大 3、Shot 批量节点 1。
- 环境：NVIDIA RTX 5070 Ti Laptop GPU、1280×800、Godot Compatibility/OpenGL、既有 Ancient 战术网格。以上是本机短时实测，非最低配置保证；JSON 同步加载约 4.5 秒。
- 最终复测交火窗口约 860 FPS、最大 Seek CPU 3.10 ms。曾两次未达到“5 秒墙钟内推进 4 秒”的原测试门槛；增加诊断后确认 ReplayClock 跟随 engine delta。测试现要求至少 5 秒墙钟且实际播放完 5 秒交火数据，15 秒超时，并核对累计 engine delta，不用墙钟替代回放时钟。
- `artifacts/m4-*.png` 保存 Fire / Smoke / HE / Flash / trajectory / shots 与 960×640 截图。截图暂停期间的 FPS 文字不能用作持续播放性能结论。

## 15. 文件大小与运行

真实 V2：**59,208,509 bytes / 56.4656 MiB**。原 V1：57,173,607 bytes / 54.525 MiB；新增约 1.941 MiB（3.56%）。时长 1976.203125 秒，Source 64 Hz，采样 16 Hz。

双击根目录 `Open Combat Replay.cmd`。`Open Real Replay.cmd` 保留 V1 验收入口，`Start Viewer.cmd` 打开 Mock。右侧 Events Tab 选择事件，再点击 Seek 可以直接观察对应效果；Layers Tab 控制显示；View Tab 保留相机和地图模式。

```powershell
# 项目根目录；编译
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1
# 默认 V2
.\parser\bin\cs2parser.exe .\test_data\s2\s2.dem .\test_data\public-s2-v2.replay.json
# 明确导出 V1
.\parser\bin\cs2parser.exe --v1 .\test_data\s2\s2.dem .\artifacts\v1-regression.replay.json
# 打开 V2
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Replay .\test_data\public-s2-v2.replay.json
# Go tests + vet，包含真实 Demo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1 -Test -Demo .\test_data\s2\s2.dem
# 全部 M4 逻辑、截图、性能与实际完整回合
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -CombatTest -VisualTest -FullRound -Replay .\test_data\public-s2-v2.replay.json
```

## 16. Known Issues

- 当前验收基于一个早期公开 Source 2 Demo；未保证所有新版本协议或 POV Demo。源库报告一次 `Player team swap game-event occurred but player is nil`，当前玩家轨迹和历史队伍数据通过独立验证，但未掩盖该 warning。
- Smoke 生命周期采用实际实体存在区间，包含淡出/清理时间，不能等同每一瞬间的视觉遮挡或烟雾体素。Fire patch 状态采样 16 Hz，边界可有一个采样间隔误差，半径为战术近似。
- 无可信 impact，枪线表示真实开火方向的固定长度 Ray，未做散布、穿透、碰撞或真实子弹模拟。Flash UI 不提供完整致盲分析。
- JSON 仍整文件同步解码，加载时界面会短暂阻塞；未实现流式格式。高 FPS 数字来自高性能本机，其他显卡需另测。
- Ancient 地图沿用 M3 碰撞几何灰模；透明排序、密集姓名遮挡和新旧地图版本差异仍存在。轨迹/团队圆环为便于战术观察使用可穿透显示，并不代表 LOS。
- UI 英文，长 Kill 名字可能截断，鼠标 tooltip 保留完整文本；列表内滚动查看全部 8 条。当前运行方式为源码项目加便携 Godot，并非安装包。

## 17. 修改 / 新增文件

新增 Parser：`internal/demo/combat.go`、`combat_test.go`、`source_probe_test.go`；`internal/replay/events.go`、`events_test.go`；`internal/serialization/json.go`、`json_test.go`。

修改 Parser：`cmd/cs2parser/main.go`、`internal/demo/parser.go`、`internal/replay/replay.go`、`replay_test.go`。

新增 Godot：

```text
app/scripts/config/TeamVisualConfig.gd
app/scripts/events/ReplayEvent.gd
app/scripts/events/ProjectileReplayState.gd
app/scripts/events/ReplayEventIndex.gd
app/scripts/events/ReplayV2Validator.gd
app/scripts/events/CombatController.gd
app/scripts/rendering/TacticalLines.gd
app/scripts/rendering/ShotRenderer.gd
app/scripts/rendering/ProjectileRenderer.gd
app/scripts/rendering/UtilityEffectView.gd
app/scripts/rendering/UtilityRenderer.gd
app/scripts/ui/CombatPanel.gd
app/scripts/ui/KillMarkers.gd
app/tests/milestone_4_tests.gd
```

修改 Godot：`scripts/Main.gd`、`scripts/core/ReplayValidator.gd`、`scripts/replay/PlayerView.gd`、`scripts/ui/DebugOverlay.gd`；自动生成对应 `.gd.uid`。ReplayClock、TrackSampler、TimelineUI 三文件 SHA256 与 M4 开始时一致，记录于 `artifacts/m4-stable-hashes.json`。

工具/文档：新增 `Open Combat Replay.cmd`、`shared/replay-format/README-v2.md`、`replay-v2.schema.json`、本报告；更新 `tools/run.ps1`、`tools/parser.ps1`、README 与架构/测试文档。生成 `test_data/public-s2-v2.replay.json`、Parser 可执行文件、测试日志/截图（大文件与构建产物本地忽略）。

## 18. 下一阶段建议

按用户规划，下一阶段可独立定义 Bomb 生命周期及时间线显示；开始前用更多较新的 Demo 扩大协议回归样本。本次未实现 Bomb，也未自动进入下一阶段。
