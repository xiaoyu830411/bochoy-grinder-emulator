# 场景格式与故障规则

场景是版本化 JSON。除 `name` 等需要覆盖的字段外，可以省略字段使用默认值；最小合法文件是 `{}`。启动时会校验完整结果。

Web 只能选择七个内置目录名，不接受文件路径：`default`、`delayed-apply`、`notification-lab`、`optional-notify-off`、`required-notify-off`、`smart-manual-finish`、`stop-on-session-end`。CLI `load <path>` 仍可加载显式本地文件。Device Power 和 Web 目录没有加入 Scenario JSON，`schemaVersion` 保持 1。

字段名区分大小写。当前解码器会忽略未知 JSON 字段，因此拼错的可选字段可能静默使用默认值；加载后应通过 `status`、`faults` 和场景日志核对实际配置。

```json
{
  "schemaVersion": 1,
  "name": "example",
  "deviceName": "CRYSTAL-E57C",
  "initialRegisters": {
    "mtRPM": 0,
    "xdRPM": 0,
    "bootSign": 0,
    "sysState": 0,
    "servoAngle": 830,
    "tfAngle": 0
  },
  "behavior": {
    "timedDurationMs": 5000,
    "smartDurationMs": 5000,
    "disconnectPolicy": "pause"
  },
  "layout": {
    "includeService": true,
    "omittedCharacteristics": [],
    "notifyDisabled": []
  },
  "faults": []
}
```

## 1. 初值与行为

- `initialRegisters` 支持完整 `0–65535`，因此可以构造未定义状态。非默认初值属于 Scenario / Test Override，不表示真机上电值。
- `timedDurationMs`：定时启动的自动结束时间；必须是整数，显式 `null` 会被拒绝。
- `smartDurationMs`：智能启动的自动结束时间；设为 `null` 表示等待控制台 `finish`。
- 行为时长与所有 `delayMs` 的上限均为 `86400000` 毫秒（24 小时），拒绝会造成计时转换溢出的配置。
- 新启动命令会取消旧 Run 计时器并选择新模式；`BOOT_SIGN=4` 只停止 Run，不取消 Apply。
- 写 `BOOT_SIGN=5` 进入 `SYS=1`；没有活动 Run 时由固定的 5 秒 Apply Auto-Idle Timer 回 `0`（模拟器兜底，不是真机计时保证）；有活动 Run 时不启动该计时，Run 结束路径负责回 `0`。
- `disconnectPolicy` 在 **Observed Session End** 时执行：
  - `pause`：暂停 Apply、自动 Run 与 Apply Auto-Idle 计时器，保留剩余时间，会话恢复后继续；暂停期间新建的 delayed Apply、自动 Run 或 Apply Auto-Idle 计时器也保持冻结，直到恢复。
  - `continue`：计时器继续。
  - `stop`：停止 Run 并令 `SYS_STATE=0`；待执行 Apply 继续。

## 2. GATT 布局

```json
{
  "layout": {
    "includeService": false,
    "omittedCharacteristics": ["XD_RPM"],
    "notifyDisabled": ["TF_ANGLE", "XD_RPM"]
  }
}
```

- `includeService=false`：名称广播仍可启动，但连接后不发布主服务，用于测试服务发现失败。
- `omittedCharacteristics`：从服务中移除特征。
- `notifyDisabled`：保留 Read/Write，移除 Notify 属性。CoreBluetooth 不能动态拒绝单次订阅，因此可选/必需订阅失败通过此布局构造。

改变布局时先断开 iPad。虽然无会话、无订阅者时 `load` 会重新发布服务，推荐用 `--scenario` 重启，避免 central 缓存旧 GATT 数据库。

## 3. FaultRule 通用字段

```json
{
  "id": "drop-second-sys",
  "type": "notificationDrop",
  "characteristic": "SYS_STATE",
  "value": 1,
  "onOccurrence": 2,
  "maxTriggers": 1
}
```

| 字段 | 含义 |
|---|---|
| `id` | 场景内唯一 ID，控制台用它开关故障 |
| `type` | 下表列出的故障类型 |
| `characteristic` | 可选特征过滤；部分类型必填 |
| `value` | 可选十进制 `uint16` 过滤 |
| `onOccurrence` | 只在第 N 个匹配的已启用候选操作触发；省略表示每次 |
| `maxTriggers` | 最大触发次数；省略表示不限 |
| `delayMs` | 延迟类故障必填 |
| `attStatus` | 仅用于 `readError` / `writeError` 的非零 ATT 错误码，JSON 中写十进制；默认 14 (`unlikelyError`) |
| `extraCopies` | `notificationDuplicate` 的额外副本数，默认 1 |

规则分别计数。被禁用的规则不计数；`fault <id> off/on` 会重置该规则计数。`load` / `reset` 重置所有规则。

