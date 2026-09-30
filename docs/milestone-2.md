# Milestone 2 验收报告

本阶段已完成真实 CS2 Demo 到测试 Plane 回放的最小闭环，并在此停止。未开发真实地图、Valve 资源转换、Smoke、Flash、Molotov、HE、Bomb、Kill、Damage、Economy、Weapon、Bullet、Audio、Video Export、Steam API、AI 或网络服务。

## 1 创建或修改的文件

新增：

- `PROJECT_SPEC.md`：从原始 Word 文档完整提取 100 节项目规范。
- `parser/go.mod`、`go.sum`：固定 demoinfocs v5.2.0。
- `parser/cmd/cs2parser/main.go`、`main_test.go`：独立 CLI 与错误路径测试。
- `parser/internal/demo/parser.go`、`sampling.go`、`parser_test.go`：协议适配、16 Hz、真实源数据验证。
- `parser/internal/replay/replay.go`、`replay_test.go`：V1 模型和 Validator。
- `app/scripts/core/ReplayValidator.gd`：Viewer 侧 V1 校验。
- `app/scripts/map/DebugMapTransform.gd`：集中坐标与 yaw 转换。
- `app/scripts/ui/DebugOverlay.gd`：统计和玩家检查。
- `app/tests/real_replay_tests.gd`：真实回放验收。
- `shared/replay-format/replay-v1.schema.json`、`example.replay.json`：正式 Schema 和有效例子。
- `tools/parser.ps1`、`fetch-test-demo.ps1`、`Open Real Replay.cmd`：构建、公开样本、运行入口。
- `test_data/README.md`、`source.json`：来源、固定提交与 SHA256。
- 本验收报告。

修改：

- `ReplayLoader.gd`、`ReplayController.gd`、`TrackSampler.gd`、`Main.gd`。
- `PlayerView.gd`、`Player.tscn`、`TacticalCamera.gd`、`TimelineUI.gd`。
- `mock_replay.json`、`run_tests.gd`、`tools/run.ps1`、`.gitignore`。
- 根 README、架构说明、测试说明、Replay Format 说明。

`ReplayClock.gd` 未修改；Timeline 控制流程和插值算法保留，只增加真实数据必要的扩展。

本机产物：`parser/bin/cs2parser.exe`、`test_data/s2/s2.dem`、`test_data/public-s2.replay.json`、测试日志和截图。上述大文件/二进制不纳入版本控制。

## 2 Go Parser 架构

`CLI → internal/demo（demoinfocs 适配 + 身份 + 采样）→ internal/replay（纯数据 + Validator）→ JSON`。

CLI 负责文件头、输入输出隔离、错误码、统计和临时文件提交。Protocol adapter 仅读取本阶段的玩家状态，不依赖 Godot。输出前 Validator 检查完整关系和数据约束。

## 3 Replay Format V1 最终结构

- 顶层：`version`、`metadata`、`players`、`tracks`。
- metadata：`map`、`duration`、`source_tick_rate`、`sample_rate`、`coordinate_system=cs2_raw`、`source_start_tick`、`source_end_tick`。
- player：`id`、`steam_id`（字符串，缺失为空串）、`name`、`team`（初始阵营）。
- track：`player_id`、`frames`。
- frame：`time`、`tick`、`position={x,y,z}`、`yaw`、`health`、`alive`、`team`（当前阵营）、`available`。

所有文件位置和 yaw 均为原始 CS2 坐标/角度；唯一世界变换在 Viewer 的 DebugMapTransform。原始数据仍完整保留，以供 Overlay 检查。Mock 也采用同样格式、16 Hz，每人 321 帧。

## 4 Demo 如何解析

使用官方 `github.com/markus-wa/demoinfocs-golang/v5` 固定版本 `v5.2.0`，Go 1.25.1 构建。文件须具有 CS2 `PBDEMS2` 头。Source 2 文件头/ServerInfo 提供地图和 tick rate；FrameDone 后从玩家实体读取原始状态。

16 Hz 门限选择现有源快照，不输出每个 tick，不在 Parser 中转换坐标。禁止范围内的游戏事件不注册业务回调、没有输出数据模型；底层库本身仍需解码协议实体。

