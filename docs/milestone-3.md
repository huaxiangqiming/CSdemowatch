# Milestone 3 — Ancient / Camera / X-Ray

本阶段在 Replay V1 上实现真实 Ancient 战术几何、可旋转相机、X-Ray 和地图透明度。开发到此停止，没有进入 Milestone 4。

## 1. 新增与修改文件

新增：

- `app/scripts/map/MapDefinition.gd`：地图配置加载和校验。
- `app/scripts/map/MapTransform.gd`：统一坐标转换。
- `app/scripts/map/MapManager.gd`：地图加载、灰材质、透明度和 Plane 回退。
- `app/scripts/ui/ViewControls.gd`：模式、透明度、相机预设和投影控件。
- `app/scripts/world/WorldAxes.gd`：原点和 XYZ 轴。
- `app/maps/de_ancient/map.json`、`map.glb`、`map.build.json`、`source.json`：地图定义、本地模型、构建统计、来源校验。
- `tools/import-ancient.ps1`、`tools/build-tactical-map.py`：可重复的本地地图提取流程。
- `app/tests/milestone_3_tests.gd`：相机、模式、坐标与几何对齐、遮挡画面对比。
- `docs/milestone-3.md`：本报告。

修改：`app/project.godot`、`app/scenes/Main.tscn`、`app/scripts/Main.gd`、`core/ReplayController.gd`、`map/DebugMapTransform.gd`、`camera/TacticalCamera.gd`、`replay/PlayerView.gd`、`ui/DebugOverlay.gd`、`tools/run.ps1`、`.gitignore`、README、架构与测试文档。Godot 可能生成相应 `.gd.uid` / `.glb.import` 元数据。

`ReplayClock.gd`、`TrackSampler.gd`、`TimelineUI.gd`、Go 核心 `parser.go` 与开始时 SHA256 一致。Replay Format V1、Loader、Validator、Mock JSON 和真实 Replay 均未修改。旧的 DebugMapTransform 仅保留兼容类名，继承正式 MapTransform。

## 2. Camera 架构

```text
TacticalCamera (Node3D / Rig，负责平移)
└── Pivot (Node3D，yaw / pitch)
    └── Camera3D (沿局部 Z 设置距离)
```

yaw 包装到 [-180,180)，可连续旋转整圈；pitch 限制 15°–89.9°，避免极点翻转。缩放大小最小 12，最大按轨迹范围配置；Mock 仍是 12–65。Home 使用轨迹边界恢复取景。正交与透视切换保持近似视野跨度。相机接收外部提供的场景高度上界，以保守高度约束避免进入建筑，不识别地图名或加载地图。

## 3. MapManager 架构

Main 负责连接模块：打开 Replay → MapManager 选择地图 → 注入 MapTransform 给 ReplayController → 配置相机和显示控件。

MapManager 负责地图定义、GLB 运行时加载、统一材质、透明度、模型边界和缺失地图的 Plane 回退。MapDefinition 负责配置校验。ReplayController 只通过通用 transform 接口转换采样状态；PlayerView 不执行任何 CS2 坐标换算。相机不包含 Ancient 特例。

## 4. MapDefinition

`app/maps/de_ancient/map.json`：

```json
{
  "map": "de_ancient",
  "model_path": "map.glb",
  "scale": 0.01,
  "rotation": 0.0,
  "offset": [0, 0, 0],
  "model_coordinates": "Normalized Y-up Source units: X, Z, -Y"
}
```

model_path 相对配置文件。rotation 为绕 Godot +Y 的角度，offset 为 Godot 世界单位。模型预处理已统一坐标轴，但尚未乘以 viewer scale。配置缩放、旋转、偏移同时用于模型和玩家。

## 5. Ancient 来源与处理

来自本机合法安装目录 `<CS2_INSTALL>/game/csgo/maps/de_ancient.vpk`，CS2 build 25218825。完整 SHA256 位于同目录 `source.json`。

