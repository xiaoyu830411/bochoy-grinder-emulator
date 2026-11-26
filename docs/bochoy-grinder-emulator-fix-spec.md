# CRYSTAL 磨豆机模拟器：上电初值、SYS_STATE 与 Apply 自动回空闲修正规格

> 仓库：`xiaoyu830411/bochoy-grinder-emulator`
> 代码基线：`main` @ `099297e`（`1.0.0-beta.1`）
> 规格状态：已确认，待实施
> 规格修订日期：2026-11-26
> 目标发布：下一预发布 `1.0.0-beta.2` 候选；不得重写或移动 `v1.0.0-beta.1`
> 依据：设备方真机实测 + 设备方指定的模拟器规则
> 执行要求：实施时必须遵循仓库 `AGENTS.md` 的 Red–Green–Refactor；先写测试并实际观察因目标行为缺失而失败，再写最小实现达到 Green。

---

## 0. 本轮范围

本文件是实现规格，不是本轮代码变更。本轮只优化本规格，不修改 Swift、Web、测试、README、CHANGELOG 或其它文档，不 commit、不 push、不发布。

实施时，代码、测试、用户文档和领域词汇必须在同一变更中保持一致。本文第 8 节列出必须同步的位置；不得只改实现而让文档继续描述旧默认值或旧 `SYS_STATE` 含义。

---

## 1. 事实等级与领域术语

### 1.1 设备方确认事实

| 场景 | 真机行为 | 模拟器目标行为 |
|---|---|---|
| 冷上电后首次连接 | `SERVO_ANGLE=830`；`SYS/MT/XD/TF/BOOT=0` | 相同 |
| 写 `BOOT_SIGN=1` | `SYS_STATE=1`，停止前保持 | 正常在线控制中保持到写 `4` |
| 写 `BOOT_SIGN=2/3` | `SYS_STATE=1`，内部时长结束回 `0` | `SYS=1`，按场景时长回 `0`；默认场景为 5 秒 |
| 写 `BOOT_SIGN=5` | `SYS_STATE=1`，舵机到位回 `0` | `SYS=1`，模拟器固定 5 秒后回 `0` |
| 写 `BOOT_SIGN=4` | `SYS_STATE=0` | 相同，并取消待执行的 Apply 自动回空闲计时 |
| 写 `MT_RPM=0` | 不是停止命令 | 只改变 `MT_RPM` 寄存器；`SYS_STATE` 和 Run 不变 |

`SERVO_ANGLE=830` 是真机确认上电值，不再标为协议示例假设。

### 1.2 明确的模拟器规则

真机的 `BOOT_SIGN=5` 是“舵机到位后回 0”，真实到位时间未由本仓库确认。模拟器为了可重复测试，统一采用：

- 写 `5` 时立即进入 `SYS_STATE=1`。
- 没有活动 Run 时，从收到写命令开始启动固定 5000 ms 的 **Apply Auto-Idle Timer（Apply 自动回空闲计时）**。
- 到点且仍无活动 Run 时，把 `SYS_STATE` 置 `0`。
- Apply 的延迟、完成、stall 或被新 Apply 取代，都不决定 `SYS_STATE`。

该 5 秒规则是 Simulation Assumption，不得写成真机固定时序。

### 1.3 术语

- **System State / `SYS_STATE`**：`0=空闲`，`1=设备动作中`。动作包括电机 Run 或 Apply 调磨流程。
- **Run Mode**：仍只包括 `manual`、`timed`、`smart`。Apply 不是 Run Mode。
- **Apply Auto-Idle Timer**：仅服务无活动 Run 的 `BOOT_SIGN=5`，实现效果名可保持 `scheduleStateReset` / `cancelStateReset`。
- **Power-on State**：冷启动或场景加载时的寄存器初值。
- **Device Power**：虚拟磨豆机电源。`power off` 本身不清寄存器；`power on` 按第 4 节复位易失寄存器。
- **Test Override**：显式测试通道。它不是协议正常写入，也不得被隐藏计时器事后覆盖。

上游 `docs/PROTOCOL.md` 不改。Decaid 插件仍可能把 `SYS_STATE=1` 映射显示为 `grinding`；这是外部插件展示映射，实施文档必须注明，不得反过来限制本模拟器的领域定义。

---

## 2. 需求 A：冷启动与场景默认初值

### 2.1 冷启动 / 场景加载初值

新进程启动、使用默认场景、或场景 JSON 漏写 `initialRegisters` 字段时，客户端首次读取应为：

