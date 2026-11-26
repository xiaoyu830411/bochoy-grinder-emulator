# 变更记录 / Changelog

本项目使用语义化版本。首个公开 beta 以 GitHub Pre-release 发布；本文件同时作为该版本的发布说明。

## 中文

### [1.0.0-beta.2] — 2026-11-26

按设备方确认的真机行为修正电源与 Apply 状态语义。仍为预发布（Pre-release），仅提供源码包。

#### 行为变更

- 冷启动与默认场景初值改为 `MT=0`、`XD=0`、`TF=0`、`BOOT=0`、`SYS=0`、`SERVO=830`；`SERVO_ANGLE=830` 是设备方确认的真机冷启动上电值，其余 0 值是与观察一致的模拟器默认值。
- `SYS_STATE=1` 的语义从“研磨中”扩展为“设备动作中”，覆盖电机 Run 与 Apply 调磨。
- 写 `BOOT_SIGN=5` 且无活动 Run 时，`SYS_STATE` 立即变为 `1`，并由固定的 5 秒 Apply Auto-Idle Timer 回 `0`；该 5 秒是模拟器兜底规则，不是真机计时保证。有活动 Run 时不启动该计时。
- `BOOT_SIGN=2/3` 仍使用场景 `timedDurationMs` / `smartDurationMs`，未改为全局硬编码 5 秒；`BOOT_SIGN=1` 保持活动直到 `BOOT_SIGN=4`。
- `power on` 现在把易失寄存器 `MT/XD/TF/BOOT` 复位为 0，仅保留 `SERVO_ANGLE`，且不恢复旧 Run/Apply/计时器；`power off` 期间设置仍保留。
- SERVO Test Override 取消 pending Apply 时同时取消 Auto-Idle Timer，无活动 Run 时 `SYS_STATE` 回 `0`；显式 `SYS_STATE` Test Override 取消待执行的 Auto-Idle Timer。
- Web 控制台寄存器解释更新为“设备动作中 / Device Active”，motor 输入框默认值改为 `0`；会话暂停（Session Pause）同样冻结 Apply Auto-Idle Timer。

#### 自动化验证范围

与 beta.1 相同的发布门槛：全部 Node 测试、Debug/Release Swift 测试、Debug/Release 构建与签名校验、真实 CoreBluetooth 启动冒烟、HTTP/SSE 集成冒烟（含 Apply 5 秒回 0 轮询与暂停冻结检查、电源循环寄存器复位断言），以及对发布提交的干净克隆（clean clone）完整复验。任何门槛失败都不得创建标签或 Release。

#### 已知限制与人工验收

- 本版只发布 GitHub 自动生成的源码包，不上传本机二进制；未提供 universal binary、DMG、公证或正式签名分发流程。
- 5 秒 Apply Auto-Idle 与电源复位行为未做真机对照；实机验收仍需人工执行，实机未验证（real-device unverified）的项目不得视为已通过。
- 真机日志中的 `bluetoothd unused` 主动断连仍是独立未解决问题，本版不宣称修复。
- 浏览器视觉布局、真实通知接收与真实 Link Loss 仍未由自动化证明。
- 广播内容未变：仍只广播本地设备名，不附加 128 位主服务 UUID。

### [1.0.0-beta.1] — 2026-11-25

首个公开预发布（Pre-release），提供 macOS 原生 CRYSTAL BLE GATT 外设模拟器。

#### 功能

- 使用 CoreBluetooth 广播 `CRYSTAL-E57C`，发布六个固定 2 字节大端 `uint16` 协议特征，支持读取、带响应写和通知。
- 支持 manual/timed/smart 研磨流程、停止、目标研磨度和非事务 Apply。
- 同进程 CLI 与 Web 控制台共用同一设备模型；Web 提供中英切换、设备控制、六寄存器解释和实时日志。
- 支持多个 central、独立观察记录、人工确认断开、全局移出/恢复和重连后的新观察记录；移出不删除 JSONL 或原始事件。
- 提供七个内置场景、ATT/通知/延迟故障和显式 Test Override。
- 提供带 sequence ID、重放和重同步的 SSE，以及可选 JSONL 结构化事件。
- 新增只读 `--version`，输出 `bochoy-grinder-emulator 1.0.0-beta.1` 后立即退出，不启动 BLE、CLI 或 Web。
- 提供中英文 README、统一 AI agent 工程规范、完整 Apache License 2.0 和带来源信息的协议快照。

#### 自动化验证范围

发布门槛包括全部 Node 测试、Debug/Release Swift 测试、Debug/Release 构建与签名校验、真实 CoreBluetooth 启动冒烟、HTTP/SSE 集成冒烟，以及在不同路径对发布提交进行干净克隆后重复完整验证。任何门槛失败都不得创建标签或 Release。

#### 已知限制与人工验收

- 本版只发布 GitHub 自动生成的源码包，不上传本机二进制；未提供 universal binary、DMG、公证或正式签名分发流程。
- 当前没有 CI 状态声明。自动化不能替代另一台手机或平板的 BLE 验收。
- CoreBluetooth 没有可靠的单 central connect/disconnect 回调或公开的 per-central 强制断开 API；Disconnect Request、取消订阅、session-end 和服务移除均不证明 Link Loss。
- `MT_RPM` 是设定值而非刀盘实测转速，`XD_RPM` 的机械对象和单位仍待厂家确认；未定义 SYS/BOOT 值必须标为未定义。
- 真机日志中的 `bluetoothd unused` 主动断连仍是独立未解决问题，本版不宣称修复。
- 浏览器视觉布局、真实通知接收、真实 Link Loss 与实机验收仍需人工执行，未由自动化证明。

