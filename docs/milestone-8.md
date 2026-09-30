# Milestone 8 — Automatic Map Provisioning + Multi-Map Expansion

应用 v0.8-dev；独立 Map Converter 0.8.0；Classifier 1（沿用 M7.1）。Replay 仍为 V1/V2，Demo Parser 仍为 0.6.0。验收日期 2026-09-24/25。本阶段完成后停止，不进入 M9。

普通入口：`dist/windows/CS2TacticalReplay.exe`。保留整个发行目录。最终机器报告：`artifacts/milestone-8-report.json`、`milestone-8-core-report.json`。本地使用的 Valve 地图不随包分发。

## 1. Dust2 原先无法获得地图的原因

M7 新用户默认 Ask，缺地图虽然可以继续 Plane，但不会自动生成；准备完成仍需要点击加载。原提取流程直接假设地图 VPK 和固定 world_physics 路径，缺少资源索引发现，也没有产品级跨回放准备队列。不能把用户看到的“没有地图”误报为 Parser 不支持 Dust2：本次真实 Dust2 Demo 成功解析。

## 2. 根因修复

新设置默认 Auto，旧 Ask/Never 不覆盖。Replay 加载成功与地图准备成功彻底分开。缺失或 stale 地图先用 Plane，后台准备成功自动热替换；失败只显示地图能力错误，继续 Replay。增加应用生命周期串行队列，切换 Replay 不销毁正在执行的准备工作。回归中修复了 Replay metadata 尚未就绪时队列轮询访问数据的问题。

## 3. MapSourceResolver 架构

Go `parser/cmd/cs2maptool/resolver.go` 负责发现；CLI、Godot 均不包含 Dust2 专用转换分支。输入 map_name、有效 CS2 game 目录、相对安装的 Source2Viewer CLI。先遍历实际 loose 资源，再枚举地图和共享 VPK，通过 CLI 列出条目；统一选择地图命名空间下的 world、physics/collision model 和 nav。返回 found/can_prepare/source/layout/world_resource/physics_resource/navigation_resource/reason/error_code。

## 4. Source Layout 范围

- 实际验收：当前本机 CS2 的 map-specific VPK，包含编译 world、physics model 和 nav。
- 已实现：maps 子树其他 VPK、`pak*_dir.vpk` 共享容器、`maps/<name>/` loose 编译资源树。编号分卷不重复当作独立索引。
- loose 与嵌套路径使用单元 fixture 验证；共享容器使用同一索引选择器，尚无完整真实共享布局地图端到端样本。不宣称所有历史或 Workshop 布局均支持。

开发者诊断（普通用户无需执行）：

```powershell
.\dist\windows\cs2maptool.exe probe-map de_dust2 "<CS2_PATH>"
.\dist\windows\cs2maptool.exe prepare de_dust2 "<CS2_PATH>"
```

本机解析出 `maps/de_dust2/world.vwrld_c`、`maps/de_dust2/world_physics.vmdl_c`、`maps/de_dust2.nav`。原始资源以只读方式访问。

## 5. Auto Prepare 流程

Open Demo → Parser/Replay Cache → metadata.map → MapAssetManager → ready 则加载，否则 Plane → MapPreparationQueue → CS2 discovery → resolver → extraction → gray geometry + classification → 写缓存 → 自动加载。

AppController 管生命周期与 UI；MapPreparationService 在线程内执行相对路径工具；MapPreparationQueue 去重且一次仅启动一个任务。CLI 输出真实阶段 JSON，状态文件供 UI 读取。输出中的非 JSON 行不会再触发 Godot JSON 错误。Settings 提供 Prepare/Rebuild/Delete Cache/View Log，Home 标记 Map Ready/Map Missing。

## 6. Fresh Machine Dust2 人工流程

对已有 Dust2 缓存做同目录隐藏备份，目标 `de_dust2` 为空；使用独立新设置/Replay 缓存启动正式 EXE，经 Open Demo 文件对话框打开本机 `2.dem`。亲自观察到 Plane 上的 Preparing Tactical Map，随后在同一 Viewer 自动出现 Dust2；未点击 Prepare/Load Map，也未重开 Demo。实际播放在地图就绪后继续。