| 特征 | 值 | hex | base64 |
|---|---:|---|---|
| `SYS_STATE` | 0 | `00 00` | `AAA=` |
| `SERVO_ANGLE` | 830 | `03 3E` | `Az4=` |
| `TF_ANGLE` | 0 | `00 00` | `AAA=` |
| `MT_RPM` | 0 | `00 00` | `AAA=` |
| `XD_RPM` | 0 | `00 00` | `AAA=` |
| `BOOT_SIGN` | 0 | `00 00` | `AAA=` |

这张表只描述冷启动和场景默认加载，不描述 `power on` 后的 `SERVO_ANGLE`；电源循环见第 4 节。

### 2.2 必须同时修改的三处默认值

`Sources/CrystalCore/Protocol.swift`：

- `RegisterValues.default`：`mtRPM=0`、`xdRPM=0`、`tfAngle=0`，`servoAngle=830` 保持不变。
- `RegisterValues.init(from:)` 的 decode 回落值：`mtRPM ?? 0`、`xdRPM ?? 0`、`tfAngle ?? 0`，`servoAngle ?? 830` 保持不变。

`Scenarios/default.json`：

- `initialRegisters.mtRPM=0`
- `initialRegisters.xdRPM=0`
- `initialRegisters.tfAngle=0`

三处必须同时改，否则会出现“默认场景是 0、漏字段场景回到 900/40/830”的分裂。当前其它场景没有 `initialRegisters`，会继承新默认值，这是预期。

不得修改 `Characteristic.writableRange`、UUID、字节序或 2 字节编码。

---

## 3. 需求 B：`SYS_STATE` 状态机

### 3.1 命令规则

| 命令 | 无活动 Run 时 | 有活动 Run 时 |
|---|---|---|
| `BOOT_SIGN=1` | 取消 Apply Auto-Idle Timer；`SYS=1`；manual Run 保持到 `4` | 替换当前 Run；`SYS` 继续为 `1` |
| `BOOT_SIGN=2` | 取消 Apply Auto-Idle Timer；`SYS=1`；按 `timedDurationMs` 回 `0` | 替换当前 Run 并重新计时 |
| `BOOT_SIGN=3` | 取消 Apply Auto-Idle Timer；`SYS=1`；按 `smartDurationMs` 回 `0`；`null` 场景例外保留 | 替换当前 Run 并按新场景规则处理 |
| `BOOT_SIGN=4` | 取消 Apply Auto-Idle Timer；`SYS=0` | 取消 Apply Auto-Idle Timer、停止 Run；`SYS=0` |
| `BOOT_SIGN=5` | `SYS=1`；启动或重启 5000 ms Apply Auto-Idle Timer；同时执行 Apply | 只执行 Apply；不启动该计时，`SYS` 由当前 Run 决定 |

补充规则：

1. `BOOT_SIGN=1` 的正常在线停止命令只有 `BOOT_SIGN=4`。任何 5 秒计时、Apply 完成、重复写 `5` 都不得提前结束 manual Run。
2. `power off/on` 是独立电源路径，不受上一条“只能写 4”的限制。
3. `BOOT_SIGN=2/3` 的时长仍来自场景配置；只有默认场景是 5000 ms。不得把 `timedDurationMs` / `smartDurationMs` 改成全局硬编码。
4. `SYS_STATE` 已为 `1` 时，重复写 `1/2/3/5` 不重复产生相同值通知；现有通知去重语义保持不变。
5. 连续写两次 `5`：先取消旧 Apply Auto-Idle Timer，再启动新计时；只有新 id 能置 `0`。
6. Apply 被延迟、stall、被新 Apply 取代或已经完成，都不决定 `SYS_STATE`。
7. 5 秒到点时即使 Apply 仍 pending，`SYS_STATE` 也置 `0`，pending Apply 保留。这是模拟器兜底。
8. `SYS_STATE` 仍然不可写；正常 ATT 写仍按现有只读特征规则处理。
9. `BOOT_SIGN` 寄存器仍保留最后命令值 `5`。
10. `MT_RPM=0` 只更新电机设定值，不是停止命令。

### 3.2 Apply Auto-Idle Timer 的取消条件

以下路径都必须取消待执行的 Apply Auto-Idle Timer：