## English

### [1.0.0-beta.2] — 2026-11-26

Corrects power and Apply state semantics to match vendor-confirmed real-device behavior. Still a Pre-release with source archives only.

#### Behavior changes

- Cold-start and default-scenario registers are now `MT=0`, `XD=0`, `TF=0`, `BOOT=0`, `SYS=0`, `SERVO=830`. `SERVO_ANGLE=830` is the vendor-confirmed real-device power-on value; the remaining zeros are simulator defaults consistent with observation.
- `SYS_STATE=1` now means “device active”, covering both motor runs and Apply operations, instead of only “grinding”.
- Writing `BOOT_SIGN=5` with no active Run sets `SYS_STATE` to `1` immediately, and a fixed five-second Apply Auto-Idle Timer returns it to `0`. The five seconds is a simulator fallback rule, not a real-device timing guarantee. The timer never starts during an active Run.
- `BOOT_SIGN=2/3` still use the scenario `timedDurationMs` / `smartDurationMs` rather than a global hardcoded five seconds; `BOOT_SIGN=1` remains active until `BOOT_SIGN=4`.
- `power on` now resets the volatile `MT/XD/TF/BOOT` registers to zero, retains only `SERVO_ANGLE`, and never restores old Runs, Applies, or timers; settings are still preserved while powered off.
- A SERVO Test Override that cancels a pending Apply also cancels the auto-idle timer and returns `SYS_STATE` to `0` when no Run is active; an explicit `SYS_STATE` Test Override cancels a pending auto-idle timer.
- The Web console register explanation now reads “设备动作中 / Device Active”, the motor input default is `0`, and Session Pause also freezes the Apply Auto-Idle Timer.

#### Automated verification scope

The same release gates as beta.1: all Node tests, Debug and Release Swift tests, both build configurations with code-signature verification, real CoreBluetooth startup smoke tests, HTTP/SSE integration smoke tests (including polling for the five-second Apply auto-idle, pause-freeze checks, and power-cycle register-reset assertions), and a clean clone of the release commit followed by the complete verification again. No tag or Release may be created if any gate fails.

#### Known limitations and manual acceptance

- Only GitHub-generated source archives are published. No local binaries are uploaded; there is no universal binary, DMG, notarization, or production signing pipeline.
- The five-second Apply auto-idle and power-reset behavior have not been compared against a real device; real-device acceptance remains manual, and real-device unverified items must not be treated as passed.
- The `bluetoothd unused` disconnect observed in real-device logs remains a separate unresolved issue; this release does not claim to fix it.
- Browser visual layout, real notification receipt, and real Link Loss remain unverified by automation.
- Advertising is unchanged: only the local device name is broadcast, without the 128-bit primary service UUID.

### [1.0.0-beta.1] — 2026-11-25

The first public Pre-release of the native macOS CRYSTAL BLE GATT peripheral emulator.

#### Features

- Advertises `CRYSTAL-E57C` through CoreBluetooth and publishes six fixed two-byte big-endian `uint16` characteristics with reads, writes-with-response, and notifications.
- Supports manual, timed, and smart grinding flows, stop, target grind setting, and non-transactional Apply.
- Runs CLI and Web control against the same in-process device model. The Web console provides Chinese/English switching, device controls, six-register explanations, and live logs.
- Tracks multiple centrals and independent observation records, with manual disconnect confirmation, shared hide/restore, and a new observation after renewed activity. Hiding never deletes JSONL or raw events.
- Includes seven scenarios, ATT/notification/delay faults, and explicit Test Overrides.
- Provides SSE sequence IDs, replay and resynchronization, plus optional JSONL structured events.
- Adds read-only `--version`, which prints `bochoy-grinder-emulator 1.0.0-beta.1` and exits immediately without starting BLE, CLI, or Web.
- Includes Chinese and English READMEs, shared AI-agent engineering rules, the complete Apache License 2.0, and a protocol snapshot with provenance.

#### Automated verification scope

Release gates cover all Node tests, Debug and Release Swift tests, both build configurations and code-signature verification, real CoreBluetooth startup smoke tests, HTTP/SSE integration smoke tests, and a clean clone of the release commit at a different path followed by the complete verification again. No tag or Release may be created if any gate fails.

#### Known limitations and manual acceptance

- Only GitHub-generated source archives are published. No local binaries are uploaded; there is no universal binary, DMG, notarization, or production signing pipeline.
- No CI status is claimed. Automation does not replace BLE acceptance with another phone or tablet.
- CoreBluetooth has no reliable per-central connect/disconnect callback or public per-central force-disconnect API. Disconnect Request, unsubscription, session-end, and service removal do not prove Link Loss.
- `MT_RPM` is a setting, not a measured burr speed. The mechanical target and unit of `XD_RPM` still require manufacturer confirmation. Undefined SYS/BOOT values must remain explicitly undefined.
- The `bluetoothd unused` disconnect observed in real-device logs remains a separate unresolved issue; this release does not claim to fix it.
- Browser visual layout, real notification receipt, real Link Loss, and real-device acceptance remain manual and unverified by automation.

[1.0.0-beta.2]: https://github.com/xiaoyu830411/bochoy-grinder-emulator/releases/tag/v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/xiaoyu830411/bochoy-grinder-emulator/releases/tag/v1.0.0-beta.1
