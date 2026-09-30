# CS2 Tactical Replay Viewer

> Counter-Strike 2 Demo 三维战术回放与分析软件

项目暂定名称：

CS2 Tactical Replay Viewer

也可以后续改名为：

- CS2 Replay Viewer

- CS2 Tactical Viewer

- CS2 Demo Visualizer

- CS2 Replay Director

---

# 1. 项目概述

本项目是一个面向 Counter-Strike 2 的独立桌面 Demo 回放软件。

用户可以将 CS2 生成的 `.dem` 文件拖入软件。

软件解析 Demo 中记录的比赛数据，并使用自定义三维场景重新演示整场比赛。

本软件不会启动 CS2 来播放 Demo。

本软件也不会对 CS2 游戏进程进行：

- 内存读取

- DLL 注入

- 游戏 Hook

- 实时 Overlay

- 实时透视

- 实时辅助

整个系统工作于：

“已经完成的比赛 Demo 文件”

之上。

因此软件本质上是：

CS2 Demo Parser

+

3D Tactical Replay Viewer

+

Timeline Replay System

目标视觉效果类似一个三维战术沙盘。

玩家可以从俯视 / 45° 等视角观察双方队员的位置、移动、交火、投掷物以及战术执行。

---

# 2. 核心产品理念

软件不是传统 CS2 Demo Player。

传统 Demo Player 的目标是：

“重新进入游戏观看比赛。”

本项目的目标是：

“把比赛转换为三维战术数据，然后重新可视化。”

例如：

原始 CS2 Demo：

match.dem

经过解析：

Player Position

Player Rotation

Player Health

Weapon

Kills

Shots

Grenades

Smoke

Molotov

Bomb

Round

Events

最终渲染成为：

三维地图

+

10 名玩家

+

时间轴

+

事件

+

战术视图

最终体验类似：

CS2 比赛的三维战术沙盘。

---

# 3. 核心使用流程

用户启动程序。

首页显示：

CS2 Tactical Replay Viewer

Drag CS2 Demo Here

或者：

Open Demo

用户拖入：

match.dem

程序开始解析：

Parsing Demo...

解析完成以后识别：

Map

Match Duration

Rounds

Players

Teams

例如：

Map:

de_mirage

Rounds:

24

Duration:

42:36

Players:

10

随后进入 Replay Viewer。

用户可以：

播放

暂停

拖动时间轴

改变播放速度

切换 Round

自由移动摄像机

查看所有玩家

查看击杀事件

查看手雷

查看 Smoke

查看 Molotov

查看 Bomb

---

# 4. 软件核心界面

整体界面推荐：

┌──────────────────────────────────────────────┐

│                  Top Bar                     │

│ File / View / Settings                       │

├─────────────┬────────────────────────────────┤

│             │                                │

│ Match       │                                │

│ Rounds      │                                │

│ Players     │         3D Replay View         │

│ Events      │                                │

│ Grenades    │                                │

│             │                                │

├─────────────┴────────────────────────────────┤

│                                              │

│  ◀  ▶  |──────── Timeline ────────|  1.0x  │

│                                              │

└──────────────────────────────────────────────┘

左侧：

Match

Rounds

Players

Events

中间：

三维地图。

底部：

Playback Controls。

---

# 5. 核心视觉目标

地图整体使用简化三维风格。

不需要还原 CS2 原版画质。

地图重点展示：

墙体

地面

楼梯

高度差

箱子

主要掩体

重要建筑结构

地图整体可以使用：

灰白色

浅灰色

低饱和度材质

玩家使用简单三维模型表示。

例如：

Capsule

Cylinder

Pawn

T 玩家：

橙色 / 黄色

CT 玩家：

蓝色

玩家上方显示：

Player Name

例如：

Daniel

Hunter

MOUNTAIN

视觉效果类似一个三维棋盘 / 战术沙盘。

---

# 6. 为什么使用真正的 3D

本项目不应该只使用 2D Radar。

因为 CS2 存在大量复杂的高度结构。

例如：

Nuke

Vertigo

Train

两个玩家可能：

X = 100

Y = 200

Z = 300

以及：

X = 100

Y = 200

Z = -200

二维地图中会发生位置重叠。

因此 Replay 数据必须保留：

X

Y

Z

地图也应该保留真正的高度结构。

---

# 7. 推荐技术架构

