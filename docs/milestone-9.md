# M9 二进制回放与按时间分块轨迹

版本：App / Parser 0.9.0-dev / 0.9.0；Binary Container 1；Replay 事实格式继续 V1/V2；Map Converter 0.8.1 / Classifier 2 不变。日期：2026-09-30。

## 本轮结果

新解析的 Demo 默认缓存为 `replay.replay`。玩家轨迹按 10 秒分块，独立 zlib 压缩，坐标量化到 1/32 Source unit 并进行整数差分编码；文件索引提供每块时间、偏移、大小和校验值。首次进入只解码第一个轨迹窗口，随机 Seek 直接读取目标窗口，LRU 最多保留三个窗口。

坐标始终为原始 CS2 XYZ，显示转换仍由 MapTransform 统一负责。全局相机范围通过文件中的真实轨迹 bounds 提供，避免只用当前十秒范围取景。ReplayClock、玩家离散状态、队伍换边和时间轴语义保留。事件分为 Events、Damage、Bomb、Projectiles、Rounds 等独立压缩块；同 tick 的原始事件顺序通过 `_order` 保留。

CLI 根据输出后缀选择格式：`.replay` 为新容器，`.json` 继续输出开发格式；`--v1` 仍有效。Debug 的 Open Replay File 和 Viewer 拖入支持两种格式。普通用户仍直接打开 `.dem`。

## 真实样本与性能

本机同一 Ancient Demo：32 分 56 秒、10 名玩家、314,497 个轨迹帧、3,500 个事件。JSON 和二进制均由同一 Parser 从同一源重新生成。

| 指标 | JSON | Binary |
|---|---:|---:|
| 文件字节数 | 59,786,325 | 1,793,205 |
| 单次读取、验证与解码 | 3,812.666 ms | 251.519 ms |
| Godot 静态内存增量 | 328,320,272 bytes | 22,324,936 bytes |
| Godot 静态内存峰值 | 1,294,546,522 bytes | 75,785,652 bytes |
| 初始常驻轨迹帧 | 314,497 | 974 |

文件约缩小 97%；该次读取约快 15 倍；静态内存增量约降低 93%。这不是整个 Open Demo 端到端时间，也不包含首次 Parser/地图准备。两种格式分别在独立 Godot 进程测量，未清空 Windows 文件缓存；内存数字是 Godot 分配器统计，不是操作系统进程工作集。不能据单机样本承诺所有电脑秒开。

198 个轨迹块中执行 167 个含边界、前后跳转和末帧的取样，最终复测最慢单次块读取/解码 5.928 ms，最多保留三个块，最终常驻 4,870 个轨迹帧。Mirage 真实伤害样本也完成相同跨格式检查，最慢 3.169 ms。Seek 测量不包含 UI/绘制耗时。

## 测试与视觉检查

- Go 全套 `go test ./...` 与 `go vet ./...` 通过。新增容器头、压缩校验、连续索引、边界帧、量化误差及写入失败测试。
- Ancient 跨格式 115,198 项检查通过：元数据、玩家、所有事件属性、原始事件顺序，以及随机时刻的位置、朝向和精确离散状态。
- Mirage 跨格式 66,797 项检查通过，覆盖真实伤害事件。
- 损坏文件/缓存 13 项通过：未知版本、截断、超大长度、重叠块、解压上限、校验失败、未访问块的损坏在 Seek 时被拒绝、缓存 hash 触发重建。
- 真实场景 241 项通过：逐事件后的 Smoke/Fire/Flash/Bomb/Status/Kill Feed 状态与 JSON 相同，连续播放跨越块边界，损坏时暂停并隐藏过期状态，再加载 Mock 正常。
- 正式 Windows EXE 11 项通过：新 Demo 创建二进制、第二次打开命中缓存、损坏后自动重建、旧 Parser 0.6.0 JSON 缓存在原 Demo 缺失时仍能打开。
- Mock 基础 84 项通过。已查看 Ancient 二进制回放和正式 EXE Dust2 截图，播放器、玩家、时间轴和地图剖切显示正常。密集姓名重叠仍属于已有 M11 待处理项。

证据位于本机 `artifacts/m9/`：两个 benchmark JSON、consistency 日志/报告、corruption-report.json、scene-report.json、formal/report.json、build.log、binary-scene.png 和 formal/formal-replay.png。真实样本、缓存和截图继续排除在 Git 源码之外。

## 缓存兼容与失败处理

