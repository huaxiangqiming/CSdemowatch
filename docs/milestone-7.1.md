# Milestone 7.1 — Tactical Geometry Cleanup Hotfix

版本：0.7.1-dev。范围仅为战术几何可读性；Replay V1/V2、Demo Parser、Combat、坐标和播放系统不升级，不进入 M8。启动 `dist/windows/CS2TacticalReplay.exe`，本机 Mirage 缓存已自动重新生成，无需手动删除旧文件。

## 1. 原始遮挡原因

M7 将 `world_physics.vmdl_c` 碰撞三角形转成统一灰色、双面材质。原过滤规则处理 clip/植被/装饰，但没有区分天空碰撞边界、屋顶和可行走楼层。真实 Mirage 导出中包含 `physics_sky`，其巨大水平面被当作实体盖板绘制，其他建筑封盖也覆盖部分导航空间。碰撞几何不能直接等同于战术 Render Mesh。

没有按 Mirage 名称、固定坐标或指定 triangle index 删除几何；没有手工修改 GLB。

## 2. Roof classifier 设计

新增 Go `internal/tactical/classifier.go`。读取碰撞与导航 GLB 后，先构建水平面的共享边连通分组，再结合面积、AABB、高度范围、来源语义以及各层导航数据分类。类型为 FLOOR、WALL、STAIR、MAJOR_COVER、ROOF、CEILING、UNKNOWN。分类在地图准备阶段执行，运行时没有新增逐帧分类或裁切计算。

导航数据来自同一 VPK 的 `maps/de_map.nav`，使用随包 Source2Viewer 20.0 导出全部 hull 的导航多边形，避免重新实现二进制导航协议。坐标归一化复用现有 GLB 读取转换，与碰撞几何一致。实现依据 [VRF 20.0 导航导出源码](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/20.0/ValveResourceFormat/IO/GltfModelExporter.NavMesh.cs)。Nav 只辅助地图转换，不添加到 Replay，也不实现寻路或 LOS。

## 3. 分类条件

所有距离和面积均为 Source 单位，不含地图绝对高度阈值。

- 水平候选：单位法线竖直分量绝对值至少 0.94；共享量化后的边，相邻法线夹角余弦绝对值大于 0.98 时合并。顶点沿用原有 0.001 单位量化。
- 大封盖候选：连通面积至少 65,536 平方单位，组内高度范围不超过 64；下方至少存在一个投影重叠且距离不小于 128 的导航区域；整个组不能触发楼层保护。
- 有明确 sky 边界语义的表面，在有效导航存在且不触发楼层保护时归为 ROOF。该规则处理资源语义，适用于任何地图，不是特定 mesh 编号。
- 向下候选标为 CEILING，其他封盖标为 ROOF；两者均从正常 Render Mesh 分离。
- 接近竖直的结构保持 WALL；导航附近斜面作为 STAIR 候选；较小高处水平覆盖作为 MAJOR_COVER 候选；证据不足保持 UNKNOWN，并继续渲染。

分类名称是保守启发式概念，不声称每一个阶梯/箱子都被精确语义识别。UNKNOWN 不会被删除。

## 4. 如何保护 walkable floor

读取所有导航 hull 和全部高度层，排除近竖直梯子作为楼层证据。导航在水平面扩展 24 单位容差，补偿导航侵蚀和边缘缝隙；候选三角形的包围盒只要与任一导航区域水平重叠、竖直距离在 72 单位内，就保护整个连通组，包括可行走面下面的楼板。这种包围盒判断有意偏向多保留。

没有有效导航时，不删除不确定屋顶，明确输出警告。不使用“最高层就是屋顶”或简单 Z 截断。合成双层案例验证上下楼层、薄楼板、小掩体均保留，无导航时完整保留。真实 Mirage/Vertigo 另用独立的三角形重心垂直射线比较过滤前后的导航支撑，不只检查分类器自己的标签。

## 5. Mirage source triangle count

真实导出源：133,133 triangles。旧装饰/clip 过滤移除 11,962，M7 正常渲染为 121,171。

## 6. Roof removed triangle count

本次移除 775：ROOF 688，CEILING 87。巨大盖板由面积很大的少量三角形构成，因此小幅降低三角形数量也能显著改善可读性。

`map.json.geometry_stats` 和 CLI 最终 JSON 包含 source_triangles、render_triangles、kept_structural_triangles、roof_removed_triangles、decorative_removed_triangles、unknown_triangles、navigation_triangles、walkable_protected_triangles 与各类别计数。

