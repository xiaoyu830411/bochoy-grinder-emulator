# Web 控制台与真机验收清单

本清单区分自动化 HTTP/SSE 验证、浏览器视觉检查和真实 BLE 验收。任何一项 HTTP 测试通过，都不代表手机已经收到通知或确认断连。

## 1. 启动

仅本机浏览器：

```bash
bash Scripts/run.sh --web 127.0.0.1:8080 --json-log Logs/manual-web.jsonl
```

局域网浏览器：

```bash
CRYSTAL_WEB_TOKEN='replace-with-a-long-random-token' bash Scripts/run.sh --web 0.0.0.0:8080 --json-log Logs/manual-web-lan.jsonl
```

打开终端显示的地址。不要从同一台 Mac 自广播、自扫描、自连接来做 BLE 验收；central 必须是另一台手机或平板。

## 2. 浏览器视觉与通用行为

- [ ] 桌面左控制、右日志各占一半，两个区域可以独立滚动。
- [ ] 缩窄窗口后出现“控制 / 日志”标签页，不出现整页横向滚动。
- [ ] 窄屏仍能输入并保存局域网访问令牌。
- [ ] 六个寄存器均显示中文标题、原始寄存器名、十进制和四位 hex，以及直接可见的简短解释；未知或无效值不伪装成合法 uint16。
- [ ] MT 显示“电机转速设定”，明确不是刀盘实测转速；XD 显示“下豆参数”，正常控制按钮为“设置下豆”，不再误写为研磨度。
- [ ] BOOT 1/2/3/4/5 分别解释为手动启动/定时启动/智能启动/停止/Apply；SYS 0=空闲、1=研磨中；其他动态值标为“未定义 / Test Override”，不猜成有效命令或空闲。
- [ ] SERVO 是当前研磨度寄存器值但不证明机械到位；TF 是 Apply 捕获的目标，单独修改不立即改变当前研磨度；卡片不自行添加物理单位。
- [ ] 日志可按类型、来源、文本和 Test Override 筛选；“清空当前视图”不删除 JSONL。
- [ ] 页面没有“退出模拟器”操作，正常控制与 Test Override 分区清晰。
- [ ] 刷新页面后重新获得 snapshot 和最近事件；别名保留，访问令牌按 sessionStorage 语义保存。
- [ ] 首次打开默认中文；切换 English 后标题、按钮、动态状态、寄存器解释、操作反馈和日期变为英文，原始日志仍保持原文。
- [ ] 刷新后保留最后选择的界面语言；切换语言不会清空日志、修改寄存器或影响 BLE。
- [ ] 模拟器进程若重启，手动刷新页面，避免把上一进程的 sequence 与新进程混合。

## 3. 正常控制

- [ ] manual 启动：Run 显示 manual，`SYS_STATE=1`；停止后回到 0。
- [ ] timed / smart 启动：默认 5 秒自动结束；对应特殊场景按场景定义执行。
- [ ] 设置 MT=1200、XD=88、TF=1000，寄存器与 hex 同步变化。
- [ ] 单独 Apply 后 SERVO 等于 Apply 时捕获的 TF。
- [ ] “设置并 Apply”依次完成两步，日志来源均为 `web`。
- [ ] CLI 修改寄存器后 Web 可见；Web 修改后 CLI `status` 可见。
- [ ] 广播 off 不声称现有 BLE 链路断开；on 只表示请求恢复广播。
- [ ] session-end 只执行 Disconnect Policy，日志不声称 Link Loss。

## 4. Override、场景和故障

- [ ] Test Override 接受 0 与 65535，必须显式选择 notify 或 quiet，并带 `TEST_OVERRIDE` 标记。
- [ ] quiet Override 更新通知去重基线但不提交通知。
- [ ] 七个内置场景均可选择；Web 没有任意路径加载入口。
- [ ] 活动会话或已知订阅者阻止场景加载/重置。
- [ ] `delayed-apply` 中 Apply 保持 pending，`apply-finish` 使用捕获目标完成。
- [ ] 故障开关即时反映；切换会重置该规则计数。
- [ ] 注入 `writeError` 时 HTTP 422 包含原始 ATT status/faultID，模型不被该写修改。
- [ ] “设置并 Apply”第二步失败时，TF 不回滚，页面明确提示非事务结果。
- [ ] `responseDelay` 不延迟 Web HTTP 控制；它仍只作用于真实 ATT。
- [ ] `terminateProcess` 故障仍以退出码 70 结束进程；这不是普通 Web 退出按钮。

