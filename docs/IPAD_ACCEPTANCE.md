# iPad 实机验收清单

> 状态：**待实机执行**。本清单中的预期值来自协议和已确认的模拟行为，不表示已经通过 iPad 或 Decaid 测试。

实机测试由你执行。建议先完成通用 BLE 工具验收，再测试 Decaid，以便区分模拟器协议问题和插件/宿主问题。

## 1. 准备

### Mac

1. 打开蓝牙。
2. 构建并签名：

   ```bash
   bash Scripts/build.sh
   ```

3. 启动默认场景：

   ```bash
   .build/debug/bochoy-grinder-emulator --json-log Logs/ipad-default.jsonl
   ```

4. 等待日志同时出现：
   - `GATT service published ... characteristics=6`
   - `advertising started`
5. 保持终端和模拟器运行。

### iPad

- 通用工具：安装 nRF Connect 或 LightBlue，并允许蓝牙权限。
- Decaid：代码支持 iPadOS 16.7 或更高；实际安装、签名和运行仍需实机确认。
- 测试期间保持 App 在前台。后台扫描行为不在已验证范围内。
- 若附近有真实 CRYSTAL 设备，确认测试对象是 `CRYSTAL-E57C`，不要向真机写入测试值。

### 写入选项

- 选择 **Write Request / Write With Response**。
- 输入下表的原始 hex，不输入 base64、ASCII 十进制或 ATT Handle。
- 读取与通知同样按 2 字节大端解释。

## 2. 通用 BLE 工具：发现、订阅和初读

- [ ] 扫描到 `CRYSTAL-E57C`。
- [ ] 能连接，不要求预先系统配对。
- [ ] 发现主服务 `7fa2d10c-12f3-4b9e-9d77-1a9b65432100`。
- [ ] 主服务下发现全部六个特征。
- [ ] 默认每个特征都有 Read/Write/Notify 属性。
- [ ] 依次订阅 `SYS_STATE`、`SERVO_ANGLE`、`MT_RPM`。
- [ ] 再订阅 `TF_ANGLE`、`XD_RPM`；`BOOT_SIGN` 无需订阅。

> 模拟器采用名称优先广播，广播中不附加 128 位主服务 UUID；连接后必须发现主服务。这是平台适配假设，不表示真机也采用相同分包方式。Decaid 当前按名称前缀扫描。

逐一读取：

| 特征 | 预期 hex | 十进制 |
|---|---|---:|
| `SYS_STATE` | `00 00` | 0 |
| `SERVO_ANGLE` | `03 3E` | 830 |
| `TF_ANGLE` | `03 3E` | 830 |
| `MT_RPM` | `03 84` | 900 |
| `XD_RPM` | `00 28` | 40 |
| `BOOT_SIGN` | `00 00` | 0（模拟器假设：最后已定义命令） |

记录 Mac 日志应能看到订阅和读取事件。此时尚不能仅凭 Mac 日志判断 iPad 已收到通知，以 iPad 显示为准。

## 3. 正常写命令与通知

### 3.1 研磨度两步写

1. 向 `TF_ANGLE` 写 `04 B0`（1200）。
2. 确认写响应成功，读取 `TF_ANGLE = 04 B0`。
3. 此时读取 `SERVO_ANGLE` 仍应为旧值 `03 3E`。
4. 向 `BOOT_SIGN` 写 `00 05`。
5. 预期 `SERVO_ANGLE` 通知为 `04 B0`；回读也为 `04 B0`。

恢复默认值可写 `TF_ANGLE = 03 3E`，再写 `BOOT_SIGN = 00 05`。

- [ ] 第一步不会提前改变当前值。
- [ ] 第二步后当前值变为目标值。
- [ ] 两步各有独立 ATT 写响应，没有应用层“动作完成”应答。

### 3.2 电机值与下豆值