分类诊断保存在 `map.glb.classification.json`；被移除几何保存在独立 `map.glb.roofs.glb`。普通 Viewer 只加载 `map.glb`，不会加载这两个诊断文件。Debug Overlay 增加 `Roof removed: 775 triangles`。本阶段没有添加普通用户屋顶开关，也没有实现可选的 Debug 开关；开发者可单独打开 roofs GLB 复核。

## 7. 最终 triangle count

Mirage 最终 120,396 triangles：

| 类型 | 数量 |
|---|---:|
| FLOOR | 13,230 |
| WALL | 72,924 |
| STAIR | 2,824 |
| MAJOR_COVER | 8,353 |
| UNKNOWN（保留） | 23,065 |

已识别并保留结构为 97,331，加 UNKNOWN 等于正常渲染总数。导航附近受保护三角形为 41,278（含墙/斜面等，不能将其与 FLOOR 数直接相加）。

## 8. GLB before / after size 与加载

| 指标 | Before | After |
|---|---:|---:|
| Render triangles | 121,171 | 120,396 |
| 正常 GLB bytes | 3,481,080 | 3,460,356 |
| 场景提交/加载 | 29ms | 28ms |
| 截图地图 alpha | 1.0 | 1.0 |

这是单次本机测量，Before 用同版 Godot 4.5.1 图形运行，After 使用最终 Windows Release；并非清理操作系统缓存后的性能基准，不声称 1ms 差值是显著提速。被移除几何的诊断 GLB 为 78,904 bytes；正常运行不加载它。完整分组诊断 JSON 约 31.8MB，增加磁盘调试数据，但不会增加正常地图三角形或逐帧成本。

## 9. Before / After screenshots

同一真实 `damage-source.dem`、282.48125 秒、1920×1080、同一固定 Top 正交相机位置/朝向/尺寸、100% 地图不透明度。没有通过低透明度解决问题。以下两张已实际打开对比：

![Before](../artifacts/m7-1-mirage-before.png)

![After](../artifacts/m7-1-mirage-after.png)

前图几乎整片内部被连续灰板遮住；后图内部结构、通道、玩家和朝向可见。八处近距离 45°、100% 不透明度截图也逐张检查了 A/B、Mid、Connector、Jungle、Short、T/CT Spawn，墙体、平台、楼梯和箱体没有出现大面积丢失。楼板和建筑外部的不确定顶面仍有保留，不能把所有从上方可见的平面都当作错误屋顶。

## 10. Mirage alignment regression

使用与 M7 相同的真实轨迹抽样和碰撞射线：Before/After 均为 1,099 次采样、1,099 命中；高度差在 50 Source 单位内均为 1,059。中位高度差从 0.00541186 到 0.00541735 Godot 单位，仅浮点三角形重排量级变化。八处参考区域的 Raw 和 Converted 坐标完全相同，未修改 MapTransform、玩家坐标或 Replay。

另外，3,442 个可用于竖直支撑检查的导航三角形中心中，原几何支持 3,438 个；过滤后仍为 3,438，丢失支撑 0、支撑高度改变 0。原本未命中的 4 个不冒称已修复。见 `artifacts/m71-mirage.glb.safety.json`、`m7-1-before-report.json`、`m7-1-after-report.json`。

## 11. Ancient regression

既有 M3 Ancient 资产保留兼容；本次没有重新生成或改写其 mesh，仍为 958,606 triangles、24,088,732 bytes。最终 EXE 可打开真实 Ancient 回放；M7 完整回归再次验证地图和播放。专用地图回归 117 检查通过，1,393 个真实轨迹射线全部命中、1,379 个在 50 Source 单位内，见 `artifacts/m71-ancient-regression.log`。这种兼容不等于声称 Ancient 全部几何已由新分类器分类。

## 12. Multi-level safety test

真实 Vertigo 的 `world_physics.vmdl_c` 和同包 `.nav` 导出为中间 GLB，运行完全相同的分类器，无地图 override。未把 Vertigo 安装进正式地图缓存，保持 M7 的第三地图 fallback 验收。

源 210,596 triangles；旧装饰过滤 13,986；屋顶/天花板移除 790；保留 195,820。FLOOR 28,320，WALL 110,517，STAIR 14,856，MAJOR_COVER 12,016，UNKNOWN 30,111；导航附近保护 92,932。导航数据共 2,939 triangles，竖直支撑检查使用 2,905 个中心（竖直梯子/陡面不计）。