- 写 `BOOT_SIGN=1/2/3/4`。
- 再次写 `BOOT_SIGN=5`，然后以新 id 重启计时。
- `finishRun` / `forceFinishRun` 等经由 `stopRun` 的结束路径。
- 会话策略 `stop` 经由 `stopRun` 的路径。
- `powerOff`。
- `SERVO_ANGLE` Test Override 取消 pending Apply 时。
- 任何显式 `SYS_STATE` Test Override。
- 场景 `reset` / `load` 导致模型替换时，旧模型计时不得影响新模型。

`completeStateReset(id:)` 必须校验 id、电源状态和当前模型身份；旧 id、已取消 id、断电后回调或旧模型回调都不得修改状态。

### 3.3 Session Pause

Apply Auto-Idle Timer 复用 `DeviceScheduler`，与 Run/Apply 计时一样会在 `sessionEnded(.pause)` 时暂停。本需求不增加暂停豁免。

因此“5 秒”表示调度器未被暂停时的 5000 ms；如果 Observed Session End 触发 pause，实际 wall-clock 回空闲时间可能更晚。不得在 `completeStateReset` 里绕过 pause。

### 3.4 Test Override 规则

- `SERVO_ANGLE` Test Override 只有在它取消 pending Apply 时，才同时取消 Apply Auto-Idle Timer；无活动 Run 时立即把 `SYS_STATE` 收回 `0`，并标记 Test Override。
- 任何显式 `SYS_STATE` Test Override 都先取消 Apply Auto-Idle Timer，再写入测试值。隐藏计时器不得在第 5 秒覆盖测试人员设置的值。
- 不用 Test Override 或 `finishRun` 伪造“5 秒自动回空闲”的集成测试通过。

---

## 4. 需求 C：`power on` 复位易失寄存器

### 4.1 电源循环语义

`power off` 本身不清零寄存器；关机后没有 GATT，客户端读不到值。复位发生在 `power on`：

| 特征 | `power on` 后 |
|---|---|
| `SYS_STATE` | quiet 置 `0` |
| `SERVO_ANGLE` | 保留关机前值 |
| `TF_ANGLE` | `0` |
| `MT_RPM` | `0` |
| `XD_RPM` | `0` |
| `BOOT_SIGN` | `0` |

`power on` 不恢复旧 Run、旧 Apply 或旧 Apply Auto-Idle Timer。

### 4.2 实现要求

`DeviceModel.powerOn`：

- 清 `activeRun`、`pendingApply`、`pendingStateResetID`。
- 直接复位 `registers.mtRPM/xdRPM/tfAngle/bootSign = 0`。
- 同步复位 `notificationBaseline[.mtRPM/.xdRPM/.tfAngle] = 0`，避免开机后写入相同值被旧 baseline 错误去重。
- 保留 `SERVO_ANGLE`。
- 保留现有 quiet `setRegister(.sysState, value: 0, source: "device-power-on", suppressNotification: true)`，以维持 Device Power 的 quiet 事件语义。
- 控制日志改为“volatile settings reset, SERVO_ANGLE retained”语义。

直接复位 MT/XD/TF/BOOT 不产生逐寄存器 `register changed` 事件；电源控制事件的 before/after 快照负责记录变化。该事件日志边界必须写入测试或文档，避免消费者误以为每个寄存器都有独立通知。

---

## 5. 需求 D/E：Override 与计时器一致性

### 5.1 `SERVO_ANGLE` override 取消 Apply

当 `SERVO_ANGLE` Test Override 取消 pending Apply 时：

1. 取消 pending Apply。
2. 取消 Apply Auto-Idle Timer。
3. 无活动 Run 时，把 `SYS_STATE` 置 `0`，来源标记为 Test Override。
4. 有活动 Run 时，不改变 Run 对 `SYS_STATE` 的所有权。

该改动的目的不是“防止 SYS 永远卡住”——旧计时器本来也可能在 5 秒后清 0；目的是让显式测试通道立即、确定地收回状态，并在 Session Pause 等计时器被冻结的情况下仍保持一致。

### 5.2 `SYS_STATE` override 取得控制权

任何显式 `SYS_STATE` Test Override 都必须先取消 Apply Auto-Idle Timer。示例：

```text
写 BOOT_SIGN=5
SYS_STATE=1，计时器已启动
Override SYS_STATE=2
等待超过 5 秒
SYS_STATE 必须仍为 2
```

---

## 6. 实现设计约束

### 6.1 模型层新增能力

在 `Sources/CrystalCore/DeviceModel.swift` 中实现，不放进 `BLEPeripheral`、Web 或前端。

`ModelEffect` 增加：

