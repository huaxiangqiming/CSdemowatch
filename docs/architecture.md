# 项目架构

## M7 当前地图与状态模块

有效 Replay 无地图时直接进入 Plane。AppController 的 MapPreparationPanel 非阻塞展示准备状态；MapPreparationService 在 Thread 中调用独立 cs2maptool，CS2InstallationDiscovery 负责安装发现。Go 工具只读本机 VPK，调用 Source2Viewer 导出碰撞几何，由 internal/tactical 转换为灰色 GLB，写入用户地图缓存。MapAssetManager/MapAssetCache 校验后，Main.reload_map 只重建地图层，保留 ReplayClock、轨迹和事件。MapTransform 仍统一处理坐标。

PlayerStatusResolver 按当前时间查询真实状态与最近伤害；Renderer 将 Carrier 转为红名，其余四种状态交给透明 Indicator。Replay 格式和 Parser 数据逻辑未升级。新增模块、交互流程和边界见 [M7 报告](milestone-7.md)。以下保留先前架构说明。

## M6 当前应用入口

Application.tscn → AppController 管理 Home/Loading/Replay/Settings/Error。DemoOpenService 在后台执行 Hash → ReplayCache → 隐藏 Parser → ReplayLoadJob，再由主线程提交 Main Viewer。SettingsStore、RecentReplays、ApplicationLog 独立保存配置、元数据和日志。返回 Home 释放 Viewer。

PlayerStatusResolver 将真实 Flash、PlayerHurt、当前战术 Smoke 和 BombReplayState 统一解释为五种状态；PlayerStatusRenderer/Indicator 以固定屏幕尺寸显示。时间均来自 ReplayClock，核心播放和地图缓存模块不重写。完整模块与文件清单见 [M6 报告](milestone-6.md)。下文保留基础 Viewer 架构说明。


新增 BombReplayState 独立时间查询，保留 ReplayEventIndex 的原有语义。MapAssetCache 负责版本、来源和 checksum；MapAssetManager 负责准备/加载接口；原 MapManager 负责 Godot 场景。ReplayLoadJob 后台读取、解码、校验和准备数据；Main 在工作线程结束后提交场景。详见 milestone-5.md。


M4 的正式事件字段和数据来源见 `../shared/replay-format/README-v2.md`。`combat.go` 订阅真实 Source 2 道具/击杀事件与实体更新、CMsgTEFireBullets 网络消息，构建独立 domain structs；`internal/serialization` 输出 JSON。玩家轨迹与 V1 相同，`--v1` 走原兼容分支。

Viewer 新增 `ReplayV2Validator → ReplayEvent / ProjectileReplayState → ReplayEventIndex → CombatController → UtilityRenderer / ProjectileRenderer / ShotRenderer`。唯一时间源仍为 ReplayClock。区间桶/二分查询驱动每次 Seek 和每帧渲染，避免依赖过去的 spawn 回调；颜色统一在 TeamVisualConfig 中，历史归属由数据固定。CombatPanel 与 KillMarkers 独立接入现有界面，TimelineUI 不变。详见 `milestone-4.md`。

## 独立 Parser

`cmd/cs2parser` 只处理命令行、CS2 文件头检查、文件路径保护、退出码、统计和 JSON 原子输出。

`internal/demo` 是唯一依赖 demoinfocs 的模块。固定 v5.2.0，顺序解码 Source 2 包，读取文件头 / ServerInfo 以获取地图与 tick rate，在 FrameDone 获取玩家实体快照，16 Hz 门限决定是否输出。V1 分支只提取玩家身份、阵营、位置、yaw、health、alive；V2 增加上述 combat recorder。底层库仍会解码维护实体状态所需的协议消息。

`internal/replay` 是纯 Go 数据结构和 Validator，不依赖 Godot 或 Demo 协议。文件始终保存原始 CS2 坐标。Player 身份与可用状态由 recorder 管理；team 逐帧保存以支持换边。所有数据校验成功后才替换目标文件。

## Viewer 数据路径

```text
JSON -> ReplayLoader -> ReplayValidator -> raw Vector3 / radians
                                             |
UI -> ReplayClock -> ReplayController -> TrackSampler
                              |
                        MapTransform
                              |
                          PlayerView
```

ReplayClock 未修改。原有 Timeline 的 Play / Pause / Seek / speed 和拖动行为保留，仅扩展动态时长文字及加载新文件时的信号解绑/重绑。TrackSampler 保留原有二分与线性/角度插值，增加离散状态左保持和明显中断时的插值边界。

Controller 保存当前原始采样状态，统一调用 MapTransform，再把转换后状态传给 PlayerView。PlayerView 完全不做坐标转换，负责 Capsule、方向、名字、阵营颜色、死亡压低和缺失状态隐藏。

## 地图、相机与显示

Main 连接 MapManager、ReplayController 和 UI。MapManager 根据 metadata.map 加载 maps/<name>/map.json，MapDefinition 校验并创建 MapTransform。模型已统一为 Y-up Source 单位，MapManager 使用同一 scale、rotation、offset 放置几何。Controller 接收 transform 并转换采样状态，无地图名分支。未知地图提示并回退 Plane。

Camera Rig 平移，Pivot 管理 yaw/pitch，Camera3D 沿局部 Z 控制距离；正交/透视、Top/45°/Free 共享状态。相机只接收通用范围和高度上界，不加载地图。

ViewControls 管理显示模式、透明度与相机预设；PlayerView 管理正常深度 Capsule、透明 no-depth X-Ray 副本和 billboard 姓名。MapManager 统一灰材质和透明度。DebugOverlay 观察原始/转换坐标以及相机/地图状态；WorldAxes 标识世界原点和 XYZ。

Milestone 3 未修改 ReplayClock、TrackSampler、TimelineUI 或 Go Parser 核心。精确配置、资源流程、测试和限制见 milestone-3.md。
