# Milestone 7 — Multi-Map Compatibility + Tactical Status UX Polish

应用版本 v0.7-dev。Replay 仍是 V1/V2，Demo Parser 仍为 0.6.0；新增独立 cs2maptool，不修改比赛数据格式。普通入口是 `dist/windows/CS2TacticalReplay.exe`。本报告的最终数值以 `artifacts/milestone-7-report.json` 和各回归日志为准。

## 1. Bomb Carrier 新视觉

携带者只显示红色姓名。Capsule 的 T/CT 颜色不变，换边与死亡状态延续原有逻辑。状态仍由当前 ReplayClock 时间和 BombReplayState 推导，Seek 后立即更新。

## 2. C4 Icon 删除范围

PlayerStatusRenderer 不向图标行传递 BOMB_CARRIER，Indicator 本身也过滤该类型。没有 C4 文字、额外 ring 或红色底板。内部状态和 Layers 中的 Carrier Red Name 开关保留。Bomb Dropped/Planted 世界标记、Timer、Timeline markers 和状态查询继续工作。

## 3. 透明状态视觉结构

PlayerStatusIndicator 使用 Godot 绘图：白色 Starburst、橙红火焰、黄色冲击环、灰白云朵。删除 StyleBox 背景；没有 Panel、ColorRect、矩形 badge 或系统 Emoji。细暗轮廓只沿图案边缘绘制；星芒使用线段和圆角连接，避免尖角描边外扩。

图标继续使用 CanvasLayer 屏幕投影，固定尺寸与横向间距。位置锚定玩家 Name 节点，偏移随 name_size 调整；图标不会因镜头转动侧立，也不会被地图或烟体遮挡。普通模式隐藏 Debug Overlay 和 WorldAxes；View 提供 Debug / Player Status。

## 4. HE Hit 真实 Viewer 验证

来自 `damage-source.dem` 的三条真实 hegrenade 正伤害，在正式 EXE Seek 到事件后 0.2 秒，逐张打开截图检查。图标及 Selected Player / Active Statuses / Recent Damage 一致：

| 事件时间 | Seek 时间 | 伤害 | 受害者 ID |
|---:|---:|---:|---|
| 282.28125 | 282.48125 | 26 | player-1 |
| 286.03125 | 286.23125 | 52 | player-2 |
| 383.96875 | 384.16875 | 8 | player-3 |

截图 `m7-real-he-hit.png`、`m7-he-real-1.png` 至 `m7-he-real-3.png`。只有正 HE 伤害触发 `[time,time+0.8)`，没有爆点距离推断。

## 5. Burning 真实 Viewer 验证

同一真实 Mirage Replay 的三段 inferno 伤害：

| 事件时间 | Seek 时间 | 伤害 | 受害者 ID |
|---:|---:|---:|---|
| 536.46875 | 536.66875 | 1 | player-4 |
| 538.953125 | 539.153125 | 1 | player-5 |
| 556.0625 | 556.2625 | 3 | player-6 |

截图 `m7-real-burning.png`、`m7-burning-real-1.png` 至 `m7-burning-real-3.png`。火焰轮廓位于受害者姓名上方，背景透明，Debug 同时显示 BURNING。每次正火伤刷新 0.75 秒窗口；Seek 安全，连续区间取并集。站在火区但没有真实伤害不会显示 BURNING。

## 6. Flashed 验证

使用真实 affected_players，65.928 秒截图显示受影响玩家的白色星芒。保留源致盲持续时间，图标语义没有变化。截图 `m7-real-flashed.png`。星芒是小型头顶图标，世界中更大的 Flash 爆炸形状仍是原有独立效果。

## 7. In Smoke 验证

52.266 秒真实玩家位于活动战术 Smoke 体积中，灰白 Cloud 在烟体前可读，见 `m7-real-in-smoke.png`。它仍是半径 145 Source 单位的战术球体近似，不是 CS2 voxel/LOS 精确结果。

真实数据还找到了 571.3875 秒的 FLASHED + IN_SMOKE，同时横向显示于同一玩家上方，见 `m7-multiple-real.png`。本阶段该多状态截图没有使用 fixture。