第一阶段推荐技术栈：

Desktop Client:

Godot 4

主要语言：

C#

或者：

GDScript

Demo Parser:

Go

Demo Parser Library:

demoinfocs-golang

地图转换工具：

ValveResourceFormat / Source 2 Resource Tools

Replay 中间文件：

自定义格式

第一阶段可以：

JSON

正式版本推荐：

MessagePack

或者

Protobuf

---

# 8. 为什么使用 Godot

本项目表面上是桌面软件。

但核心功能实际上接近：

一个实时三维游戏播放器。

需要实现：

3D Scene

Camera

Mesh

Shader

Particles

Animation

Timeline

Interpolation

UI

Input

Picking

使用传统桌面 GUI：

Qt

WPF

WinUI

意味着还需要额外搭建复杂的 3D Render Pipeline。

Godot 已经提供：

Node3D

Camera3D

MeshInstance3D

Label3D

Particles

Shader

Animation

UI Control

Input System

非常适合这个项目。

---

# 9. 软件整体架构

整体架构：

CS2 .dem

    |

    v

Demo Parser

    |

    v

Replay Converter

    |

    v

Custom Replay Data

    |

    v

Replay Loader

    |

    +----------------------+

    |                      |

    v                      v

Timeline System       Event System

    |                      |

    +----------+-----------+

               |

               v

          3D Renderer

               |

     +---------+---------+

     |         |         |

     v         v         v

    Map     Players   Grenades

                         |

              +----------+----------+

              |          |          |

              v          v          v

            Smoke     Molotov      Bomb

---

# 10. 项目模块划分

项目至少分成：

App

Parser

Replay Format

Map System

Timeline

Renderer

Events

UI

Cache

推荐：

CS2TacticalReplay/

app/

parser/

shared/

tools/

docs/

---

# 11. 推荐项目目录

项目初期目录：

CS2TacticalReplay/

README.md

PROJECT_SPEC.md

LICENSE

app/

    project.godot

    scenes/

        Main.tscn

        ReplayViewer.tscn

        MainMenu.tscn

        replay/

            Player.tscn

            Grenade.tscn

            Smoke.tscn

            Molotov.tscn

            Bomb.tscn

    scripts/

        core/

            ReplayController.cs

            ReplayClock.cs

            ReplayLoader.cs

            ReplayCache.cs

        map/

            MapManager.cs

            MapLoader.cs

        replay/

            PlayerController.cs

            GrenadeController.cs

            SmokeController.cs

            MolotovController.cs

            BombController.cs

        ui/

            TimelineUI.cs

            RoundListUI.cs

            PlayerListUI.cs

            EventListUI.cs

        camera/

            TacticalCamera.cs

            FreeCamera.cs

    assets/

        icons/

        shaders/

        materials/

parser/

    cmd/

        cs2parser/

            main.go

    internal/

        demo/

        player/

        events/

        rounds/

        grenades/

        replay/

    go.mod

shared/

    replay-format/

        README.md

tools/

    map-extractor/

    map-converter/

maps/

    README.md

docs/

    architecture.md

    replay-format.md

    map-system.md

---

# 12. Demo Parser

Demo Parser 是一个独立程序。

例如：

cs2parser.exe

输入：

match.dem

输出：

match.replay

命令示例：

cs2parser.exe input.dem output.replay

Parser 负责：

读取 Demo

提取：

Match Metadata

Players

Rounds

Player Tracks

Kills

Shots

Grenades

Smokes

Molotovs

Bomb Events

然后转换成软件内部统一 Replay Format。

---

# 13. 为什么 Parser 独立

Godot 不应该直接理解复杂的 CS2 Demo Protocol。

这样可以降低耦合。

Godot 只需要理解：

Replay Format

未来即使 Demo Parser 改成：

Go

Rust

C++

Godot 播放器也不需要修改。

---

# 14. Replay Format

必须设计自己的 Replay 数据格式。

不要让客户端直接读取 Demo。

数据关系：

Demo

↓

Parser

↓

Replay Format

↓

Viewer

第一阶段可以使用：

JSON

方便 Debug。

正式版本可以转换为：

MessagePack

或者

Protobuf

---

# 15. Replay 数据总体结构

概念结构：

ReplayFile

Metadata

Players

Rounds

Tracks

Events

Grenades

