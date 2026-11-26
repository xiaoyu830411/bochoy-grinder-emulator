const test = require('node:test');
const assert = require('node:assert/strict');
const Client = require('../../Sources/CrystalWeb/Web/sim-client.js');

function snapshot(poweredOn = true) {
  return {
    device: {
      poweredOn,
      registers: { mtRPM: 900, xdRPM: 60, tfAngle: 1000, servoAngle: 830, bootSign: 0, sysState: 0 },
    },
    bluetooth: { advertising: true, subscriberIDs: [] },
    centrals: [],
    availableScenarios: ['default'],
  };
}

function event(sequence, message = `event ${sequence}`, kind = 'control') {
  return { sequence, kind, message, details: {}, testOverride: false };
}

test('control matrix disables every operation except power-on while Device Power is off', () => {
  const actions = [
    'powerOn', 'powerOff', 'start', 'stop', 'setMT', 'setXD', 'setTF', 'apply',
    'setTFAndApply', 'finishRun', 'finishApply', 'override', 'advertising',
    'sessionBegin', 'sessionEnd', 'scenarioLoad', 'scenarioReset', 'faultSet', 'disconnectCentral',
    'markObservationDisconnected', 'hideObservation', 'restoreObservation', 'restoreHiddenObservations',
  ];
  for (const action of actions) {
    assert.equal(Client.isControlEnabled(snapshot(false), action), action === 'powerOn', action);
  }
  assert.equal(Client.isControlEnabled(snapshot(true), 'powerOn'), false);
  for (const action of actions.filter(action => action !== 'powerOn')) {
    assert.equal(Client.isControlEnabled(snapshot(true), action), true, action);
  }
  assert.equal(Client.isControlEnabled(null, 'powerOff'), false);
  assert.equal(Client.isControlEnabled(snapshot(true), 'quit'), false);
});

test('log merge is sequence-deduplicated, ordered and bounded to the newest 500', () => {
  const initial = [event(3), event(1), event(2)];
  assert.deepEqual(Client.mergeEvents([], initial).map(item => item.sequence), [1, 2, 3]);
  assert.deepEqual(Client.mergeEvents(initial, [event(2, 'replacement'), event(4)]).map(item => item.sequence), [1, 2, 3, 4]);
  assert.equal(Client.mergeEvents(initial, [event(2, 'replacement')])[1].message, 'replacement');
  const many = Array.from({ length: 505 }, (_, index) => event(index + 1));
  const merged = Client.mergeEvents([], many);
  assert.equal(merged.length, 500);
  assert.equal(merged[0].sequence, 6);
  assert.equal(merged[499].sequence, 505);
});

test('resync clears stale visible history and keeps the latest snapshot', () => {
  const state = { events: [event(1), event(2)], snapshot: snapshot(), resyncCount: 0 };
  const result = Client.applyResync(state, { reason: 'sequence-gap' });
  assert.deepEqual(result.events, []);
  assert.equal(result.snapshot, state.snapshot);
  assert.equal(result.resyncCount, 1);
  assert.equal(result.resyncReason, 'sequence-gap');
});

test('log filters combine kind, free text, source and Test Override without mutating input', () => {
  const events = [
    { ...event(1, 'motor written', 'write'), characteristic: 'MT_RPM', details: { source: 'web' } },
    { ...event(2, 'quiet baseline', 'override'), testOverride: true, details: { source: 'cli' } },
    { ...event(3, 'submitted to CoreBluetooth', 'notification'), details: { source: 'ble' } },
  ];
  assert.deepEqual(Client.filterEvents(events, { kind: 'write' }).map(item => item.sequence), [1]);
  assert.deepEqual(Client.filterEvents(events, { text: 'corebluetooth' }).map(item => item.sequence), [3]);
  assert.deepEqual(Client.filterEvents(events, { source: 'cli' }).map(item => item.sequence), [2]);
  assert.deepEqual(Client.filterEvents(events, { overrideOnly: true }).map(item => item.sequence), [2]);
  assert.deepEqual(Client.filterEvents(events, { text: 'mt_rpm', kind: 'write', source: 'web' }).map(item => item.sequence), [1]);
  assert.equal(events.length, 3);
});

