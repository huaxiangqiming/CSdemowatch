# Milestone 6 — Product Shell + Player Tactical Status

状态：已完成，停在 M6。应用版本 v0.6-dev，Parser 0.6.0，Godot 4.5.1，demoinfocs v5.2.0。普通入口为 `dist/windows/CS2TacticalReplay.exe`，无需手动生成 JSON 或运行命令行。以下记录区分真实 Demo、视觉测试 fixture、开发引擎和正式导出程序。

## 1. PlayerStatusResolver 架构

`PlayerStatusType` 定义五种状态；`PlayerStatusResolver` 由 ReplayEventIndex、BombReplayState 和当前玩家原始状态推导结果；`PlayerStatusRenderer` 统一管理每名玩家的 `PlayerStatusIndicator`。Flash 和伤害区间预建按秒、按玩家的索引，不逐玩家逐帧扫描整场事件。图标通过相机投影到 CanvasLayer，固定 24px、27px 间距，横向居中排列，不随世界旋转变侧面。Layers 有总开关和五个独立开关。

## 2. 新增 Damage 数据来源

Go Parser 直接订阅 demoinfocs 原生 `PlayerHurt`，保留事件 tick、攻击者及受害者 ID/当时阵营、HealthDamage、剩余 Health、WeaponString。来源仅做小写与去空白处理，缺失记为 unknown；Parser 不生成 UI 状态，不按爆点距离补造伤害。