Bomb

---

# 16. Metadata

例如：

{

    "version": 1,

    "map": "de_mirage",

    "duration": 2536.42,

    "tick_rate": 64,

    "player_count": 10

}

---

# 17. Player 数据

Player：

{

    "id": 1,

    "steam_id": "xxx",

    "name": "Daniel",

    "team": "T"

}

注意：

播放器内部不能依赖 Player Name 作为 ID。

必须拥有唯一 Player ID。

---

# 18. Player Track

PlayerTrack 表示玩家随时间变化的位置。

例如：

{

    "player_id": 1,

    "frames": [

        {

            "time": 0.0,

            "position": [100, 200, 30],

            "yaw": 90,

            "pitch": 0,

            "health": 100,

            "alive": true,

            "weapon": "ak47"

        },

        {

            "time": 0.1,

            "position": [104, 205, 30],

            "yaw": 92,

            "pitch": 0,

            "health": 100,

            "alive": true,

            "weapon": "ak47"

        }

    ]

}

---

# 19. 时间系统

不要让 Replay Renderer 直接依赖 Demo Tick。

建立统一时间：

Replay Time

单位：

seconds

例如：

12.53 seconds

播放器维护：

CurrentReplayTime

所有数据根据：

CurrentReplayTime

计算当前状态。

---

# 20. 插值系统

不能每一个 Demo Tick 生硬移动角色。

需要进行插值。

例如：

Frame A

positionA

Frame B

positionB

当前时间：

t

计算：

position = lerp(positionA, positionB, t)

Rotation 同样插值。

需要注意角度跨越：

359°

到：

1°

不能直接普通 lerp。

应该进行角度插值。

---

# 21. Replay Clock

创建：

ReplayClock

职责：

CurrentTime

Duration

PlaybackSpeed

IsPlaying

支持：

Play()

Pause()

Seek(time)

SetSpeed(speed)

Update(delta)

例如：

PlaybackSpeed:

0.25x

0.5x

1x

2x

4x

---

# 22. Timeline

Timeline 是项目核心系统之一。

底部显示：

0:00 ───────────────────── 1:45

时间线上显示事件。

例如：

Smoke

Kill

Molotov

Bomb Plant

Bomb Defuse

用户点击 Kill：

跳转到该 Kill 前几秒。

例如：

Kill Time:

62.5 sec

实际 Seek：

59.5 sec

---

# 23. Round System

Replay 必须支持 Round。

例如：

Round 1

start:

0 sec

end:

102 sec

winner:

CT

reason:

Elimination

UI 左侧显示：

Round 1

Round 2

Round 3

...

点击：

Round 7

自动 Seek 到 Round 7 开始。

---

# 24. Player Renderer

第一版绝对不要制作真实人物模型。

使用简单：

CapsuleMesh

Player Node：

PlayerNode

MeshInstance3D

DirectionIndicator

Label3D

玩家上方：

PlayerName

未来可以增加：

Health

Weapon

Steam Avatar

但不是 MVP。

---

# 25. Player Direction

玩家应该显示当前朝向。

例如：

     |

     |

     ●

或者：

\   /

 \ /

  ●

玩家 Mesh 上增加：

DirectionIndicator

Yaw 控制方向。

---

# 26. Team Color

推荐：

CT：

蓝色

T：

橙黄色

Dead：

灰色 / 半透明

这些颜色以后允许用户在 Settings 修改。

---

# 27. Death

玩家死亡事件发生时：

alive = false

V0.1 可以简单：

隐藏 Player

或者：

变为半透明

以后可以：

留下 Death Marker

例如：

X

表示死亡位置。

---

# 28. Camera System

至少支持两种 Camera：

Tactical Camera

Free Camera

---

# 29. Tactical Camera

默认 Camera。

主要效果：

俯视 45°

或者：

Orthographic Camera

操作：

Mouse Wheel

Zoom

Right Mouse Drag

Pan

Middle Mouse Drag

Rotate

Home

Reset Camera

---

# 30. Camera Presets

未来提供：

Top View

45° Tactical View

Free View

快捷键：

1

Top

2

45°

3

Free Camera

---

# 31. Map System

地图系统是项目最重要、也是最困难的部分之一。

不要直接将完整 CS2 地图原封不动加载。

需要进行：

Map Simplification

只保留：

Floor

Wall

