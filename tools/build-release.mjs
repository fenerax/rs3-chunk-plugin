// Builds the Plugin Hub upload: plugins/chunk-picker zipped with main.lua and plugin.json at the
// top, as chunk-picker-<version digits>.zip. It refuses anything that must never ship: a version
// that isn't digits and dots or disagrees with the manifest, probe or test files, the beta dev
// tools and cheat commands. A Hub build leaves loopback server URLs out of the zipped manifest
// and needs at least one HTTPS server; --allow-local keeps them, for a beta zip.
// Run: node tools/build-release.mjs <output dir outside the repo> --version 0.1.0 [--allow-local]
import { mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { crc32, deflateRawSync } from 'node:zlib';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Jagex's dev cheat commands, and the call that runs them. Comments count too: a shipped file
// that names them invites the question in review.
const CHEATS = /ExecuteConsoleCommand|!(tele|give|bank|getcoord|coordsave|coordtele|objadd|listinv|clearinv|clearworn|listlocs|listnpcs|listobjs|skillset|setlevel|setxp|getvarc?|setvarc?|godmode|maxhp|hitall|allinone|resetsave|unresetsave|setironman|pouch\w*|arch\w*|invent\w*|tli\w*)\b/i;
const LOCAL = /localhost|\b127\.\d+\.\d+\.\d+|\b0\.0\.0\.0|\[::1\]/i;

export class Refusal extends Error {}

function files(dir, prefix = '') {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...files(path.join(dir, entry.name), rel));
    else if (entry.isFile()) out.push(rel);
    else throw new Refusal(`Not a plain file: ${rel}`);
  }
  return out;
}

// Returns {zip, warnings, files}; throws Refusal with the reason otherwise.
export function build({ pluginDir = path.join(repo, 'plugins', 'chunk-picker'), outDir, version, allowLocal = false, repoDir = repo }) {
  const warnings = [];
  if (typeof version !== 'string' || !/^\d+(\.\d+)*$/.test(version)) throw new Refusal('Give --version as digits and dots, e.g. 0.1.0');
  if (!outDir) throw new Refusal('Give an output directory outside the repo');
  const out = path.resolve(outDir), inside = path.relative(path.resolve(repoDir), out);
  if (!inside || (!inside.startsWith('..') && !path.isAbsolute(inside))) throw new Refusal('The output directory must be outside the repo');
  let manifest;
  try { manifest = JSON.parse(readFileSync(path.join(pluginDir, 'plugin.json'), 'utf8')); }
  catch { throw new Refusal('plugin.json is missing or not JSON'); }
  if (manifest.version !== version) throw new Refusal(`plugin.json says version ${manifest.version}, not ${version}`);
  const list = files(pluginDir);
  for (const required of ['main.lua', 'plugin.json']) if (!list.includes(required)) throw new Refusal(`${required} is missing`);
  for (const rel of list) {
    const parts = rel.toLowerCase().split('/'), name = parts.at(-1);
    if (/^probe.*\.lua$/.test(name)) throw new Refusal(`Probe file must not ship: ${rel}`);
    if (parts.some(p => p === 'dev' || p === 'tests' || p === 'test') || /\.test\./.test(name)) throw new Refusal(`Dev or test file must not ship: ${rel}`);
    if (name.startsWith('.')) throw new Refusal(`Hidden file must not ship: ${rel}`);
  }
  for (const rel of list) {
    const text = readFileSync(path.join(pluginDir, rel), 'latin1');
    const hit = text.match(CHEATS);
    if (hit) throw new Refusal(`Cheat command in ${rel}: ${hit[0]}`);
  }
  const urls = Object.entries(manifest.urls ?? {});
  const local = urls.filter(([, url]) => LOCAL.test(String(url))).map(([name]) => name);
  let manifestData = readFileSync(path.join(pluginDir, 'plugin.json'));
  if (allowLocal) {
    if (local.length) warnings.push(`Beta build only: loopback server URLs (${local.join(', ')})`);
  } else {
    const hosted = urls.filter(([name]) => !local.includes(name));
    if (!hosted.length) throw new Refusal(`Only loopback server URLs in plugin.json (${local.join(', ')}); a Hub build needs the hosted picker. --allow-local builds a beta zip anyway`);
    const plain = hosted.filter(([, url]) => !/^https:\/\//i.test(String(url))).map(([name]) => name);
    if (plain.length) throw new Refusal(`Hub server URLs must use HTTPS: ${plain.join(', ')}`);
    if (local.length) {
      manifestData = Buffer.from(JSON.stringify({ ...manifest, urls: Object.fromEntries(hosted) }, null, 2) + '\n');
      warnings.push(`Left loopback servers out of the Hub manifest: ${local.join(', ')}`);
    }
  }
  mkdirSync(out, { recursive: true });
  const zip = path.join(out, `chunk-picker-${version.replaceAll('.', '')}.zip`);
  writeFileSync(zip, zipFiles(list.map(rel => ({ name: rel, data: rel === 'plugin.json' ? manifestData : readFileSync(path.join(pluginDir, rel)) }))));
  return { zip, warnings, files: list };
}

// A plain deflate zip with a fixed timestamp, so the same tree gives the same bytes.
export function zipFiles(entries) {
  const locals = [], centrals = [];
  let offset = 0;
  const time = 0, date = (2026 - 1980) << 9 | 1 << 5 | 1;
  for (const { name, data } of entries) {
    const nameBytes = Buffer.from(name, 'utf8'), packed = deflateRawSync(data, { level: 9 }), crc = crc32(data);
    const head = Buffer.alloc(30);
    head.writeUInt32LE(0x04034b50, 0); head.writeUInt16LE(20, 4); head.writeUInt16LE(0x0800, 6); head.writeUInt16LE(8, 8);
    head.writeUInt16LE(time, 10); head.writeUInt16LE(date, 12); head.writeUInt32LE(crc, 14);
    head.writeUInt32LE(packed.length, 18); head.writeUInt32LE(data.length, 22); head.writeUInt16LE(nameBytes.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6); central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(8, 10); central.writeUInt16LE(time, 12); central.writeUInt16LE(date, 14); central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(packed.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(nameBytes.length, 28);
    central.writeUInt32LE(offset, 42);
    locals.push(head, nameBytes, packed); centrals.push(central, nameBytes);
    offset += head.length + nameBytes.length + packed.length;
  }
  const size = centrals.reduce((n, b) => n + b.length, 0), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(size, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, ...centrals, end]);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), flag = name => args.includes(name);
  const value = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
  const outDir = args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--version');
  try {
    const result = build({ outDir, version: value('--version'), allowLocal: flag('--allow-local') });
    for (const w of result.warnings) console.warn(`WARNING: ${w}`);
    console.log(`Built ${result.zip} (${result.files.length} files, ${statSync(result.zip).size} bytes)`);
  } catch (error) {
    if (!(error instanceof Refusal)) throw error;
    console.error(`REFUSED: ${error.message}`);
    process.exitCode = 1;
  }
}