人工证据：`artifacts/m8-manual-dust2-preparing.jpg`、`m8-manual-dust2-ready.jpg`；日志 `artifacts/m8-manual-fresh/logs/`。日志记录 02:06:07 cache miss/auto start，02:06:12 hot swap。这里“Fresh”指应用设置与 Dust2 地图缓存为空；没有删除用户其他地图或 CS2 安装。

## 7. Dust2 Prepare Time

最终自动验收为 **3,979 ms**；人工那轮 CLI 报告 **3,691 ms**。指标从开始提取准备到写缓存，资源索引发现和 Replay 解析另计，不能当作完整 Open Demo 耗时。

## 8. Dust2 GLB Size

**11,011,064 bytes**（约 10.50 MiB），只统计默认渲染 GLB，不包含分类诊断 JSON 或 removed-roof GLB。

## 9. Dust2 Triangle Count / Load

默认渲染 **412,834** triangles，低于 500k 目标。首次 GLB 加载 **129 ms**，同会话 reload **120 ms**。Cold 指当前进程首次加载，并未清空操作系统文件缓存。硬件为本机 RTX 5070 Ti Laptop GPU，Godot 4.5.1 Compatibility。

## 10. Dust2 Geometry Cleanup Stats

| 指标 | 三角形 |
|---|---:|
| Source | 435,649 |
| Render | 412,834 |
| Roof + Ceiling removed | 940 |
| Decorative removed | 21,875 |
| Kept structural | 355,771 |
| Unknown kept | 57,063 |
| Walkable protected | 130,215 |

分类：Floor 42,491；Wall 263,509；Stair 29,223；Major Cover 20,548；Roof 838；Ceiling 102。导航三角形 3,155。保留了墙体和主要箱体；不是按绝对高度裁掉模型。

## 11. Dust2 Alignment

真实 `2.dem`：10 players，时长 2360.359375 s。每轨每 97 帧取 alive + available 点，共 **2,791**，命中 **2,791 / 100%**。垂直差中位数 **0.009416 Godot units**（约 0.942 Source units）；|delta| > 0.5 的命中点 **67**。

射线从玩家位置上方 0.35 向下 8 Godot units，允许背面。该指标包含跳跃/台阶/箱体等时刻，不能把 large error 自动等同转换错误，也不能把命中率当作地图版本完全匹配的证明。没有为通过测试改写 Player Track。坐标始终 raw CS2 XYZ；统一 MapTransform：X=x×0.01、Y=z×0.01、Z=−y×0.01。

## 12. Dust2 Screenshots 与人工检查

已保存并逐张打开：`m8-dust2-fallback.png`、`m8-dust2-preparing.png`、`m8-dust2-ready.png`、`m8-dust2-top.png`、`m8-dust2-tactical.png`。

区域截图 `artifacts/m8-dust2-{t-spawn,ct-spawn,long,short,mid,b-site,a-site,lower-tunnel,upper-tunnel}.png`。从真实轨迹选取附近点，确切 time/raw/Godot/gap/reference_distance 见机器报告。区域目标是近似参考点，Lower Tunnel 最近点距离参考位置约 226 Source units，其余约 13–127。

人工结论：未见整体镜像、旋转错误或整体平移；A/B 箱体、街道和墙体可辨。大型顶部盖板已移除；隧道仍有保守保留的小型高处构件，CT 上方存在合法上层结构，100% 不透明度下不能保证每个内部空间全可见。分类诊断显示隧道剩余构件多属于小面积 Major Cover，未冒险按地图区域硬删除。

## 13. Ancient Regression

旧 M3 authored cache 继续兼容，未强制重做 Ancient。958,606 triangles，24,088,732 bytes。M3 **117** checks，1,393/1,393 射线命中，1,379 在 50 Source units 内，中位差 0.006174 Godot units。M7 正式包再次加载成功。Legacy 缓存仍按原 source identifier 与 mesh hash 验证。

