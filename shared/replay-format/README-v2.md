# Replay Format V2

Milestone 7 保持此格式不变，没有 V3。地图发现、准备、缓存、坐标转换与透明图标均属于 Viewer / Map 工具。BOMB_CARRIER 仍由既有 Bomb 事件推导，视觉只显示红名；HE Hit / Burning 继续依据真实正 PlayerHurt，不添加距离推测伤害。地图模型不会嵌入 Replay。

V2 保留 [V1](README.md) 的 metadata、players、tracks 及所有时间、身份、坐标和插值语义，增加 `events` 与 `projectiles` 两个必需数组（允许为空）。正式结构见 [JSON Schema](replay-v2.schema.json)。Parser 默认输出 V2；`--v1` 输出原 V1。Viewer 同时读取两种版本。

```text
ReplayV2
  version: 2
  metadata: map, duration, source_tick_rate, sample_rate,
            coordinate_system="cs2_raw", source_start_tick, source_end_tick
  players[]: id, steam_id, name, team
  tracks[]: player_id, frames[{time,tick,position,yaw,health,alive,team,available}]
  events[]: ReplayEvent
  projectiles[]: ProjectileReplayState
```

所有位置及射击方向均为 **CS2 原始世界坐标系**；Parser 不进行 Godot 坐标转换。时间单位为秒，`time = (tick - source_start_tick) / source_tick_rate`。玩家/弹体常规采样为 16 Hz；事件保留原始 tick，弹体额外保留投掷、反弹及结束节点。

## 统一事件

公共字段：`id: string`、`type: string`、`time: number`、`tick: integer`、`actor_player_id: string`、`actor_team: T | CT | UNKNOWN`。

`actor_player_id` 对 Utility 表示 thrower，对 Shot 表示 shooter，对 Kill 表示 killer。Utility 的 `actor_team` 固定为**投掷时**阵营；Shot/Kill 固定为**事件发生时**阵营。禁止依据 roster 的最终 team 重新着色。无法可靠确认 actor 时使用空字符串和 UNKNOWN，不虚构归属。

事件按 `time` 非递减排序；同 tick 可有多个不同 ID。事件与弹体 ID 全局不重复。缺失的可选引用不输出；存在的引用必须有效。

| type | 专有字段 / 含义 |
|---|---|
| smoke | `position` 为爆点，`throw_time`、`activate_time`、`expire_time`、`projectile_id`、`grenade_type="smoke"`、`end_reason` |
| fire | 同上，`grenade_type` 为 molotov/incendiary（未关联时 fire）；`patches[]` 保存实际 flame positions 和各自生灭时间 |
| he | 爆点与上述时间字段；`expire_time` 是 Viewer 战术脉冲结束时间（爆炸后 0.35 秒，上限为 replay duration），不表示游戏伤害持续 |
| flash | 同上，脉冲 0.25 秒；可有 `affected_players[{player_id,flash_duration,flash_amount?}]` |
| shot | `origin`、单位向量 `direction`、`direction_source`；可靠命中点可选 `impact`。当前来源为 `fire_bullets_angles`，未提供 impact |
| kill | `victim_player_id`、`victim_team`、`weapon`、`headshot`；可选 `assister_player_id` |

Utility 满足 `throw_time <= time == activate_time <= expire_time <= duration`。可见区间均为左闭右开 `[activate_time, expire_time)`。`patches[{position,activate_time,expire_time}]` 的区间必须包含于所属 fire 区间。`flash_amount` 若存在，为 0–1；未知时省略。`flash_duration` 为源数据提供的致盲持续时间，当前 89 条 affected-player 记录。

当前 Go serializer 会给非 Utility 事件输出值为 0 的三个 Utility 时间字段，并给非 Kill 事件输出 `headshot:false`；这些字段仅在对应类型中有意义，消费者不得据此推断其他事件类型。

## 弹体

```text
{
  id, type: smoke | molotov | incendiary | he | flash,
  actor_player_id, actor_team,
  throw_time, end_time, end_reason,
  frames: [{time,tick,position:{x,y,z}}]
}
```

frames 非空、time 严格递增，位于 `[throw_time,end_time]`；end_time 以实际爆炸/落地燃烧/实体结束为界。仅在 `[throw_time,end_time)` 显示弹体及已经飞过的路径。轨迹位置通过同一时间下相邻原始位置插值，之后交给 MapTransform。

## 原始数据与视觉近似的边界