```swift
case scheduleStateReset(id: UInt64, delayMs: UInt64)
case cancelStateReset(id: UInt64)
```

`DeviceModel` 增加：

```swift
public private(set) var pendingStateResetID: UInt64?
private var stateResetCounter: UInt64 = 0
```

建议语义：

```swift
private func scheduleStateReset(delayMs: UInt64 = 5_000) -> [ModelEffect]
private func cancelStateReset() -> [ModelEffect]
public func completeStateReset(id: UInt64) -> [ModelEffect]
```

`completeStateReset` 只在 id 匹配、设备 powered on 且没有活动 Run 时，把 `SYS_STATE` 置 `0`；否则返回空效果。它不得触碰 pending Apply。

### 6.2 调用点

- `beginApply()`：先按当前状态设置 `SYS=1`；无活动 Run 时启动/重启 Apply Auto-Idle Timer；有活动 Run 时确保没有遗留计时器。Apply 的捕获、延迟、stall、取代逻辑保持独立。
- `start(mode:)`：顶部先取消 Apply Auto-Idle Timer，再处理 Run 替换和场景计时。
- `stopRun(...)`：顶部先取消 Apply Auto-Idle Timer，即使当前没有活动 Run，也不能让旧计时器继续存活。
- `powerOff(...)`：取消 Apply Auto-Idle Timer。
- `powerOn(...)`：清 `pendingStateResetID`，并按第 4 节复位易失寄存器。
- `overrideRegister(.sysState, ...)`：先取消 Apply Auto-Idle Timer。
- `overrideRegister(.servoAngle, ...)` 取消 pending Apply 时：同时取消计时器并按第 5.1 节处理 `SYS_STATE`。
- `completeApply` / `forceFinishApply`：保持不修改 `SYS_STATE`。当前代码本来就没有 Apply 完成清 `SYS` 的逻辑；不要新增。

### 6.3 BLE 调度

`Sources/CrystalSim/BLEPeripheral.swift` 的 `execute(_:)` 只负责把效果映射到 `DeviceScheduler`：

```swift
case .scheduleStateReset(let id, let delayMs):
    scheduler.schedule(id: "state-reset-\(id)", delayMs: delayMs) { [weak self] in
        guard let self, self.model === effectModel, self.model.poweredOn else { return }
        self.execute(self.model.completeStateReset(id: id))
    }
case .cancelStateReset(let id):
    scheduler.cancel(id: "state-reset-\(id)")
```

场景替换、断电和 stale callback 继续依赖现有 generation / model identity 防护。

---

## 7. 测试计划

### 7.1 Red–Green 顺序

新 API 的测试引用了当前不存在的 `ModelEffect` case、`pendingStateResetID` 和 `completeStateReset`。实施时按以下顺序获得有效 Red：

1. 先写目标测试。
2. 添加最小编译接口或 stub，不实现目标行为。
3. 运行测试，实际观察因行为缺失而失败。
4. 写最小实现达到 Green。
5. Green 后才重构，并重跑相关测试。

不得通过删除、跳过、削弱或改写既有测试制造 Green。

### 7.2 `DeviceModelTests` 必须覆盖

保留原规格中的核心用例，并补齐遗漏边界：

- `testApplySchedulesFiveSecondAutoIdle`
- `testManualStartCancelsApplyAutoIdle`
- `testStopCancelsApplyAutoIdleWithoutSecondNotification`
- `testApplyDuringRunDoesNotScheduleAutoIdle`
- `testRepeatedApplyRestartsAutoIdleTimer`
- `testPowerOffCancelsApplyAutoIdle`
- `testDelayedApplyCompletionDoesNotClearSysStateEarly`
- `testStateResetFiresDuringApplyStallAndRetainsPendingApply`
- `testSystemStateOverrideCancelsApplyAutoIdle`
- 场景 `reset/load` 后旧计时 id 不影响新模型（可在模型或集成层覆盖）
- Session Pause 冻结 Apply Auto-Idle Timer（在 scheduler/BLE 集成层覆盖；不得绕过 pause）

更新现有用例：

- `testImmediateApplyUsesTargetWithoutClaimingMechanicalCompletion`：Apply 完成后 `SYS_STATE` 仍为 `1`，等待状态复位。
- `testServoOverrideCancelsPendingApply`：`pendingStateResetID == nil`，无活动 Run 时 `SYS_STATE == 0`。
- `testTimedAndSmartRunsScheduleDeterministicCompletion`：继续覆盖 `2/3` 的场景计时，不改语义。