Stairs

Boxes

Major Cover

Doors

Important Geometry

删除：

Decoration

Small Objects

Complex Textures

Unnecessary Props

---

# 32. 地图视觉风格

目标：

战术沙盘。

而不是：

CS2 高清画面。

推荐：

灰色墙体

浅灰地面

低饱和度

简单 Shader

玩家颜色突出。

这样用户可以快速判断：

位置

站位

轮转

交火

投掷物

---

# 33. Map Coordinate

必须解决：

Demo Coordinate

和：

Godot Coordinate

之间的转换。

例如：

CS2:

X

Y

Z

Godot:

X

Y

Z

两者坐标轴定义可能不同。

必须建立：

MapTransform

例如：

GodotX = CS2X * Scale

GodotZ = -CS2Y * Scale

GodotY = CS2Z * Scale

具体实现需要通过实际地图测试确定。

这个转换必须统一封装。

禁止在不同模块里直接手写坐标转换。

---

# 34. MapManager

MapManager 负责：

根据 Replay Metadata：

map = de_mirage

加载：

maps/de_mirage/map.glb

例如：

MapManager.Load("de_mirage")

---

# 35. 地图资产策略

非常重要：

GitHub 项目不要直接包含大量 Valve 原始：

Textures

Models

Maps

Sounds

推荐方式：

用户已经安装 CS2。

软件第一次启动：

Detect CS2 Installation

找到：

Counter-Strike Global Offensive/game/csgo/

然后运行地图转换工具。

从用户本机资源生成：

Simplified Tactical Map

缓存到：

AppData

例如：

AppData/Local/CS2TacticalReplay/maps/

这样项目本身主要发布：

代码

解析器

地图转换器

而不是重新发布完整 Valve 游戏资源。

正式发布 GitHub 和 Steam 之前需要再次确认最新的 Valve / Steam 资源使用条款。

---

# 36. Grenade System

未来需要支持：

HE

Flash

Smoke

Molotov

Decoy

V0.1 可以暂时不做全部。

---

# 37. Grenade Trajectory

投掷物：

spawn_time

start_position

trajectory

explode_time

例如：

GrenadeTrack

[

    t0 position

    t1 position

    t2 position

]

播放时根据时间插值。

可以显示：

Grenade Model

以及：

Trajectory Line

---

# 38. Smoke

Smoke 激活后：

在世界中显示一个烟雾范围。

第一阶段不需要真实粒子烟雾。

可以使用：

透明 Sphere

或者：

简单半透明 Volume

表示 Smoke Area。

重点是：

战术信息

而不是画面真实性。

---

# 39. Molotov

Molotov 可以第一阶段使用：

平面区域

加：

简单火焰颜色

未来再实现粒子。

---

# 40. Bomb

Bomb 状态：

Carried

Dropped

Planted

Defused

Exploded

需要展示：

Bomb Position

未来可以显示：

Bomb Timer

---

# 41. Kill Event

Kill Event：

time

attacker

victim

weapon

position

headshot

Timeline 上展示 Kill Marker。

点击 Kill Event：

Camera 可以自动跳转到战斗区域。

这个功能可以后续开发。

---

# 42. Event System

统一定义：

ReplayEvent

例如：

KillEvent

ShotEvent

GrenadeEvent

SmokeStartEvent

SmokeEndEvent

BombPlantEvent

BombDefuseEvent

BombExplodeEvent

RoundStartEvent

RoundEndEvent

---

# 43. Cache

Demo 第一次打开：

match.dem

↓

Parse

↓

生成 Replay

以后再次打开相同 Demo：

直接读取缓存。

缓存路径：

Windows：

%LOCALAPPDATA%/CS2TacticalReplay/cache/

例如：

cache/

    demo_hash.replay

Demo Hash 可以使用：

SHA256

根据 Demo 文件计算。

---

# 44. 为什么使用 Cache

Demo Parser 没必要每次重新解析整个比赛。

第一次：

几秒钟解析。

第二次：

接近立即打开。

---

# 45. Replay 数据大小

不要保存所有不必要的数据。

如果 Demo 是：

64 Tick

一场：

45 分钟

理论 Tick 数：

172800

10 个 Player：

1,728,000 个玩家 Tick 状态。

如果全部保存成 JSON 会非常大。

因此后期需要优化。

---