测试 Demo 来自 demoinfocs 官方回归数据仓库 `markus-wa/cs-demos-2` 的 `s2.7z / s2/s2.dem`，固定提交和 SHA256 记录于 test_data/source.json。未重新发布 Demo。

## 5 运行命令

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1
.\parser\bin\cs2parser.exe .\test_data\s2\s2.dem .\test_data\public-s2.replay.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Replay .\test_data\public-s2.replay.json
```

也可以直接双击 `Open Real Replay.cmd`。默认 `Start Viewer.cmd` 继续打开 Mock。

Parser 成功退出 0；输入/解析/验证/写入错误退出 1；参数错误退出 2。最终编译与真实解析命令均已成功。

## 6 Replay 大小

实际文件 **57,173,607 字节**，约 **54.53 MiB**，未压缩紧凑 JSON。源 Demo 为 39,265,142 字节。

## 7 实际玩家数量

**10 名**，全部从源 Demo 动态发现，不硬编码 10 人。地图 `de_ancient`，时长 **1976.203125 秒（32:56.203）**。

## 8 实际 Player Track 数量

**10 条**，总计 **314,497 帧**。源 tick rate **64 Hz**，目标采样率 **16 Hz**，源 tick 范围 **0–126477**。晚加入的不可用前缀和最后终点包含在总帧数中。

## 9 Godot 是否成功播放真实轨迹

**成功**。已在真实 OpenGL 窗口渲染和验证，仍然只有测试 Plane。动态 Capsule、名字、阵营、缺席隐藏、alive 显示、换边、原始/转换坐标调试信息均可用。

最终测得加载耗时约 **3.56 秒**。这是本机单次测试值。Godot 记录的静态分配量约 371.0 MiB，不等同于进程总内存或峰值。

实际截图：`artifacts/real-replay-120s.png`、`real-replay-600s.png`、`real-replay-960.png`。

## 10 Play Pause Seek 验证

**全部通过**，0.5x / 1x / 2x 也通过。验证包括真实帧循环、实际 Timeline 控件输入、反向 Seek、离散状态恢复、文件切换与错误恢复。

- Go：`go test -v ./...`、`go vet ./...` 成功。
- 真实源数据：独立重新解码 30 个源 tick 快照，对照 XYZ、yaw、health、alive、team 全部一致。
- Mock：84 项无界面检查、88 项图形检查通过。
- Real：359 项无界面检查、362 项图形检查通过。
- 图形窗口：1280×800、960×640 均已检查。

记录见 artifacts/go-tests.log、tests.log、real-tests.log、real-viewer-report.json。

## 11 Known Issues

1. 当前只完成一份较早公开 CS2 样本的全链路验证，尚未验证最新比赛/所有 POV 录制或所有协议版本。
2. 解析库输出一条非致命警告 `Player team swap game-event occurred but player is nil`。警告未隐藏，记录在 parser-public.log；30 个独立源样本对照及真实换边显示检查均通过，但不能将抽样对照视为全量逐 tick 证明。
3. 未压缩 JSON 体积较大，同步加载约 3.5 秒会暂时阻塞界面；没有异步加载或缓存。
4. 16 Hz 为观测采样，瞬时状态可能延迟最多一个常规采样间隔；稀疏源帧可能更久。跨缺席、复活、换边、大间隔和明显瞬移采用前值保持。
5. Plane 不是地图：没有墙体/楼层/地形，真实 Z 高度保留，因此玩家可能悬在参照平面上方。
6. 玩家密集时姓名可能重叠。UI 英文，其他系统/显卡未验证；Viewer 尚未导出独立发行版。
7. 无 SteamID 的实体重建无法可靠去重，可能分配新的本地 ID。
8. 正式 V1 与之前实验性 godot_y_up JSON 不兼容；仓库 Mock 已迁移并通过全部回归。

## 12 下一阶段建议

先用近期比赛 Demo 扩充兼容性回归，并考虑后台加载/解析进度；随后再单独规划一张真实地图的资源策略与坐标对齐。需要用户另行确定下一阶段范围，本次不继续实现。