## 14. Mirage Regression

通用 0.8.0 缓存实际生成/加载，120,396 triangles，3,460,356 bytes。M7 **52** checks、M7.1 **11** checks 全通过；真实轨迹 1,099/1,099 命中，1,059 在 50 units 内，中位差 0.005417 Godot units。原 HE/Fire/Flash/Smoke 状态、红名与透明图标继续正常。

## 15. Vertigo Preparation Result

真实 `third-map.dem`，10 players，3250.328125 s。空缓存自动生成成功：**3,311 ms**；GLB **5,286,100 bytes**；**195,820** triangles；首次/重复加载 **70/68 ms**。移除 roof/ceiling 790、装饰 13,986；保护 92,932，Unknown 保留 30,111。

真实轨迹 **4,053** samples，**4,048 hits / 99.8766%**；中位差 **0.000832** Godot units，large error **127**，未命中 **5**。高度没有被压成 Plane。

已查看 fallback、ready、top、tactical 和 `m8-vertigo-region-1.png` 至 `region-8.png`。上下平台、楼梯和边缘通道保留；region-5 位于较低层（raw Z 11488），其他采样区域多在 11744–11843。上层楼板遮住下层是保留真实结构的结果。region-6 为明显离地采样，gap 0.6713，未伪称完全贴地。

## 16. 其它实际测试地图：Inferno

同一管线真实生成：**15,459 ms**，**68,191,348 bytes**，**2,673,984 triangles**，首次/重复加载 **942/940 ms**。Roof/ceiling 移除 3,169，装饰 56,450，Unknown 保留 990,271，walkable protected 650,427。明显高于 500k 目标，保留结构优先，没有按数量强删。

两个公开真实短 Demo：`inferno-short.dem`（14034，3.28125 s）490 valid points 全命中，中位差 0.019031，large error 2；`inferno-spawn.dem`（13978，2.5625 s）410 valid points 全命中，中位差 0.0016675，large error 0。总计 **900** 有效采样，但不是一份 500+ 点长比赛；没有复制/合并假造轨迹。来源和 SHA 见 `test_data/m8-inferno-sources.json`。

已逐张查看 region-1 至 region-8、top/tactical。八个真实采样视角分布于路径、建筑和场地区域；部分仍被斜屋顶/上层结构遮挡，不能宣称每个内部房间均清空。完整公开 POV 样本尝试过，Parser 因 tick 从 467934 回退到 0 拒绝，未篡改 Parser 时间轴或将该样本报为成功。

## 17. Verified Maps

Settings catalog：**Ancient、Mirage、Dust2、Vertigo、Inferno**。Verified 表示本机已真实准备/加载并做所述轨迹与视觉检查，范围受样本与地图版本限制；尤其 Inferno 为两段短样本。Nuke 保持 Unverified，不宣称所有 CS2 地图完整支持。

## 18. Fallback Maps

任意可成功解析的 Demo，在缺地图、stale、找不到 CS2 或准备失败时仍使用 Plane。未准备/未验收地图显示 Unverified 或 Automatic preparation，绝不通过把名字加入 catalog 来伪装实际支持。M7 历史 Vertigo 缺图回归改用独立空缓存，继续验证真实缺图分支。

## 19. Roof Classifier Integration

沿用 M7.1 Classifier 1：连通近水平面、面积、局部高度范围、导航邻接/下方导航，以及 sky 语义。Unknown 默认 Keep；导航缺失保留不确定面；没有绝对高度阈值或地图名称分支。默认渲染 mesh 不含已分类 Roof/Ceiling，removed geometry 单独输出 `map.glb.roofs.glb` 供开发诊断（当前无普通 UI 开关）。

## 20. Multi-Level Safety

