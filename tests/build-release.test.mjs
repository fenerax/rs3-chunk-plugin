// Run: node --test tests/build-release.test.mjs
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, test } from 'node:test';
import { crc32, inflateRawSync } from 'node:zlib';
import { build, Refusal } from '../tools/build-release.mjs';

const work = mkdtempSync(path.join(tmpdir(), 'cp-release-'));
after(() => rmSync(work, { recursive: true, force: true }));
const hosted = { name: 'Chunk Picker', version: '0.1.0', urls: { home: 'https://picker.example.com' } };
let n = 0;
function plugin(files, manifest = hosted) {
  const dir = path.join(work, `plugin${++n}`);
  for (const [rel, text] of Object.entries({ 'main.lua': 'local x = require("net")\n', 'net.lua': 'return {}\n', ...files })) {
    mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true }); writeFileSync(path.join(dir, rel), text);
  }
  if (manifest) writeFileSync(path.join(dir, 'plugin.json'), JSON.stringify(manifest));
  return dir;
}
const out = () => path.join(work, `out${++n}`);
const refused = (options, pattern) => assert.throws(() => build({ repoDir: path.join(work, 'repo'), outDir: out(), version: '0.1.0', ...options }),
  error => error instanceof Refusal && pattern.test(error.message));

// The zip's entries, read back from the central directory and checked against their CRCs.
function unzip(file) {
  const zip = readFileSync(file), end = zip.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  const count = zip.readUInt16LE(end + 10), entries = {};
  let at = zip.readUInt32LE(end + 16);
  for (let i = 0; i < count; i++) {
    const nameLength = zip.readUInt16LE(at + 28), name = zip.subarray(at + 46, at + 46 + nameLength).toString();
    const local = zip.readUInt32LE(at + 42), size = zip.readUInt32LE(at + 20), crc = zip.readUInt32LE(at + 16);
    const start = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28);
    const data = inflateRawSync(zip.subarray(start, start + size));
    assert.equal(crc32(data), crc, `CRC of ${name}`);
    entries[name] = data.toString();
    at += 46 + nameLength + zip.readUInt16LE(at + 30) + zip.readUInt16LE(at + 32);
  }
  return entries;
}

test('a clean plugin zips with main.lua and plugin.json at the top', () => {
  const dir = plugin({ 'art/icon.lua': 'return 1\n' });
  const result = build({ pluginDir: dir, repoDir: path.join(work, 'repo'), outDir: out(), version: '0.1.0' });
  assert.equal(path.basename(result.zip), 'chunk-picker-010.zip');
  assert.deepEqual(result.warnings, []);
  const entries = unzip(result.zip);
  assert.deepEqual(Object.keys(entries).sort(), ['art/icon.lua', 'main.lua', 'net.lua', 'plugin.json']);
  assert.equal(JSON.parse(entries['plugin.json']).version, '0.1.0');
  assert.equal(entries['main.lua'], 'local x = require("net")\n');
  // Same tree, same bytes.
  const again = build({ pluginDir: dir, repoDir: path.join(work, 'repo'), outDir: out(), version: '0.1.0' });
  assert.ok(readFileSync(again.zip).equals(readFileSync(result.zip)));
});

test('versions must be digits and dots and match the manifest', () => {
  const dir = plugin({});
  for (const version of ['0.1.0-beta', 'v0.1.0', '', undefined, '0..1']) refused({ pluginDir: dir, version }, /digits and dots/);
  refused({ pluginDir: plugin({ 'main.lua': 'local v = "Chunk Picker 0.0.9"\n' }) }, /main\.lua shows version 0\.0\.9, not 0\.1\.0/);
  refused({ pluginDir: dir, version: '0.2.0' }, /says version 0\.1\.0/);
  refused({ pluginDir: plugin({}, null) }, /plugin\.json is missing/);
});

test('probe, test and dev files never ship', () => {
  refused({ pluginDir: plugin({ 'probe.lua': 'return 1\n' }) }, /Probe file/);
  refused({ pluginDir: plugin({ 'Probe_bank.lua': 'return 1\n' }) }, /Probe file/);
  refused({ pluginDir: plugin({ 'tests/net.lua': 'return 1\n' }) }, /Dev or test file/);
  refused({ pluginDir: plugin({ 'dev/main.lua': 'return 1\n' }) }, /Dev or test file/);
  refused({ pluginDir: plugin({ 'net.test.lua': 'return 1\n' }) }, /Dev or test file/);
});

test('cheat commands never ship, even in a comment', () => {
  refused({ pluginDir: plugin({ 'net.lua': 'ExecuteConsoleCommand("x")\n' }) }, /Cheat command in net\.lua: ExecuteConsoleCommand/);
  refused({ pluginDir: plugin({ 'net.lua': '-- try !tele 0,50,50\n' }) }, /!tele/);
  refused({ pluginDir: plugin({ 'net.lua': 'local s = "!give coins 5"\n' }) }, /!give/);
  // Lua's not-equal is not a cheat.
  build({ pluginDir: plugin({ 'net.lua': 'if a ~= b then return end\n' }), repoDir: path.join(work, 'repo'), outDir: out(), version: '0.1.0' });
});

test('a Hub build leaves loopback servers out; --allow-local keeps them and warns', () => {
  const onlyLocal = plugin({}, { ...hosted, urls: { scratch: 'http://127.0.0.1:8950', home: 'http://localhost:8789' } });
  refused({ pluginDir: onlyLocal }, /Only loopback server URLs in plugin\.json \(scratch, home\)/);
  const beta = build({ pluginDir: onlyLocal, repoDir: path.join(work, 'repo'), outDir: out(), version: '0.1.0', allowLocal: true });
  assert.match(beta.warnings[0], /Beta build only/);
  const mixed = plugin({}, { ...hosted, urls: { scratch: 'http://127.0.0.1:8950', production: 'https://picker.example.com' } });
  const hub = build({ pluginDir: mixed, repoDir: path.join(work, 'repo'), outDir: out(), version: '0.1.0' });
  assert.deepEqual(JSON.parse(unzip(hub.zip)['plugin.json']).urls, { production: 'https://picker.example.com' });
  assert.match(hub.warnings[0], /Left loopback servers out of the Hub manifest: scratch/);
  refused({ pluginDir: plugin({}, { ...hosted, urls: { production: 'http://picker.example.com' } }) }, /must use HTTPS: production/);
});

test('the zip goes outside the repo', () => {
  const repoDir = path.join(work, 'repo');
  assert.throws(() => build({ pluginDir: plugin({}), repoDir, outDir: path.join(repoDir, 'dist'), version: '0.1.0' }), /outside the repo/);
  assert.throws(() => build({ pluginDir: plugin({}), repoDir, outDir: repoDir, version: '0.1.0' }), /outside the repo/);
});

test('the real plugin builds for beta, and for the Hub with only the hosted picker', () => {
  const version = JSON.parse(readFileSync(new URL('../plugins/chunk-picker/plugin.json', import.meta.url))).version;
  const result = build({ outDir: out(), version, allowLocal: true });
  const entries = unzip(result.zip);
  assert.ok('main.lua' in entries && 'plugin.json' in entries);
  assert.ok(result.warnings.some(w => /Beta build only/.test(w)), result.warnings.join('; '));
  const hub = build({ outDir: out(), version });
  assert.deepEqual(JSON.parse(unzip(hub.zip)['plugin.json']).urls, { production: 'https://chunkpicker.ca' });
});
