# M8.1 地图遮挡清理与多层观察验收

版本：App 0.8.1-dev，Map Converter 0.8.1，Geometry Classifier 2。Parser 0.6.0、Replay V1/V2 不变。本次按 detail.docx 的最高优先级补完 M8 地图生态及用户明确要求的高模型遮挡检查；未进入 M9 二进制回放或后续分析功能。

## 使用结果

启动 `dist/windows/CS2TacticalReplay.exe`，保留同目录 PCK、Parser 和 map-tools。真实回放默认开启 View → Height cutaway：最高有效存活玩家轨迹以上保留 2 个场景单位（200 Source units）的空间，超过的地图表面不绘制。滑块可调低以查看下层；关闭开关恢复完整的已转换地图。玩家、投掷物、烟火、Bomb 和事件不受剖切影响。

剖切是可逆的显示功能，不是把高层楼板从资产删除。未经过玩家的高层可能被默认剖切隐藏，需要关闭开关查看全部楼层。切换回放时新场景初始化剖切；同一场景 Reload 和后台热替换保留用户的开关和高度。

旧地图缓存，包括此前绕过通用转换的 Legacy Ancient，会独立失效并按用户既有 Auto/Ask/Never 设置处理。Auto 使用 Plane 继续回放并后台重建；Ask/Never 不被擅自修改。没有 CS2 时不能重建，继续使用 Plane。Replay 缓存不因地图转换器更新而失效。此次检查输出隔离在工作区 `artifacts/m81`，未批量覆盖用户现有 LocalAppData 缓存。

## 转换规则

- 沿用原来的近水平大顶盖、天空边界和导航邻接保护。
- 新增连通斜面顶盖识别：法线垂直分量至少 0.5、投影面积至少 65,536 平方 Source units、每个三角形下方存在导航、整个面组均无邻近导航支撑时才剔除。
- 水平面和斜面分别成组，避免浅倒角把原本可识别的水平天花板并入不确定结构。
- 无导航、不确定几何、小掩体、墙面和导航附近的楼板/坡道保留；不按地图名字或绝对海拔删除模型。
- 不透明剖切使用正常深度缓冲；低透明度剖切独立使用透明材质，避免 100% 模式也进入透明排序。
- CLI 与 Viewer 统一支持 `CS2_MAP_CACHE_ROOT`，后台进度也读取同一目录，便于隔离验收。

## 检查范围与证据

本机安装中的 16 张非 `_vanity` 的 `de_*.vpk` 全部实际准备成功，包括 Ancient Night 和本机额外地图。每张地图都从真实 collision/nav 资源运行分类前后支撑比较：对所有非竖直导航三角形中心进行垂直支撑查询，逐高度带统计。全部 lost_support=0、changed_support=0。这证明这些采样处没有因分类而丢失/改变地面，不等于证明每个可跳跃角落或历史地图版本完全一致。

每张地图输出并查看 Top、45° 和高度剖切截图。地图检查截图明确标为 No Demo loaded，不把 mock 玩家当真实轨迹证据。Vertigo 采用导航高度带定位观察层，避免整栋楼的外壳高度错误拉低镜头。Nuke 的真实上层地板仍保留；查看地下层需要调低剖切高度和聚焦。没有声称所有房间在任意角度都完全无遮挡。

证据：`artifacts/m81/de_*-{top,tactical,cutaway}.png`；`artifacts/m81/safety/<map>/map.glb.safety.json`、`map.glb.metrics.json` 和 `test.log`；分类原因见 `map.glb.classification.json`。原始 Valve 几何及派生缓存仅用于本机，不加入 Windows 发布包。

## 自动测试与正式程序