## 8. Damage 数据来源与可见性诊断

继续使用 demoinfocs 原生 PlayerHurt，Parser 只保存来源事实。Mirage 有 264 条伤害，HE 15、inferno 38；第三地图 Vertigo 有 681 条 PlayerHurt。原 Ancient 样本仍为 0，原生回调与 Generic 事件排查结果沿用 M6。

因此“看不到标记”需要区分样本确实没有伤害与渲染问题。Debug 会显示 `Damage events unavailable`，正常 UI 不报错。所选玩家的真实状态及最近 5 秒最多四条伤害放在诊断区顶部，避免埋在坐标信息下方。Events 新增 player_hurt 过滤、伤害详情和 `Inspect victim at +0.2s`，Debug 提供显式 `Focus selected player`，方便用户复核；没有自动导演。

## 9. Unsupported Map 新行为

移除 AppController 的 MAP_UNAVAILABLE 阻塞分支。有效 Replay 不需要用户点击 Use Debug Plane，也不把地图缺失视为 AppError。非法文件、损坏 Demo、Parser 缺失或无效 Replay 仍进入原有 ErrorScreen。

## 10. 自动 Fallback 流程

Demo → Hash/ReplayCache → Parser（需要时）→ ReplayLoadJob → 查询 MapAssetManager → 有地图加载，无地图直接 Plane → Replay。顶部有可 Dismiss 的 MAP FALLBACK 提示，View 中仍可准备地图。Player、Utility、Shots、Kill、Bomb、Status、Play/Pause/Seek 全部继续使用当前比赛数据。

## 11. 真实 Demo 清单

| 地图 | 本地 Demo | 来源 |
|---|---|---|
| Ancient | test_data/s2/s2.dem | demoinfocs 公开 cs-demos-2，见 test_data/source.json |
| Mirage | test_data/damage-source.dem | LaihoE/demoparser 的 test_demo.dem，见 damage-source.json |
| Vertigo | test_data/third-map.dem | saul/demofile-net 公布测试归档中的 mouz-nxt-vs-space-m1-vertigo.dem |