# 46. Track Sampling

第一版本可以采样：

10 Hz

或者：

16 Hz

例如每：

100 ms

记录一次玩家位置。

Renderer 使用插值。

视觉上仍然非常流畅。

未来可以根据需求调整。

---

# 47. 数据压缩

第一版：

JSON

正式版本：

MessagePack

或者：

Protobuf

再配合：

gzip

或者：

zstd

轨迹数据还可以：

Delta Encoding

例如：

Position 不是每次存完整：

1000

2000

300

而是：

+4

+2

0

降低数据大小。

但这些不是 MVP。

---

# 48. 第一阶段 MVP

最简实现目标：

只解决一个问题：

“把一个真实 CS2 Demo 拖进程序，然后看到玩家在三维地图中移动。”

MVP 只支持：

Windows

一张地图

推荐：

de_mirage

支持：

打开 Demo

解析 Demo

获取玩家

获取玩家 X Y Z

获取玩家方向

获取玩家名称

加载简化 Mirage 地图

显示 10 个 Player Capsule

显示 Player Name

显示 CT / T 颜色

播放

暂停

拖动 Timeline

1x 播放

Camera 移动

Camera Zoom

---

# 49. MVP 明确不实现

为了避免项目第一阶段失控：

MVP 不实现：

真实玩家模型

枪械模型

Smoke

Molotov

Flash

HE

Bullet Tracer

Sound

Voice

Weapon Animation

Kill Animation

Heatmap

AI Analysis

Video Export

Auto Camera

POV Mode

Steam Integration

Cloud

Account System

Multiplayer

Online Demo

服务器

---

# 50. MVP 完成标准

一个真实：

de_mirage.dem

拖入软件。

5-10 秒内完成解析。

进入三维 Mirage。

地图上显示：

10 名玩家。

玩家：

位置正确

高度正确

移动正确

方向基本正确

T / CT 区分正确。

用户可以：

Play

Pause

Seek

玩家随着 Timeline 正确变化。

如果这些实现：

MVP 完成。

---

# 51. V0.1

MVP 完成以后开发：

V0.1

V0.1 应该成为：

可以公开给用户试玩的第一个版本。

包含：

Demo Upload / Drag & Drop

Demo Cache

Match Metadata

Round List

Timeline

Player Movement

Player Direction

Player Name

Player Alive / Dead

CT / T Team Colors

Playback Speed

0.25x

0.5x

1x

2x

4x

Tactical Camera

Top Camera

Free Camera

Kills

Bomb

基础 Grenade

Round Navigation

---

# 52. V0.1 支持地图

最开始：

de_mirage

然后增加：

de_dust2

de_inferno

de_nuke

de_ancient

de_anubis

de_vertigo

不要一开始同时处理所有地图。

推荐开发顺序：

Mirage

↓

Dust2

↓

Inferno

↓

Nuke

↓

Vertigo

Nuke / Vertigo 用于验证：

Z Axis

以及多层地图系统。

---

# 53. V0.2

后续版本：

Smoke Area

Molotov Area

Flash Event

HE Explosion

Grenade Trajectory

Kill Markers

Weapon Information

Player Health

Armor

Economy

Bomb Timer

Event Filtering

---

# 54. V0.3

高级战术功能：

Player POV Cone

Line Of Sight

Visibility

Crossfire

Rotation Path

Player Trail

Team Movement

Entry Path

Heatmap

---

# 55. V1.0

正式成熟版本可以考虑：

Auto Camera

Replay Director

Video Export

4K Rendering

60 FPS Offline Rendering

Highlight Generator

Tactical Analysis

Share Replay

Replay Annotation

Coach Tools

---

# 56. 自动导演系统

未来功能。

软件检测：

即将发生交火的位置。

Camera 自动：

移动

缩放

跟随战斗。

类似电竞 Observer。

例如：

Player A

即将遇到：

Player B

Camera 自动移到：

A Site

然后播放交火。

这样可以用于：

YouTube

Bilibili

比赛分析视频。

---

# 57. 视频导出

未来可以实现：

Export Replay

分辨率：

1080p

1440p

4K

FPS：

30

60

输出：

MP4

这样内容创作者可以直接使用软件生成战术演示。

不属于早期版本。

---

# 58. 性能目标

V0.1：

10 Player

单张地图

稳定：

60 FPS