test('uint16 formatting validates range and includes fixed-width big-endian hex', () => {
  assert.equal(Client.formatUInt16(0), '0 · 0x0000');
  assert.equal(Client.formatUInt16(900), '900 · 0x0384');
  assert.equal(Client.formatUInt16(65535), '65535 · 0xFFFF');
  assert.equal(Client.formatUInt16(-1), '—');
  assert.equal(Client.formatUInt16(65536), '—');
  assert.equal(Client.formatUInt16('900'), '—');
});

test('numeric control input rejects blank, fractional and out-of-range values instead of coercing blank to zero', () => {
  assert.equal(Client.parseIntegerInput('0', 1500), 0);
  assert.equal(Client.parseIntegerInput('001', 1500), 1);
  assert.equal(Client.parseIntegerInput('1500', 1500), 1500);
  for (const value of ['', ' ', '-1', '1501', '1.5', '0x10', 'abc']) {
    assert.equal(Client.parseIntegerInput(value, 1500), null, JSON.stringify(value));
  }
});

test('SSE URL only adds an encoded query token when one is needed', () => {
  assert.equal(Client.eventsURL(), '/api/events');
  assert.equal(Client.eventsURL(''), '/api/events');
  assert.equal(Client.eventsURL('a b/+'), `/api/events?token=${encodeURIComponent('a b/+')}`);
});

test('session token storage is optional and storage failures never break monitoring', () => {
  const values = new Map();
  const storage = {
    getItem: key => values.get(key) || null,
    setItem: (key, value) => values.set(key, value),
    removeItem: key => values.delete(key),
  };
  assert.equal(Client.loadToken(storage), '');
  Client.saveToken(storage, 'secret');
  assert.equal(Client.loadToken(storage), 'secret');
  Client.saveToken(storage, '');
  assert.equal(Client.loadToken(storage), '');
  const broken = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('denied'); }, removeItem() { throw new Error('denied'); } };
  assert.equal(Client.loadToken(broken), '');
  assert.doesNotThrow(() => Client.saveToken(broken, 'secret'));
});

test('central aliases are local browser labels, validated and resilient to corrupt storage', () => {
  const values = new Map([['crystal-central-aliases', JSON.stringify({ abc: 'iPhone' })]]);
  const storage = {
    getItem: key => values.get(key) || null,
    setItem: (key, value) => values.set(key, value),
  };
  assert.deepEqual(Client.loadAliases(storage), { abc: 'iPhone' });
  const updated = Client.saveAlias(storage, 'xyz', '  小米  ');
  assert.equal(updated.xyz, '小米');
  Client.saveAlias(storage, 'abc', '');
  assert.deepEqual(Client.loadAliases(storage), { xyz: '小米' });
  values.set('crystal-central-aliases', '{broken');
  assert.deepEqual(Client.loadAliases(storage), {});
  const broken = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('denied'); } };
  assert.deepEqual(Client.loadAliases(broken), {});
  assert.doesNotThrow(() => Client.saveAlias(broken, 'abc', 'phone'));
});

test('Observed Central descriptions report observations, never a confirmed connection or Link Loss', () => {
  const subscribed = { id: 'ABC', subscriptions: ['SYS_STATE'], inferredSessionActive: true };
  const activityOnly = { id: 'DEF', subscriptions: [], inferredSessionActive: false };
  assert.match(Client.centralStatus(subscribed), /1/);
  assert.match(Client.centralStatus(subscribed), /会话/);
  assert.match(Client.centralStatus(activityOnly), /仅观察/);
  for (const value of [subscribed, activityOnly]) {
    assert.doesNotMatch(Client.centralStatus(value), /已连接|Link Loss|断连已确认/);
  }
});

function observation(overrides = {}) {
  return {
    id: 'CENTRAL-A',
    recordID: 'RECORD-1',
    firstSeen: '2026-11-25T01:00:00Z',
    lastSeen: '2026-11-25T02:00:00Z',
    lastActivity: 'read',
    subscriptions: [],
    inferredSessionActive: false,
    hasObservedSubscription: false,
    manuallyDisconnected: false,
    hidden: false,
    disconnectRequested: false,
    ...overrides,
  };
}

