# 协议保证、模拟假设与平台限制

本文防止把模拟器的测试行为误认为真实 CRYSTAL 固件或机械保证。上游依据为已收入本仓库的 [`docs/PROTOCOL.md`](PROTOCOL.md)。

## 1. 按协议或既有固件记录实现

- 主服务和六个特征 UUID。
- 所有特征值固定为 2 字节、无符号、大端；base64 仅用于 Decaid 桥日志对照。
- 正常客户端使用 Write With Response；ATT 写响应不是机械动作完成应答。
- `MT_RPM`、`XD_RPM`、`TF_ANGLE` 的有效范围，以及 `BOOT_SIGN` 的已定义命令 1–5。
- 研磨度需要先写 `TF_ANGLE`，再写 `BOOT_SIGN=5`；两步不是事务。
- `BOOT_SIGN=4` 是停止命令；`MT_RPM=0` 不等价于停止。
- 正常通知按特征去重；相同写入不要求产生通知。
- 错误长度写入保留当前值且不通知；越界写入忽略、不回写、不通知。
- 真机冷启动上电后 `SERVO_ANGLE=830`（设备方确认）；模拟器把它作为默认初值。
- `BOOT_SIGN=1` 的正常在线停止只有 `BOOT_SIGN=4`；`power off/on` 是独立的电源路径。
- 不设置加密 GATT 访问要求，不增加应用层鉴权。
- 插件必需/可选订阅语义属于被测客户端；模拟器通过布局场景构造相应成功或失败条件。

## 2. 明确的 Simulation Assumption

以下行为是为了可重复测试而选定的，不是上游协议对真机的保证：

| 模拟行为 | 默认选择 |
|---|---|
| 上电初值 | `SYS=0`、`SERVO=830`、`TF=0`、`MT=0`、`XD=0`、`BOOT=0`；其中 `SERVO=830` 是设备方确认真机值，其余 0 是与观察一致模拟器默认值 |
| 手动启动 | 立即进入 `SYS=1`，直到收到停止 |
| 定时 / 智能启动 | 立即进入 `SYS=1`，默认 5 秒自动回到 `0` |
| 重复启动 | 重新选择 Run Mode 并取代旧计时器 |
| 停止空闲设备 | 写成功、状态不变、不通知 |
| Apply | 捕获命令到达时的目标；默认立即更新当前值；写 `5` 时 `SYS=1`，无活动 Run 时由 Apply Auto-Idle Timer 5 秒后回 `0`（模拟器兜底，不是真机计时保证）；有活动 Run 时不启动该计时 |
| Apply 交错 | 新 Apply 取代旧 Apply 并重启其 Auto-Idle Timer；单独修改目标不改变已捕获值 |
| 停止与 Apply | 停止 Run 不取消 Apply；停止/结束路径同时取消 Auto-Idle Timer |
| 研磨中修改参数 | 寄存器立即接受；不模拟物理效果何时生效 |
| `BOOT_SIGN` 读取 | 保留最后已定义命令，保留值不替换它，也不是执行状态 |
| `BOOT_SIGN` 通知 | 正常流程不发送；Test Override 可强制 |
| 保留命令及状态/当前值写入 | ATT 写成功、忽略动作并记录违规，不污染模型，也不触发进程退出故障 |
| 通知去重基线 | quiet Test Override 推进基线但不发通知；写回先前已通知的值仍可产生通知 |
| 新会话首次同步 | 清空去重基线，下一次状态同步可发布未变值；不会主动重放全部寄存器 |
| Observed Session End | 可配置 `pause / continue / stop`，默认 `pause` |
| 持久化 | 不保存运行状态，重启由默认文件或场景决定 |
| Device Power off | 取消 Run/Apply/Auto-Idle Timer、quiet 进入 `SYS=0`、保留其他设置、停止广播并移除 GATT；不是 Observed Session End，也不保证真实 Link Loss |
| Device Power on | 新建服务对象、默认恢复广播、进入空闲；易失寄存器 `MT/XD/TF/BOOT` 归 0，仅保留 `SERVO_ANGLE`，不恢复旧 Run/Apply/计时器 |
| Web 正常写 | 与 BLE 共用正常写模型路径；`writeError` 保留，ATT-only 的 `readError` / `responseDelay` 不伪造到 HTTP |
| Web “设置并 Apply” | 两次有序写而非事务；Apply 失败保留已经改变的 TF 值 |
| Web 关机控制 | 除开机外统一 HTTP 409；CLI 显式 Test Override 仍是特殊测试通道 |

`SYS_STATE` 的未定义值只能由异常初值或 Test Override 构造。它们不表示安全空闲。

## 3. CoreBluetooth 与无线电限制

### 连接和断连不可等同

