// Fake game: posts a recorded sequence of plugin reports to a picker, so picker-side checks run
// without logging in. Each fixture line is one report without v, seq and sentAt, which are
// filled in here the way net.lua does. Blank lines and lines starting with # are skipped.
// Run: node tools/replay.mjs <picker origin> <key file> <fixture.jsonl> [--gap ms] [--allow-remote] [--allow-live-world]
// The key is read from the file and never printed; neither is the picker's address.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

export const REPORT = '/api/plugin/v1/report', STATUS = '/api/plugin/v1/status';
const KEY = /^gpk_[A-Za-z0-9_-]{20,200}$/;

export class ReplayError extends Error {}

// Fixture lines as reports; bad JSON names its line.
export function parseFixture(text) {
  const reports = [];
  text.split(/\r?\n/).forEach((line, i) => {
    if (!line.trim() || line.trimStart().startsWith('#')) return;
    let report;
    try { report = JSON.parse(line); } catch { throw new ReplayError(`Line ${i + 1} is not JSON`); }
    if (!report || typeof report !== 'object' || Array.isArray(report)) throw new ReplayError(`Line ${i + 1} is not a report object`);
    for (const filled of ['v', 'seq', 'sentAt']) if (filled in report) throw new ReplayError(`Line ${i + 1}: leave ${filled} out; replay fills it in`);
    if (!report.position) throw new ReplayError(`Line ${i + 1} needs a position`);
    reports.push({ line: i + 1, report });
  });
  return reports;
}

// The optional fields this report uses; the picker refuses ones its status doesn't accept.
export function needs(report) {
  const out = [];
  for (const name of ['achievements', 'items', 'bank']) if (report[name] !== undefined) out.push(name);
  if (report.items?.pouch !== undefined) out.push('pouch');
  if (report.items?.toolbelt !== undefined) out.push('toolbelt');
  return out;
}
export function kind(report) {
  return report.bank ? `bank ${report.bank.part}/${report.bank.parts}` : report.items ? 'items' : report.achievements ? 'achievements'
    : report.skills || report.quests ? 'progress' : 'position';
}
// sentAt the way net.lua writes it: whole seconds, Z.
export const iso = ms => new Date(Math.floor(ms / 1000) * 1000).toISOString().replace('.000Z', 'Z');
const redact = (text, key) => String(text ?? '').replaceAll(key, '[redacted]').replace(/gpk_[\w-]+/g, '[redacted]').replace(/https?:\/\/\S+/g, '[URL]').replace(/[\x00-\x1f]/g, ' ').slice(0, 160);

function loopback(origin) {
  try { const host = new URL(origin).hostname; return host === '127.0.0.1' || host === 'localhost' || host === '[::1]'; } catch { return false; }
}

// One line per report: line number, kind, HTTP code and what the picker's status says it holds.
export async function replay({ origin, key, reports, gapMs = 1100, allowRemote = false, allowLiveWorld = false, log = console.log, fetchImpl = fetch }) {
  if (!KEY.test(key ?? '')) throw new ReplayError('The key file does not hold a plugin key (gpk_…)');
  let url;
  try { url = new URL(origin); } catch { throw new ReplayError('The picker origin is not a URL'); }
  if (!['http:', 'https:'].includes(url.protocol) || url.pathname !== '/' || url.search) throw new ReplayError('Give the picker origin only, e.g. http://127.0.0.1:8950');
  if (!loopback(origin) && !allowRemote) throw new ReplayError('Not a loopback picker; add --allow-remote to replay into it');
  for (const { line, report } of reports) {
    if (report.world?.beta === false && !allowLiveWorld) throw new ReplayError(`Line ${line} claims a live world; live item evidence ticks real goals. Add --allow-live-world on purpose`);
  }
  const headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  const call = async (method, route, body) => {
    const response = await fetchImpl(new URL(route, url), { method, headers, body, redirect: 'error', signal: AbortSignal.timeout(30000) });
    const text = await response.text();
    let json = null; try { json = JSON.parse(text); } catch {}
    return { code: response.status, json, date: Date.parse(response.headers.get('date') ?? ''), retry: Number(response.headers.get('retry-after')) };
  };
  log(`Replaying ${reports.length} reports into a ${loopback(origin) ? 'loopback' : 'remote'} picker`);
  const first = await call('GET', STATUS);
  if (first.code === 401) throw new ReplayError('The picker did not accept the key (401)');
  if (first.code !== 200 || !first.json) throw new ReplayError(`Status check failed (HTTP ${first.code})`);
  const accepts = new Set(Array.isArray(first.json.accepts) ? first.json.accepts : []);
  // The picker's clock, as the plugin uses it, so sentAt never runs ahead of the server.
  const offset = Number.isFinite(first.date) ? first.date - Date.now() : 0;
  let seq = 0, failures = 0;
  const results = [];
  for (const [index, { line, report }] of reports.entries()) {
    const missing = needs(report).filter(name => !accepts.has(name));
    if (missing.length) { log(`line ${line} ${kind(report)}: skipped, picker doesn't accept ${missing.join(', ')}`); results.push({ line, skipped: missing }); continue; }
    if (index > 0) await delay(gapMs);
    let result;
    for (let attempt = 0; attempt < 2; attempt++) {
      const now = Date.now() + offset;
      seq = Math.max(seq + 1, now);
      result = await call('POST', REPORT, JSON.stringify({ v: 1, seq, sentAt: iso(now), ...report }));
      if (result.code !== 429 || attempt) break;
      await delay(1000 * Math.min(120, result.retry > 0 ? result.retry : 60));
    }
    const s = result.json ?? {};
    const parts = [`HTTP ${result.code}`];
    if (result.code === 200) {
      parts.push(`chunk ${s.chunkId ?? 'none'} ${s.state ?? '?'}`);
      if (report.items) parts.push(`items ${s.items?.snapshot === report.items.snapshot ? 'held' : 'not held'}`);
      if (report.bank) parts.push(`bank ${s.bank?.snapshot === report.bank.snapshot ? 'held' : report.bank.part < report.bank.parts ? 'part taken' : 'not held'}`);
    } else {
      failures++;
      if (s.error) parts.push(redact(s.error, key));
    }
    log(`line ${line} ${kind(report)}: ${parts.join('; ')}`);
    results.push({ line, code: result.code, status: result.json });
  }
  return { results, failures };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), positional = [];
  let gapMs = 1100;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--gap') gapMs = Number(args[++i]);
    else if (!args[i].startsWith('--')) positional.push(args[i]);
  }
  const [origin, keyFile, fixture] = positional;
  try {
    if (!origin || !keyFile || !fixture) throw new ReplayError('Usage: node tools/replay.mjs <picker origin> <key file> <fixture.jsonl> [--gap ms] [--allow-remote] [--allow-live-world]');
    if (!Number.isFinite(gapMs) || gapMs < 0) throw new ReplayError('--gap takes milliseconds');
    let key;
    try { key = readFileSync(keyFile, 'utf8').trim(); } catch { throw new ReplayError('Could not read the key file'); }
    const { failures } = await replay({ origin, key, reports: parseFixture(readFileSync(fixture, 'utf8')), gapMs,
      allowRemote: args.includes('--allow-remote'), allowLiveWorld: args.includes('--allow-live-world') });
    if (failures) process.exitCode = 1;
  } catch (error) {
    // Only our own messages: a fetch error could carry the address.
    console.error(`REPLAY STOPPED: ${error instanceof ReplayError ? error.message : `request failed (${error.name})`}`);
    process.exitCode = 1;
  }
}