test('device activity states are green, yellow, blue or manually-confirmed gray without inventing Link Loss', () => {
  const subscribed = Client.centralPresentation(observation({
    subscriptions: ['SYS_STATE', 'MT_RPM'], hasObservedSubscription: true, lastActivity: 'subscribe', inferredSessionActive: true,
  }));
  assert.equal(subscribed.tone, 'green');
  assert.equal(subscribed.label, '正在订阅');
  assert.equal(subscribed.isHistory, false);
  assert.equal(subscribed.canHide, false);

  const disconnectedRequest = Client.centralPresentation(observation({ disconnectRequested: true }));
  assert.equal(disconnectedRequest.tone, 'yellow');
  assert.match(disconnectedRequest.label, /请求断开/);
  assert.match(disconnectedRequest.label, /未确认/);

  const unsubscribed = Client.centralPresentation(observation({
    hasObservedSubscription: true, lastActivity: 'unsubscribe',
  }));
  assert.equal(unsubscribed.tone, 'yellow');
  assert.match(unsubscribed.label, /无订阅/);

  const readWriteOnly = Client.centralPresentation(observation());
  assert.equal(readWriteOnly.tone, 'blue');
  assert.equal(readWriteOnly.label, '仅观察到读写');
  assert.equal(readWriteOnly.canHide, false);

  const manual = Client.centralPresentation(observation({
    manuallyDisconnected: true, subscriptions: ['SYS_STATE'], hasObservedSubscription: true,
  }));
  assert.equal(manual.tone, 'gray');
  assert.equal(manual.label, '人工确认已断开');
  assert.equal(manual.isHistory, true);
  assert.equal(manual.canHide, true);
  assert.equal(Client.centralPresentation(observation({ manuallyDisconnected: true, hidden: true })).canHide, false);
});

test('device activity grouping supports multiple centrals and repeated records, with global hidden records separated', () => {
  const records = [
    observation({ id: 'CENTRAL-A', recordID: 'OLD-A', lastSeen: '2026-11-25T01:00:00Z', manuallyDisconnected: true }),
    observation({ id: 'CENTRAL-A', recordID: 'CURRENT-A', lastSeen: '2026-11-25T03:00:00Z', subscriptions: ['SYS_STATE'] }),
    observation({ id: 'CENTRAL-B', recordID: 'CURRENT-B', lastSeen: '2026-11-25T04:00:00Z' }),
    observation({ id: 'CENTRAL-C', recordID: 'HIDDEN-C', manuallyDisconnected: true, hidden: true }),
  ];
  const groups = Client.groupObservations(records);
  assert.deepEqual(groups.current.map(record => record.recordID), ['CURRENT-B', 'CURRENT-A']);
  assert.deepEqual(groups.history.map(record => record.recordID), ['OLD-A']);
  assert.deepEqual(groups.hidden.map(record => record.recordID), ['HIDDEN-C']);
  assert.equal(groups.hiddenCount, 1);
  assert.equal(records[0].recordID, 'OLD-A', 'grouping must not mutate snapshot records');
});

function registerMap(values) {
  return Object.fromEntries(Client.registerCards(values).map(card => [card.key, card]));
}

