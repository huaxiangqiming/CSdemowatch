# Milestone 5 — Tactical Visual Polish + Bomb + Map Cache

本阶段扩展 M4 稳定基线，保持本地三维战术沙盘定位。Godot 4.5.1 Standard / GDScript、Go 1.25.1、demoinfocs v5.2.0。没有实现 M6。

## 1–6. Flash、HE、Smoke、Fire 视觉

FlashProjectileVisual 提供共享的低多边形 Utility 几何：Flash 是白色 Capsule，Smoke 是深灰短柱，HE 是深色球体，Molotov / Incendiary 是细长锥形瓶体，均有来自 TeamVisualConfig 的阵营色环。辨识不依赖文字。

Flash 爆炸使用白色核心、扩展圆环、八向三角星芒和团队外环，0.25 秒内淡出；HE 是小型冲击球和双层扩散冲击环，0.35 秒，无白色星芒。可复用节点随当前 replay time 设置相位，不使用 wall-clock tween 或每次永久创建节点。

FlashedPlayerRenderer 读取真实 affected_players，以持续时间建立查询桶，在玩家上方显示白色 ✦ 并衰减。没有数据时不虚构受影响玩家；不模拟屏幕变白。

Smoke 使用灰色低多边形体积、22% 的轻微阵营混色、实体 Torus 外环和可关闭的顶部标记。可见度 Low / Tactical / Strong 对应 alpha 0.35 / 0.55 / 0.75，默认 Tactical。关闭 tint 后主体回归灰色，阵营外环保留。为适应建筑遮挡的战术查看，体积及标记使用可穿透显示，不表示真实 LOS 或烟雾遮挡结果。

Fire 继续使用真实 flame patches、橙红区域和依据 ReplayClock 的轻微 pulse，T 为 amber 轮廓，CT 为 cyan 轮廓，没有纯蓝火焰或粒子。

所有团队颜色集中在 TeamVisualConfig。历史 Utility 读取投掷时 actor_team。新增独立图层：Smoke Team Tint、Smoke Marker、Flash Effects、Flashed Players、HE Effects、Bomb；原有图层和 Kill Feed 保留。

## 7–10. Bomb 数据、数量、状态与 Seek

Go 新增 `internal/demo/bomb.go`，读取 demoinfocs 从真实 C4 实体生成的 pickup/drop/plant/defuse/explode 回调。Dropped 额外记录 16 Hz 位置轨迹。回调后 FrameDone 才读取 drop/plant 世界坐标，避免库尚未更新 carrier 时拿到错误位置。

| 事件 | 实际数量 |
|---|---:|
| bomb_pickup | 32 |
| bomb_drop | 21 |
| bomb_plant | 11 |
| bomb_defuse | 5 |
| bomb_explode | 0 |
| bomb_reset（真实 RoundStart） | 21 |

当前 Demo 没有爆炸回合；独立 RoundEnd 原因中 TargetBombed 也是 0，5 个 BombDefused 与拆除事件吻合。没有生成假数据补齐事件类型。旧有 Smoke 48、Fire 41、HE 67、Flash 68、Shot 3023、Kill 163 不变。M5 总事件 3500。

交付文件 `test_data/public-s2-m5.replay.json` 为 **59,674,325 bytes / 56.91 MiB**，10 players / 10 tracks，duration 1976.203125 秒，仍使用 V2 JSON；原 M4 V2 与 V1 样本保留用于回归。

`BombReplayState` 独立二分查询时间点之前最后的 Bomb 状态，支持 Unknown / Carried / Dropped / Planted / Defused / Exploded；真实 round reset 防止跨回合残留。Dropped 位置从专有轨迹插值；Carried 指示跟随已有玩家轨迹。

BombRenderer 显示红色盒子、BOMB 标签和安放脉冲，携带时显示 C4 标记。计时是距真实记录中的 defuse/explode 的时间，不冒充基于规则常数的爆炸倒计时。没有可靠后续终止事件时显示 `End time unavailable`。

Timeline 使用独立 BombMarkers：安放三角、拆除方框、爆炸叉形，与 Kill 短线区分，鼠标穿透不影响 Seek。测试覆盖 160 个跨全场时间点、90 个真实事件边界、反向跳转、安放计时和图层隐藏。

## 11–16. MapAssetManager 与地图缓存