真实 Vertigo collision/nav 分类前后导航支撑回归：2,905 个非竖直导航中心点；三个高度带的 before/after 支撑数量分别 **584/584、776/776、1529/1529**，lost_support **0**，changed_support **0**，非水平结构保留。日志 `artifacts/m8-vertigo-safety.log`。合成双层、楼板底面、小箱体、无导航测试同时通过。Nuke 未实际准备，不能以 Vertigo 结果代替 Nuke 验收。

## 21. Cache Lifecycle / Reuse

地图根目录 `%LOCALAPPDATA%/CS2TacticalReplay/maps`。每张地图 map.glb/map.json/cache.json，另有 roof 和分类诊断文件。map.json 记录 transform、bounds、source_identifier/source_resource/source_files、converter/classifier、triangles、bytes、preparation_ms、geometry_stats。

泛型缓存检查独立 converter/classifier version、源文件 mtime/size、mesh SHA256。旧泛型 0.7 缓存失效，下一次 Auto 后台重建；不能退回 bundled 旧资产冒充新版本。CS2 已卸载时允许仍完整的 prepared cache 离线使用。Legacy Ancient 继续兼容。Delete Cache 仅删除已知生成文件，拒绝路径穿越和 map 目录链接。

## 22. 同地图第二份 Demo

先真实完整 Dust2 `2.dem` 生成地图，再重开该 Demo，然后打开另一份真实 `dust2-short.dem`（公开 13987，17.28125 s）。均直接 map cache hit，新增 prepare count **0**。Replay 缓存按 Demo 分开，地图按 map 共用，不触发 Source2Viewer。

## 23. No CS2 / Installed Later

用独立空地图根目录与不存在的 CS2 路径模拟缺安装：Replay 打开、继续播放，显示 “CS2 installation not found. Tactical map unavailable.”，见 `m8-no-cs2-fallback.png`。随后恢复实际路径、Prepare 并加载，Replay cache hit，未重解析原 Demo。该测试模拟路径缺失，没有卸载本机 CS2。

## 24. Failure / Queue

实际请求不存在的 `de_m8_missing_resource`，返回地图能力失败；缺源 MAP_SOURCE_NOT_FOUND，存在 world 但缺可用 physics 为 MAP_PHYSICS_UNSUPPORTED，转换/工具启动失败为 MAP_CONVERSION_FAILED。UI 提供 Retry 和 Settings View Log，失败不跳整应用 Error。

强制请求 Dust2、Vertigo、重复 Vertigo，pending 只有一个，顺序完成。同步启动失败也通过 poll 返回，避免 UI 永远 Preparing。任务在同一应用实例内串行；多开 EXE 暂无跨进程全局锁。取消在当前外部工具结束后生效。

## 25. Hot Swap Preservation

最终正式包记录 **4 次**自动切换，逐项比较 before/after：CurrentTime、Play/Pause、speed、selected、camera target/yaw/pitch/size/projection、layers、所有玩家 current states、Bomb state、Combat counts、status、Kill Feed IDs、Replay controller instance ID。全部相等。Dust2 切换发生在 time **510.77022638095**、playing=true、speed=2；关闭 Shots 与玩家选择均保留。只替换地图，不重新 Parse 或载入 Replay。

## 26. Windows Distribution

已构建并以正式 EXE 运行：CS2TacticalReplay.exe/PCK、cs2parser.exe、cs2maptool.exe、map-tools/Source2Viewer-CLI.exe、libSkiaSharp.dll、spirv-cross.dll、MIT LICENSE.txt、README.txt。运行时工具均按应用目录定位。构建前检查四项 map-tools 依赖，缺任意项立即失败。无开发机器绝对工具路径；验收脚本的 Demo 路径是本机测试输入，可用参数替换。

## 27. 新增 / 修改文件

新增：

- `parser/cmd/cs2maptool/resolver.go`、`resolver_test.go`
- `app/scripts/map/MapPreparationQueue.gd`（及 Godot uid）
- `app/tests/milestone_8_tests.gd`、`milestone_8_core_tests.gd`
- `tools/test-milestone8.ps1`、本报告、Inferno/Dust2 公开短 Demo 来源记录和测试输入

修改：