第三份来源通过 [官方下载脚本](https://github.com/saul/demofile-net/blob/main/demos/download.sh) 确认，仅从归档范围下载单个条目并校验 ZIP CRC。Demo 319,159,846 bytes，SHA256 `6f836d878f54dae8d5304cc795539acc102b9fededdddef0a796038574b7b4e5`，记录在 `test_data/third-map-source.json`。没有把地图名改写为第三张地图，也没有合成比赛数据。

## 12. 每个 Demo 打开结果

Ancient：真实地图、10 人、原有全部事件正常。Mirage：空私有地图缓存时自动 Plane；后台准备后切换为真实 Mirage。Vertigo：10 人、3,250.328125 秒、520,030 玩家帧、4,790 events、511 projectiles，自动 Plane 成功。

Vertigo 包含 Smoke 138、Fire 135、HE 110、Flash 252、Shot 3,103、Kill 169、PlayerHurt 681，以及真实 Bomb 全周期事件。输出 Replay 100,823,532 bytes，仍为 V2。正式 EXE 验证多个时间点 Seek 和三种速度。

## 13. CS2 Installation Detection

cs2maptool discover 优先查询当前用户 SteamPath 和 Windows 默认 Steam 目录，再读取 Steam Library Folders；手动路径明确给出时先验证该路径。支持 CS2 根目录、game 目录和 game/csgo 目录归一化。

验证必要 `gameinfo.gi`、`pak01_dir.vpk` 和 maps 下 VPK 的存在，不接受任意空目录。Settings 有 Browse、Valid/Invalid 状态，首次发现后保存路径。本机实际检测到 D 盘 SteamLibrary，没有硬编码该盘符。所有查询只读，不访问 Steam API 或用户认证。

## 14. MapPreparationService 架构

GDScript MapPreparationService 提供 can_prepare、prepare、cancel_request、get_status，Thread 中运行安装发现和隐藏的 cs2maptool。该工具调用随包提供的 Source2Viewer 20.0 CLI 导出 collision，再由独立 Go tactical 包转成灰色 GLB。不需要普通用户安装 Python、Go 或手动运行 PowerShell。

后台准备只返回数据和状态，UI 主线程轮询。没有可靠百分比时显示 Preparing Tactical Map + indeterminate。Cancel 是安全阶段结束后丢弃 UI 结果；已经安全提交的缓存可能保留，不强杀线程或 CLI。

## 15. MapAssetManager / Cache 配合

MapPreparationService 只负责 Source → Asset；MapAssetManager/Cache 继续校验和加载。输出 `%LOCALAPPDATA%/CS2TacticalReplay/maps/de_map/{map.glb,map.json,cache.json}`。map.json 包含 scale/rotation/offset、bounds、default_camera、source_identifier、converter_version、triangles、glb_bytes、preparation_ms。cache.json 保留原有版本和 mesh SHA256 语义。

生成过程使用缓存根目录下独立临时目录，manifest 最后提交；异常产物不被视为有效缓存。地图名称使用严格字符白名单，写入目标检查 junction/symlink 跳转。源 VPK 只读，不修改 CS2 游戏文件。源码兼容缓存增加 SHA256 大小写无关比较；可选 `CS2_MAP_CACHE_ROOT` 仅用于隔离测试缓存。

## 16. Mirage 准备方式

相同数据驱动流程读取 `maps/de_mirage.vpk` 中 `maps/de_mirage/world_physics.vmdl_c`，经 Source2Viewer 输出 collision_physics.glb。Go 转换器保留结构碰撞三角形，移除命名的 clip/植被/装饰类别，焊接 0.001 Source 单位顶点，按 512 单位空间块输出。

无原始贴图、灯光或材质；单一灰材质，重新计算法线。资产坐标归一化与旧 Ancient 工具一致，比赛 raw XYZ 不变。模型缩放和偏移仍统一通过 MapDefinition/MapTransform。

## 17. Mirage 对齐验证

对实际模型创建临时测试碰撞面，向 1,099 个真实玩家轨迹采样点下方发射射线，全部命中；1,059 个（96.36%）在 50 Source 单位内，地面高度差中位数 0.00541 Godot 单位。未镜像，未额外为玩家添加地图特判。

另选 T Spawn、CT Spawn、A、B、Mid、Connector、Jungle、Short 附近实际轨迹点，报告保存玩家、时间、raw/converted XYZ、距参考区域中心距离和地面差。区域名称是人工选择的粗参考中心，并非 Parser 提供的官方地名。八张 `m7-alignment-*.png` 配合射线数据检查位置与高度；不能将射线命中等同于完整墙体穿透验证。

## 18. 正式支持地图

Ancient：已有战术模型/缓存继续加载。Mirage：本阶段通用准备工具实际生成、校验并加载成功。两者均为灰色战术几何，非原版视觉地图。

## 19. Fallback 地图

已实际验证 Vertigo 无准备资产时正常回放；Mirage 也在空缓存环境验证自动 fallback。其他解析成功且 Replay 有效的地图走相同 fallback 分支，不承诺所有 Demo 协议都能被当前库解析。准备工具目前要求本机对应 de_*.vpk 含所需 collision 资源；未验收的地图不列为正式支持。

## 20. GLB 大小

Ancient 24,088,732 bytes（约 22.97MiB）；Mirage 3,481,080 bytes（约 3.32MiB）。地图独立于 Replay JSON，也没有将 Valve mesh 放入 Windows 发行目录。

## 21. Triangle Count 与 Bounds

Ancient 958,606 triangles，Godot bounds position `(-41.51308,-2.29,-30.89398)`、size `(67.67308,16.5485,72.23398)`。

Mirage 121,171 triangles，114 空间块，Godot bounds position `(-40.95999,-4.48,-20.48004)`、size `(59.19999,13.94,59.12004)`。Debug 显示 triangle count、GLB size、bounds、transform、origin 和加载时间。

评估后保留 authored collision 三角形，没有为降低 Ancient 数字而无约束简化重要墙体/楼梯。Mirage 较少的三角形来自其碰撞资源，本阶段没有把这个差值宣称为通用减面算法的收益。

## 22. Map Load Time

实测数值见最终 `milestone-7-report.json` 的 maps：cold_load_ms 是当前进程新建地图场景，warm_load_ms 是同进程从磁盘缓存重新实例化，不是清除 Windows 文件缓存后的物理冷读。返回/切换仍有短暂主线程 GLB 提交，不重写加载系统。

最终正式 EXE 验收：Ancient cold/warm 为 190/294ms，Mirage 为 51/42ms。这些是一次具体运行，不保证 warm 必然更快。打开流程耗时 Ancient 6,233ms、Mirage 3,595ms（初始 Plane，不含后来准备时间）、Vertigo 13,975ms。Vertigo 的 100.8MB JSON 加载明显更慢；缓存可省 Parser 时间，不能消除 JSON 解码时间。

本机 RTX 5070 Ti Laptop、1920×1080、Mirage 真实模型、默认相机构图、地图透明度 50%，播放 530–535 秒的五秒窗口平均 665.31 FPS。这只是该场景的实测，不代表低配机器或整场最低帧率。Release 内存监控不可用。

## 23. First Map Prepare Time

Mirage 空目标缓存的第一次命令行准备实际耗时 2,055ms。Viewer 后台准备也实际执行 Source2Viewer 和 Go 转换；最终报告记录后段等待 935ms、1,184 个 UI 帧。该等待计时开始于准备提示截图之后，不是完整准备耗时。没有用拷贝已有 Mirage GLB 冒充 Source → Asset。重复准备会重新导出；普通打开只复用已准备缓存。

## 24. Home / Loading / Replay

正式导出 EXE 测试从 Home 打开 Mirage → 自动 fallback → 无效 CS2 路径准备失败仍留在 Replay → 自动发现有效 CS2 → 后台准备 → Reload Map 保持时间 → Home → Ancient → Home → Vertigo → Home。Settings 增加 MAPS、Ask/Auto/Never（默认 Ask）、路径验证、Prepared Maps 和缓存目录。Recent 显示 Map Ready / Fallback Available，不阻止打开。

Ask 使用非阻塞 Prepare 按钮；Auto 进入 fallback 后启动后台准备；Never 隐藏准备入口。准备成功由用户点击 Reload Map，替换地图层并保持 Clock、选中玩家和现有比赛数据，不重新解析 Demo。

## 25. M1–M6 Regression

M1 88、M2 362、M3 117、M4 653、M5 285、M6 1,200 检查全部通过，日志分别是 `artifacts/m7-m1-console.log` 至 `m7-m6-console.log`。M6 原测试中“缺 Mirage 进入 Error”的预期改为 M7 自动 Replay；不再执行三个条件式等待 Error → Plane 的检查，因此计数从 1,203 变为 1,200。其余伤害随机 Seek、播放、缓存、设置、错误和多 Session 检查保留。

Go 15 个顶层测试通过，2 个可选诊断跳过，go vet 通过；包含真实 Damage/Bomb/Combat 源数据对比以及新的 GLB 坐标、clip 过滤、源文件不变、坏文件和安装路径验证。没有重新运行历史 FullRound，不把历史日志作为本次新结果。

## 26. 文件变更

新增：

- `parser/cmd/cs2maptool/main.go`、`main_test.go`、`hide_windows.go`、`hide_other.go`。
- `parser/internal/tactical/glb.go`、`glb_test.go`。
- `app/scripts/map/CS2InstallationDiscovery.gd`、`MapPreparationService.gd`。
- `app/scripts/ui/MapPreparationPanel.gd`。
- `app/tests/milestone_7_tests.gd`、`tools/test-milestone7.ps1`、`docs/milestone-7.md`。
- `test_data/third-map-source.json`；新增 GDScript 的 Godot .uid。

修改：

- `app/scripts/application/AppController.gd`、`AppInfo.gd`、`HomeScreen.gd`、`SettingsScreen.gd`、`SettingsStore.gd`。
- `app/scripts/status/PlayerStatusIndicator.gd`、`PlayerStatusRenderer.gd`、`PlayerStatusResolver.gd`。
- `app/scripts/Main.gd`、`app/scripts/map/MapManager.gd`、`MapAssetCache.gd`。
- `app/scripts/ui/DebugOverlay.gd`、`CombatPanel.gd`、`app/tests/milestone_6_tests.gd`。
- `tools/build_windows.ps1`、`README.md`、`docs/architecture.md`、`docs/testing.md`、`docs/windows-quick-start.txt`、`shared/replay-format/README-v2.md`。

本地生成：cs2maptool.exe、重新导出的 EXE/PCK、map-tools 依赖与 MIT license、Mirage 用户地图缓存、第三份 Demo/Replay、M7 日志/报告/截图及隔离缓存。当前目录无 Git，清单依据本阶段实际编辑记录；大型产物沿用忽略策略。

## 27. 测试与操作复现

普通用户双击 `dist/windows/CS2TacticalReplay.exe`。将整个目录一起保留，尤其 PCK、cs2parser.exe、cs2maptool.exe 和 map-tools。Demo 打开不需要 CS2；地图准备才读取本机安装。

```powershell
# 项目根目录；开发者命令，普通用户不需要
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-milestone7.ps1
.\parser\bin\cs2maptool.exe discover
.\parser\bin\cs2maptool.exe prepare de_mirage "<CS2_INSTALL>"
```

上例安装路径只是本机实测值，产品会发现/浏览安装路径。cs2maptool 的 Source2Viewer 依赖位于相邻 map-tools；构建脚本从 `.tools/vrf` 打包已有官方 20.0 工具和许可证。Replay 格式不变，无新网络服务。

正式 EXE 测试包含三真实 Demo、状态截图、背景 alpha 像素、仅红名、安装准备失败恢复、实际 Source → Asset、保留时间 Reload、Mirage 实际三角形对齐、速度、Error 和多 Session。最终为 52 检查、0 失败，进程退出码 0；日志没有 ERROR/SCRIPT ERROR。检查数、失败数组和性能写入 `artifacts/milestone-7-report.json`。

另用 Computer Use 启动普通 EXE（无测试参数），实际点击 Open Demo，在文件选择器输入 damage-source.dem，观察 Loading → Mirage Replay 成功。随后检测到用户正在操作窗口，停止接管鼠标。六个伤害场景和八处对齐截图已逐张视觉检查；精确 Seek、速度及地图准备断言来自正式 EXE 中的测试驱动，不冒称全部由鼠标逐次点击。最终图标无背景板，地图透视图能看到结构和实际玩家位置，屋顶遮挡与密集姓名问题保留在下节。

## 28. Known Issues

- 烟雾是战术近似，不代表 voxel/LOS。伤害依赖真实 Demo 事件，没有来源就不显示 HE/Burning。
- 灰色碰撞几何含屋顶/大型结构，某些近距离视角会遮挡内部；可使用 Tactical/透明度模式。不是完整游戏视觉或精确导航网格。
- Mirage 96.36% 的射线样本高度差在 50 Source 单位内，其余可能是跳跃/空中或版本差异；不能宣称所有位置与当前 CS2 地图完全一致。
- Steam 发现和准备首版面向 Windows；只完整验收 Ancient/Mirage，其他资源布局可能失败，但失败继续保留 fallback。
- 准备取消可能等待当前导出/转换结束，已提交缓存可保留；不会强杀线程。用户仍可返回首页。
- JSON 全量加载，第三份较大 Demo 首开有明显等待；地图 Scene 提交仍有短暂停顿。没有 Streaming/Binary，也不承诺低配机器性能。
- 密集玩家姓名可能重叠，本阶段没有复杂避让算法；状态同行排列，不解决不同玩家间全部文字碰撞。
- Release 的 Godot 静态内存指标不可用，UI 显示 unavailable，不把 0 当实际内存。
- 本地发行包含独立 Source2Viewer 工具，体积增加；不包含 Valve 地图模型、安装器、更新器、云服务或账号。

## 29. 下一阶段建议

建议用户用日常 Demo 验证默认视角、状态可读性和地图准备流程后，再决定后续范围。可优先考虑碰撞几何的屋顶可读性、更广的 Demo/地图样本、低配性能与大文件加载。仅列建议，不实现 M8。
