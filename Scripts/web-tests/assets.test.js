const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '../../Sources/CrystalWeb/Web');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const Client = require('../../Sources/CrystalWeb/Web/sim-client.js');

test('HTML provides semantic Chinese control/log panes and all requested control families', () => {
  assert.match(html, /<html lang="zh-CN">/);
  for (const id of [
    'control-pane', 'log-pane', 'tab-controls', 'tab-logs', 'power-on', 'power-off',
    'power-state', 'bluetooth-state', 'register-grid', 'central-list', 'run-mode',
    'motor-value', 'feed-value', 'target-value', 'scenario-select', 'fault-list',
    'override-characteristic', 'override-value', 'override-notification',
    'log-stream', 'log-kind', 'log-text', 'log-source', 'override-only', 'event-source-status',
  ]) {
    assert.match(html, new RegExp(`id="${id}"`), id);
  }
  for (const action of [
    'start', 'stop', 'setMT', 'setXD', 'setTF', 'apply', 'setTFAndApply',
    'finishRun', 'finishApply', 'override', 'sessionBegin', 'sessionEnd', 'scenarioReset',
  ]) {
    assert.match(html, new RegExp(`data-action="${action}"`), action);
  }
  assert.match(html, /Observed Central/);
  assert.match(html, /Test Override/);
  assert.match(html, /断连未确认/);
  assert.match(html, /通知提交不代表手机已收到/);
  assert.doesNotMatch(html, /data-action="quit"|退出模拟器/);
  assert.match(html, /src="sim-client\.js"/);
  assert.match(html, /src="app\.js"/);
});

test('desktop layout is exactly two equal panes with independent scrolling', () => {
  assert.match(css, /grid-template-columns:\s*minmax\(0,\s*1fr\)\s+minmax\(0,\s*1fr\)/);
  assert.match(css, /\.pane\s*\{[^}]*overflow:\s*auto/s);
  assert.match(css, /\.log-stream\s*\{[^}]*overflow:\s*auto/s);
});

test('narrow layout exposes control/log tabs rather than squeezing both panes', () => {
  assert.match(css, /@media\s*\(max-width:\s*760px\)/);
  assert.match(css, /\.tabs\s*\{/);
  assert.match(css, /data-active-tab/);
});

test('narrow layout retains the token entry needed for LAN authentication', () => {
  const narrow = css.slice(css.indexOf('@media (max-width: 760px)'));
  assert.match(narrow, /\.topbar\s*\{[^}]*flex-wrap:\s*wrap/s);
  assert.doesNotMatch(narrow, /\.connection-tools\s+(?:input|button)[^{]*\{[^}]*display:\s*none/s);
});

test('DOM binding uses the same-process API and SSE without dependencies or unsafe log HTML', () => {
  assert.match(app, /\/api\/snapshot/);
  assert.match(app, /\/api\/control/);
  assert.match(app, /EventSource/);
  assert.match(app, /addEventListener\(['"]log['"]/);
  assert.match(app, /addEventListener\(['"]snapshot['"]/);
  assert.match(app, /addEventListener\(['"]resync['"]/);
  assert.match(app, /sessionStorage/);
  assert.match(app, /localStorage/);
  assert.doesNotMatch(app, /\.innerHTML\s*=/);
  assert.doesNotMatch(html + app, /https?:\/\//);
});

test('normal-control labels distinguish motor setting, feed parameter and target grind setting', () => {
  assert.match(html, /MT_RPM 电机转速设定/);
  assert.match(html, /XD_RPM 下豆参数/);
  assert.match(html, /data-action="setXD"[^>]*>设置下豆</);
  assert.match(html, /TF_ANGLE 目标研磨度/);
  assert.doesNotMatch(html, /XD_RPM 研磨度/);
  assert.doesNotMatch(html, /data-action="setXD"[^>]*>设置研磨度</);
});

test('device activity has visible current devices, collapsed history and globally restorable hidden records', () => {
  assert.match(html, /id="centrals-heading">设备活动</);
  assert.match(html, /当前设备/);
  assert.match(html, /<details id="central-history">/);
  assert.doesNotMatch(html, /<details id="central-history" open>/);
  for (const id of ['central-list', 'central-history-list', 'central-history-count', 'hidden-central-list', 'hidden-central-count']) {
    assert.match(html, new RegExp(`id="${id}"`), id);
  }
  assert.match(html, /已移出/);
  assert.match(html, /data-action="restoreHiddenObservations"/);
  assert.match(html, /全部恢复/);
  assert.match(html, /人工确认已断开/);
});

test('device activity colors and register explanations have dedicated visible styling', () => {
  for (const tone of ['green', 'yellow', 'blue', 'gray']) {
    assert.match(css, new RegExp(`\\.central-card\\.tone-${tone}\\s*\\{`), tone);
  }
  assert.match(css, /\.register-title\s*\{/);
  assert.match(css, /\.register-explanation\s*\{/);
});

test('aliases follow central UUID while observation commands follow recordID', () => {
  assert.match(app, /saveAlias\(local, central\.id, alias\.value\)/);
  assert.match(app, /dataset\.recordId = central\.recordID/);
  assert.match(app, /case 'markObservationDisconnected':/);
  assert.match(app, /case 'hideObservation':/);
  assert.match(app, /case 'restoreObservation':/);
  assert.match(app, /request\.recordID = button\.dataset\.recordId/);
  assert.match(app, /central\.id/);
  assert.match(app, /central\.recordID/);
});

test('Web console exposes a Chinese/English toggle and keeps raw log messages unchanged', () => {
  assert.match(html, /id="language-toggle"/);
  assert.match(html, /BOCHOY · GRINDER EMULATOR/);
  assert.match(html, /data-i18n="documentTitle"/);
  assert.match(app, /Client\.loadLanguage\(local\)/);
  assert.match(app, /Client\.saveLanguage\(local, state\.language\)/);
  assert.match(app, /document\.documentElement\.lang = Client\.dateLocale\(state\.language\)/);
  assert.match(app, /querySelectorAll\('\[data-i18n\]'\)/);
  assert.match(app, /Client\.controlFeedback\(/);
  assert.match(app, /node\('div', 'log-message', item\.message \|\| ''\)/);
});

test('every declared interface translation key has both Chinese and English text', () => {
  const keys = new Set();
  for (const match of html.matchAll(/data-i18n(?:-placeholder|-aria-label)?="([^"]+)"/g)) keys.add(match[1]);
  assert.ok(keys.size >= 45, `expected comprehensive interface coverage, got ${keys.size} keys`);
  for (const key of keys) {
    assert.notEqual(Client.t('zh', key), key, `missing zh translation: ${key}`);
    assert.notEqual(Client.t('en', key), key, `missing en translation: ${key}`);
  }
});
