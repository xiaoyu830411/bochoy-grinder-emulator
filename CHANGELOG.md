# 变更记录 / Changelog

本项目使用语义化版本。首个公开 beta 以 GitHub Pre-release 发布；本文件同时作为该版本的发布说明。

## 中文

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

[1.0.0-beta.1]: https://github.com/xiaoyu830411/bochoy-grinder-emulator/releases/tag/v1.0.0-beta.1