- Smoke：检测 `m_bDidSmokeEffect` 和 `m_vSmokeDetonationPos`，以观察到实体更新的 source tick 为激活 tick；实体消失/清理/EOF 结束。嵌入实体的 smoke effect tick 使用不同基准，不能直接当 replay tick。
- Fire：InfernoStart/Expired + 实际 burning flame patches；16 Hz 观察 patch 生灭。结束以最后一个 burning patch 熄灭为准，避免把仍存在的 Inferno 实体误当持续燃烧。
- HE：实际 explode effect tick/position 状态；Flash：demoinfocs Source 2 合成的真实 FlashExplode 事件。
- Shot：原始 `CMsgTEFireBullets` 的 pawn handle、origin、pitch/yaw；不以 WeaponFire 回调数冒充实际枪线数。角度转单位方向是源坐标系内的数学计算。
- Kill：真实 Kill 事件。测试 Demo 含 warmup，因此整场 Kill 数包括 warmup。
- Smoke 半径 145、Fire patch 半径 55 Source 单位是战术视觉近似；不声称复原烟雾体素或火焰碰撞覆盖。
- 射击线寿命 0.12 秒、无 impact 时长度 1200 Source 单位，由 TeamVisualConfig 决定。不是弹道物理或击中位置推断。

## M5 兼容扩展：Bomb

仍为 `version:2`，Player Track、时间基准及既有事件字段不变。增加 `bomb_pickup`、`bomb_drop`、`bomb_plant`、`bomb_defuse`、`bomb_explode`，以及由真实 RoundStart 生成的 `bomb_reset`。公共 `actor_player_id` / `actor_team` 延续既有约定，未知 actor 为空 / UNKNOWN；可靠位置使用可选 `position`，不把缺失位置当成真实原点。

`bomb_drop.position_frames` 可选，结构为 `{time,tick,position}` 的数组，记录炸弹落地运动的 16 Hz 原始坐标。time 严格递增且不早于 drop；Viewer 插值只作用于这些位置。所有坐标仍通过 MapTransform 转换。

Bomb 状态根据目标时间之前最后一条 Bomb 事件重建；同一 tick 按文件顺序处理。真实 round reset 清除前一回合状态，避免上一局的 Planted / Defused 延续到下一局。计时仅在 plant 后、下次 reset 前存在实际 defuse / explode 事件时计算，显示“距记录中的拆除/爆炸还有多少秒”，不是假设 40 秒游戏规则。未知结束时间显示 unavailable。

当前公开样本：pickup 32、drop 21、plant 11、defuse 5、explode 0、reset 21。独立解析回合结束原因也未出现 TargetBombed，未捏造爆炸。旧 V2 不含 Bomb 时状态为 Unknown；V1 同样保持基础播放。

## 分层与验证（实现）

Go demoinfocs adapter → Replay domain structs → validator → Serializer → JSON。
Godot JSON boundary → base/V2 validator → ReplayEvent/ProjectileReplayState → ReplayEventIndex → renderers。

Schema 负责形状；Go 与 Godot 运行时另行验证引用、ID 唯一、时间顺序/边界、tick 一致、有限坐标、单位方向和 patch 区间。渲染层不访问 JSON 节点，未来可替换序列化格式。

## M6 兼容扩展：Player Hurt

仍使用 version 2，既有 V1 tracks、事件时间和身份语义不变。新增 type `player_hurt`：

```json
{
  "id": "hurt-example", "type": "player_hurt", "time": 282.28125, "tick": 18066,
  "actor_player_id": "steam:76561198000000001", "actor_team": "CT",
  "victim_player_id": "steam:76561198000000002", "victim_team": "T",
  "damage": 26, "health_remaining": 74, "damage_source": "hegrenade"
}
```

此处 id 是示意值；其余为真实样本的一条源事件。沿用公共 actor 字段表示 attacker，不另建冲突的 attacker 字段。双方阵营为事件发生时阵营；受害者必须引用有效玩家。damage/health_remaining 为非负值，damage_source 为非空源名称。原生 demoinfocs PlayerHurt 提供事实，WeaponString 仅去空白并转小写，缺失为 unknown。不会通过爆炸距离推断伤害。

Go serializer 会给其他事件输出 damage:0 和 health_remaining:0，这两个字段只有 player_hurt 类型有意义；无伤害的旧 V2 仍可加载。Parser 不保存 UI Status。Viewer 将正 HE 伤害解释为 0.8 秒 HE_HIT，火伤解释为 0.75 秒 BURNING；重复伤害延长区间，全部依据 ReplayClock。IN_SMOKE 只属于战术体积近似，既不是伤害事件，也不是引擎 occupancy。

新公开 Mirage 样本有 264 条 PlayerHurt（15 HE、38 inferno），旧 Ancient 样本为零；不能将一个样本的数量作为格式约束。完整来源、校验及限制见 [M6 报告](../../docs/milestone-6.md)。