`MapAssetCache` 负责独立于 Replay 的磁盘缓存、版本与完整性检查；`MapAssetManager` 继承缓存读取接口并负责安装已准备资产，提供 `is_map_ready`、`prepare_map`、`load_map`、`get_map_definition`。现有 MapManager 保留场景、材质和 MapTransform 职责。

```text
%LOCALAPPDATA%/CS2TacticalReplay/maps/
  de_ancient/
    map.glb
    map.json
    cache.json
```

`cache.json` 保存 cache_version、map、source_identifier、mesh_sha256 和 prepared_unix。来源标识来自现有本机提取记录 source_sha256；当前准备好的资源变化时会使旧缓存失效。不会每次打开 Replay 重新读取或导出原始 VPK。真正更新 CS2 地图后需先重新运行已有本机 import 工具，更新准备资产与来源记录。

MapDefinition 保留现有 scale / rotation / offset，同时增加 source_identifier、cache_version、bounds 和 default_camera。运行时加载几何后记录实际 Godot AABB；默认相机配置接入现有相机 Home 行为。

首次准备 Ancient 是把已由 M3 本机转换的 tactical GLB 安装到正式缓存并创建 manifest；这不是再导出一次 CS2 地图。后续校验缓存并直接读取，且同一打开会话再次载入 Ancient Replay 时复用内存中的地图节点。缓存与 Replay 文件完全分离。

UI 显示 `Preparing Tactical Map` 或 `Loading Map`；后台载入 Replay 完成后主线程生成地图场景。缓存损坏或定义无效可从本机准备资产修复；若本机资产也缺失，提示 unavailable 并使用 Debug Plane。View 中提供 Retry tactical map。未知地图仍可查看玩家和战斗数据，本阶段不自动转换所有地图。

隔离缓存测试覆盖首次准备、重复命中、GLB 修改时间不变、无效 map.json、损坏 GLB checksum、恢复修复、不支持地图及路径穿越拒绝。测试缓存位于 artifacts，不破坏用户缓存。

## 17–20. 后台加载、耗时、内存、性能

正常启动、文件选择和拖放均进入 ReplayLoadJob。工作线程只执行 File IO、JSON decode、验证、domain 数据准备、缓存检查/准备和 replay bounds 计算；不接触 SceneTree 或创建 Node。主线程轮询完成状态、join，再更新 ReplayController 和场景。

保留同步入口用于既有确定性回归测试；用户 UI 使用异步入口。加载失败保留前一个有效 Replay。加载中再次请求文件时保留最后一次请求，旧任务结束后处理；退出时等待工作线程结束，避免资源悬空。

加载界面使用活动点动画，没有伪造百分比。总解码时间仍是约 4 秒，主要改进是期间界面持续响应。最终测得后台加载 4178 ms、主线程更新 5681 帧，最大 frame gap 227.961 ms；主线程场景提交仍有短暂停顿，尚未分帧创建全部节点。

Godot MEMORY_STATIC 454,902,385 bytes，约 433.83 MiB（不是操作系统 RSS 或 GPU 显存，也不是加载过程峰值）。既有 Ancient 网格 958606 三角形。本机 1920×1080、RTX 5070 Ti Laptop GPU 的最终交火片段约 843 FPS。此结果不能代表核显或最低配置 60 FPS 已验证；仍须在目标低端机器实测。

Debug Overlay 显示地图三角形、Smoke、Fire patch、活动 Utility、Shot 线段、Flash visuals、被闪玩家、Replay/Map 加载时间及 Godot 静态内存。最终完整回合、加载与性能数值见 `artifacts/milestone-5-report.json`。

## 21. 文件变更

新增：

```text
parser/internal/demo/bomb.go
parser/internal/demo/bomb_test.go
app/scripts/events/BombReplayState.gd
app/scripts/rendering/BombRenderer.gd
app/scripts/rendering/FlashProjectileVisual.gd
app/scripts/rendering/FlashedPlayerRenderer.gd
app/scripts/map/MapAssetManager.gd
app/scripts/map/MapAssetCache.gd
app/scripts/core/ReplayLoadJob.gd
app/scripts/ui/BombMarkers.gd
app/tests/milestone_5_tests.gd
docs/milestone-5.md
```