macOS `CBPeripheralManager` 没有单个 central 的 connect/disconnect 回调，也没有主动断开指定 central 的 API。

- 任一特征的订阅都可开始或恢复推断会话；协议必需/可选语义仍由客户端决定。
- 订阅消失后没有剩余订阅者，只能形成 **Observed Session End** 推断。
- 日志中的 `linkLossConfirmed=false` 是有意为之。
- `session-end` 是模型控制命令，不关闭 BLE 链路。
- Web/CLI 的 Disconnect Request 使用停止广播及本模拟器 GATT 清理等 best-effort 手段，不是公开的单 central force-disconnect API。主动请求、取消订阅和服务移除都不能证明对端已经断连。
- Web 设备活动由 **Observation Record** 组成，来自订阅、取消订阅、读和写回调，不是完整实时连接清单，也不保证提供手机名称。记录 ID 与 central UUID 分离；同一 central 可以有多条历史记录，浏览器别名仍跟随 central UUID。
- 普通取消订阅、Observed Session End 和 Disconnect Request 不自动结束观察记录。只有用户根据手机或平板端情况执行“人工确认已断开”才把记录归为灰色历史；这是用户输入，不是系统 Link Loss 回调。
- 人工断开后，同一 central 再次出现活动会新建一条观察记录，后续活动归入新记录；旧记录保持灰色或隐藏。多个 central 可以同时展示，不新增连接数量限制、读写仲裁或 Run/Apply/Disconnect Policy 改动。
- 只有人工确认断开的记录可以移出普通视图。移出和恢复是同进程共享展示状态，通过 snapshot/SSE 同步到所有浏览器；不删除 JSONL、原始事件或别名，不操作 BLE 链路，也不承诺进程重启后持久保存。
- 真实 Link Loss 由手机或平板端断开、关闭蓝牙或进程退出制造。
- 进程退出后的重启使用新初值，不用它验证“同一固件持续运行并重连”。

### 订阅和 GATT 布局

系统不接受应用层拒绝单次订阅的回调结果。订阅失败只能通过预先移除 Notify 属性或特征实现。布局变化推荐重启，避免 central 缓存。

### 广播与连接参数

- 模拟器采用名称优先广播，只向系统提交完整设备名 `CRYSTAL-XXXX`，不在广播中附加 128 位主服务 UUID。这是 **Simulation Assumption / 平台适配**：完整名称加 128 位 UUID 超过传统 31 字节广播数据的可用空间，而且 Decaid 只按名称前缀发现设备。
- 连接后仍发布完整主服务和六个特征；客户端必须通过服务发现核对主服务 UUID，不能把名称当作设备身份认证。
- CoreBluetooth 不提供本协议所需的 100–200 ms 广播间隔精确控制，也不保证指定连接 interval/latency/supervision timeout。
- 本项目不伪造固定 ATT Handle，不验证空中抓包，也不替代蓝牙协议分析仪。

### 通知语义

`notification submitted to CoreBluetooth` 只表示 `updateValue` 接受提交。队列背压、无订阅者、故障丢弃和实际远端接收是不同事件；远端收到与否仍需手机或平板验证。

### Web 事件与安全边界

- Web 与 CLI 在同一进程、同一 MainActor 上操作同一模型，不是另一个模拟设备。
- 最近 500 条 SSE 事件是易失监控视图；JSONL 是持久记录。慢客户端会被关闭并依赖重连 replay/resync，不逐条静默丢失。
- heartbeat 只维持 HTTP 事件流，不是 BLE 心跳、在线状态伪造或断连规避。
- 非 loopback 必须配置令牌，Host/Origin 校验和无 CORS 许可不能替代可信网络、操作系统权限与用户令牌保管。
- 网页没有模拟器进程退出按钮，但已启用的 `terminateProcess` 故障仍会退出进程。

## 4. 明确不覆盖

- 真实机械位置、刀盘 rpm、下豆物理单位和称重/自动触发条件。
- 多广播实例、多 central 并发仲裁。
- 随机故障、自动保存运行状态、真实设备断链 watchdog 结论。
- Decaid HTTP/WebSocket 服务、插件首快照发布失败、宿主内部错误。
- Web 数据库、长期趋势图、任意路径场景加载、多实例管理或通用多浏览器协同编辑。观察记录的移出/恢复是唯一新增的共享展示操作，不等同于通用协同编辑。
- 紧急停止或任何人身安全联锁。

**BLE STOP 不是紧急停止。模拟器不能证明真实磨豆机在断连、异常或断电时的行为。**

此前真机日志中的 macOS `bluetoothd` “unused” 主动断链仍是独立未解决问题。Web 监控与控制不会用心跳、自动重连或伪造在线状态掩盖它，也不宣称已经修复。