## 5. Device Power

- [ ] 关机后页面显示“已关机”，停止广播并移除 GATT；Run/Apply 取消，`SYS_STATE=0`。
- [ ] MT/XD/TF/SERVO/BOOT 等设置保留。
- [ ] 除开机外所有页面设备控制禁用；直接 API 请求也返回 HTTP 409 `Device Powered Off`。
- [ ] 监控、日志、筛选和别名在关机后仍可使用。
- [ ] 日志只显示 Disconnect Request / 断连未确认，不显示“手机已断连”。
- [ ] 开机创建全新 GATT 服务并默认恢复广播，即使关机前执行过广播 off。
- [ ] 开机进入空闲，保留设置，不恢复关机前 Run/Apply。
- [ ] 关机状态 CLI 显式 Test Override 仍可作为特殊测试通道；场景加载/重置仍被拒绝。

## 6. 设备活动、人工确认与主动断开

用 iPhone、Android 或其他独立 central：

- [ ] 多个 central 的订阅、取消订阅、读或写可以同时出现在“当前设备”；卡片突出别名、中文状态、最近活动时间和订阅特征。
- [ ] 完整 central UUID、独立观察记录 ID、首次活动位于可展开“详情”；别名跟随 central UUID，同一设备的多个历史记录共享别名。
- [ ] 正在订阅为绿色；无订阅或已请求断开但未确认为黄色；仅观察到读写为蓝色；用户根据手机端人工确认已断开后为灰色。
- [ ] 取消订阅只减少订阅记录，不自动写成 Link Loss、不自动变灰，也不新建观察记录；session-begin/session-end 同样不新建。
- [ ] 人工确认断开的记录进入默认折叠的历史记录；只有这种灰色记录显示“移出列表”，活动记录不能直接移出。
- [ ] 移出后所有已打开浏览器同步隐藏；JSONL、原始事件、别名和 BLE 状态保持不变。
- [ ] “已移出 N 条”中可恢复单条或全部恢复，恢复同步到所有浏览器；恢复只改变展示状态，不把旧记录复活成当前活动。
- [ ] 人工断开的设备再次出现读、写或订阅活动时创建新记录，旧记录保持灰色或隐藏；新记录后续活动持续归入同一记录，不是每个事件一条记录。
- [ ] 点击“请求断开”后记录为断开未确认，日志明确 best-effort / unconfirmed；页面不提供由系统自动确认 Link Loss 的假结论。
- [ ] 在手机端记录实际表现：仍连接、断开、服务缓存或需要重新发现，均如实记录。
- [ ] 不把 CoreBluetooth 缺少单 central force-disconnect API 的实现描述为精确单设备断连保证；多设备是否更容易断连仍是实机观察假设，不是已确认根因。

## 7. 真实 BLE 联合验收

- [ ] nRF Connect / LightBlue 能发现预期 CRYSTAL 名称，直接 CONNECT，不进行系统 Pair/Bond。
- [ ] 服务发现核对主服务和六个特征 UUID。
- [ ] Web 启动/停止/参数/Apply 的真实通知在手机端可见；注意 ATT 写响应与动作完成不同。
- [ ] `notification submitted to CoreBluetooth` 与手机实际收到分别记录。
- [ ] 关机后若手机仍有残留链路，真实 ATT 正常写应得到确定性错误且不改变模型；缓存显示不等于服务仍存在。
- [ ] 从手机主动断开、关闭手机蓝牙或退出进程制造真实 Link Loss，与 Observed Session End 分开记录。
- [ ] 长时间连接稳定性单独观察。此前 `bluetoothd unused` 根因未解决，本 Web 功能不作为修复验证。

## 8. 自动化回归命令

```bash
bash Scripts/test.sh
swift test -c release
bash Scripts/build.sh release
codesign --verify --verbose .build/release/bochoy-grinder-emulator
```

自动化 Web 冒烟使用独立端口、临时目录、临时 JSONL 和独立设备名，不会操作用户自己启动的模拟器。本地 Red/Green 开发日志不随公开仓库发布；浏览器与真机勾选项由人工验收填写。