Timeline Seek：

尽可能立即响应。

内存：

尽量控制在普通 PC 可以接受的范围。

因为地图是简化地图：

GPU 压力应该很低。

主要性能压力：

Demo Parsing

Replay Data Loading

Timeline Seek

---

# 59. Parser Progress

Parser 应该可以报告：

Parsing Demo

10%

20%

50%

80%

100%

Godot 启动：

cs2parser.exe

并读取：

stdout

例如：

PROGRESS 0.10

PROGRESS 0.20

PROGRESS 0.70

Godot UI 显示：

Parsing Demo...

██████████░░░░

---

# 60. Parser Output

Parser 成功：

退出码：

0

失败：

非 0

同时输出：

Error Message

例如：

UNSUPPORTED_DEMO_VERSION

CORRUPTED_DEMO

UNKNOWN_MAP

---

# 61. 错误处理

软件必须正确处理：

Demo 损坏

Demo 版本不支持

地图不支持

地图资源缺失

Parser 崩溃

Replay Cache 损坏

不能：

直接崩溃。

应该显示：

Unable to parse this demo.

Reason:

Unsupported Demo Version

---

# 62. 软件设置

未来 Settings：

Camera Speed

Mouse Sensitivity

Player Size

Player Name Size

CT Color

T Color

Map Brightness

Replay Cache

CS2 Installation Path

---

# 63. GitHub 发布

项目最终准备：

GitHub Public Repository

推荐：

MIT License

如果决定使用其它 License：

需要确认所有依赖兼容。

仓库包含：

Source Code

Documentation

Build Instructions

Contributing

Issues

Roadmap

---

# 64. GitHub README

README 最终应该展示：

项目截图

Demo GIF

功能说明

安装说明

Build 方法

Roadmap

Contributing

Disclaimer

---

# 65. Steam 发布

软件计划：

免费发布。

Steam 版本主要作用：

方便安装

自动更新

社区曝光

GitHub：

保持完整源码

并提供 Releases。

Steam 和 GitHub 版本功能应该基本一致。

---

# 66. 产品边界

非常重要。

项目定位：

Demo Replay

Tactical Analysis

Offline Visualization

不开发：

Live Cheat

Wallhack

Aimbot

Realtime Radar Cheat

Game Memory Reader

DLL Injection

Kernel Driver

VAC Bypass

任何功能均基于：

已经存在的 Demo 文件。

---

# 67. UI 风格

推荐：

简洁

现代

深色 UI

3D Scene 作为重点。

不要做：

复杂游戏菜单。

整体类似：

专业分析软件

+

电竞工具。

---

# 68. 软件首页

大致：

CS2 Tactical Replay

Drop Demo Here

[ Open Demo ]

Recent Replays

Mirage

13-8

Yesterday

Nuke

16-14

2026-09-20

---

# 69. Replay Screen

顶部：

Map

Round

Score

Timer

左边：

Rounds

Players

Events

右上：

Camera Mode

底部：

Timeline

Playback Controls

---

# 70. 用户体验原则

用户不应该需要：

安装 Python

安装 Go

配置 Environment

手动运行 Parser

手动转换 Demo

最终发布版：

下载软件

打开

拖 Demo

播放。

---

# 71. 开发原则

项目开发过程中遵循：

第一：

先完成数据闭环。

Demo

↓

Parser

↓

Replay

↓

Player Movement

第二：

再完成地图。

第三：

再完成 UI。

第四：

再添加事件。

不要第一阶段花大量时间：

UI 动画

Shader

漂亮特效

Steam API

---

# 72. 推荐开发顺序

Phase 1

创建 Godot 项目。

显示一个：

Plane

Camera

Player Capsule。

---

Phase 2

写 Mock Replay。

不使用 Demo。

创建：

mock_replay.json

让 Player：

从 A

移动到 B。

确认：

Timeline

Interpolation

Renderer

正确。

---

Phase 3

实现 ReplayClock。

支持：

Play

Pause

Seek

Speed。

---

Phase 4

实现 ReplayLoader。

加载：

JSON Replay。

---

Phase 5

建立 Go Parser。

使用真实 Demo。

先只获取：

Player

Position

Yaw

Alive

Team。

---

Phase 6

输出：

Replay JSON。

---

Phase 7

Godot 加载真实 Replay。

此时地图可以仍然是：

