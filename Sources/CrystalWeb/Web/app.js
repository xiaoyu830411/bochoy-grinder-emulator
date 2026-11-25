(function () {
  'use strict';

  const Client = globalThis.SimClient;
  const $ = id => document.getElementById(id);
  const state = {
    snapshot: null,
    events: [],
    resyncCount: 0,
    resyncReason: '',
    busy: false,
    aliases: {},
    language: 'zh',
    feedback: null,
    pendingAction: null,
  };
  let eventSource;
  let token = '';
  let centralRenderKey = '';
  let faultRenderKey = '';
  let logRenderScheduled = false;
  let connectionStatusKey = 'eventConnecting';
  let connectionOffline = false;

  function storage(name) {
    try { return window[name]; } catch (_) { return null; }
  }

  const session = storage('sessionStorage');
  const local = storage('localStorage');
  state.aliases = Client.loadAliases(local);
  state.language = Client.loadLanguage(local);

  function node(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  }

  function replaceChildren(container, children) {
    container.replaceChildren(...children);
  }

  function formatDate(value) {
    if (!value) return '—';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString(Client.dateLocale(state.language), { hour12: false });
  }

  function formatTime(value) {
    if (!value) return '—';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? '—' : date.toLocaleTimeString(Client.dateLocale(state.language), { hour12: false });
  }

  function setConnectionStatus(key, offline = false) {
    connectionStatusKey = key;
    connectionOffline = offline;
    $('event-source-status').textContent = Client.t(state.language, key);
    $('event-source-status').classList.toggle('offline', offline);
  }

  function showMessage(message, error = false) {
    $('control-message').textContent = message || '';
    $('control-message').classList.toggle('error', error);
  }

  function renderFeedback() {
    if (state.pendingAction) {
      showMessage(Client.t(state.language, 'executingAction', { action: state.pendingAction }));
      return;
    }
    if (!state.feedback) return;
    const feedback = state.feedback;
    showMessage(
      Client.controlFeedback(state.language, feedback.action, feedback.status, feedback.body),
      feedback.status < 200 || feedback.status >= 300 || !feedback.body.ok,
    );
  }

  function applyLanguage() {
    document.documentElement.lang = Client.dateLocale(state.language);
    document.title = Client.t(state.language, 'documentTitle');
    document.querySelectorAll('[data-i18n]').forEach(element => {
      element.textContent = Client.t(state.language, element.dataset.i18n);
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(element => {
      element.placeholder = Client.t(state.language, element.dataset.i18nPlaceholder);
    });
    document.querySelectorAll('[data-i18n-aria-label]').forEach(element => {
      element.setAttribute('aria-label', Client.t(state.language, element.dataset.i18nAriaLabel));
    });
    $('language-toggle').textContent = state.language === 'zh' ? 'English' : '中文';
    $('centrals-heading').textContent = Client.t(state.language, 'deviceActivity');
    setConnectionStatus(connectionStatusKey, connectionOffline);
    centralRenderKey = '';
    faultRenderKey = '';
    if (state.snapshot) applySnapshot(state.snapshot);
    renderFeedback();
    renderLogs();
  }

  function bluetoothName(raw) {
    return ({
      0: 'unknown', 1: 'resetting', 2: 'unsupported', 3: 'unauthorized',
      4: 'poweredOff', 5: 'poweredOn',
    })[raw] || `state ${raw}`;
  }

  function updateButtonStates() {
    document.querySelectorAll('[data-action]').forEach(button => {
      const noHiddenRecords = button.dataset.requiresHidden === 'true'
        && !(state.snapshot && (state.snapshot.centrals || []).some(central => central.hidden));
      button.disabled = state.busy || noHiddenRecords
        || !Client.isControlEnabled(state.snapshot, button.dataset.action);
    });
  }

  function applySnapshot(snapshot) {
    const firstSnapshot = !state.snapshot;
    state.snapshot = snapshot;
    const device = snapshot.device;
    const bluetooth = snapshot.bluetooth;
    const poweredOn = device.poweredOn;

    $('power-state').textContent = Client.t(state.language, poweredOn ? 'poweredOnState' : 'poweredOffState');
    $('power-state').classList.toggle('off', !poweredOn);
    document.querySelector('.power-card').classList.toggle('powered-off', !poweredOn);
    $('power-note').textContent = Client.t(state.language, poweredOn ? 'powerNoteOn' : 'powerNoteOff');
    $('bluetooth-state').textContent = `${bluetoothName(bluetooth.state)} · ${Client.t(state.language, 'characteristicCount', { count: bluetooth.publishedCharacteristics })}`;
    $('advertising-state').textContent = Client.t(state.language, bluetooth.advertising
      ? 'advertisingActive'
      : bluetooth.advertisingStartPending
        ? 'advertisingStarting'
        : bluetooth.advertisingRequested ? 'advertisingRequested' : 'advertisingStopped');
    $('run-state').textContent = device.activeRun
      ? `${device.activeRun.mode} · #${device.activeRun.id}` : Client.t(state.language, 'idle');
    $('apply-state').textContent = device.pendingApply
      ? `pending · TF ${device.pendingApply.target}` : Client.t(state.language, 'noPendingApply');
    $('session-state').textContent = Client.t(state.language, device.sessionActive ? 'sessionActive' : 'sessionInactive');
    $('timer-state').textContent = Client.t(state.language, device.timersPaused ? 'timersPaused' : 'timersRunning');
    $('scenario-name').textContent = `${device.scenarioName} · ${device.deviceName}`;

    replaceChildren($('register-grid'), Client.registerCards(device.registers, state.language).map(card => {
      const item = node('article', 'register-item');
      item.append(
        node('h4', 'register-title', card.title),
        node('div', 'register-name', card.name),
        node('div', 'register-value', Client.formatUInt16(card.decimal)),
      );
      if (card.valueMeaning) item.append(node('p', 'register-value-meaning', card.valueMeaning));
      item.append(node('p', 'register-explanation', card.explanation));
      return item;
    }));

    if (firstSnapshot) {
      $('motor-value').value = device.registers.mtRPM;
      $('feed-value').value = device.registers.xdRPM;
      $('target-value').value = device.registers.tfAngle;
    }
    renderScenarios(snapshot.availableScenarios || []);
    renderFaults(device.faults || []);
    renderCentrals(snapshot.centrals || []);
    updateButtonStates();
  }

  function renderScenarios(scenarios) {
    const select = $('scenario-select');
    const signature = JSON.stringify(scenarios);
    if (select.dataset.signature !== signature) {
      select.dataset.signature = signature;
      replaceChildren(select, scenarios.map(name => {
        const option = node('option', '', name);
        option.value = name;
        return option;
      }));
    }
    const current = state.snapshot.device.scenarioName;
    if (scenarios.includes(current) && !select.matches(':focus')) select.value = current;
  }

  function renderFaults(faults) {
    const signature = JSON.stringify([faults, state.language]);
    if (signature === faultRenderKey) return;
    faultRenderKey = signature;
    if (!faults.length) {
      replaceChildren($('fault-list'), [node('p', 'empty-state', Client.t(state.language, 'noFaultRules'))]);
      return;
    }
    replaceChildren($('fault-list'), faults.map(fault => {
      const row = node('div', 'fault-row');
      const rule = fault.rule;
      const target = rule.characteristic ? ` · ${rule.characteristic}` : '';
      row.append(node('div', 'fault-meta', `${rule.id} · ${rule.type}${target}`));
      const button = node('button', 'secondary', Client.t(state.language, fault.enabled ? 'disable' : 'enable'));
      button.type = 'button';
      button.dataset.action = 'faultSet';
      button.dataset.faultId = rule.id;
      button.dataset.enabled = String(!fault.enabled);
      row.append(button);
      return row;
    }));
  }

  function observationAction(central, action, labelKey, className = 'secondary') {
    const button = node('button', `${className} record-action`, Client.t(state.language, labelKey));
    button.type = 'button';
    button.dataset.action = action;
    button.dataset.recordId = central.recordID;
    return button;
  }

  function renderObservationCard(central) {
    const presentation = Client.centralPresentation(central, state.language);
    const card = node('article', `central-card tone-${presentation.tone}`);
    const title = node('div', 'central-title');
    title.append(
      node('strong', '', state.aliases[central.id] || Client.t(state.language, 'unnamedDevice')),
      node('span', `central-status tone-${presentation.tone}`, presentation.label),
    );
    const activityNames = {
      subscribe: 'activitySubscribe', unsubscribe: 'activityUnsubscribe',
      read: 'activityRead', write: 'activityWrite',
    };
    const subscriptions = (central.subscriptions || []).join(', ') || Client.t(state.language, 'none');
    const activity = Client.t(state.language, activityNames[central.lastActivity] || 'unknownActivity');
    card.append(
      title,
      node('div', 'central-last-seen', Client.t(state.language, 'recentActivity', { time: formatDate(central.lastSeen), activity })),
      node('div', 'central-subscriptions', Client.t(state.language, presentation.isHistory ? 'previousSubscriptions' : 'currentSubscriptions', { subscriptions })),
    );
    const details = node('details', 'central-details');
    details.append(
      node('summary', '', Client.t(state.language, 'details')),
      node('div', 'central-uuid', Client.t(state.language, 'centralUUID', { id: central.id })),
      node('div', 'central-uuid', Client.t(state.language, 'observationRecordID', { id: central.recordID })),
      node('div', '', Client.t(state.language, 'firstActivity', { time: formatDate(central.firstSeen) })),
    );
    card.append(details);

    const actions = node('div', 'central-actions');
    const alias = node('input');
    alias.type = 'text';
    alias.maxLength = 40;
    alias.value = state.aliases[central.id] || '';
    alias.placeholder = Client.t(state.language, 'aliasPlaceholder');
    alias.setAttribute('aria-label', Client.t(state.language, 'centralAliasAria', { id: central.id }));
    const save = node('button', 'secondary', Client.t(state.language, 'saveAlias'));
    save.type = 'button';
    save.addEventListener('click', () => {
      state.aliases = Client.saveAlias(local, central.id, alias.value);
      centralRenderKey = '';
      renderCentrals(state.snapshot.centrals || []);
    });
    actions.append(alias, save);
    if (!presentation.isHistory && !central.hidden) {
      const disconnect = node('button', 'danger-soft record-action', Client.t(state.language, 'requestDisconnect'));
      disconnect.type = 'button';
      disconnect.dataset.action = 'disconnectCentral';
      disconnect.dataset.centralId = central.id;
      actions.append(
        disconnect,
        observationAction(central, 'markObservationDisconnected', 'markDisconnected'),
      );
    }
    if (presentation.canHide) {
      actions.append(observationAction(central, 'hideObservation', 'hideRecord'));
    }
    if (presentation.canRestore) {
      actions.append(observationAction(central, 'restoreObservation', 'restoreRecord'));
    }
    card.append(actions);
    return card;
  }

  function renderObservationList(id, records, emptyKey) {
    replaceChildren($(id), records.length
      ? records.map(renderObservationCard)
      : [node('p', 'empty-state', Client.t(state.language, emptyKey))]);
  }

  function renderCentrals(centrals) {
    const signature = JSON.stringify([centrals, state.aliases, state.language]);
    if (signature === centralRenderKey) return;
    centralRenderKey = signature;
    const groups = Client.groupObservations(centrals);
    $('central-history-count').textContent = Client.t(state.language, 'recordCount', { count: groups.history.length });
    $('hidden-central-count').textContent = Client.t(state.language, 'recordCount', { count: groups.hiddenCount });
    renderObservationList('central-list', groups.current, 'noCurrentDevices');
    renderObservationList('central-history-list', groups.history, 'noHistory');
    renderObservationList('hidden-central-list', groups.hidden, 'noHidden');
  }

  function numberParameter(id, maximum) {
    const value = Client.parseIntegerInput($(id).value, maximum);
    if (value === null) {
      throw new Error(Client.t(state.language, 'integerRange', { id, maximum }));
    }
    return value;
  }

  function commandFor(button) {
    const action = button.dataset.action;
    const request = { action };
    switch (action) {
      case 'start': request.mode = $('run-mode').value; break;
      case 'setMT': request.value = numberParameter('motor-value', 1500); break;
      case 'setXD': request.value = numberParameter('feed-value', 150); break;
      case 'setTF': request.value = numberParameter('target-value', 1500); break;
      case 'setTFAndApply': request.value = numberParameter('target-value', 1500); break;
      case 'override':
        request.characteristic = $('override-characteristic').value;
        request.value = numberParameter('override-value', 65535);
        request.notification = $('override-notification').value;
        break;
      case 'advertising': request.enabled = button.dataset.enabled === 'true'; break;
      case 'scenarioLoad': request.scenario = $('scenario-select').value; break;
      case 'faultSet':
        request.faultID = button.dataset.faultId;
        request.enabled = button.dataset.enabled === 'true';
        break;
      case 'disconnectCentral': request.centralID = button.dataset.centralId; break;
      case 'markObservationDisconnected':
      case 'hideObservation':
      case 'restoreObservation':
        request.recordID = button.dataset.recordId;
        break;
      default: break;
    }
    return request;
  }

  async function sendControl(button) {
    const action = button.dataset.action;
    if (state.busy || !Client.isControlEnabled(state.snapshot, action)) return;
    let request;
    try {
      request = commandFor(button);
    } catch (error) {
      state.feedback = null;
      showMessage(error.message, true);
      return;
    }
    state.busy = true;
    state.pendingAction = action;
    state.feedback = null;
    updateButtonStates();
    renderFeedback();
    let status = 0;
    let body = {};
    try {
      const response = await fetch('/api/control', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(request),
      });
      status = response.status;
      body = await response.json();
      if (body.snapshot) applySnapshot(body.snapshot);
    } catch (_) {
      status = 0;
      body = {};
    } finally {
      state.busy = false;
      state.pendingAction = null;
      state.feedback = { action, status, body };
      renderFeedback();
      updateButtonStates();
    }
  }

  async function requestSnapshot() {
    try {
      const response = await fetch('/api/snapshot', {
        cache: 'no-store',
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
      const body = await response.json();
      if (!response.ok) throw new Error('Snapshot request failed');
      applySnapshot(body);
    } catch (_) {
      setConnectionStatus('snapshotUnavailable', true);
    }
  }

  function scheduleLogRender() {
    if (logRenderScheduled) return;
    logRenderScheduled = true;
    requestAnimationFrame(() => {
      logRenderScheduled = false;
      renderLogs();
    });
  }

  function renderLogs() {
    const stream = $('log-stream');
    const stickToBottom = stream.scrollHeight - stream.scrollTop - stream.clientHeight < 60;
    const filters = {
      kind: $('log-kind').value,
      source: $('log-source').value,
      text: $('log-text').value,
      overrideOnly: $('override-only').checked,
    };
    const visible = Client.filterEvents(state.events, filters);
    $('log-count').textContent = Client.t(state.language, 'eventCount', { visible: visible.length, total: state.events.length });
    const fragment = document.createDocumentFragment();
    for (const item of visible) {
      const entry = node('div', `log-entry ${item.kind || ''}`);
      entry.append(
        node('span', 'log-sequence', `#${item.sequence}`),
        node('span', 'log-time', formatTime(item.timestamp)),
        node('span', 'log-kind', item.kind || 'event'),
      );
      const message = node('div', 'log-message', item.message || '');
      const details = [];
      if (item.characteristic) details.push(item.characteristic);
      if (item.value !== undefined) details.push(`value=${item.value}`);
      if (item.hex) details.push(`hex=${item.hex}`);
      if (item.attStatus !== undefined) details.push(`att=0x${Number(item.attStatus).toString(16).padStart(2, '0')}`);
      if (item.faultID) details.push(`fault=${item.faultID}`);
      for (const [key, value] of Object.entries(item.details || {})) details.push(`${key}=${value}`);
      if (details.length) message.append(node('span', 'log-details', details.join(' · ')));
      if (item.testOverride) message.append(node('span', 'override-marker', ' TEST_OVERRIDE'));
      entry.append(message);
      fragment.append(entry);
    }
    stream.replaceChildren(fragment);
    if (stickToBottom) stream.scrollTop = stream.scrollHeight;
  }

  function connectEvents() {
    if (eventSource) eventSource.close();
    setConnectionStatus('eventConnecting');
    eventSource = new EventSource(Client.eventsURL(token));
    eventSource.onopen = () => setConnectionStatus('eventConnected');
    eventSource.onerror = () => setConnectionStatus('eventReconnecting', true);
    eventSource.addEventListener('snapshot', event => {
      applySnapshot(JSON.parse(event.data));
    });
    eventSource.addEventListener('log', event => {
      state.events = Client.mergeEvents(state.events, [JSON.parse(event.data)]);
      scheduleLogRender();
    });
    eventSource.addEventListener('resync', event => {
      const updated = Client.applyResync(state, JSON.parse(event.data));
      state.events = updated.events;
      state.resyncCount = updated.resyncCount;
      state.resyncReason = updated.resyncReason;
      setConnectionStatus('eventResync', true);
      scheduleLogRender();
    });
  }

  document.addEventListener('click', event => {
    const button = event.target.closest('[data-action]');
    if (button) void sendControl(button);
  });

  document.querySelectorAll('[data-tab]').forEach(button => {
    button.addEventListener('click', () => {
      document.querySelector('.workspace').dataset.activeTab = button.dataset.tab;
      document.querySelectorAll('[data-tab]').forEach(tab => {
        tab.setAttribute('aria-selected', String(tab === button));
      });
      if (button.dataset.tab === 'logs') scheduleLogRender();
    });
  });

  for (const id of ['log-kind', 'log-source', 'override-only']) {
    $(id).addEventListener('change', renderLogs);
  }
  $('log-text').addEventListener('input', scheduleLogRender);
  $('log-clear').addEventListener('click', () => {
    state.events = [];
    renderLogs();
  });
  $('token-save').addEventListener('click', () => {
    token = $('token-input').value;
    Client.saveToken(session, token);
    state.events = [];
    connectEvents();
    void requestSnapshot();
  });
  $('language-toggle').addEventListener('click', () => {
    state.language = state.language === 'zh' ? 'en' : 'zh';
    Client.saveLanguage(local, state.language);
    applyLanguage();
  });
  window.addEventListener('beforeunload', () => eventSource && eventSource.close());

  token = Client.loadToken(session);
  $('token-input').value = token;
  applyLanguage();
  updateButtonStates();
  connectEvents();
  void requestSnapshot();
})();