使用官方 [Source 2 Viewer 20.0](https://github.com/ValveResourceFormat/ValveResourceFormat/releases/tag/20.0) CLI，从 `maps/de_ancient/world_physics.vmdl_c` 导出 `collision_physics.glb`。导出参数依据[官方 CLI 文档](https://s2v.app/ValveResourceFormat/guides/command-line.html)。

保留静态碰撞几何的地面、墙壁、高度、楼梯和掩体；移除 playerclip/npcclip、grenadeclip 和 blocklight 这三个不可见限制组。按空间分成 167 块，移除原材质、纹理，焊接精度 0.001 Source 单位，重新计算法线。最终保留 958,606 个原始碰撞三角形；没有削减地面三角形。

最终 `map.glb`：24,088,732 字节，约 22.97 MiB。它是本地派生 Valve 资源，已加入忽略规则，不作为可再分发源码资源提交。项目当前已包含本地模型，可直接运行；另一台机器需要从其本机 CS2 生成。

重建命令（需要 Python + pip，首次需要联网下载官方 CLI 和 numpy）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\import-ancient.ps1 -CS2Path '<CS2_INSTALL>' -Python python
```

这只是离线资产处理，不增加应用网络服务，也不处理 Replay V2 事件。

## 6. 坐标参数

Replay JSON 继续保存 Raw CS2 XYZ，yaw 为 CS2 角度。Loader 保留其语义，仅将内存 yaw 表示成弧度。

```text
Godot = Y轴旋转(rotation) × Vector3(CS2.X, CS2.Z, -CS2.Y) × scale + offset
Ancient: scale = 0.01, rotation = 0°, offset = (0,0,0)
Godot yaw = CS2 yaw - 90° + rotation
```

Source2Viewer 的导出空间先通过离线脚本从 `(export X,Y,Z)` 变为 `(Z,Y,-X) / 0.0254`，得到统一的 Y-up Source 单位模型。Godot MapTransform 才负责世界缩放/旋转/偏移。没有在 Parser 内做 Godot 转换，也没有逐个玩家的特殊偏移。

## 7. 玩家位置验证

使用已有 Ancient 真实 Demo，10 名玩家、10 条轨迹、1976.203125 秒、16 Hz。

- 原有真实回放检查验证各时刻 XYZ、yaw、Seek、中点插值、换边、死亡、三档速度和文件切换。
- 新测试沿完整轨迹每约 9.8 秒抽样有效存活状态，共 1,393 点；全部位于模型边界内。
- 对实际导入三角形建立临时测试碰撞，从脚上 35 Source 单位向下射线；1,393/1,393 命中地面。
- 1,379/1,393（99.0%）与脚下表面的高度差不超过 50 Source 单位，中位差 0.617 Source 单位。
- 报告保留每名玩家首个有效抽样点和高度差，覆盖双方出生区及移动轨迹。空中跳跃、箱体和不同地图版本会影响局部高度差；这不是每一帧都完全一致的保证。
- 另测非默认 scale、rotation、offset，确认 XYZ 与 yaw 同步转换。

完整原始结果：`artifacts/milestone-3-report.json`。Top / Tactical / Perspective 截图在 `artifacts/m3-ancient-*.png`。

## 8. X-Ray

PlayerView 保留正常深度 Capsule，另外复制一个 Capsule MeshInstance3D。副本使用 unshaded、alpha、no_depth_test 材质：X-Ray 活人 alpha 0.3，Tactical 0.5，死人 0.08。副本不投影。它与普通 Capsule 共享位置、缩放和 alive 状态。

Normal 隐藏副本且姓名进行深度测试；X-Ray / Tactical 显示副本且姓名穿透深度。材质排序为地图 -10、X-Ray 10、标签 20，避免透明地图覆盖姓名。标签 billboard，并按视野跨度保持约 14 像素高度；死人约 11 像素、暗灰，Capsule 压低。

独立不透明墙体场景同时放置墙前与墙后玩家，对 Normal / X-Ray 实际帧截图逐像素比较，验证墙后 Capsule 确实可见，而不只是检查材质属性。

## 9. Map Opacity

共用 StandardMaterial3D，支持 100/75/50/25%。100% 使用正常不透明深度；其余使用 alpha 混合。Tactical 模式将有效地图 alpha 限制在最多 50%，并加强玩家副本。设置原值保留，切回其他模式恢复。

## 10. 启动和操作

双击 `Open Real Replay.cmd` 打开真实 Ancient；双击 `Start Viewer.cmd` 打开 Mock。也可执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Replay .\test_data\public-s2.replay.json
```

| 操作 | 功能 |
|---|---|
| 滚轮 | Zoom |
| 右键拖动 | Pan |
| 中键拖动 / Alt + 左键拖动 | Orbit |
| 1 | Top View |
| 2 | Tactical 45° |
| 3 | Free Perspective |
| P / 投影按钮 | Orthographic / Perspective |
| Home / Reset camera | 恢复相机 |
| 右侧模式和透明度下拉框 | Normal / X-Ray / Tactical，地图透明度 |
| 左侧玩家下拉框 | 原始/转换坐标、yaw、health、alive |
| Play / Pause / Timeline / 三档速度 | 原有播放控制 |

## 11. FPS 与验收

Windows、Godot 4.5.1 GL Compatibility、RTX 5070 Ti Laptop GPU、1280×800、4× MSAA。实际播放 3 秒采样的 Tactical + Perspective 约 761 FPS，具体本次值见报告；不是跨设备性能保证。地图和约 54.5 MiB Replay 同步加载约 4–5 秒。

已验证 Mock 无界面 84 / 图形 88；原 Real 无界面 359 / 图形 362；M3 图形 117；Go tests + vet。Play / Pause / Seek / 0.5x / 1x / 2x 正常。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Test
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -RealTest -Replay .\test_data\public-s2.replay.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -MapTest -VisualTest -Replay .\test_data\public-s2.replay.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\parser.ps1 -Test -Demo .\test_data\s2\s2.dem
```

## 12. Known Issues

- 地图是碰撞代理几何，不是原版视觉模型；部分装饰被省略，几何边缘与原版画面不完全相同。碰撞体之间可能存在重叠接缝。
- 当前安装版地图与较早公开 Demo 不保证同版本；已验证总体坐标、出生区和高度基本对齐，未逐帧逐区域人工审计。
- alpha 模式有常见的透明几何排序/重叠效果；未做楼层分离或深度剥离。
- 镜头使用保守全图高度上界，在低 pitch 的透视近距离缩放时会限制实际靠近距离。尚无室内漫游或局部相机碰撞导航。
- 出生区多人重叠时姓名仍可能重叠；右侧面板也可能遮住靠近边缘的标签，可平移/缩放查看。UI 仍为英文。
- 同步 JSON 校验/地图加载会短暂阻塞；未新增缓存或异步加载。未知地图回退为 Plane，并明确提示。
- 运行方式仍是便携 Godot + 源码项目，未新增独立发行安装包。

## 13. 下一阶段建议

先收集地图版本差异样本，完善对齐回归、标签避让和分层观察，再由用户确定 Milestone 4 范围。没有自动实现 Smoke、Flash、HE、Molotov、Bomb、Weapon、Kills、Economy、音频、导出、Steam API、AI 或网络服务。