| Source 高度带（256 单位） | 导航样本 | 原支撑 | 新支撑 |
|---|---:|---:|---:|
| 44 | 585 | 584 | 584 |
| 45 | 787 | 776 | 776 |
| 46 | 1,533 | 1,529 | 1,529 |

三个高度带丢失支撑 0、支撑高度改变 0，所有非 sky 的非水平结构保留。没有因为绝对高度较高而删除上层楼板。诊断：`artifacts/m71-vertigo.glb.metrics.json`、`m71-vertigo.glb.safety.json`。这证明本次样本的楼层支撑安全，不是所有未来地图的数学保证。

## 13. Cache invalidation method

通用转换器从 0.7.0 升到 0.7.1，manifest/map.json 增加 `classifier_version: "1"`。Viewer 自动拒绝缺少当前 classifier 标记的 0.7 系列缓存；不依赖地图名。旧 M3 手工准备的兼容资产没有通用 converter 标记，继续按原 checksum 校验，避免无关 Ancient 资产被强制替换。

本机 Mirage 已由新版 cs2maptool 从只读 VPK 自动重建，最终准备约 2.7 秒（一次实测）。旧文件不要求用户自行寻找删除。其他旧通用缓存变 stale 后仍能进入 Replay/Plane；下一次 Prepare 会覆盖重建。Ask/Auto/Never 的 M7 偏好不改变，不强制静默转换用户选择 Never 的地图。

最终 EXE 专项测试明确用旧完整缓存验证 stale → Replay/Plane → 新缓存加载；地图准备失败不破坏 Any Parsed Demo Opens。

## 14. 新增 / 修改文件与测试

新增：`parser/internal/tactical/classifier.go`、`classifier_test.go`、`app/tests/milestone_7_1_tests.gd`、`tools/test-milestone7.1.ps1`、本报告。

修改：`parser/internal/tactical/glb.go`（读取/分类/写入分离）、`parser/cmd/cs2maptool/main.go`（导航导出、版本、诊断提交）、`app/scripts/map/MapAssetCache.gd`、`MapManager.gd`、`app/scripts/ui/DebugOverlay.gd`、`app/scripts/application/AppInfo.gd`、README、Windows 快速说明。新增测试脚本的 Godot UID、本机发行二进制、用户地图缓存与 artifacts 随测试生成。

未改 Replay 格式、Demo Parser 数据逻辑、ReplayClock、TrackSampler、Timeline、MapTransform、Combat 事件。当前工作区没有 Git，文件清单依据实际修改记录。

构建：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_windows.ps1`。

专项验收：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-milestone7.1.ps1`，需要已保存的本地 M7 原缓存基准和已重建的 Mirage。最终 EXE 11 检查、0 失败；M7 完整回归 52 检查、0 失败（包含 Play/Pause/Seek/速度、状态、实际准备、三 Demo 和错误恢复）。报告与日志为 `m7-1-after-report.json`、`m71-export.log`、`m71-m7-regression.json`、`m71-m7-regression.log`。

Go 全包 12 个顶层单元测试及 go vet 通过，7 个可选测试默认跳过，不把它们算成重新执行；真实地图分类和安全测试另外显式运行了 Mirage/Vertigo。Mock 88 检查通过。Mock 与 Ancient 专项日志分别为 `m71-mock.log`、`m71-ancient-regression.log`。交付审计 `m71-delivery-audit.json` 确认版本、二进制一致、地图 checksum 正确、源 VPK 标识未变、正式运行日志无 ERROR/SCRIPT ERROR。

## 15. Known Issues

- 这是保守的导航辅助分类；导航不完整、特殊连通拓扑、斜屋顶和小封盖可能保留。缺导航时优先保留几何，不能保证每张地图都自动去掉所有遮挡。
- 导航附近 24/72 单位容差和整组保护有意多保留；STAIR/MAJOR_COVER 是概念分类，不是精确游戏语义。
- 合法上层楼板仍会遮挡下层，这是多层地图的真实结构；本阶段不做分层视图、LOS 或动态剖切。
- 诊断 JSON 较大且独立保存；正常 Viewer 不加载。没有新增 roofs 交互开关，检查被分离几何需单独打开诊断 GLB。
- 当前导航适配依赖随包 VRF 20.0。新资源版本导出失败可能保留不确定屋顶或使准备失败；Replay 仍可 Plane 播放。
- 密集姓名重叠、部分真实墙体遮挡、碰撞模型与旧 Demo 地图版本差异、较大 JSON 加载时间等 M7 限制仍存在。

M7.1 到此停止，不自动进入 M8。