## 4. 故障类型

### `readError` / `writeError`

对匹配的读或写返回指定 ATT 错误。`characteristic` 必填。写错误不会进入设备模型，也不会改变寄存器。

BLE 与 Web 正常写都经过 `writeError`。Web 注入写拒绝返回 HTTP 422、`attStatus` 和 `faultID`；“设置并 Apply”的第二步若被拒绝，第一步 TF 写入不会回滚。`readError` 只对 ATT read 生效。

```json
{
  "id": "mt-write-busy",
  "type": "writeError",
  "characteristic": "MT_RPM",
  "attStatus": 17,
  "maxTriggers": 1
}
```

### `responseDelay`

延迟读或写 ATT Response，`characteristic`、`delayMs` 必填。同一条规则同时统计该特征的读和写。

- 读取值在请求到达时取得。
- 写命令和寄存器变化仍立即处理，只延迟 ATT Response。
- 通知和调度效果在 Response 完成后执行。
- 需要延迟机械语义上的 Apply 时，使用 `applyDelay`，不要混淆两者。

该故障是 **ATT-only**。Web 正常写没有 ATT Response，因此不会执行或消费 `responseDelay`；寄存器、Run/Apply 和通知效果仍按共享模型处理。

### `notificationDrop`

状态照常改变，但不提交匹配通知。去重记录已经推进；不要期待相同值随后自动补发。在 `notification-lab` 中验证“第一条 SYS 通知丢弃”时注意：写 `BOOT_SIGN=5` 产生的 `SYS=1` 通知可能先消费该规则，后续 Run 状态通知不再被丢弃。

### `notificationDelay`

按指定毫秒延迟提交通知，通知内容捕获触发时的值。多个延迟规则同时匹配时取最大延迟。

### `notificationDuplicate`

为匹配通知增加副本。多个重复规则同时匹配时使用最大的 `extraCopies`，不叠加乘法。

### `applyDelay`

延迟 Apply 完成。每次 `BOOT_SIGN=5` 仍立即捕获目标值。此故障作用于 Apply 操作本身，不接受 `characteristic` 或 `value` 过滤：

- 后续单独修改 `TF_ANGLE` 不改变已捕获目标。
- 新 Apply 取代旧 Apply，旧计时器失效。
- 停止电机不取消 Apply。
- `set SERVO_ANGLE ...` 或场景重置会取消 Apply。

### `applyStall`

Apply 到完成点仍保持 pending，不更新当前研磨度。到点的计时器已被消费，关闭故障不会自动重试；控制台 `apply-finish`、新 Apply、Servo Test Override 或重置可以结束该状态。不接受 `characteristic` 或 `value` 过滤。stall 不阻止 Apply Auto-Idle Timer：写 `5` 后 `SYS=1` 仍在约 5 秒后回 `0`，pending Apply 继续保留。

### `runStall`

只阻止自动 Run 完成。到点的计时器已被消费，关闭故障不会自动补排或重试；`BOOT_SIGN=4` 和控制台 `finish` 仍可停止。不接受 `characteristic` 或 `value` 过滤。

### `terminateProcess`

在匹配且被正常处理的 BLE 或 Web 写命令完成后退出进程，退出码为 70。被 ATT 写错误拒绝、错误长度、越界、保留 `BOOT_SIGN` 命令以及 `SYS_STATE` / `SERVO_ANGLE` 违规写入不触发。可用于真实链路消失测试，但不等同于 CoreBluetooth 提供的“断开指定 central”API。

```json
{
  "id": "exit-on-auto-start",
  "type": "terminateProcess",
  "characteristic": "BOOT_SIGN",
  "value": 3
}
```

进程退出后不会保存寄存器；重启加载默认状态或指定场景。

## 5. 会话、电源与重置限制

- 有已知订阅者、活动测试会话或待返回 ATT Response 时，`load` / `reset` 拒绝执行。
- Device Power off 时，CLI 和 Web 的场景加载/重置都拒绝，防止替换模型时意外上电。
- 场景替换保留独立 Observed Central 观察存储；它不属于 DeviceModel，也不会凭空变成真实连接清单。
- CoreBluetooth 看不到从未订阅、也尚未读写的外层连接；涉及布局变化时仍应显式断开手机或平板并重启。
- `session-end` 只执行断连策略，不关闭广播、不取消订阅，也不产生真实 Link Loss。
- `power off` 不是场景重置：它取消 Run/Apply/Apply Auto-Idle Timer 并 quiet 进入空闲，寄存器在关机期间保留。`power on` 新建服务、默认恢复广播，不恢复旧操作或旧计时器，并把易失寄存器 `MT/XD/TF/BOOT` 复位为 0，仅保留 `SERVO_ANGLE`。
- 真实断连请从手机或平板操作，或使用进程退出故障。