- Go 全套单元测试、`go vet ./...` 通过；新增斜屋顶、真实可行走坡道、无导航和远处无关导航的回归。
- 16 张真实地图分类前后导航支撑检查通过。
- Mock 84 项、真实 Ancient V1 回放 359 项、V2 战斗 651 项通过。
- 地图加载、UI 剖切、每个 mesh 的材质绑定、透明度和恢复共 2,458 项检查通过，见 `artifacts/m81/visual-report.json`。最终版本 48 张地图截图已查看。
- 最终正式 Windows EXE 实际打开真实 `dust2-short.dem`：空缓存 Fallback、自动准备、自动热替换、第二次 Replay/Map 缓存命中且无新转换，共 11 项通过。热替换逐项比较时间、速度、相机、玩家选择、图层、玩家状态、Bomb、Combat、Status、Kill Feed；额外确认自定义剖切高度及禁用状态可保留。证据 `artifacts/m81/final-live-replay/report.json` 和 `final-lifecycle.log`。
- Windows 导出成功，证据 `artifacts/m81/build.log`。运行环境为 Godot 4.5.1 Compatibility / RTX 5070 Ti Laptop GPU。本次没有重新进行跨显卡 FPS 基准测试。

沙箱运行日志含系统证书读取及 GPU shader 磁盘缓存写入提示；实际图形绘制、截图和测试通过，没有 GDScript 或 shader 编译错误。不把这些环境提示描述为零日志错误。

## 兼容性及剩余限制

Ancient、Mirage、Dust2、Vertigo 沿用已有真实回放验收；Inferno 只有既有短 Demo 样本，目录现明确标记 Experimental。Nuke、Train 等其余地图通过本次转换与几何检查，尚缺完整真实长 Demo 验收，也标记 Experimental。未安装的地图、Workshop 布局及无法解析的 Demo 不在本次保证范围内。

Boulder、Fachwerk、Inferno 等几何量仍较大；保留未知结构优先，本次不强行按三角形预算删几何。默认高度剖切只能隐藏当前高度以上的结构；多层间楼板和高度以下的墙体仍可能遮挡，可继续调低高度、旋转相机或降低地图透明度。透明模式仍可能存在排序限制。大 Replay JSON 的内存和加载问题留在 M9。

## 主要变更文件与复现

转换：`parser/internal/tactical/classifier.go`、`classifier_test.go`、`parser/cmd/cs2maptool/main.go`、`resolver.go`。

Viewer：`MapManager.gd`、`MapAssetCache.gd`、`MapAssetManager.gd`、`MapPreparationService.gd`、两个 HeightCutaway shader、`ViewControls.gd`、`SettingsScreen.gd`、`AppInfo.gd` 和 `app/maps/catalog.json`。

验收：`tools/test-map-visibility.ps1`、`app/tests/map_visibility_tests.gd`、`map_visibility_replay_tests.gd`。地图安全脚本默认覆盖七张主要地图，`-Maps` 可指定其余地图；只读 CS2 资源，输出到工作区。图形测试设 `CS2_MAP_CACHE_ROOT` 指向隔离的 prepared maps。生命周期测试另设空地图目录、`CS2_REPLAY_DATA_ROOT` 和 `M81_PROJECT`，使用正式 EXE 的 `--script` 运行。

本阶段完成后停在 M8.1，下一阶段需按文档节奏确认后再进入。

## 逐地图最终统计

以下移除数为该版本累计 Roof/Ceiling 三角形，不是相对旧版本增加的数量。

| 地图 | 保留三角形 | 移除 Roof/Ceiling | 丢失支撑 | 改变支撑 |
|---|---:|---:|---:|---:|
| de_ancient | 957259 | 1347 | 0 | 0 |
| de_ancient_night | 964771 | 1347 | 0 | 0 |
| de_anubis | 661873 | 775 | 0 | 0 |
| de_boulder | 8427590 | 2321 | 0 | 0 |
| de_cache | 1611860 | 5543 | 0 | 0 |
| de_debris | 572320 | 306 | 0 | 0 |
| de_dust2 | 412834 | 940 | 0 | 0 |
| de_eldorado | 1034214 | 1318 | 0 | 0 |
| de_fachwerk | 5343218 | 1137 | 0 | 0 |
| de_inferno | 2673958 | 3195 | 0 | 0 |
| de_mirage | 120396 | 775 | 0 | 0 |
| de_nuke | 174100 | 1432 | 0 | 0 |
| de_overpass | 1371151 | 1232 | 0 | 0 |
| de_poseidon | 408834 | 74431 | 0 | 0 |
| de_train | 1528804 | 4498 | 0 | 0 |
| de_vertigo | 195820 | 790 | 0 | 0 |