新 manifest 记录文件名和独立 storage_version；旧 manifest 默认使用 replay.json。旧 Parser 0.6.0 的 JSON 事实仍兼容，不要求旧 Replay 立即失效。损坏缓存且源 Demo 存在时自动重建；源文件缺失且没有有效缓存时显示错误。map cache 不因本次 Replay 更新而失效。

块损坏会暂停播放并显示错误，不继续渲染上一窗口的玩家位置和战斗效果。文件头和索引在初次加载时验证；未访问轨迹块延迟验证；完整缓存 hash 在缓存复用时检查。SHA-256 用于损坏检测，不用于验证文件来源可信性。

## 明确边界和后续工作

本轮完成 M9 的二进制存储和轨迹按需加载核心，尚非所有数据的完整流式实现：

1. 事件、伤害、Bomb 与投掷物仍整体读取，以保留全局 Timeline 和已有状态重建逻辑；只有玩家轨迹受三窗口上限约束。超大事件/投掷物数据仍需后续分块。
2. Rounds 块当前为空，V2 尚未记录可靠 Round 事实；没有根据 Bomb 或时间猜测回合。事件索引到压缩家族块，还没有逐事件 offset 索引。
3. 已增加下一轨迹窗口的后台预取；冷跳转或预取尚未完成时仍同步读取。慢磁盘或超大玩家数量仍可能出现停顿，不是全异步 Seek。
4. Parser 仍先收集整场事实再写文件，尚未优化解析器本身的峰值内存。单块大小上限为 32 MiB，超过会明确失败，保留原有目标输出。
5. 坐标量化和 float32 yaw 引入微小数值误差；不能称为逐字节无损编码。本轮真实样本位置误差在 0.04 Source units 以内，离散状态保持一致。

本轮停在 M9，不进入 M10 高级分析。本地完成开发与 Windows 构建；未自动推送到公开 GitHub 仓库。

## 复现与主要文件

`tools/test-milestone9.ps1 -Demo <本地.dem> -Visual` 编译 Parser、生成两种格式、运行一致性/损坏测试、分别测量读取，再做图形场景测试。样本默认不随仓库分发。地图资产通过既有本地缓存提供；可用 `CS2_MAP_CACHE_ROOT` 指向隔离目录。

正式 EXE 测试使用 `app/tests/milestone_9_export_tests.gd`，设置 `M9_PROJECT`、全新的 `CS2_REPLAY_DATA_ROOT` 和已有 prepared map cache。完整构建命令为 `tools/build_windows.ps1`。

格式规范见 `shared/replay-format/README-binary.md`。主要实现为 `parser/internal/serialization/binary.go`、`app/scripts/core/BinaryReplayStream.gd`，以及 ReplayLoader、ReplayController、ReplayCache、DemoOpenService 和 MapTransform 的兼容接入。

## 续开发：轨迹后台预取

增加单个后台工作线程，使用独立文件句柄读取、校验和解码下一段 10 秒轨迹。主线程只接收已完成结果，LRU 仍最多三个窗口；工作线程额外最多保留一个窗口。快速跳转后不相关结果丢弃，结束回放时等待线程退出，避免悬空调用。预取到损坏的未来窗口不会影响当前正常画面，真正访问损坏窗口时沿用暂停与隐藏旧状态的处理。

新增 55 项预取回归检查通过，包含六次连续窗口命中、快速前后跳转、损坏预取延迟报错，以及五次立即关闭时读取对象释放。六次已预取边界调用最大 1.453 ms（包含调度下一次预取，不含绘制），只代表本机样本。Ancient 115,198 项、Mirage 66,797 项一致性和 13 项损坏/缓存检查再次通过；随机冷跳转最大分别 10.097 / 4.830 ms，不能据此声称所有跳转都加速。证据为 `artifacts/m9/prefetch-*.log` 和 `prefetch-report.json`。

复现脚本已加入预取测试，并将 Godot 日志中的运行时错误计为失败，避免仅依赖进程退出码漏报。事件和投掷物仍整体加载，完整按需加载留在 M9 后续处理；文件格式及原有 JSON 缓存兼容不变。

本次预取版本追加验收：真实场景 241 项、重新构建的 Windows EXE 11 项全部通过，无脚本运行时错误。正式导出不包含测试脚本，使用外部 `app/tests/milestone_9_export_tests.gd` 的绝对路径启动验收。日志为 `prefetch-scene.log`、`prefetch-build.log`、`prefetch-formal.log`，隔离缓存报告位于 `artifacts/m9/formal-prefetch/report.json`。