既有 Ancient 公开样本没有原生 PlayerHurt，额外 raw Generic `player_hurt` 检查也为零。因此使用第二个公开真实样本：[demoparser test_demo.dem](https://github.com/LaihoE/demoparser/blob/main/src/parser/test_demo.dem)。本地为 `test_data/damage-source.dem`，来源记录为 `test_data/damage-source.json`。

- Demo：60,601,900 bytes；SHA256 `84a1a4191302bdd2a3bbb5a727842093744b1fb1a228aeec630369e44b622cb2`。
- 地图 de_mirage，906.015625 秒，64 Hz 源 tick、16 Hz 玩家采样。
- 10 players、10 tracks、144,980 frames、1,831 events、151 projectiles。
- `test_data/damage-source.replay.json`：27,261,511 bytes。保存原始 CS2 坐标。
- Mirage 在本阶段使用 Debug Plane，没有新增真实 Mirage 地图。

## 3. Player Hurt 实际数量

264 条 PlayerHurt，其中 hegrenade 15、inferno 38。其余为 ak47 75、m4a1 38、mac10 22、hkp2000 20、deagle 9、p250 8、glock 7、mp9 6、ssg08 6、awp 6、fiveseven 4、unknown 4、famas 4、smokegrenade 2。非 HE/火焰来源不会显示 HE_HIT/BURNING。

独立 Go 测试重新遍历原生回调，对全部 264 条的 tick、双方 ID/阵营、伤害、剩余生命和来源逐项比对。示例：tick 18066 / 282.28125 秒为 HE 伤害 26、剩余生命 74；tick 34334 / 536.46875 秒为 inferno 伤害 1、剩余生命 47。

## 4. HE Hit

正伤害且 `damage_source == hegrenade`，受害者在 `[event.time, event.time + 0.8)` 显示黄色冲击图标。没有 proximity 判断，也没有 wall-clock Timer。

## 5. Burning

正伤害且来源为 molotov/incgrenade/incendiary/inferno，区间为 `[event.time, event.time + 0.75)`。连续真实伤害的区间并集使图标持续，最后一次伤害后自动结束；本次实际火伤来源全部为 inferno。

## 6. In Smoke

`is_inside_tactical_smoke()` 在当前 Replay Time 检查活动 Smoke。与现有战术球体一致：源坐标半径 145，球心为爆点上方 116 单位，玩家检查点为 feet 上方 85 单位。玩家需要存活且位置有效。显示灰色 Cloud，与烟雾投掷者队伍颜色无关。这是战术体积近似，不是 CS2 voxel、LOS 或引擎级 occupancy。

## 7. Flashed 接入

真实 `affected_players` 的受影响玩家和持续时间接入统一索引，保留原有区间语义。旧 `FlashedPlayerRenderer.gd` 作为兼容入口继承统一 renderer，不再独立叠加另一套图标。白色星芒与 HE 冲击图标有明显差别。

## 8. Bomb Carrier 视觉

继续读取 `BombReplayState.at(time)`：携带者姓名红色、名字上方红色 C4，Capsule 保持当前队伍颜色。旧 carried label 隐藏以免重复；Dropped/Planted/Timer 保留。Seek、换人及图层开关同步恢复正确姓名颜色。

## 9. Status Seek 验收

测试全部 53 条 HE/火伤区间，覆盖开始、中间和结束；100 个随机 Seek × 10 名玩家，对五种状态与独立全扫描 oracle 比对。覆盖暂停、Play、0.5x/1x/2x、镜头三预设和各层开关。多图标截图中专门的三状态 fixture 仅用于布局测试，没有写入真实 Replay；真实 HE+C4 画面另有截图。

## 10. Home Screen

`HomeScreen` 只负责 UI 和意图信号：标题、副标题、版本、Drop Demo/Open Demo、Recent Replays、Settings。暗色界面支持 1280×720 与 1920×1080。普通 FileDialog 只选择 `.dem`；错误拖入文件显示提示。Home 不创建 3D Replay Scene。

## 11. AppController / AppState

`Application.tscn` 是正式启动场景；AppController 管理 HOME、LOADING、REPLAY、SETTINGS、ERROR。Main.tscn 仍是 Viewer，核心播放模块继续复用。返回 Home 释放整个 Viewer、选中玩家、Clock 和大型 Replay 数据；Recent 只持有 metadata。Settings 打开时暂停 Replay。非 REPLAY 状态限制 60 FPS。

## 12. DemoOpenService

流程为选择/拖入 Demo → 后台 SHA256 → ReplayCache → 缓存有效则复用，否则隐藏运行 cs2parser → ReplayLoadJob 解码/校验 → 地图准备 → 主线程提交 Viewer。工作线程只处理数据，不创建 SceneTree 节点。捕获合并 stdout/stderr 和 exit code，写入应用日志。取消是安全阶段边界检查/当前操作结束后丢弃结果，不强杀线程。

## 13. Replay Cache

默认目录 `%LOCALAPPDATA%/CS2TacticalReplay/replays/<demo-sha256>/`，含 `replay.json`、`cache.json`。Manifest 含 demo_hash、demo_size、demo_last_modified、parser_version、replay_version、created_at、source_demo_path、replay_sha256。校验 Demo hash、Parser 0.6.0、Replay 2 和 Replay 内容 SHA256；加载器继续执行结构校验。损坏缓存有源文件时自动重新解析。测试可用 `CS2_REPLAY_DATA_ROOT` 隔离数据目录。

## 14. 第一次打开

正式 EXE 新进程、空缓存：选择真实 Mirage Demo，计算 hash、启动 Parser、写入缓存、加载 Replay。缺少地图显示友好页面，选择 Use Debug Plane 后继续。测得打开耗时 4,017ms；该计时不包含用户在地图选择页停留时间。

## 15. 第二次打开

关闭并重启同一正式 EXE，点击 Recent Replay，确认 cache hit、不再解析，测得 1,729ms。仍需 hash/校验/JSON 解码和 Scene 创建，不是零成本加载。两次使用相同测试数据目录。

## 16. Recent Replays

`recent_replays.json` 为 `{version:1,replays:[...]}`，最多 15 条，按 hash 去重。每条包含 demo_path、demo_hash、file_name、map、duration、last_opened、replay_cache_key。首页显示地图、时长、上次打开和文件名。原 Demo 缺失时提示并允许使用有效缓存；两者均不可用时进入可恢复错误页面。重启持久化已测。

## 17. SettingsStore

统一 `settings.json`，加载时验证，临时文件写入后替换；支持 Reset Defaults。包含 CS2 安装路径、Player Name Size、Player Scale、Smoke Visibility、Map Opacity、T/CT 颜色、Pan/Zoom/Orbit 速度及默认图层。提供缓存目录入口。可即时应用的选项更新当前 Viewer。正式 EXE 重启验证 smoke=2、map opacity=0.5、name size=18 保持，再验证恢复默认。CS2 路径目前仅保存配置，不自动转换地图。

## 18. Error Handling

AppError 保存 code、title、message、technical_details、recoverable、suggested_action。ErrorScreen 显示人可读说明、Home、View Log；缺地图提供 Use Debug Plane。覆盖不存在路径、非法拖入、损坏 Demo、Parser 缺失/失败、损坏缓存、缺原文件缓存回放和 unsupported map。日志位于数据根目录 `logs/`，包含 Parser 输出。错误不会要求普通用户手动修改 JSON。

## 19. Loading Stages

显示实际阶段：Checking Replay Cache、Parsing Demo、Loading Replay、Checking Tactical Map、Loading Tactical Map、Preparing Scene。没有可靠 tick 进度时使用 indeterminate activity，不编造百分比。取消等待当前安全操作结束后返回 Home。

## 20. Windows Build

`dist/windows/` 必须作为完整目录保留：

| 文件 | 大小（bytes） |
|---|---:|
| CS2TacticalReplay.exe | 96,725,504 |
| CS2TacticalReplay.pck | 363,156 |
| cs2parser.exe | 12,341,248 |

另附 README.txt。无需安装 Godot/Go 便可运行导出程序。没有 Installer 或自动更新。包不包含 Valve 地图 mesh；本机已准备 Ancient 缓存可复用，新机器没有缓存时选择 Debug Plane。

开发者重建：安装兼容 Go，将 Godot 4.5.1 引擎与对应 Windows x86_64 debug/release export templates 放在 `.tools/godot/`，执行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_windows.ps1`。模板路径见 `app/export_presets.cfg`。普通用户直接双击 EXE。

## 21. 正式入口验收

实际启动导出 EXE 并操作 Open Demo 文件对话框，确认 Home、Loading 和无 Parser Console。另用同一正式 EXE 执行外部验收脚本，实例化包内 Application 场景并验证生产信号链路。两次独立进程共 17 项检查，无失败；不是只运行编辑器项目。最终截图已打开人工检查。

## 22. 多 Session

覆盖 Mirage A → Home → A 缓存命中 → Home → Ancient B。返回 Home 后 viewer 为 null，切换后地图/事件/玩家属于 B，没有 A 状态残留。正式导出也覆盖 A → Home → B。Ancient 0 秒可能尚无有效 pawn，Play 后出现玩家，这是源数据行为。

## 23. 内存、Loading、FPS

开发引擎 M6 测试：首次 5,116ms、缓存 2,808ms；Godot MEMORY_STATIC 从 Replay 237,504,199 bytes（226.50MiB）降至 Home 57,827,029 bytes（55.15MiB）。这不是进程 RSS、GPU 内存或峰值内存。

最终 Release 两次进程：首次 4,017ms，重启缓存 1,729ms；Loading 帧最大间隔分别 35.177ms / 197.895ms，后者包含随后 Ancient 加载。仍存在场景提交短暂停顿。Release MEMORY_STATIC 返回 0，表示该指标不可用，不能解释为零内存。

正式 EXE 在 RTX 5070 Ti Laptop、1920×1080、Mirage Debug Plane、530–535 秒、1x 播放的五秒窗口测得约 592 FPS；这不是 Ancient 或低配机器的性能承诺。

## 24. 文件清单

新增源码：

- `app/scenes/Application.tscn`、`app/export_presets.cfg`。
- `app/scripts/application/`：AppController、AppError、AppInfo、ApplicationLog、DemoOpenService、ErrorScreen、HomeScreen、LoadingScreen、RecentReplays、ReplayCache、SettingsScreen、SettingsStore、ShellStyle（均为 .gd，另有 Godot .uid）。
- `app/scripts/status/`：PlayerStatusType、PlayerStatusResolver、PlayerStatusIndicator、PlayerStatusRenderer（.gd 及 .uid）。
- `parser/internal/demo/damage.go`、`damage_test.go`、`damage_probe_test.go`。
- `app/tests/milestone_6_tests.gd`、`milestone_6_export_tests.gd`（及 .uid）。
- `tools/build_windows.ps1`、`docs/milestone-6.md`、`docs/windows-quick-start.txt`、`test_data/damage-source.json`。

修改源码/配置/文档：

- `app/project.godot`、`app/scripts/Main.gd`、`app/scripts/core/ReplayLoadJob.gd`。
- `app/scripts/events/ReplayEvent.gd`、`ReplayV2Validator.gd`、`CombatController.gd`。
- `app/scripts/rendering/FlashedPlayerRenderer.gd`、`BombRenderer.gd`。
- `app/scripts/replay/PlayerView.gd`、`app/scripts/config/TeamVisualConfig.gd`、`app/scripts/camera/TacticalCamera.gd`、`app/scripts/ui/CombatPanel.gd`。
- `parser/internal/demo/combat.go`、`combat_test.go`、`parser/internal/replay/events.go`、`parser/cmd/cs2parser/main.go`。
- `shared/replay-format/replay-v2.schema.json`、`README-v2.md`、`tools/parser.ps1`、`tools/run.ps1`、`Start Viewer.cmd`、`.gitignore`、`README.md`、`docs/architecture.md`、`docs/testing.md`。

本地生成产物：Parser/Windows binaries、Godot export templates、真实 Demo/Replay、`artifacts/m6-*`、`artifacts/milestone-6-report.json`、隔离测试缓存和日志。它们不是需手工维护的源码。此目录无 Git，清单按本阶段编辑记录整理；自动导入缓存不逐项列出。

稳定文件 SHA256 与 `artifacts/m6-stable-hashes.json` 一致：ReplayClock、TrackSampler、TimelineUI、ReplayEventIndex、BombReplayState、MapAssetCache、MapAssetManager；没有重写上述核心。

## 25. 测试结果与复现

| 测试 | 本次结果 |
|---|---|
| Go 顶层测试（包含真实两个 Demo） | 11 通过；2 个可选诊断默认跳过 |
| go vet | 通过 |
| M1 Mock | 88 检查通过 |
| M2 Real V1 | 362 检查通过 |
| M3 Map/Camera | 117 检查通过；包含 1,393 个地图对齐射线样本 |
| M4 Combat | 653 检查通过 |
| M5 | 285 检查通过 |
| M6 开发场景 | 1,203 检查、0 失败 |
| M6 正式 EXE 两次进程 | 6 + 11 检查、0 失败 |
| V2 JSON Schema | 既有 M5 与新 M6 Replay 均通过 |

M4/M5 历史 FullRound 报告保留；本阶段回归没有重新运行 FullRound，不把历史结果当本次测试。

```powershell
# 在项目根目录执行；测试样本已经在当前工作区
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1 -Test -Demo .\test_data\s2\s2.dem -DamageDemo .\test_data\damage-source.dem
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Milestone6 -VisualTest
# 可选开发者手动解析（普通 UI 不需要）
.\parser\bin\cs2parser.exe .\test_data\damage-source.dem .\test_data\damage-source.replay.json
# 原有 Mock
.\"Start Viewer.cmd"
```

主要机器可读报告：`artifacts/milestone-6-report.json`、`m6-export-first.json`、`m6-export-second.json`。M1–M5 结果见各测试日志/报告。

全部要求截图已生成并检查，位于 artifacts：`m6-home.png`、`m6-loading.png`、`m6-replay.png`、`m6-settings.png`、`m6-error.png`、`m6-recent-replays.png`、`m6-status-flashed.png`、`m6-status-burning.png`、`m6-status-he-hit.png`、`m6-status-smoke.png`、`m6-status-multiple.png`、`m6-bomb-carrier.png`。另有 `m6-export-*.png` 正式程序截图、地图缺失及 Ancient 截图。

## 26. Known Issues

- Smoke 是明确的战术近似；16Hz 玩家位置及已有区间语义限制精度，不承诺引擎级伤害/遮挡模拟。
- 验收使用两份公开 Demo，不能推断支持所有新协议/POV Demo。解析库对部分 grenade model 发出警告；未知来源保留 unknown，不猜测。
- 新伤害样本是 Mirage，使用 Plane；只有已有 Ancient 地图准备流程，发行包不带 Valve mesh，也不会根据 CS2 路径自动转换所有地图。
- 完整 JSON 仍需解码驻留内存；未实现 Streaming/Binary，主线程场景提交仍有短暂停顿。
- Cancel/退出可能等待正在执行的 Parser/加载阶段安全结束，不强杀工作线程。
- 密集玩家姓名仍可能重叠；当前 UI 为英文；未完成低配机或全地图性能验收。
- Release 内存监视值不可用，上述开发内存和短窗口 FPS 有明确测量边界。
- 未制作 Installer、签名发布、Steam 集成或自动更新。

## 27. 下一阶段建议

先由用户用自己的 Demo 验证协议兼容性和日常操作，再确定下一阶段范围。可优先评估大 Replay 加载与低配性能、地图资产准备引导、密集姓名可读性和更广泛的真实样本回归。本次没有实现这些后续内容，也没有进入 M7。
