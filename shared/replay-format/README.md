# Replay Format V1

V1 由独立 Go Parser 输出、Godot 读取。Mock 与真实数据使用相同接口。机器可读定义为 `replay-v1.schema.json`，可直接加载的最小示例为 `example.replay.json`。

## 数据结构

```json
{
  "version": 1,
  "metadata": {
    "map": "de_ancient",
    "duration": 0.0625,
    "source_tick_rate": 64,
    "sample_rate": 16,
    "coordinate_system": "cs2_raw",
    "source_start_tick": 100,
    "source_end_tick": 104
  },
  "players": [
    {"id": "steam:76561198000000000", "steam_id": "76561198000000000", "name": "Example", "team": "T"}
  ],
  "tracks": [
    {
      "player_id": "steam:76561198000000000",
      "frames": [
        {"time": 0, "tick": 100, "position": {"x": 100, "y": 200, "z": 30}, "yaw": 90, "health": 100, "alive": true, "team": "T", "available": true},
        {"time": 0.0625, "tick": 104, "position": {"x": 104, "y": 202, "z": 30}, "yaw": 92, "health": 100, "alive": true, "team": "T", "available": true}
      ]
    }
  ]
}
```

## 身份与状态

- 玩家 `id` 是稳定字符串，不依赖名字。已有 SteamID 使用 `steam:<SteamID64>`；缺少 SteamID 的实体使用本次解析唯一的 `local:<序号>`。
- `steam_id` 始终是字符串，缺失时为 `""`，避免 JSON / 客户端丢失 64 位整数精度。晚到的 SteamID 仅补充字段，不更改已分配 ID。
- `players.team` 是首次观察到的阵营；`frames.team` 是当前样本的 T / CT，处理比赛换边。每个玩家恰好对应一条轨迹，不限定人数。
- `health` 为非负整数；`alive` 为布尔值，直接来自玩家状态，不推导击杀事件。
- `available=false` 表示该时间没有有效的已连接 T/CT pawn。此时必须 `alive=false`，Viewer 隐藏模型；保留的位置不代表新的真实观测。
- 晚加入玩家在 0 秒添加不可用前缀，然后从首次观察开始采样；中间缺席时保留上一位置并标记不可用，不生成虚假移动。
- 当前实现以首次有效名字作为标签，没有逐帧改名字段。无 SteamID 的实体重建无法可靠判定是否同一人，会分配新本地 ID。

## 时间与 16 Hz 采样

- `time` 单位秒，`tick` 是源 Demo 的游戏 tick，不是 JSON 数组下标或 Parser 帧计数。
- `time = (tick - source_start_tick) / source_tick_rate`。时长为有效源 tick 范围之差除以源 tick rate；包括 Demo 中的热身及录制时间，不剔除回合间隔。
- `source_start_tick` 是收到有效 tick rate 后的首个非负源 tick；忽略 sign-on 的负 tick。`source_end_tick` 是最后有效 tick。
- Parser 固定 `sample_rate=16`，仅在跨过 1/16 秒门限后的首个可用源快照采样。64 tick 连续数据通常每 4 tick 一个样本。
- 不输出每个 Demo tick；源帧缺口不补造状态。为了覆盖完整时长，可额外输出末尾不足 1/16 秒的终点样本。晚加入的不可用前缀也是边界标记。
- 时间、tick 严格递增，每条轨迹包含 0 与 duration。源 tick 倒退或 tick rate 在中途变化目前返回明确错误。

## 坐标与 yaw

文件里保存原始 CS2 世界坐标，脚底位置，Z-up，原始游戏单位。`position` 必须是含有限数字 x / y / z 的对象；Parser 不平移、归一化、缩放或重排坐标。

JSON yaw 是 CS2 原始角度（度，可能为负值）；0° 朝 +X，90° 朝 +Y。Loader 只将度换成内存中的弧度；保留 CS2 坐标和朝向含义。

唯一转换点是 Viewer 的 `DebugMapTransform`：

```text
GodotX = CS2X * 0.01
GodotY = CS2Z * 0.01
GodotZ = -CS2Y * 0.01
GodotYaw = radians(CS2Yaw) - PI/2
```

不对玩家坐标施加自动偏移。测试 Plane 位置和摄像机取景根据转换后的有效轨迹边界调整；调试面板同时显示原始和转换坐标。

## 插值与校验

沿用 TrackSampler 的二分查找、Vector3.lerp、lerp_angle。health、alive、team、available 和 tick 使用左侧样本值，遇到下一帧的时间才切换。不可用状态、死亡/复活、换边、超过 0.25 秒的缺口、超过 256 原始单位的位移不跨帧插值；这是原型的明确保守策略。

Go 输出前与 Godot 加载时均检查版本、地图、时长、采样率、源 tick 范围、玩家、轨迹引用、唯一 ID、时间/tick 递增、tick-time 一致性、有限坐标/yaw、状态类型和首尾覆盖。JSON Schema 负责字段类型与必要字段；跨记录关系和排序由代码 Validator 检查。

## Mock 迁移

`app/data/mock_replay.json` 仍为 20 秒、Alpha 和 Bravo 两人，每人 321 帧（含首尾），16 Hz。合成数据也采用 cs2_raw 和相同字段，转回 Godot 后保留上一阶段的路径：

| 时间 | Alpha Godot 位置 | Bravo Godot 位置 |
|---|---|---|
| 0 s | (0,0,0) | (5,0,5) |
| 2 s | (2,0,-1.5) | (3.5,0,6) |
| 10 s | (8,0,-0.5) | (-5,0,2.5) |
| 20 s | (10,0,10) | (-10,0,-10) |

上一阶段实验性 `position: [x,y,z] / godot_y_up` 外部 JSON 不是本次正式 V1，不会被自动解释为原始 CS2 数据。
