# AI Agent Development Guide

**[中文](#中文)** · **[English](#english)**

本文件是本仓库对人类与 AI 辅助贡献的共同工程约束。Claude Code 通过根目录 `CLAUDE.md` 引用本文件；其他 AI agent 应直接读取本文件，或由开发者将其内容加载为项目指令。

## 中文

### 1. 开始之前

先阅读项目事实与边界，不要只从某个函数开始猜协议：

1. [`README.md`](README.md)：构建、运行、Web 和测试入口。
2. [`docs/PROTOCOL.md`](docs/PROTOCOL.md)：CRYSTAL BLE 协议快照。该文档来自上游，不表示上游项目也使用 Claude Code 开发。
3. [`CONTEXT.md`](CONTEXT.md)：领域术语，包括 Protocol Guarantee、Simulation Assumption、Observation Record 和 Link Loss 的边界。
4. [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md)：模拟假设、CoreBluetooth 限制和安全边界。
5. 涉及场景时阅读 [`docs/SCENARIOS.md`](docs/SCENARIOS.md)；涉及真实 central 时阅读 [`docs/WEB_ACCEPTANCE.md`](docs/WEB_ACCEPTANCE.md)。

公开产品和可执行文件名为 `bochoy-grinder-emulator`。内部模块 `CrystalCore`、`CrystalWeb`、`CrystalSim`，Bundle ID `local.bocai.crystal-ble-mock`，以及 CRYSTAL 设备名和 GATT UUID 都不是可以自由重命名的装饰文本。

### 2. 环境与基线测试

需要 macOS、Swift、Node.js 和 Python 3。完整测试还需要蓝牙权限；真实 BLE 验收需要另一台手机或平板。项目没有第三方 Swift package 或 npm 依赖，不要求执行 `npm install`。

修改前运行适合任务的基线测试：

```bash
swift test
node --test Scripts/web-tests/*.test.js
```

需要验证完整本机行为时运行：

```bash
bash Scripts/test.sh
```

如果基线已经失败，先记录并区分既有失败与本任务引入的失败。不要因为失败存在就继续叠加修改，也不要擅自修复无关问题。缺少权限或工具时，明确记录未验证项，而不是声称通过。

### 3. 严格 Red–Green–Refactor

所有实现、缺陷修复以及 Swift、JavaScript、Python、Shell 变更都遵循以下顺序：

1. **Red 测试先行**：先写一个能表达目标行为的测试，实际运行并观察它因目标行为缺失而失败。未运行的测试不算 Red；既有无关失败不算本功能的 Red。
2. **最小 Green**：只写让目标测试通过的最小实现，保持现有兼容行为。
3. **重构后重跑**：只有 Green 后才重构；重构后再次运行相关测试。

不得通过删除、跳过、削弱、放宽或改写既有测试来制造 Green。测试本身有误时可以修正，但必须有独立证据并说明原因，不能只为适配新实现。

每个变更保持边界清晰。先理解 `DeviceModel`、BLE 生命周期、CLI/Web 共用控制路径和 snapshot/SSE 的所有权，不创建第二个隐式设备模型。

### 4. 协议与安全边界

- 所有寄存器值固定为 2 字节大端 `uint16`；不要把 base64 文本写入 BLE。
- `TF_ANGLE → BOOT_SIGN=5` 是两次有序写入，不是事务；Apply 失败不回滚已写入的 TF。
- `SYS_STATE=1` 表示设备动作中（电机运行或 Apply 调磨）；未定义 SYS/BOOT 值必须标为未定义，不得猜成空闲或有效命令。
- `MT_RPM` 是设定/寄存器值，不是已证实的刀盘实测转速；`XD_RPM` 的机械对象和单位仍待厂家确认。
- HTTP 成功、ATT 写响应和通知提交不证明机械动作完成或对端收到通知。
- 取消订阅、Observed Session End、Disconnect Request、停止广播和移除服务都不等于 Link Loss。
- 人工确认断开是用户输入，不是 CoreBluetooth 系统回调；隐藏观察记录不删除事件或操作 BLE。
- BLE STOP 不是紧急停止。不得把模拟器用作真实设备的人身安全联锁。
- 不用 SSE heartbeat、自动重连或伪造在线状态掩盖独立的 `bluetoothd unused` 断连问题。

详细定义以协议和 [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md) 为准；发现代码与文档矛盾时应提出并核实，不要静默扩大协议保证。

### 5. 依赖、密钥与前端约束

- 未经讨论不增加第三方 Swift package、npm 包、前端框架或本机路径依赖。
- 不提交访问令牌、真实凭据、构建产物、运行日志、`.claude/` 本机配置或 Xcode 用户数据。
- 保留 Host/Origin 校验、非 loopback token、请求大小限制和 SSE 慢客户端边界。
- Web 场景只能从固定目录选择，不增加任意文件路径加载。
- 动态 DOM 使用 `textContent` / `replaceChildren`；不要用 `innerHTML` 渲染日志、别名或服务器内容。
- Web 与 CLI 必须继续操作同一进程、同一 MainActor 上的同一模型。

### 6. 验证与报告

按变更范围运行相关测试；准备合并前运行完整入口：

```bash
bash Scripts/test.sh
```

需要 Release 验证时运行：

```bash
swift test -c release
bash Scripts/build.sh release
codesign --verify --verbose .build/release/bochoy-grinder-emulator
```

完整测试会启动真实 BLE peripheral 和独立 HTTP 端口。自动化必须使用独立设备名、端口和临时日志，不得停止或替换用户自己的模拟器进程。

完成报告必须包含：

- 变更的行为与未改变的边界。
- 实际运行的命令、真实结果和测试数量。
- Red/Green 的实际观察，而不是仅引用测试源码。
- 未运行、未验证或仍需人工验收的项目。
- 若引入故障，包含实际错误输出和所采取的处理。

不强制披露所用 AI 工具或模型名称，但贡献者必须对变更、验证和披露负责。不得编造 CI、测试、浏览器视觉或实机结果。浏览器布局、真实通知和 Link Loss 等无法自动证明的项目应保留为未验证。

### 7. 实机验收

HTTP/API 测试不能替代另一台手机或平板的 BLE 验收。按 [`docs/IPAD_ACCEPTANCE.md`](docs/IPAD_ACCEPTANCE.md) 和 [`docs/WEB_ACCEPTANCE.md`](docs/WEB_ACCEPTANCE.md) 检查扫描、服务发现、读写、订阅、通知、人工断开和重连。

真实设备上的成功或失败只记录实际观察。不要把模拟器结果扩展为 CRYSTAL 固件、机械动作或所有 central 平台的保证。

### 8. Git 与外部操作边界

- 不因为使用 AI 就自动 commit、amend 或 push；这些操作需要用户分别明确授权。
- 不强制覆盖远端，也不假设远端为空；操作前检查。
- 不操作用户自行启动的进程、服务或浏览器数据。
- 不将日志、提示词中的凭据或本机路径发送到外部服务。
- 提交信息应描述实际变更，不能用“全部测试通过”掩盖未运行的验证。

## English

This file defines shared engineering constraints for human and AI-assisted contributions. Claude Code imports it through the root `CLAUDE.md`; other AI agents should read it directly, or developers can load it as project instructions.

### 1. Before Changing Anything

Read the project facts and boundaries instead of inferring protocol behavior from an isolated function:

1. [`README.en.md`](README.en.md): build, run, Web, and test entry points.
2. [`docs/PROTOCOL.md`](docs/PROTOCOL.md): the vendored CRYSTAL BLE protocol snapshot, which remains in Chinese. Its upstream origin does not imply that the upstream project used Claude Code.
3. [`CONTEXT.md`](CONTEXT.md): domain vocabulary, including Protocol Guarantee, Simulation Assumption, Observation Record, and Link Loss boundaries.
4. [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md): simulation assumptions, CoreBluetooth limitations, and safety boundaries.
5. For scenario work, read [`docs/SCENARIOS.md`](docs/SCENARIOS.md). For real-central work, read [`docs/WEB_ACCEPTANCE.md`](docs/WEB_ACCEPTANCE.md).

The public product and executable are named `bochoy-grinder-emulator`. The internal modules `CrystalCore`, `CrystalWeb`, and `CrystalSim`, the bundle identifier `local.bocai.crystal-ble-mock`, and CRYSTAL device names and GATT UUIDs are intentional identities, not decorative text available for arbitrary renaming.

### 2. Environment and Baseline Tests

The project requires macOS, Swift, Node.js, and Python 3. The complete suite also needs Bluetooth permission; real BLE acceptance requires another phone or tablet. There are no third-party Swift packages or npm dependencies, and `npm install` is not required.

Run baseline tests appropriate to the task before editing:

```bash
swift test
node --test Scripts/web-tests/*.test.js
```

For complete local behavioral verification:

```bash
bash Scripts/test.sh
```

If the baseline already fails, record and distinguish existing failures from task-introduced failures. Do not stack changes on top of unexplained failures or silently fix unrelated issues. When permissions or tools are unavailable, report the unverified items instead of claiming success.

### 3. Strict Red–Green–Refactor

Every implementation and bug fix, including Swift, JavaScript, Python, and Shell changes, follows this sequence:

1. **Red first**: write a test expressing the target behavior, run it, and observe failure caused by the missing behavior. An unrun test is not Red, and an unrelated existing failure is not evidence for this feature.
2. **Minimal Green**: add only the minimal implementation needed to pass while preserving existing compatible behavior.
3. **Rerun after refactoring**: refactor only while Green, then run the relevant tests again.

Never delete, skip, weaken, or rewrite existing tests merely to manufacture Green. A genuinely incorrect test can be corrected with independent evidence and an explanation, not simply to accommodate a new implementation.

Keep each change narrowly scoped. Understand the ownership of `DeviceModel`, BLE lifecycle, the shared CLI/Web control path, and snapshot/SSE before changing them. Do not create a second implicit device model.

### 4. Protocol and Safety Boundaries

- Every register value is a fixed two-byte big-endian `uint16`; never write base64 text to BLE.
- `TF_ANGLE → BOOT_SIGN=5` is two ordered writes, not a transaction. A failed Apply does not roll back TF.
- `SYS_STATE=1` means device active (motor running or Apply in progress). Undefined SYS/BOOT values must be labeled undefined, never inferred as idle or a valid command.
- `MT_RPM` is a setting/register value, not a proven measured burr speed. The mechanical target and unit of `XD_RPM` still require manufacturer confirmation.
- HTTP success, an ATT write response, and notification submission do not prove mechanical completion or peer receipt.
- Unsubscription, Observed Session End, Disconnect Request, stopping advertising, and removing services are not Link Loss.
- Manual disconnect confirmation is user input, not a CoreBluetooth callback. Hiding an observation record neither deletes events nor operates on BLE.
- BLE STOP is not an emergency stop. Never use this simulator as a personal-safety interlock for real equipment.
- Do not use SSE heartbeat, automatic reconnect, or fabricated presence to conceal the separate `bluetoothd unused` disconnect issue.

The protocol and [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md) are the detailed references. If code and documentation disagree, surface and investigate the contradiction instead of silently expanding protocol guarantees.

### 5. Dependencies, Secrets, and Frontend Constraints

- Do not add third-party Swift packages, npm packages, frontend frameworks, or local-path dependencies without discussion.
- Never commit access tokens, real credentials, build products, runtime logs, local `.claude/` configuration, or Xcode user state.
- Preserve Host/Origin validation, non-loopback tokens, request-size limits, and slow-client SSE boundaries.
- Web scenarios must come from the fixed catalog; do not introduce arbitrary file-path loading.
- Use `textContent` and `replaceChildren` for dynamic DOM. Never use `innerHTML` for logs, aliases, or server content.
- Web and CLI must continue operating on the same model on the same MainActor in one process.

### 6. Verification and Reporting

Run tests relevant to the change and use the complete entry point before preparing a merge:

```bash
bash Scripts/test.sh
```

For Release verification:

```bash
swift test -c release
bash Scripts/build.sh release
codesign --verify --verbose .build/release/bochoy-grinder-emulator
```

The complete suite starts a real BLE peripheral and an isolated HTTP port. Automation must use isolated device names, ports, and temporary logs and must not stop or replace a user's simulator process.

Completion reports must include:

- Changed behavior and boundaries intentionally left unchanged.
- Commands actually run, actual results, and test counts.
- Observed Red/Green evidence rather than references to test source alone.
- Tests not run, unverified behavior, and remaining manual acceptance.
- Actual error output and the action taken when a failure occurs.

Contributors are not required to disclose an AI tool or model name, but they remain responsible for changes, verification, and disclosure. Never fabricate CI, test, browser-visual, or real-device results. Behavior that automation cannot prove, including browser layout, real notification receipt, and Link Loss, must remain explicitly unverified.

### 7. Real-Device Acceptance

HTTP/API tests are not a substitute for BLE acceptance with another phone or tablet. Follow [`docs/IPAD_ACCEPTANCE.md`](docs/IPAD_ACCEPTANCE.md) and [`docs/WEB_ACCEPTANCE.md`](docs/WEB_ACCEPTANCE.md) for scanning, service discovery, reads/writes, subscriptions, notifications, manual disconnection, and reconnection.

Record only observed real-device outcomes. Do not generalize simulator results into guarantees about CRYSTAL firmware, mechanical motion, or every central platform.

### 8. Git and External Operation Boundaries

- Using AI never implies permission to commit, amend, or push; each operation requires explicit user authorization.
- Never force-overwrite a remote or assume it is empty; inspect it first.
- Do not operate on user-started processes, services, or browser data.
- Do not send credentials, prompt secrets, or local paths embedded in logs to external services.
- Commit messages must describe actual changes; never use “all tests passed” to conceal verification that was not run.