test('all six register cards expose Chinese titles, raw names, decimal/four-digit hex and concise explanations', () => {
  const cards = Client.registerCards({
    mtRPM: 900, xdRPM: 60, bootSign: 1, sysState: 1, servoAngle: 830, tfAngle: 1000,
  });
  assert.deepEqual(cards.map(card => card.name), ['MT_RPM', 'XD_RPM', 'BOOT_SIGN', 'SYS_STATE', 'SERVO_ANGLE', 'TF_ANGLE']);
  const byKey = registerMap({
    mtRPM: 900, xdRPM: 60, bootSign: 1, sysState: 1, servoAngle: 830, tfAngle: 1000,
  });
  assert.equal(byKey.mtRPM.title, '电机转速设定');
  assert.equal(byKey.mtRPM.decimal, 900);
  assert.equal(byKey.mtRPM.hex, '0x0384');
  assert.match(byKey.mtRPM.explanation, /0–1500/);
  assert.match(byKey.mtRPM.explanation, /不是刀盘实测转速/);
  assert.equal(byKey.xdRPM.title, '下豆参数');
  assert.match(byKey.xdRPM.explanation, /0–150/);
  assert.match(byKey.xdRPM.explanation, /待厂家确认/);
  assert.doesNotMatch(byKey.xdRPM.title, /研磨度/);
  assert.equal(byKey.servoAngle.title, '当前研磨度');
  assert.match(byKey.servoAngle.explanation, /不证明机械到位/);
  assert.equal(byKey.tfAngle.title, '目标研磨度');
  assert.match(byKey.tfAngle.explanation, /Apply 捕获目标/);
  assert.match(byKey.tfAngle.explanation, /单独修改不立即改变当前研磨度/);
  for (const card of cards) assert.equal(Object.hasOwn(card, 'unit'), false, 'protocol defines no physical unit');
});

test('BOOT_SIGN and SYS_STATE meanings are dynamic and reserved values are never presented as valid commands or idle', () => {
  const bootMeanings = new Map([
    [1, '手动启动'], [2, '定时启动'], [3, '智能启动'], [4, '停止'], [5, 'Apply'],
  ]);
  for (const [value, meaning] of bootMeanings) {
    const card = Client.describeRegister('bootSign', value);
    assert.match(card.valueMeaning, new RegExp(`^${value} = ${meaning}`));
    assert.doesNotMatch(card.valueMeaning, /未定义/);
  }
  for (const value of [6, 10, 65535]) {
    assert.match(Client.describeRegister('bootSign', value).valueMeaning, /未定义 \/ Test Override/);
  }
  assert.match(Client.describeRegister('bootSign', 0).valueMeaning, /初始/);
  assert.doesNotMatch(Client.describeRegister('bootSign', 0).valueMeaning, /手动启动|停止|Apply/);
  assert.match(Client.describeRegister('sysState', 0).valueMeaning, /^0 = 空闲/);
  assert.match(Client.describeRegister('sysState', 1).valueMeaning, /^1 = 设备动作中/);
  assert.match(Client.describeRegister('sysState', 1).valueMeaning, /电机|Apply/);
  for (const value of [2, 65535]) {
    const meaning = Client.describeRegister('sysState', value).valueMeaning;
    assert.match(meaning, /未定义 \/ Test Override/);
    assert.doesNotMatch(meaning, /空闲|设备动作中/);
  }
  assert.equal(Client.describeRegister('sysState', 1).title, '系统状态');
  assert.equal(Client.describeRegister('bootSign', 1).title, '动作命令');
});

test('language selection defaults to Chinese, persists explicitly and survives unavailable storage', () => {
  const values = new Map();
  const storage = {
    getItem: key => values.get(key) || null,
    setItem: (key, value) => values.set(key, value),
  };
  assert.equal(Client.loadLanguage(storage), 'zh');
  Client.saveLanguage(storage, 'en');
  assert.equal(Client.loadLanguage(storage), 'en');
  assert.equal(values.get('crystal-web-language'), 'en');
  Client.saveLanguage(storage, 'zh');
  assert.equal(Client.loadLanguage(storage), 'zh');
  values.set('crystal-web-language', 'unsupported');
  assert.equal(Client.loadLanguage(storage), 'zh');
  const broken = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('denied'); } };
  assert.equal(Client.loadLanguage(broken), 'zh');
  assert.doesNotThrow(() => Client.saveLanguage(broken, 'en'));
  assert.equal(Client.dateLocale('zh'), 'zh-CN');
  assert.equal(Client.dateLocale('en'), 'en-US');
});

