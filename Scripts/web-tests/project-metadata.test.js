const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');

test('public package and executable use bochoy-grinder-emulator while internal modules stay stable', () => {
  const manifest = read('Package.swift');
  assert.match(manifest, /name:\s*"bochoy-grinder-emulator"/);
  assert.match(manifest, /\.executable\(name:\s*"bochoy-grinder-emulator",\s*targets:\s*\["CrystalSim"\]\)/);
  for (const moduleName of ['CrystalCore', 'CrystalWeb', 'CrystalSim']) {
    assert.match(manifest, new RegExp(`"${moduleName}"`));
  }
  for (const file of ['Scripts/build.sh', 'Scripts/run.sh', 'Scripts/smoke_test.py', 'Scripts/web_smoke_test.py']) {
    assert.match(read(file), /bochoy-grinder-emulator/, file);
  }
  assert.doesNotMatch(read('Scripts/build.sh'), /\.build\/\$CONFIGURATION\/crystal-sim/);
  assert.doesNotMatch(read('Scripts/run.sh'), /\.build\/debug\/crystal-sim/);
  assert.doesNotMatch(read('Scripts/smoke_test.py'), /"debug" \/ "crystal-sim"/);
  assert.doesNotMatch(read('Scripts/web_smoke_test.py'), /"debug" \/ "crystal-sim"/);
});

test('embedded executable metadata and CLI usage adopt the new name without changing Bluetooth identity', () => {
  const plist = read('Resources/Info.plist');
  assert.match(plist, /<key>CFBundleExecutable<\/key>\s*<string>bochoy-grinder-emulator<\/string>/);
  assert.match(plist, /<key>CFBundleName<\/key>\s*<string>Bochoy Grinder Emulator<\/string>/);
  assert.match(plist, /<key>CFBundleIdentifier<\/key>\s*<string>local\.bocai\.crystal-ble-mock<\/string>/);
  const options = read('Sources/CrystalSim/AppOptions.swift');
  assert.match(options, /bochoy-grinder-emulator \[--scenario/);
  assert.match(options, /bochoy-grinder-emulator --permission-probe/);
  assert.match(options, /bochoy-grinder-emulator --version/);
  assert.match(options, /CRYSTAL_WEB_TOKEN/);
  assert.match(read('Sources/CrystalCore/Scenario.swift'), /CRYSTAL-E57C/);
});

test('beta runtime version and embedded bundle metadata have one consistent release value', () => {
  const version = '1.0.0-beta.2';
  const versionSource = read('Sources/CrystalSim/AppVersion.swift');
  const declaredVersion = versionSource.match(/static let current = "([^"]+)"/);
  assert.equal(declaredVersion?.[1], version, 'runtime version constant');

  const plist = read('Resources/Info.plist');
  assert.match(plist, new RegExp(`<key>CFBundleShortVersionString</key>\\s*<string>${version.replaceAll('.', '\\.')}</string>`));
  assert.match(plist, /<key>CFBundleVersion<\/key>\s*<string>3<\/string>/);
});