- `parser/cmd/cs2maptool/main.go`：resolver、阶段、版本/来源元数据与错误分类
- `app/scripts/map/MapPreparationService.gd`、`MapAssetCache.gd`、`MapAssetManager.gd`、`MapManager.gd`
- `app/scripts/application/AppController.gd`、`AppInfo.gd`、`SettingsStore.gd`、`SettingsScreen.gd`、`HomeScreen.gd`
- `app/scripts/ui/DebugOverlay.gd`、`app/maps/catalog.json`
- `app/tests/milestone_7_tests.gd`、`milestone_7_1_tests.gd`：显式 Ask 和缺图测试隔离
- `tools/build_windows.ps1`、`README.md`、`docs/windows-quick-start.txt`；重建 parser/bin 与 dist/windows

未改 Replay Format、Parser 的地图坐标、ReplayClock、Timeline 插值实现；未开发 M9、高级战术、网络、视频或 Binary Replay。

## 28. 测试数量与结果

| 套件 | Checks | 结果 |
|---|---:|---|
| M1 Mock | 88 | 通过 |
| M2 Real Replay | 362 | 通过 |
| M3 Ancient | 117 | 通过 |
| M4 Combat | 653 | 通过 |
| M5 Bomb/cache/async | 285 | 通过 |
| M6 Application | 1200 | 修复加载时序后复测通过，无脚本错误 |
| M7 正式 EXE | 52 | 通过 |
| M7.1 正式 EXE | 11 | 通过 |
| M8 正式 EXE 空缓存 | 83 | 通过，无脚本错误 |
| M8 Core | 16 | 通过 |

合计 **2,867** Viewer checks。Go JSON 日志 **33** test/subtest pass、**7** optional skip；真实 Vertigo 几何测试另行启用通过；`go vet ./...` 通过。构建 exit 0。测试源码/日志与报告在 app/tests、tools、artifacts。

复现：`tools/run.ps1` 的 Test/RealTest/MapTest/CombatTest/Milestone5/Milestone6（配合 VisualTest）；`tools/test-milestone7.ps1`、`test-milestone7.1.ps1`、`test-milestone8.ps1 -DustDemo <真实 Dust2.dem>`。M8 空缓存测试运行前需保留备份并清空目标地图缓存；不会在脚本里静默删除用户缓存。专项 core 用 Godot headless 执行 `res://tests/milestone_8_core_tests.gd`，需要已有 Dust2 prepared cache。

## 29. Known Issues

- Conservative classification 留下部分小型/斜屋顶和 Unknown 面；多层合法地板会遮住下层。不能把 X-ray 玩家可见等同所有内部几何清晰。
- Inferno 超预算，GLB 加载约 0.94 秒同步阶段可出现短暂停顿；分类诊断 JSON 也较大。大 Replay JSON 加载仍需数秒。
- Inferno 验收只有短真实 clips；POV tick rewind 样本明确失败，尚无完整 Inferno 比赛覆盖。
- 自动对齐包含跳跃和地图版本差异，Dust2/Vertigo 有大差值，Vertigo 有 5 个未命中点，已保留原始统计。
- Source 更新以 mtime/size 检测；内容变化但时间和长度都不变可能漏检。Replay 历史地图与当前安装地图不做版本回溯匹配。
- 共享/其他 loose 布局并非全部真实端到端验收；未知命名且没有可识别 physics model 返回能力错误。
- 队列仅单实例串行，多开 EXE 无全局进程锁；取消不强杀正在执行的 exporter。
- 无 CS2 时 prepared cache 可用但无法重建。Nuke 未验证。没有承诺 All CS2 Maps Fully Supported。

## 30. 下一阶段建议（仅建议，未执行）

优先获取完整 Inferno 与 Nuke 多层真实样本，再扩展斜屋顶/小型顶盖的可靠语义分类与局部剖面观察。评估 Inferno 几何和大 JSON 加载性能，补充真实 shared-container fixture、跨实例锁和更强源内容指纹。是否进入下一阶段由用户决定。