修改：Go combat recorder、events domain/validator、CLI 统计、原 combat source test 和 source probe；Godot Main、ReplayController（接收已解码数据）、ReplayEvent/V2Validator、CombatController、TeamVisualConfig、UtilityEffectView/UtilityRenderer、ProjectileRenderer、CombatPanel、DebugOverlay、MapDefinition/MapManager/MapTransform、TacticalCamera 默认相机；V2 Schema/说明、README、测试/架构说明、tools/run.ps1、Open Combat Replay.cmd。新增 GDScript 对应 UID 由 Godot 生成。

ReplayClock、TrackSampler、TimelineUI 保持原文件不变；Player Track Format、EventIndex 原有查询语义与 Kill Feed 数据逻辑不改写。

## 22. 运行与测试

双击 `Open Combat Replay.cmd` 打开 M5 样本；`Open Real Replay.cmd` 保留 V1，`Start Viewer.cmd` 保留 Mock。

```powershell
# 根目录编译并生成 M5 数据，仍为 Replay V2
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1
.\parser\bin\cs2parser.exe .\test_data\s2\s2.dem .\test_data\public-s2-m5.replay.json
# Go tests + vet
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1 -Test -Demo .\test_data\s2\s2.dem
# Mock / V1 / M3 / 原 M4 回归
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -VisualTest
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -RealTest -VisualTest -Replay .\test_data\public-s2.replay.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -MapTest -VisualTest -Replay .\test_data\public-s2.replay.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -CombatTest -VisualTest -Replay .\test_data\public-s2-v2.replay.json
# M5 + 完整真实回合 + artifacts/m5-*.png
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Milestone5 -VisualTest -FullRound -Replay .\test_data\public-s2-m5.replay.json
```

Go 新测试独立解析第二次源 Demo，核对所有 90 个 Bomb 事件 tick 与实际数量；原 M4 Go 测试继续核对六类战斗事件与 V1 tracks 完全一致。M4 Viewer 653 项回归已通过。最终回归结果见下方验收补充及 artifacts 日志。

验收补充：Go 10 个顶层测试（含真实源比对）及 go vet 通过；Mock 图形 88 项、V1 真实图形 362 项、M3 地图相机 117 项、M4 战斗 653 项均通过。M5 新增颜色实际材质断言和真实 Debug Plane 回退后的最终图形检查为 **285 项，0 失败**；加上 FullRound 是 **286 项，0 失败**。完整真实回合为 tick 14311–21010，2x 实际播放约 52.84 秒，记录于 `artifacts/m5-full-round-report.json`。正式扩展 Schema 对完整 56.91 MiB 文件验证通过。ReplayClock、TrackSampler、TimelineUI 的 M5 前后 SHA256 一致。

最终图形交付复测保存在 `artifacts/milestone-5-report.json`，完整回合记录独立保留。Fire 最后修正为可穿透的橙红主体加阵营轮廓，避免建筑遮挡时 CT 火区只剩蓝色轮廓；截图已复查。正常用户启动入口单独验证加载成功，日志 `artifacts/m5-normal-start.log`；Godot 最终编辑器导入与 Parser 编译通过。

## 23. Known Issues

- 一个早期公开 Demo 完成真实数据验收；本样本没有 bomb_explode，因此爆炸处理分支没有真实样本覆盖。
- 部分安放没有后续 defuse/explode；计时显示 unknown，直到真实 round reset 清除状态，未假定游戏规则常数。
- JSON 仍全量读入内存；后台化改善响应但未变成流式加载，主线程场景提交仍可能产生短暂 frame gap。
- 只为已准备好的 Ancient 提供正式缓存安装；原始 VPK 转换仍用已有工具，未自动发现/准备所有地图。
- Smoke 体积、HE/Flash 视觉和 Fire patch 半径是抽象战术表示，不是 CS2 体素、真实光照、碰撞或 LOS。高空视角下小型弹体仍可能需要放大观察。
- 保留原 M4 的协议范围、枪线无可靠 impact、名字密集重叠和半透明排序限制。Godot 内存指标不等于整个进程峰值内存。
- 未在核显/旧独显完成实测，不把本机高 FPS 宣称为最低配置保证。

## 24. 下一阶段建议

优先增加较新 Demo 与含真实 Bomb explosion 的回归样本，再在普通核显验证 1080p 60 FPS。是否进入下一阶段等待用户指令，本次不继续实现其他系统。
