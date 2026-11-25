const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const runner = fs.readFileSync(path.resolve(__dirname, '../test.sh'), 'utf8');

test('the repository test entry point includes frontend and real Web integration suites', () => {
  assert.match(runner, /node --test .*Scripts\/web-tests\/\*\.test\.js/);
  assert.match(runner, /python3 .*Scripts\/web_smoke_test\.py/);
});
