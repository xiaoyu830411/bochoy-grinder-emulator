(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.SimClient = api;
})(globalThis, function () {
  'use strict';

  const controllableActions = new Set([
    'powerOff', 'start', 'stop', 'setMT', 'setXD', 'setTF', 'apply',
    'setTFAndApply', 'finishRun', 'finishApply', 'override', 'advertising',
    'sessionBegin', 'sessionEnd', 'scenarioLoad', 'scenarioReset', 'faultSet',
    'disconnectCentral', 'markObservationDisconnected', 'hideObservation',
    'restoreObservation', 'restoreHiddenObservations',
  ]);

  const messages = {
    documentTitle: { zh: 'Bochoy 磨豆机模拟器', en: 'Bochoy Grinder Emulator' },
    switchLanguage: { zh: '切换为 English', en: 'Switch to Chinese' },
    eventConnecting: { zh: '正在连接事件流', en: 'Connecting to event stream' },
    eventConnected: { zh: '实时事件已连接', en: 'Live events connected' },
    eventReconnecting: { zh: '事件流断开，正在自动重连', en: 'Event stream disconnected; reconnecting' },
    eventResync: { zh: '检测到序列缺口，正在重新同步', en: 'Sequence gap detected; resynchronizing' },
    accessToken: { zh: '访问令牌', en: 'Access Token' },
    tokenPlaceholder: { zh: '仅非本机绑定需要', en: 'Required for non-loopback binding' },
    saveReconnect: { zh: '保存并重连', en: 'Save & Reconnect' },
    narrowView: { zh: '窄屏视图', en: 'Compact view' },
    controls: { zh: '控制', en: 'Controls' },
    logs: { zh: '日志', en: 'Logs' },
    deviceControl: { zh: '设备控制', en: 'Device Controls' },
    waitingSnapshot: { zh: '等待快照', en: 'Waiting for snapshot' },
    unknown: { zh: '未知', en: 'Unknown' },
    powerNoteInitial: { zh: 'Device Power 不是模拟器进程寿命。', en: 'Device Power is independent of simulator process lifetime.' },
    powerOn: { zh: '开机', en: 'Power On' },
    powerOff: { zh: '关闭磨豆机', en: 'Power Off Grinder' },
    advertising: { zh: '广播', en: 'Advertising' },
    observedSession: { zh: '观察会话', en: 'Observed Session' },
    timers: { zh: '计时器', en: 'Timers' },
    advertiseOn: { zh: '开启广播', en: 'Start Advertising' },
    advertiseOff: { zh: '停止广播', en: 'Stop Advertising' },
    protocolRegisters: { zh: '协议寄存器', en: 'Protocol Registers' },
    bigEndian: { zh: 'uint16 · 大端', en: 'uint16 · big-endian' },
    normalRunControl: { zh: '正常研磨控制', en: 'Normal Grinding Controls' },
    sharedModel: { zh: '与 BLE 共用模型', en: 'Shares the BLE model' },
    manualOption: { zh: 'manual · 手动', en: 'manual · Manual' },
    timedOption: { zh: 'timed · 定时', en: 'timed · Timed' },
    smartOption: { zh: 'smart · 智能', en: 'smart · Smart' },
    startGrinding: { zh: '启动研磨', en: 'Start Grinding' },
    stopGrinding: { zh: '停止研磨', en: 'Stop Grinding' },
    motorSettingLabel: { zh: 'MT_RPM 电机转速设定', en: 'MT_RPM Motor Speed Setting' },
    setMotor: { zh: '设置转速', en: 'Set Speed' },
    feedSettingLabel: { zh: 'XD_RPM 下豆参数', en: 'XD_RPM Feed Parameter' },
    setFeed: { zh: '设置下豆', en: 'Set Feed' },
    targetSettingLabel: { zh: 'TF_ANGLE 目标研磨度', en: 'TF_ANGLE Target Grind Setting' },
    setTarget: { zh: '设置目标', en: 'Set Target' },
    applyOnce: { zh: '单独 Apply', en: 'Apply Only' },
    setAndApply: { zh: '设置并 Apply', en: 'Set & Apply' },
    applyNontransactionNote: { zh: '“设置并 Apply”按顺序执行两次写入，不是事务；Apply 失败不会回滚 TF_ANGLE。', en: '“Set & Apply” performs two ordered writes, not a transaction; a failed Apply does not roll back TF_ANGLE.' },
    advancedOperations: { zh: '高级操作与故障注入', en: 'Advanced Operations & Fault Injection' },
    forceFinish: { zh: '强制完成', en: 'Force Completion' },
    nonProtocolBehavior: { zh: '非协议正常行为', en: 'Not normal protocol behavior' },
    characteristic: { zh: '特征', en: 'Characteristic' },
    anyUInt16: { zh: '任意 uint16', en: 'Any uint16' },
    notificationMode: { zh: '通知方式', en: 'Notification Mode' },
    executeOverride: { zh: '执行 Test Override', en: 'Execute Test Override' },
    sessionEndNote: { zh: 'session-end 只执行 Disconnect Policy，不主动断开 BLE。', en: 'session-end only applies Disconnect Policy; it does not disconnect BLE.' },
    builtInScenarios: { zh: '内置场景', en: 'Built-in Scenarios' },
    loadScenario: { zh: '加载场景', en: 'Load Scenario' },
    resetScenario: { zh: '重置当前场景', en: 'Reset Current Scenario' },
    deviceActivity: { zh: '设备活动', en: 'Device Activity' },
    notLiveInventory: { zh: '不是完整实时连接清单', en: 'Not a complete live connection inventory' },
    deviceActivityNote: { zh: 'Observed Central 来自读写和订阅观察。绿色=正在订阅；黄色=无订阅或已请求断开、断连未确认；蓝色=仅读写；灰色=人工确认已断开。别名按 central UUID 保存在当前浏览器。', en: 'Observed Centrals come from read/write and subscription callbacks. Green=subscribing; yellow=no subscriptions or disconnect requested/unconfirmed; blue=read/write only; gray=manually marked disconnected. Aliases are stored per central UUID in this browser.' },
    currentDevices: { zh: '当前设备', en: 'Current Devices' },
    historyRecords: { zh: '历史记录', en: 'History' },
    historyNote: { zh: '只有在手机端确认断开后才人工标记；普通取消订阅不会自动进入这里。', en: 'Mark a record only after confirming disconnection on the phone; ordinary unsubscription does not move it here.' },
    hiddenRecords: { zh: '已移出', en: 'Hidden' },
    hiddenNote: { zh: '移出在所有浏览器同步，不删除 JSONL、原始事件或别名，也不影响 BLE。', en: 'Hidden state syncs across browsers without deleting JSONL, raw events, or aliases, and does not affect BLE.' },
    restoreAll: { zh: '全部恢复', en: 'Restore All' },
    liveLogs: { zh: '实时日志', en: 'Live Logs' },
    logFilters: { zh: '日志筛选', en: 'Log filters' },
    kind: { zh: '类型', en: 'Kind' },
    all: { zh: '全部', en: 'All' },
    source: { zh: '来源', en: 'Source' },
    searchLogs: { zh: '搜索日志', en: 'Search logs' },
    logSearchPlaceholder: { zh: '搜索消息、特征或 faultID', en: 'Search messages, characteristics, or faultID' },
    overrideOnly: { zh: '仅 Test Override', en: 'Test Override Only' },
    clearView: { zh: '清空当前视图', en: 'Clear Current View' },
    acceptanceLimits: { zh: '验收边界', en: 'Acceptance Boundaries' },
    notificationTruth: { zh: '通知提交不代表手机已收到；取消订阅不等于 Link Loss。', en: 'Notification submission does not prove phone receipt; unsubscription is not Link Loss.' },
    eventRetentionTruth: { zh: '磁盘 JSONL 是持久记录，此处仅保留最近 500 条事件。SSE heartbeat 不改变 BLE 状态。', en: 'On-disk JSONL is persistent; this view keeps the latest 500 events. SSE heartbeat does not change BLE state.' },
    poweredOnState: { zh: '已开机', en: 'Powered On' },
    poweredOffState: { zh: '已关机', en: 'Powered Off' },
    powerNoteOn: { zh: 'Device Power 与 System State、Observed Session End 和模拟器进程寿命不同。', en: 'Device Power is distinct from System State, Observed Session End, and simulator process lifetime.' },
    powerNoteOff: { zh: '已关机：GATT 已移除，监控和日志继续；只有开机可用，断连未确认。', en: 'Powered off: GATT is removed; monitoring and logs continue. Only power-on is available; disconnection is unconfirmed.' },
    characteristicCount: { zh: '{count} 特征', en: '{count} characteristics' },
    advertisingActive: { zh: '广播中', en: 'Advertising' },
    advertisingStarting: { zh: '启动中', en: 'Starting' },
    advertisingRequested: { zh: '已请求，等待广播', en: 'Requested; waiting' },
    advertisingStopped: { zh: '已停止', en: 'Stopped' },
    idle: { zh: '空闲', en: 'Idle' },
    noPendingApply: { zh: '无 pending Apply', en: 'No pending Apply' },
    sessionActive: { zh: '活动（推断）', en: 'Active (inferred)' },
    sessionInactive: { zh: '未活动', en: 'Inactive' },
    timersPaused: { zh: '已暂停', en: 'Paused' },
    timersRunning: { zh: '运行', en: 'Running' },
    noFaultRules: { zh: '当前场景没有故障规则', en: 'The current scenario has no fault rules' },
    disable: { zh: '禁用', en: 'Disable' },
    enable: { zh: '启用', en: 'Enable' },
    unnamedDevice: { zh: '未命名设备', en: 'Unnamed Device' },
    activitySubscribe: { zh: '订阅', en: 'Subscribe' },
    activityUnsubscribe: { zh: '取消订阅', en: 'Unsubscribe' },
    activityRead: { zh: '读取', en: 'Read' },
    activityWrite: { zh: '写入', en: 'Write' },
    unknownActivity: { zh: '未知活动', en: 'Unknown activity' },
    none: { zh: '无', en: 'None' },
    recentActivity: { zh: '最近活动 {time} · {activity}', en: 'Last activity {time} · {activity}' },
    previousSubscriptions: { zh: '断开前订阅记录：{subscriptions}', en: 'Subscriptions before disconnect: {subscriptions}' },
    currentSubscriptions: { zh: '订阅特征：{subscriptions}', en: 'Subscribed characteristics: {subscriptions}' },
    details: { zh: '详情', en: 'Details' },
    centralUUID: { zh: 'Central UUID：{id}', en: 'Central UUID: {id}' },
    observationRecordID: { zh: '观察记录 ID：{id}', en: 'Observation Record ID: {id}' },
    firstActivity: { zh: '首次活动：{time}', en: 'First activity: {time}' },
    aliasPlaceholder: { zh: '浏览器本地别名', en: 'Browser-local alias' },
    centralAliasAria: { zh: 'Central {id} 的别名', en: 'Alias for Central {id}' },
    saveAlias: { zh: '保存别名', en: 'Save Alias' },
    requestDisconnect: { zh: '请求断开（不保证 Link Loss）', en: 'Request Disconnect (Link Loss Not Guaranteed)' },
    markDisconnected: { zh: '人工确认已断开', en: 'Manually Mark Disconnected' },
    hideRecord: { zh: '移出列表', en: 'Hide from List' },
    restoreRecord: { zh: '恢复此条', en: 'Restore This Record' },
    noCurrentDevices: { zh: '尚未观察到当前设备活动。', en: 'No current device activity observed.' },
    noHistory: { zh: '没有人工确认断开的历史记录。', en: 'No manually disconnected history.' },
    noHidden: { zh: '没有已移出记录。', en: 'No hidden records.' },
    recordCount: { zh: '{count} 条', en: '{count} record(s)' },
    integerRange: { zh: '{id} 必须是 0…{maximum} 的整数', en: '{id} must be an integer from 0 to {maximum}' },
    executingAction: { zh: '正在执行 {action}…', en: 'Executing {action}…' },
    controlRequestFailed: { zh: '控制请求失败', en: 'Control request failed' },
    snapshotUnavailable: { zh: '快照不可用', en: 'Snapshot unavailable' },
    eventCount: { zh: '{visible} / {total} 条', en: '{visible} / {total} events' },
    centralSubscribing: { zh: '正在订阅', en: 'Subscribing' },
    centralDisconnectRequested: { zh: '已请求断开 · 断连未确认', en: 'Disconnect Requested · Unconfirmed' },
    centralNoSubscriptions: { zh: '无订阅 · 断连未确认', en: 'No Subscriptions · Disconnect Unconfirmed' },
    centralReadWriteOnly: { zh: '仅观察到读写', en: 'Read/Write Activity Only' },
    centralManualDisconnect: { zh: '人工确认已断开', en: 'Manually Marked Disconnected' },
    centralSubscriptionDetail: { zh: '正在订阅 {count} 项 · {session}', en: 'Subscribing to {count} characteristic(s) · {session}' },
    inferredSessionActive: { zh: '推断会话活动', en: 'inferred session active' },
    inferredSessionInactive: { zh: '推断会话未活动', en: 'inferred session inactive' },
    registerMotorTitle: { zh: '电机转速设定', en: 'Motor Speed Setting' },
    registerMotorExplanation: { zh: '0–1500；设定/寄存器值，不是刀盘实测转速。', en: '0–1500; a setting/register value, not a measured burr speed.' },
    registerFeedTitle: { zh: '下豆参数', en: 'Feed Parameter' },
    registerFeedExplanation: { zh: '0–150；机械对象和物理单位待厂家确认。', en: '0–150; mechanical target and physical unit require manufacturer confirmation.' },
    registerBootTitle: { zh: '动作命令', en: 'Action Command' },
    registerBootExplanation: { zh: '最后已定义的动作命令；不代表动作已经完成。', en: 'Last defined action command; does not mean the action has completed.' },
    registerSystemTitle: { zh: '系统状态', en: 'System State' },
    registerSystemExplanation: { zh: '协议系统状态；未定义值不得视为安全空闲。', en: 'Protocol system state; undefined values must not be treated as safely idle.' },
    registerServoTitle: { zh: '当前研磨度', en: 'Current Grind Setting' },
    registerServoExplanation: { zh: '0–1500；协议当前寄存器值，不证明机械到位。', en: '0–1500; current protocol register value, not proof of mechanical position.' },
    registerTargetTitle: { zh: '目标研磨度', en: 'Target Grind Setting' },
    registerTargetExplanation: { zh: '0–1500；Apply 捕获目标，单独修改不立即改变当前研磨度。', en: '0–1500; Apply captures the target. Changing it alone does not immediately change the current grind setting.' },
    invalidValue: { zh: '值无效', en: 'Invalid value' },
    systemIdle: { zh: '0 = 空闲', en: '0 = Idle' },
    systemGrinding: { zh: '1 = 设备动作中（电机运行或 Apply 调磨）', en: '1 = Device Active (motor running or Apply)' },
    systemUndefined: { zh: '{value} = 未定义 / Test Override；不能猜成其他状态', en: '{value} = Undefined / Test Override; do not infer another state' },
    bootManual: { zh: '手动启动', en: 'Manual Start' },
    bootTimed: { zh: '定时启动', en: 'Timed Start' },
    bootSmart: { zh: '智能启动', en: 'Smart Start' },
    bootStop: { zh: '停止', en: 'Stop' },
    bootInitial: { zh: '0 = 初始占位，无动作命令', en: '0 = Initial placeholder; no action command' },
    bootUndefined: { zh: '{value} = 未定义 / Test Override；不是有效动作命令', en: '{value} = Undefined / Test Override; not a valid action command' },
    feedbackPowerOn: { zh: '磨豆机已开机；已请求恢复广播', en: 'Grinder powered on; advertising requested' },
    feedbackPowerOff: { zh: '磨豆机已关机；断连未确认', en: 'Grinder powered off; disconnection unconfirmed' },
    feedbackStart: { zh: '启动命令已处理', en: 'Start command processed' },
    feedbackStop: { zh: '停止命令已处理', en: 'Stop command processed' },
    feedbackSetMotor: { zh: '电机转速设定已更新', en: 'Motor speed setting updated' },
    feedbackSetFeed: { zh: '下豆参数已更新', en: 'Feed parameter updated' },
    feedbackSetTarget: { zh: '目标研磨度已更新', en: 'Target grind setting updated' },
    feedbackApply: { zh: 'Apply 已处理', en: 'Apply processed' },
    feedbackSetApply: { zh: '已写入 TF_ANGLE 并执行 Apply；两步不是事务', en: 'TF_ANGLE written, then Apply executed; not a transaction' },
    feedbackFinishRun: { zh: '已请求强制完成 Run', en: 'Forced Run completion requested' },
    feedbackFinishApply: { zh: '已请求强制完成 Apply', en: 'Forced Apply completion requested' },
    feedbackOverride: { zh: 'Test Override 已执行', en: 'Test Override applied' },
    feedbackAdvertisingOn: { zh: '已请求开启广播', en: 'Advertising requested' },
    feedbackAdvertisingOff: { zh: '广播已停止；现有 BLE 链路未因此断开', en: 'Advertising stopped; existing BLE links are not disconnected' },
    feedbackSessionBegin: { zh: '测试会话已开始', en: 'Test session began' },
    feedbackSessionEnd: { zh: '仅模拟 Observed Session End；未断开 BLE', en: 'Observed Session End simulated only; BLE was not disconnected' },
    feedbackScenario: { zh: '场景操作已完成', en: 'Scenario operation completed' },
    feedbackFault: { zh: '故障开关已更新', en: 'Fault setting updated' },
    feedbackDisconnect: { zh: '已发出 Disconnect Request；单设备断连未确认，Link Loss 也未确认', en: 'Disconnect Request issued; per-central disconnection and Link Loss are unconfirmed' },
    feedbackMarkDisconnected: { zh: '已人工标记断开；不代表收到系统 Link Loss 回调', en: 'Manually marked disconnected; no system Link Loss callback is implied' },
    feedbackHide: { zh: '已在所有浏览器移出；事件和 BLE 状态不变', en: 'Hidden in all browsers; events and BLE state unchanged' },
    feedbackRestore: { zh: '已在所有浏览器恢复此记录', en: 'Observation restored in all browsers' },
    feedbackRestoreAll: { zh: '已在所有浏览器恢复 {count} 条移出记录', en: 'Restored {count} hidden observation(s) in all browsers' },
    feedbackDeviceOff: { zh: '磨豆机已关机', en: 'Device is powered off' },
    feedbackWriteRejected: { zh: '写入被故障注入拒绝，模型未改变；ATT={att} · fault={fault}', en: 'Write rejected by injected fault; model unchanged; ATT={att} · fault={fault}' },
    feedbackApplyRejected: { zh: 'Apply 失败；TF_ANGLE 修改已保留（非事务）；ATT={att} · fault={fault}', en: 'Apply failed; TF_ANGLE change retained (non-transactional); ATT={att} · fault={fault}' },
    feedbackUnknownRecord: { zh: '未知观察记录', en: 'Unknown observation record' },
    feedbackUnknownCentral: { zh: '未知 Observed Central', en: 'Unknown Observed Central' },
    feedbackUnknownScenario: { zh: '未知场景', en: 'Unknown scenario' },
    feedbackUnknownFault: { zh: '未知故障 ID', en: 'Unknown fault ID' },
    feedbackHideRequiresManual: { zh: '必须先人工确认断开，才能移出记录', en: 'Confirm disconnection manually before hiding this record' },
    feedbackConflict: { zh: '当前状态不允许此操作', en: 'The current state does not allow this action' },
    feedbackInvalidRequest: { zh: '控制请求参数无效', en: 'Invalid control request parameters' },
    feedbackAuthentication: { zh: '访问令牌无效或请求来源被拒绝', en: 'Invalid access token or rejected request origin' },
    feedbackActionFailed: { zh: '操作失败（HTTP {status}）', en: 'Action failed (HTTP {status})' },
    feedbackGenericSuccess: { zh: '操作已完成', en: 'Action completed' },
  };

  function normalizeLanguage(language) {
    return language === 'en' || language === 'en-US' ? 'en' : 'zh';
  }

  function dateLocale(language) {
    return normalizeLanguage(language) === 'en' ? 'en-US' : 'zh-CN';
  }

  function t(language, key, parameters = {}) {
    const entry = messages[key];
    const template = entry && entry[normalizeLanguage(language)] ? entry[normalizeLanguage(language)] : key;
    return template.replace(/\{([A-Za-z]+)\}/g, (match, name) => (
      Object.hasOwn(parameters, name) ? String(parameters[name]) : match
    ));
  }

  function loadLanguage(storage) {
    try {
      return normalizeLanguage(storage && storage.getItem('crystal-web-language'));
    } catch (_) {
      return 'zh';
    }
  }

  function saveLanguage(storage, language) {
    try {
      if (storage) storage.setItem('crystal-web-language', normalizeLanguage(language));
    } catch (_) {
      // Language persistence is optional; the console remains usable without storage.
    }
  }

  function isControlEnabled(snapshot, action) {
    if (!snapshot || !snapshot.device) return false;
    if (!snapshot.device.poweredOn) return action === 'powerOn';
    if (action === 'powerOn') return false;
    return controllableActions.has(action);
  }

  function mergeEvents(current, incoming, limit = 500) {
    const bySequence = new Map();
    for (const item of [...(current || []), ...(incoming || [])]) {
      if (item && Number.isSafeInteger(item.sequence)) bySequence.set(item.sequence, item);
    }
    return [...bySequence.values()]
      .sort((left, right) => left.sequence - right.sequence)
      .slice(-limit);
  }

  function applyResync(state, payload) {
    return {
      ...state,
      events: [],
      resyncCount: (state.resyncCount || 0) + 1,
      resyncReason: payload && payload.reason ? payload.reason : 'resync',
    };
  }

  function filterEvents(events, filters = {}) {
    const text = (filters.text || '').trim().toLowerCase();
    return (events || []).filter(item => {
      if (filters.kind && filters.kind !== 'all' && item.kind !== filters.kind) return false;
      if (filters.source && filters.source !== 'all' && (item.details || {}).source !== filters.source) return false;
      if (filters.overrideOnly && item.testOverride !== true) return false;
      if (!text) return true;
      const details = Object.values(item.details || {}).join(' ');
      const haystack = [item.message, item.kind, item.characteristic, item.faultID, details]
        .filter(Boolean).join(' ').toLowerCase();
      return haystack.includes(text);
    });
  }

  function formatUInt16(value) {
    if (!Number.isInteger(value) || value < 0 || value > 65535) return '—';
    return `${value} · 0x${value.toString(16).toUpperCase().padStart(4, '0')}`;
  }

  function parseIntegerInput(text, maximum) {
    if (typeof text !== 'string' || !/^\d+$/.test(text)) return null;
    const value = Number(text);
    return Number.isSafeInteger(value) && value <= maximum ? value : null;
  }

  function eventsURL(token) {
    return token ? `/api/events?token=${encodeURIComponent(token)}` : '/api/events';
  }

  function loadToken(storage) {
    try {
      const value = storage && storage.getItem('crystal-web-token');
      return typeof value === 'string' ? value : '';
    } catch (_) {
      return '';
    }
  }

  function saveToken(storage, token) {
    try {
      if (!storage) return;
      if (token) storage.setItem('crystal-web-token', token);
      else storage.removeItem('crystal-web-token');
    } catch (_) {
      // Monitoring remains usable when browser storage is unavailable.
    }
  }

  function loadAliases(storage) {
    try {
      const parsed = JSON.parse(storage && storage.getItem('crystal-central-aliases'));
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
      return Object.fromEntries(Object.entries(parsed).filter(
        ([id, alias]) => id && typeof alias === 'string' && alias.trim(),
      ));
    } catch (_) {
      return {};
    }
  }

  function saveAlias(storage, id, alias) {
    const aliases = { ...loadAliases(storage) };
    const label = typeof alias === 'string' ? alias.trim() : '';
    if (label) aliases[id] = label;
    else delete aliases[id];
    try {
      if (storage) storage.setItem('crystal-central-aliases', JSON.stringify(aliases));
    } catch (_) {
      // Aliases are a convenience only, never device identity.
    }
    return aliases;
  }

  function centralPresentation(central, language = 'zh') {
    const record = central || {};
    const subscriptions = Array.isArray(record.subscriptions) ? record.subscriptions : [];
    if (record.manuallyDisconnected) {
      return {
        tone: 'gray', label: t(language, 'centralManualDisconnect'), isHistory: true,
        canHide: !record.hidden, canRestore: Boolean(record.hidden),
      };
    }
    if (record.disconnectRequested) {
      return {
        tone: 'yellow', label: t(language, 'centralDisconnectRequested'), isHistory: false,
        canHide: false, canRestore: false,
      };
    }
    if (subscriptions.length > 0) {
      return {
        tone: 'green', label: t(language, 'centralSubscribing'), isHistory: false,
        canHide: false, canRestore: false,
      };
    }
    if (record.hasObservedSubscription || record.lastActivity === 'unsubscribe') {
      return {
        tone: 'yellow', label: t(language, 'centralNoSubscriptions'), isHistory: false,
        canHide: false, canRestore: false,
      };
    }
    return {
      tone: 'blue', label: t(language, 'centralReadWriteOnly'), isHistory: false,
      canHide: false, canRestore: false,
    };
  }

  function centralStatus(central, language = 'zh') {
    const presentation = centralPresentation(central, language);
    const count = central && Array.isArray(central.subscriptions) ? central.subscriptions.length : 0;
    if (presentation.tone === 'green') {
      return t(language, 'centralSubscriptionDetail', {
        count,
        session: t(language, central.inferredSessionActive ? 'inferredSessionActive' : 'inferredSessionInactive'),
      });
    }
    return presentation.label;
  }

  function groupObservations(records) {
    const byRecentActivity = (left, right) => {
      const leftTime = Date.parse(left.lastSeen || '') || 0;
      const rightTime = Date.parse(right.lastSeen || '') || 0;
      return rightTime - leftTime || String(left.recordID).localeCompare(String(right.recordID));
    };
    const visible = (records || []).filter(record => record && !record.hidden);
    const hidden = (records || []).filter(record => record && record.hidden).sort(byRecentActivity);
    return {
      current: visible.filter(record => !record.manuallyDisconnected).sort(byRecentActivity),
      history: visible.filter(record => record.manuallyDisconnected).sort(byRecentActivity),
      hidden,
      hiddenCount: hidden.length,
    };
  }

  const registerDefinitions = {
    mtRPM: { name: 'MT_RPM', title: 'registerMotorTitle', explanation: 'registerMotorExplanation' },
    xdRPM: { name: 'XD_RPM', title: 'registerFeedTitle', explanation: 'registerFeedExplanation' },
    bootSign: { name: 'BOOT_SIGN', title: 'registerBootTitle', explanation: 'registerBootExplanation' },
    sysState: { name: 'SYS_STATE', title: 'registerSystemTitle', explanation: 'registerSystemExplanation' },
    servoAngle: { name: 'SERVO_ANGLE', title: 'registerServoTitle', explanation: 'registerServoExplanation' },
    tfAngle: { name: 'TF_ANGLE', title: 'registerTargetTitle', explanation: 'registerTargetExplanation' },
  };

  function registerValueMeaning(key, value, language) {
    if (!Number.isInteger(value) || value < 0 || value > 65535) return t(language, 'invalidValue');
    if (key === 'sysState') {
      if (value === 0) return t(language, 'systemIdle');
      if (value === 1) return t(language, 'systemGrinding');
      return t(language, 'systemUndefined', { value });
    }
    if (key === 'bootSign') {
      const commands = { 1: 'bootManual', 2: 'bootTimed', 3: 'bootSmart', 4: 'bootStop' };
      if (value === 5) return '5 = Apply';
      if (commands[value]) return `${value} = ${t(language, commands[value])}`;
      if (value === 0) return t(language, 'bootInitial');
      return t(language, 'bootUndefined', { value });
    }
    return '';
  }

  function describeRegister(key, value, language = 'zh') {
    const definition = registerDefinitions[key];
    if (!definition) throw new RangeError(`Unknown register: ${key}`);
    return {
      key,
      name: definition.name,
      title: t(language, definition.title),
      decimal: value,
      hex: Number.isInteger(value) && value >= 0 && value <= 65535
        ? `0x${value.toString(16).toUpperCase().padStart(4, '0')}` : '—',
      explanation: t(language, definition.explanation),
      valueMeaning: registerValueMeaning(key, value, language),
    };
  }

  function registerCards(registers, language = 'zh') {
    return Object.keys(registerDefinitions).map(key => describeRegister(key, (registers || {})[key], language));
  }

  function controlFeedback(language, action, status, body = {}) {
    const message = body.message || '';
    const att = Number.isInteger(body.attStatus)
      ? `0x${body.attStatus.toString(16).toUpperCase().padStart(2, '0')}` : '—';
    const parameters = { status, att, fault: body.faultID || '—' };
    if (status === 0) return t(language, 'controlRequestFailed');
    if (!body.ok || status < 200 || status >= 300) {
      if (status === 422) {
        return t(language, action === 'setTFAndApply' ? 'feedbackApplyRejected' : 'feedbackWriteRejected', parameters);
      }
      if (message === 'Device Powered Off') return t(language, 'feedbackDeviceOff');
      if (message === 'Unknown Observation Record') return t(language, 'feedbackUnknownRecord');
      if (message === 'Unknown Observed Central') return t(language, 'feedbackUnknownCentral');
      if (message === 'Unknown Scenario') return t(language, 'feedbackUnknownScenario');
      if (message === 'Unknown fault id') return t(language, 'feedbackUnknownFault');
      if (message === 'Manual disconnection confirmation required before hiding') return t(language, 'feedbackHideRequiresManual');
      if (status === 401 || status === 403) return t(language, 'feedbackAuthentication');
      if (status === 409) return t(language, 'feedbackConflict');
      if (status === 400) return t(language, 'feedbackInvalidRequest');
      return t(language, 'feedbackActionFailed', parameters);
    }
    if (action === 'restoreHiddenObservations') {
      const count = message.match(/Restored (\d+)/);
      return t(language, 'feedbackRestoreAll', { count: count ? count[1] : 0 });
    }
    if (action === 'advertising') {
      return t(language, message.includes('existing BLE links') ? 'feedbackAdvertisingOff' : 'feedbackAdvertisingOn');
    }
    const successKeys = {
      powerOn: 'feedbackPowerOn', powerOff: 'feedbackPowerOff', start: 'feedbackStart', stop: 'feedbackStop',
      setMT: 'feedbackSetMotor', setXD: 'feedbackSetFeed', setTF: 'feedbackSetTarget', apply: 'feedbackApply',
      setTFAndApply: 'feedbackSetApply', finishRun: 'feedbackFinishRun', finishApply: 'feedbackFinishApply',
      override: 'feedbackOverride', sessionBegin: 'feedbackSessionBegin', sessionEnd: 'feedbackSessionEnd',
      scenarioLoad: 'feedbackScenario', scenarioReset: 'feedbackScenario', faultSet: 'feedbackFault',
      disconnectCentral: 'feedbackDisconnect', markObservationDisconnected: 'feedbackMarkDisconnected',
      hideObservation: 'feedbackHide', restoreObservation: 'feedbackRestore',
    };
    return t(language, successKeys[action] || 'feedbackGenericSuccess');
  }

  return {
    isControlEnabled,
    mergeEvents,
    applyResync,
    filterEvents,
    formatUInt16,
    parseIntegerInput,
    eventsURL,
    loadToken,
    saveToken,
    loadAliases,
    saveAlias,
    centralStatus,
    centralPresentation,
    groupObservations,
    describeRegister,
    registerCards,
    loadLanguage,
    saveLanguage,
    normalizeLanguage,
    dateLocale,
    t,
    controlFeedback,
  };
});
