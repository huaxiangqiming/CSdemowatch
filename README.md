# CSdemowatch — CS2 Tactical Replay

**本地运行的 CS2 三维战术复盘沙盘 / A local-first CS2 3D tactical replay sandbox**

[中文说明](#中文说明) · [English](#english)

## 中文说明

CSdemowatch 将已完成的 Counter-Strike 2 Demo 转换为可自由观察的三维战术沙盘。通过灰色抽象地图和清晰的战术信息，复盘玩家走位、交火、投掷物配合与 Bomb 状态。所有解析、缓存和播放均在本机完成。

当前版本：**0.8.1-dev（M8.1）**。这是开发中的战术复盘工具，不追求还原 CS2 原版画面，也不保证所有 Demo 或地图版本兼容。

### 已实现

- 本地 `.dem` 解析，Replay V1/V2 JSON 兼容，独立 Replay / Map 缓存。
- 播放、暂停、随机 Seek、0.5× / 1× / 2× 速度和玩家轨迹插值。
- 玩家位置、朝向、队伍、存活状态，以及携带 Bomb 时的红色姓名。
- Smoke、Fire、HE、Flash、手雷轨迹、枪线、Damage、Kill Feed 和 Bomb 状态。
- 俯视、45°、透视、平移、缩放、旋转、地图透明度和信息图层。
- 缺地图时立即使用 Fallback Plane；从用户本机 CS2 准备地图后热替换，保持回放状态。
- 通用屋顶/天花板分类及可关闭的高度剖切，减少高模型遮挡，保留真实多层结构。
- Home、Loading、Replay、Settings、Error 和 Recent Replays。

### 获取与运行

**此仓库提供源码，不包含预编译 EXE、Godot、真实 Demo 或 Valve 地图资源。** 本地开发记录中提到的 `dist/windows` 和截图不代表仓库已发布下载包。

开发环境：Windows、PowerShell、Go **1.25+**、Godot **4.5.1 Standard**。

```powershell
git clone https://github.com/huaxiangqiming/CSdemowatch.git
cd CSdemowatch

# 编译 Parser
powershell -NoProfile -ExecutionPolicy Bypass -File ./tools/parser.ps1

# 将 Godot 放到 .tools/godot/，或把 godot / godot4 加入 PATH
powershell -NoProfile -ExecutionPolicy Bypass -File ./tools/run.ps1

# Mock 场景测试；不需要真实 Demo 或 CS2 安装
powershell -NoProfile -ExecutionPolicy Bypass -File ./tools/run.ps1 -Test
```

`.tools/godot/` 下预期的便携引擎文件名为 `Godot_v4.5.1-stable_win64_console.exe`。也可直接在 Godot 编辑器中打开 `app/project.godot`。

自动地图准备需要合法安装的本机 CS2，以及 Source2Viewer CLI 及依赖。将 `Source2Viewer-CLI.exe`、`libSkiaSharp.dll`、`spirv-cross.dll` 放到 `parser/bin/map-tools/`，并编译地图工具：

```powershell
go -C parser build -trimpath -o bin/cs2maptool.exe ./cmd/cs2maptool
```

完整 Windows 打包使用 `tools/build_windows.ps1`，还需要 `.tools/godot/windows_debug_x86_64.exe`、`windows_release_x86_64.exe` 导出模板，以及 `.tools/vrf/` 中的上述 Source2Viewer 文件和 `LICENSE.txt`。地图准备失败不会阻止成功解析的回放继续使用 Plane。

### 地图支持与限制

Ancient、Mirage、Dust2、Vertigo 有既有真实回放验收。Inferno 仅覆盖短 Demo 样本；Nuke、Train、Overpass、Anubis 等目前完成本机几何检查，仍标记 Experimental。已检查的 **16 张地图不等于所有 CS2 地图完整支持**。

Smoke、Fire 和部分视觉效果属于战术近似；未实现精确引擎级 LOS。大 JSON 回放仍可能需要数秒加载；部分地图几何量较大。查看地下层或密集建筑时，可调低 **View → Height cutaway**，或降低地图透明度。

### 文档与路线

- [M8.1 地图可视性验收](docs/milestone-8-1.md)
- [项目规范](PROJECT_SPEC.md) · [架构](docs/architecture.md) · [测试](docs/testing.md)
- [Replay V1](shared/replay-format/README.md) · [Replay V2](shared/replay-format/README-v2.md)
- [历史开发说明](docs/development-history.md)

下一阶段计划：M9 二进制 Replay 与按需加载；M10 战术分析；M11 时间轴和观察体验；M12 发布工程；M13 Public Beta；M14 1.0。路线图不代表这些功能已经实现。

## English

CSdemowatch turns completed Counter-Strike 2 demos into an interactive **3D tactical replay sandbox**. A neutral gray map keeps attention on player movement, utility, engagements and bomb state. Parsing, caching and playback run locally.

Current version: **0.8.1-dev / M8.1**. This is a development build for tactical review, not a recreation of the original CS2 graphics or a promise of universal demo compatibility.

### Features

- Local `.dem` parsing, V1/V2 JSON replay compatibility, and separate replay/map caches.
- Play, pause, seek, 0.5× / 1× / 2× playback, and interpolated player tracks.
- Player position, direction, teams, alive/dead state and red bomb-carrier names.
- Smoke, fire, HE, flash, grenade trajectories, shots, damage, kill feed and bomb state.
- Top-down, tactical and perspective cameras; pan, zoom, orbit, opacity and layer controls.
- Non-blocking fallback maps, background preparation from a local CS2 installation, and map hot swapping.
- Conservative roof/ceiling classification and reversible height cutaways for multi-level inspection.
- Home, loading, replay, settings, error handling and recent replays.

### Build and test

Requirements: **Windows, PowerShell, Go 1.25+, Godot 4.5.1 Standard**. Clone the repository and run the PowerShell commands in the Chinese setup section above. `tools/run.ps1` starts the viewer; `tools/run.ps1 -Test` runs the synthetic mock tests. Open `app/project.godot` for editor development.

```powershell
go -C parser test ./...
go -C parser vet ./...
```

Real-demo acceptance tests require separately supplied samples. Map preparation requires a legitimate local CS2 installation and the Source2Viewer CLI dependencies listed above. Build the map tool with `go -C parser build -trimpath -o bin/cs2maptool.exe ./cmd/cs2maptool`. For Windows packaging, prepare the Godot export templates and `.tools/vrf/` dependencies, then run `tools/build_windows.ps1`.

**This source repository does not include prebuilt executables, engine binaries, real demos, extracted Valve assets, or local caches.** Historical documentation references local acceptance artifacts that are intentionally not included.

### Compatibility and roadmap

Ancient, Mirage, Dust2 and Vertigo have existing real-replay acceptance coverage. Inferno has short samples only. Other listed maps, including Nuke, have geometry checks and remain experimental. Local checks on 16 maps do not establish support for every CS2 map, historical version, or demo type.

Utility visuals are tactical approximations. Large JSON replays and high-triangle maps still have performance limitations. Use **View → Height cutaway** to inspect lower floors without deleting map structures.

Planned stages: binary/streamed replay storage (M9), tactical analysis (M10), timeline and viewing improvements (M11), release engineering (M12), public beta (M13), and 1.0 (M14).

## 项目结构 / Repository layout

```text
app/                  Godot viewer, UI, rendering and synthetic tests
parser/               Go demo parser and tactical map converter
shared/replay-format/ Replay specifications and schemas
tools/                Build, import and acceptance scripts
docs/                 Architecture, tests and milestone reports
test_data/            Sample provenance only; real demos excluded
```

## 资源与许可 / Assets and licensing

本项目与 Valve 没有隶属或背书关系。Counter-Strike 和相关商标属于其权利人。地图仅从用户自己的 CS2 安装中只读提取，并在本机生成缓存。请勿向仓库提交 Valve 原始/提取资源、私人 Demo、账户凭据或本机缓存。

This project is not affiliated with or endorsed by Valve. Counter-Strike and related trademarks belong to their respective owners. Game resources are read from the user's own installation; generated map caches remain local. Do not commit Valve assets, private demos, credentials or machine-specific caches.

本仓库尚未指定项目代码的开源许可证；公开可见不等于授予任意再分发许可。第三方组件遵循各自许可证。

A project-wide source license has not yet been selected. Public visibility alone does not grant unrestricted redistribution rights. Third-party components retain their respective licenses.