### 7.3 默认值和电源测试

- `ProtocolTests`：固定新默认值和 decode 回落值。
- `ScenarioTests` / `RepositoryScenarioTests`：固定 `default.json` 和漏字段场景继承值。
- `NormalWritePreparationTests`：原先用默认 `TF_ANGLE=830` 捕获 Apply target 的用例，必须先写 `TF_ANGLE=830`，避免默认值变为 0 后测试意图改变。
- `DevicePowerTests.testPowerOnAlwaysEntersQuietIdleWithoutRestoringOperations`：断言 `MT/XD/TF/BOOT=0`，`SERVO_ANGLE` 保留，Run/Apply/状态复位不恢复。

### 7.4 集成冒烟

`Scripts/smoke_test.py`：

- 初始 `TF_ANGLE` 期望从 `830 / 03 3E / Az4=` 改为 `0 / 00 00 / AAA=`。
- `power on` 日志期望改为“volatile settings reset, SERVO_ANGLE retained”语义。
- “notification suppressed for Device Power”计数仍保持 4。
- 增加电源循环后 `MT/XD/TF/BOOT=0`、`SERVO_ANGLE` 保留的检查。

`Scripts/web_smoke_test.py`：

- 默认 `mtRPM/xdRPM/tfAngle/bootSign == 0`。
- 电源循环后断言易失寄存器为 0，`SERVO_ANGLE` 保留。
- Apply 后立即断言 `sysState == 1`。
- 用轮询方式等待最多约 6.5 秒，断言 `sysState == 0`；不得用 `finishRun`、SYS Override 或固定长 sleep 掩盖时序。

### 7.5 前端和文档测试

如果实施时同步 Web 术语，必须同时更新：

- `Sources/CrystalWeb/Web/sim-client.js` 的 `SYS_STATE` 解释。
- `Scripts/web-tests/sim-client.test.js` 的中英文断言。
- `Sources/CrystalWeb/Web/index.html` 中 motor 输入框的默认值 `900`。

---

## 8. 文档同步清单

以下是实施变更的一部分，不是可选清理。`docs/PROTOCOL.md` 是上游协议快照，绝不修改。

### 8.1 领域和 agent 文档

- `CONTEXT.md`
  - System State：`1=设备动作中`，不再只写“研磨中”。
  - Device Power：power-on 复位 Motor/Feed/Target Grind/Boot Command，仅保留 Current Grind Setting。
  - Power-on State：区分设备方确认事实与模拟器假设，删除“不声明真机上电值”的旧表述。
- `AGENTS.md`：中英文 `SYS_STATE=1` 说明同步为“设备动作中 / device active”。
- `docs/ASSUMPTIONS.md`
  - 初值表更新为 `SYS=0、SERVO=830、TF=0、MT=0、XD=0、BOOT=0`。
  - 把设备方确认的上电事实与 5 秒 Apply 兜底假设分开表述。
  - Apply 行补充：写 `5` 时 `SYS=1`，模拟器 5 秒后回 `0`；有活动 Run 时不启动该计时。
  - Device Power on：易失寄存器归 0，仅保留 `SERVO_ANGLE`。

### 8.2 用户文档

- `README.md` / `README.en.md`
  - 默认值表：`MT_RPM=0`、`XD_RPM=0`、`TF_ANGLE=0`。
  - `SYS_STATE` 说明：`0=空闲、1=设备动作中（电机启动或 Apply 调磨）`。
- `docs/IPAD_ACCEPTANCE.md`
  - 初读表更新为 `SERVO=03 3E`，其余 `00 00`。
  - “恢复默认值可写 TF_ANGLE=03 3E”改为符合新默认值的表述。
  - 示例 `rpm=900/feed=40` 更新为 `rpm=0/feed=0`。
  - 研磨度两步写补充：写 `5` 后立即 `SYS=00 01`，模拟器约 5 秒后 `00 00`；默认 Apply 立即更新 SERVO，delayed-apply 场景 2 秒更新 SERVO，但 SYS 仍由 5 秒兜底决定。
- `docs/SCENARIOS.md`
  - 示例 `initialRegisters` 更新为新默认值。
  - pause 的计时器列表加入 Apply Auto-Idle Timer。
  - 行为说明和 `applyStall` 段落补充：写 `5` 进入 `SYS=1`，stall 不阻止 5 秒兜底。
  - `notification-lab.json` 说明补充：Apply 产生的 SYS 通知可能消费“第一条 SYS 通知丢弃”规则。
  - Device Power 段落更新为 power-on 复位易失寄存器、仅保留 SERVO。