1. 向 `MT_RPM` 写 `04 B0`：预期通知 `04 B0`。
2. 再写一次 `04 B0`：预期没有新的正常通知，Mac 日志记录去重。
3. 向 `XD_RPM` 写 `00 58`：预期通知 `00 58`。
4. 回读分别为 1200、88。

- [ ] 原始字节与数值正确。
- [ ] 相同值写入不重复通知。

### 3.3 启动、停止与定时结束

- 手动：写 `BOOT_SIGN = 00 01`。
  - [ ] `SYS_STATE` 通知/回读为 `00 01`。
  - [ ] 超过 5 秒仍为研磨中。
  - [ ] 写 `MT_RPM = 00 00` 后 `SYS_STATE` 仍为 1。
  - [ ] 写 `BOOT_SIGN = 00 04` 后变为 `00 00`。
- 定时：写 `00 02`。
  - [ ] 立即进入 `00 01`，默认约 5 秒后自动通知 `00 00`。
- 智能：写 `00 03`。
  - [ ] 默认约 5 秒后自动结束。
- 在自动结束前写 `00 04`。
  - [ ] 立即回到空闲，旧计时器稍后不会再次改变状态。
- 读取 `BOOT_SIGN`。
  - [ ] 返回最后已定义命令，不因动作完成自动清零。

## 4. 非法与未定义写入

先记录正常 `MT_RPM` 值，例如 1200。

| 操作 | 预期 |
|---|---|
| 向 `MT_RPM` 写单字节 `01` | ATT 写成功；寄存器不变；无通知 |
| 向 `MT_RPM` 写 `05 DD`（1501） | ATT 写成功；忽略；无通知 |
| 向 `XD_RPM` 写 `00 97`（151） | ATT 写成功；忽略；无通知 |
| 向 `BOOT_SIGN` 写 `00 00` 或 `00 06` | 写成功；无动作；命令寄存器保留最后已定义命令 |
| 向 `SYS_STATE` 写 `00 01` | 写成功；忽略；Mac 记录协议违规 |
| 向 `SERVO_ANGLE` 写 `03 E8` | 写成功；忽略；当前值不变 |

- [ ] 每种情况都通过回读确认，不以“收到写响应”推断值已被采用。
- [ ] Mac JSONL 能区分错误长度、越界和未定义写入。

## 5. Test Override 与未知状态

在 Mac 终端执行：

```text
set SYS_STATE 2 notify
```

- [ ] iPad 若订阅有效，收到 `SYS_STATE = 00 02`。
- [ ] Mac 日志明确带 `TEST_OVERRIDE`，不是正常启动动作。
- [ ] 回读得到十进制 2。

然后：

```text
set SYS_STATE 0 quiet
```

- [ ] 回读为 0，但没有这次 Override 的通知。

也可用 `notify BOOT_SIGN` 验证强制测试通知；它不属于正常协议行为，测试后重新开始默认场景。

## 6. Apply 交错与故障场景

先断开 iPad，停止旧进程，再启动：

```bash
.build/debug/bochoy-grinder-emulator \
  --scenario Scenarios/delayed-apply.json \
  --json-log Logs/ipad-delayed-apply.jsonl
```

1. 写 `TF_ANGLE = 03 84`（900）。
2. 写 `BOOT_SIGN = 00 05`，Apply 开始等待 2 秒。
3. 立即写 `TF_ANGLE = 04 B0`（1200）。
4. 等 Apply 完成。

预期：

- [ ] `SERVO_ANGLE` 最终为 900，不是 1200。
- [ ] `TF_ANGLE` 保持 1200。
- [ ] 日志可对应捕获目标、Apply ID 和完成事件。
- [ ] 停止电机不会取消待执行 Apply。

`Scenarios/notification-lab.json` 还可分别验证响应延迟、首次状态通知丢弃和首次舵机通知重复。故障默认只在该场景中启用。

## 7. 会话策略与真实断连

### 7.1 人工会话结束，不产生 Link Loss

默认定时启动后立即在 Mac 执行：