Plane。

验证：

10 Player

Movement。

---

Phase 8

加载：

de_mirage

简化三维地图。

---

Phase 9

解决：

CS2 Coordinate

→

Godot Coordinate。

---

Phase 10

完成：

Round System

Timeline

Player Names

Team Colors。

---

Phase 11

加入：

Kills

Bomb

Grenades。

---

Phase 12

打包：

Windows Release。

---

# 73. Codex 开发要求

Codex 在实现本项目时：

不要一次性实现所有功能。

必须按照：

小模块

可运行

可测试

逐阶段

开发。

每完成一个阶段：

项目必须能够运行。

禁止：

同时生成几十个未经验证的大型系统。

---

# 74. Codex 第一任务

Codex 第一次开始项目时：

只完成：

项目骨架。

包括：

Godot Project

Go Parser Project

shared replay format

docs

目录结构。

不要立即实现完整 Demo Parser。

---

# 75. Codex 第二任务

实现：

Mock Replay System。

创建：

mock_replay.json

包含：

2 个玩家。

Player A：

从：

0,0,0

移动到：

10,0,10

Player B：

从：

5,0,5

移动到：

-10,0,-10

Godot：

读取 JSON。

显示两个 Capsule。

Timeline：

播放。

---

# 76. Codex 第三任务

实现：

ReplayClock

以及：

Interpolation。

验收：

玩家在：

0.5x

1x

2x

下移动正确。

Seek 后：

玩家立即出现在正确位置。

---

# 77. Codex 第四任务

实现：

Go Parser Prototype。

输入：

CS2 Demo。

输出：

metadata.json

只包含：

Map

Players

Duration

如果成功：

再增加 Player Position。

---

# 78. Codex 第五任务

Parser 输出：

真实 PlayerTrack。

Godot 播放。

此时项目最关键技术链完成：

Demo

↓

Parser

↓

Replay

↓

Godot

↓

3D Player Movement

---

# 79. 软件架构要求

模块之间必须尽量解耦。

ReplayController

不应该知道：

Demo Protocol。

Parser

不应该知道：

Godot Scene。

MapManager

不应该控制：

Timeline。

Timeline

不应该直接操作：

Player Mesh。

正确关系：

ReplayClock

↓

ReplayController

↓

PlayerController

---

# 80. 数据层与渲染层分离

例如：

PlayerReplayState

纯数据：

Position

Rotation

Health

Alive

Weapon

PlayerRenderer

负责：

Mesh

Label

Material

Animation

不要把两个东西混在一起。

---

# 81. Map API

建议：

MapManager.LoadMap(mapName)

例如：

MapManager.LoadMap("de_mirage")

加载：

maps/de_mirage/map.glb

同时获取：

MapConfig

例如：

{

    "scale": 0.01,

    "offset": [0, 0, 0],

    "rotation": 0

}

方便处理不同地图坐标。

---

# 82. Replay Controller API

推荐：

LoadReplay(path)

Play()

Pause()

Seek(seconds)

SetSpeed(speed)

GetCurrentTime()

GetDuration()

GetCurrentRound()

---

# 83. Event API

EventManager：

GetEvents(startTime, endTime)

GetEventsByType(type)

例如：

GetEventsByType(KILL)

---

# 84. Replay Version

Replay Format 必须包含：

version

例如：

"version": 1

因为未来格式会升级。

Loader 必须检查：

Replay Version。

未来：

Version 2

可以加入：

Weapon

Economy

新的字段。

---

# 85. 后向兼容

不要假设 Replay 文件永远只有一个版本。

使用：

ReplayVersion

未来可以：

ReplayV1Loader

ReplayV2Loader

---

# 86. Logging

应用必须拥有统一 Logging。

例如：

[INFO]

Replay loaded.

[INFO]

Map loaded: de_mirage

[ERROR]

Parser failed.

日志位置：

AppData/Local/CS2TacticalReplay/logs/

方便 GitHub Issue 调试。

---

# 87. Debug Mode

开发环境支持：

Debug Overlay。

显示：

FPS

Replay Time

Current Round

Player Count

Loaded Track Frames

Camera Position

这样方便开发地图坐标系统。

---

# 88. 测试 Demo

开发阶段准备：

test_data/

不要提交：

具有版权风险或不允许公开分发的 Demo。

可以：