test('translation dictionary localizes static controls and parameterized counts', () => {
  assert.equal(Client.t('zh', 'powerOn'), '开机');
  assert.equal(Client.t('en', 'powerOn'), 'Power On');
  assert.equal(Client.t('zh', 'currentDevices'), '当前设备');
  assert.equal(Client.t('en', 'currentDevices'), 'Current Devices');
  assert.equal(Client.t('zh', 'eventCount', { visible: 3, total: 5 }), '3 / 5 条');
  assert.equal(Client.t('en', 'eventCount', { visible: 3, total: 5 }), '3 / 5 events');
  assert.equal(Client.t('en', 'missing.translation.key'), 'missing.translation.key');
});

test('device activity and all six register cards have complete English presentations', () => {
  assert.equal(Client.centralPresentation(observation({ subscriptions: ['SYS_STATE'] }), 'en').label, 'Subscribing');
  assert.equal(Client.centralPresentation(observation({ disconnectRequested: true }), 'en').label, 'Disconnect Requested · Unconfirmed');
  assert.equal(Client.centralPresentation(observation({ hasObservedSubscription: true, lastActivity: 'unsubscribe' }), 'en').label, 'No Subscriptions · Disconnect Unconfirmed');
  assert.equal(Client.centralPresentation(observation(), 'en').label, 'Read/Write Activity Only');
  assert.equal(Client.centralPresentation(observation({ manuallyDisconnected: true }), 'en').label, 'Manually Marked Disconnected');

  const cards = registerMap({
    mtRPM: 900, xdRPM: 60, bootSign: 1, sysState: 1, servoAngle: 830, tfAngle: 1000,
  });
  const english = Object.fromEntries(Client.registerCards({
    mtRPM: 900, xdRPM: 60, bootSign: 1, sysState: 1, servoAngle: 830, tfAngle: 1000,
  }, 'en').map(card => [card.key, card]));
  assert.equal(cards.mtRPM.title, '电机转速设定', 'default remains Chinese');
  assert.equal(english.mtRPM.title, 'Motor Speed Setting');
  assert.match(english.mtRPM.explanation, /not a measured burr speed/);
  assert.equal(english.xdRPM.title, 'Feed Parameter');
  assert.match(english.xdRPM.explanation, /manufacturer confirmation/);
  assert.equal(english.bootSign.title, 'Action Command');
  assert.equal(english.sysState.title, 'System State');
  assert.equal(english.servoAngle.title, 'Current Grind Setting');
  assert.equal(english.tfAngle.title, 'Target Grind Setting');
  assert.equal(english.bootSign.valueMeaning, '1 = Manual Start');
  assert.equal(english.sysState.valueMeaning, '1 = Device Active (motor running or Apply)');
  assert.match(Client.describeRegister('sysState', 2, 'en').valueMeaning, /Undefined \/ Test Override/);
  assert.match(Client.describeRegister('bootSign', 6, 'en').valueMeaning, /Undefined \/ Test Override/);
});

test('control feedback is localized in the UI without changing server or raw log messages', () => {
  assert.equal(Client.controlFeedback('zh', 'powerOff', 200, {
    ok: true, message: 'Device Powered Off; disconnection unconfirmed',
  }), '磨豆机已关机；断连未确认');
  assert.match(Client.controlFeedback('zh', 'disconnectCentral', 200, {
    ok: true, message: 'Disconnect Request issued; per-central and Link Loss confirmation unavailable',
  }), /断连未确认/);
  assert.equal(Client.controlFeedback('en', 'start', 409, {
    ok: false, message: 'Device Powered Off',
  }), 'Device is powered off');
  const rejected = Client.controlFeedback('zh', 'setMT', 422, {
    ok: false, message: 'write rejected by injected ATT error; model unchanged', attStatus: 17, faultID: 'busy',
  });
  assert.match(rejected, /故障注入/);
  assert.match(rejected, /0x11/);
  assert.match(rejected, /busy/);
  assert.equal(Client.controlFeedback('zh', 'start', 500, {
    ok: false, message: 'raw server text',
  }), '操作失败（HTTP 500）');
  assert.equal(Client.controlFeedback('en', 'restoreHiddenObservations', 200, {
    ok: true, message: 'Restored 2 hidden Observation(s) for all browsers',
  }), 'Restored 2 hidden observation(s) in all browsers');
});