```text
session-end
```

- [ ] 默认 `pause` 暂停剩余 Run 计时。
- [ ] iPad 蓝牙仍保持连接。
- [ ] 执行 `session-begin` 后按剩余时间恢复。
- [ ] 日志没有把这写成已确认的真实 Link Loss。

### 7.2 iPad 真实断开

- [ ] 从 iPad 主动断开，观察 Mac 是否收到取消订阅并推断会话结束。
- [ ] 若系统没有提供可观察事件，接受该限制，不把计时器行为当成真实固件断链行为。
- [ ] 重连后重新订阅并主动读取全部状态。
- [ ] 新会话会重置模拟器通知去重记录。

### 7.3 进程退出

在研磨中执行 `quit`，或加载 `terminateProcess` 故障：

- [ ] iPad 最终报告连接丢失。
- [ ] 重启后使用场景初值，不恢复上次寄存器或计时器。
- [ ] 此结果不被解释为真实磨豆机的断链 watchdog。

## 8. GATT 布局失败路径

### 可选 Notify 关闭

```bash
.build/debug/bochoy-grinder-emulator --scenario Scenarios/optional-notify-off.json
```

- [ ] `TF_ANGLE` / `XD_RPM` 没有 Notify 属性。
- [ ] Decaid 可选订阅失败只记录日志，连接初始化仍可继续。

### 必需 Notify 关闭

```bash
.build/debug/bochoy-grinder-emulator --scenario Scenarios/required-notify-off.json
```

- [ ] `SYS_STATE` 没有 Notify 属性。
- [ ] Decaid 必需订阅失败导致连接初始化失败。

每种布局测试前都先断开并重连，必要时在 iPad 工具中忽略该设备缓存或重启 App。

## 9. 真实 Decaid + 插件

### 安装

1. 在 iPad 安装并运行 Decaid，授予蓝牙权限，保持前台。
2. 安装版本 `0.2.0` 的 `crystal-grinder.reaplugin`。源码中的安装入口支持 ZIP、GitHub Release/Branch 等方式。
3. 恢复模拟器默认场景，并确认没有其他旧模拟进程占用广播身份。
4. 让 Decaid 扫描并绑定 `CRYSTAL-E57C`。

### 初始化与快照

- [ ] 名称前缀匹配成功。
- [ ] 主服务校验、必需订阅、可选订阅及初始读取完成。
- [ ] 厂商状态显示 `connected=true`、`state=idle`、`setting=830`、`rpm=900`、`feed=40`。
- [ ] 若检查标准 `/api/v1/grinder/state`，其 `setting` 按 Decaid 约定为字符串 `"830"`，与厂商 status 的数字类型区分。
- [ ] HTTP/App 成功不被当作额外 BLE 机械完成应答。

### 控制链路

- [ ] 研磨度设置执行 `TF_ANGLE → BOOT_SIGN=5` 两次带响应写，顺序正确。
- [ ] 修改电机值和下豆值后快照/厂商接口显示新寄存器值。
- [ ] 手动、定时、智能启动分别写入 `1 / 2 / 3`。
- [ ] 停止写入 `4`，不是仅写 `MT_RPM=0`。
- [ ] 断连后插件报未连接；WebSocket/App 重连不被误认为 BLE 已重连。

> 当前插件对未知 `SYS_STATE` 的兼容映射不等于安全保证。若测试 `SYS_STATE=2`，只记录实际行为，不据此认定真机安全空闲。

## 10. 结果记录

请为每轮记录：

```text
日期：
Mac / macOS：
iPad 型号 / iPadOS：
通用 BLE 工具及版本：
Decaid 版本：
插件版本：
场景文件：
通过项目：
失败项目及实际值：
对应 Mac JSONL：
iPad 截图或日志：
```

失败时保留精确时间、原始 hex、写类型和 Mac JSONL。优先提供“预期值 / 实际值 / 复现步骤”，不要只提供“连不上”或“没反应”。