开发者本机保存。

GitHub 只保存：

mock replay。

---

# 89. 自动测试

Parser 可以添加：

Unit Tests。

测试：

Replay Metadata

Player Count

Round Count

Event Count

Godot 部分优先保证：

Replay Format Parser

Interpolation

Timeline

这些核心逻辑可测试。

---

# 90. 第一版本产品目标

第一版本不是：

“完整 CS2 Demo 平替。”

第一版本唯一核心卖点：

“把 CS2 Demo 转换成三维俯视战术回放。”

只要做到：

地图

玩家

移动

方向

时间轴

Round

基础事件

就已经具有产品价值。

---

# 91. 项目未来价值

以后可以发展为：

个人玩家复盘工具

战队教练工具

比赛分析软件

电竞内容创作工具

Demo Visualization

Replay Director

战术视频生成器

---

# 92. AI 功能

未来可以考虑：

AI Replay Analysis

例如用户问：

为什么这一局 A Site 进攻失败？

系统分析：

进入时间

Smoke

Flash

Player Spacing

Entry

Trade

Rotation

然后定位：

关键时间点。

但：

AI 不属于 MVP。

---

# 93. 最终产品愿景

最终产品应该允许用户：

打开任何 CS2 Demo

↓

选择 Round

↓

看到双方所有玩家

↓

自由观察整个地图

↓

观察战术执行

↓

查看关键事件

↓

复盘比赛

↓

生成战术演示

甚至：

自动生成比赛战术视频。

---

# 94. Codex 最重要的开发原则

Codex 阅读本文件后：

第一目标不是：

“把所有功能全部写完。”

第一目标是：

完成最小闭环：

Demo Data

↓

Replay Data

↓

3D Visualization

然后逐步扩展。

在任何阶段：

可运行

优先于：

功能数量。

架构清晰

优先于：

复杂功能。

数据正确

优先于：

视觉效果。

---

# 95. Definition of Done — MVP

MVP 只有满足以下条件才算完成：

程序可以在 Windows 启动。

可以选择：

.dem

Parser 可以成功解析。

软件识别：

de_mirage。

加载：

Mirage 三维简化地图。

显示：

10 Player。

玩家：

Team 正确。

Position 正确。

Z Height 正确。

Direction 基本正确。

Timeline：

可以播放。

可以暂停。

可以 Seek。

播放过程中：

Player Position 正确插值。

软件不需要：

CS2 正在运行。

软件不读取：

CS2 Memory。

所有内容来自：

Demo。

满足以上内容：

MVP 完成。

---

# 96. Definition of Done — V0.1

V0.1 应额外满足：

Round Navigation

Player Names

Alive / Dead

Playback Speed

Kills

Bomb

基础 Grenades

Camera Presets

Replay Cache

错误提示

Windows Build

基本设置

可以给普通用户下载使用。

---

# 97. 当前最高优先级

当前不要考虑：

AI

Steam API

Video Export

真实 Smoke Shader

高质量人物模型

完整所有地图

账号系统

云端

重点：

1.

Replay Format

2.

Mock Player Playback

3.

Demo Parser

4.

Coordinate Mapping

5.

Mirage

6.

Timeline

完成以后再增加其它功能。

---

# 98. 最终技术路线

推荐：

Godot 4

+

C#

+

Go Parser

+

demoinfocs-golang

+

Custom Replay Format

+

Source 2 Map Conversion

整个软件完全本地运行。

不需要服务器。

不需要账号。

不需要联网。

---

# 99. 项目一句话说明

CS2 Tactical Replay Viewer 是一个开源、免费的 Counter-Strike 2 Demo 三维战术回放软件，可以将 `.dem` 比赛录像转换为具有时间轴、玩家位置、投掷物和战术信息的三维俯视回放。

---

# 100. 给 Codex 的启动指令

如果 Codex 正在阅读本文件：

请不要立即实现完整软件。

首先创建符合本文档要求的项目骨架。

第一阶段只实现：

Godot Application

+

ReplayClock

+

ReplayLoader

+

Mock Replay

+

2 个三维 Player Capsule

+

Timeline Playback

保证项目可以运行。

完成第一阶段以后，再开始实现 Go Demo Parser。

整个项目始终保持：

可编译

可运行

模块化

易于 Debug

不要为了未来功能过早引入复杂架构。