- `docs/WEB_ACCEPTANCE.md`
  - `SYS_STATE` 术语和 power-on 初值同步更新。

### 8.3 Web 与发布材料

- Web 控制台寄存器解释改为“设备动作中 / Device Active”语义，并更新 Node 测试。
- motor 输入框默认值从 `900` 改为 `0`。
- 实施合并后，在 `CHANGELOG.md` 新增下一预发布条目；不得改写 `1.0.0-beta.1` 历史。
- 真正发布 `1.0.0-beta.2` 时，另行确认并更新 `AppVersion.swift`、`Resources/Info.plist`、版本测试、版本冒烟和 README release 链接。本规格不授权直接发布。

---

## 9. 本轮明确不做

1. 不修改广播内容；当前仍只广播本地设备名，不补 128 位主服务 UUID。该变更影响 adv/scan response 分包，必须单独实扫验证。
2. 不修改 `disconnectPolicy` 默认 `pause`。
3. 不把 `timedDurationMs` / `smartDurationMs` 改成全局硬编码 5 秒；`smart-manual-finish.json` 的 `null` 例外保留。
4. 不处理 per-central 强制断开；`requestDisconnect` 的 CoreBluetooth 限制单独处理。
5. 不引入新依赖，不改 UUID、字节序、2 字节编码或 ATT 写响应语义。
6. 不把 `MT_RPM=0` 当停止命令。
7. 不把 `SYS_STATE` 改成可写特征。
8. 不要求把 `pendingStateResetID` 暴露到 Web snapshot；如需公开诊断字段，另行评审。
9. 不在本轮实施、commit、push、打标签或发布。

---

## 10. 验收

### 10.1 自动验收

实施完成后至少运行：

```bash
swift test
node --test Scripts/web-tests/*.test.js
bash Scripts/test.sh
python3 Scripts/smoke_test.py
python3 Scripts/web_smoke_test.py
swift test -c release
bash Scripts/build.sh release
codesign --verify --verbose .build/release/bochoy-grinder-emulator
```

完整测试需要 macOS 蓝牙权限，并使用独立设备名、端口和临时日志，不得操作用户自己的模拟器进程。

### 10.2 手工 BLE 验收

使用 nRF Connect / LightBlue，先订阅 `SYS_STATE`：

1. 冷启动，首连六读等于第 2.1 节表（`SERVO=03 3E`，其余 `00 00`）。
2. 写 `TF_ANGLE=1000`（`03 E8`），再写 `BOOT_SIGN=5`：
   - 立即收到或读到 `SYS_STATE=00 01`；若已为 1，按去重规则可能不重复通知。
   - 默认场景 Apply 完成时 `SERVO_ANGLE` 变为 `03 E8`。
   - 约 5 秒后 `SYS_STATE=00 00`。
3. `delayed-apply` 场景：Apply 2 秒完成时 `SERVO_ANGLE` 更新，但 `SYS_STATE` 不提前回 0，仍按 5 秒兜底。
4. 写 `BOOT_SIGN=2/3`：立即 `00 01`，默认场景约 5 秒后 `00 00`。
5. 写 `BOOT_SIGN=1`：`00 01`，等待 10 秒仍为 1；写 `4` 后 `00 00`。
6. 写 `1` 后写 `5`：`SYS` 保持 1，不会在 5 秒后被清掉；写 `4` 才回 0。
7. 写 `5` 后 2 秒内写 `4`：立即 `00 00`，之后不再收到重复的 `00 00` 通知。
8. 写 `5` 后 Override `SYS_STATE=2`，等待超过 5 秒仍为 2。
9. 用 Test Override 把 `SERVO_ANGLE` 改为非 830 值，再 `power off` → `power on`：六读为 `SYS/MT/XD/TF/BOOT=0`，`SERVO_ANGLE` 保留 override 后的值。
10. 正常写 `SYS_STATE` 仍被忽略，值不变，并保留现有违规日志语义。
11. Session Pause 场景下，Apply Auto-Idle Timer 随 scheduler 暂停；恢复后继续，不得被实现绕过。

### 10.3 报告要求

实施报告必须说明：

- 修改的文件和未修改的边界。
- 实际运行的命令、真实通过/失败数量和 Red/Green 观察。
- 哪些项目需要人工验收但未执行。
- 不得声称跑过未执行的真机、浏览器视觉、通知接收或 Link Loss 验收。
