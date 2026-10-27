// Run: node --test tests/replay.test.mjs
// A stub picker on a loopback port stands in for the real one.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { after, before, test } from 'node:test';
import { needs, parseFixture, replay, ReplayError } from '../tools/replay.mjs';

const KEY = 'gpk_' + 'S'.repeat(43);
const fixture = parseFixture(readFileSync(new URL('./fixtures/replay-basic.jsonl', import.meta.url), 'utf8'));
let server, origin, accepts, received;
before(async () => {
  server = createServer(async (request, response) => {
    let body = ''; for await (const chunk of request) body += chunk;
    const reply = (code, value) => { response.writeHead(code, { 'Content-Type': 'application/json' }); response.end(JSON.stringify(value)); };
    if (request.headers.authorization !== `Bearer ${KEY}`) return reply(401, { error: 'Bad key' });
    const status = { v: 1, accepts, state: 'unlocked', chunkId: '12850', items: null, bank: null };
    if (request.method === 'GET') return reply(200, status);
    const report = JSON.parse(body); received.push(report);
    if (report.position.x === 53) return reply(400, { error: `Rejected ${KEY} at http://picker.example.com/x` });
    if (report.items) status.items = { snapshot: report.items.snapshot };
    if (report.bank && report.bank.part === report.bank.parts) status.bank = { snapshot: report.bank.snapshot };
    reply(200, status);
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  origin = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

test('the fixture is synthetic, valid-looking and covers every report kind', () => {
  assert.equal(fixture.length, 5);
  assert.deepEqual(fixture.map(r => needs(r.report).join('+')), ['', 'items+pouch+toolbelt', 'bank', 'bank', '']);
  assert.ok(fixture.every(r => r.report.world.beta === true), 'beta worlds only');
  const rows = fixture.flatMap(r => [...(r.report.items?.worn ?? []), ...(r.report.items?.backpack ?? [])]).map(row => row[3]);
  assert.deepEqual(rows, ['Bronze dagger', 'Logs', 'Tinderbox']);
});

test('replays every report with v, a rising seq and sentAt, and never logs the key', async () => {
  accepts = ['achievements', 'items', 'toolbelt', 'pouch', 'bank']; received = [];
  const lines = [];
  const { failures, results } = await replay({ origin, key: KEY, reports: fixture, gapMs: 0, log: line => lines.push(line) });
  assert.equal(received.length, 5); assert.equal(failures, 1, 'the stub refuses the last report');
  for (const [i, report] of received.entries()) {
    assert.equal(report.v, 1); assert.match(report.sentAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    if (i) assert.ok(report.seq > received[i - 1].seq, 'seq rises');
  }
  assert.deepEqual(received[1].items, fixture[1].report.items, 'fixture body sent as is');
  assert.match(lines[2], /items: HTTP 200; chunk 12850 unlocked; items held/);
  assert.match(lines[3], /bank 1\/2: HTTP 200; .*bank part taken/);
  assert.match(lines[4], /bank 2\/2: HTTP 200; .*bank held/);
  assert.match(lines[5], /position: HTTP 400; Rejected \[redacted\] at \[URL\]/);
  assert.ok(lines.every(line => !line.includes(KEY) && !line.includes(origin)), 'no key or address in the log');
  assert.equal(results.length, 5);
});

test('fields the picker does not accept are skipped, not sent', async () => {
  accepts = ['items']; received = [];
  const lines = [];
  await replay({ origin, key: KEY, reports: fixture.slice(0, 3), gapMs: 0, log: line => lines.push(line) });
  assert.equal(received.length, 1, 'only the progress report goes');
  assert.match(lines[2], /skipped, picker doesn't accept pouch, toolbelt/);
  assert.match(lines[3], /skipped, picker doesn't accept bank/);
});

test('guards: key shape, remote pickers, live worlds, a refused key', async () => {
  const quiet = () => {};
  await assert.rejects(replay({ origin, key: 'not-a-key', reports: fixture, log: quiet }), /does not hold a plugin key/);
  await assert.rejects(replay({ origin: 'https://picker.example.com', key: KEY, reports: fixture, log: quiet }), /--allow-remote/);
  await assert.rejects(replay({ origin: `${origin}/api`, key: KEY, reports: fixture, log: quiet }), /origin only/);
  const live = [{ line: 1, report: { ...fixture[0].report, world: { id: 1, beta: false } } }];
  await assert.rejects(replay({ origin, key: KEY, reports: live, log: quiet }), /--allow-live-world/);
  await assert.rejects(replay({ origin, key: 'gpk_' + 'W'.repeat(43), reports: fixture, log: quiet }), /did not accept the key/);
});

test('fixture lines must leave v, seq and sentAt to replay', () => {
  assert.throws(() => parseFixture('{"v":1,"position":{"x":1,"z":1,"floor":0}}'), error => error instanceof ReplayError && /leave v out/.test(error.message));
  assert.throws(() => parseFixture('# fine\n\n{nope'), /Line 3 is not JSON/);
  assert.throws(() => parseFixture('{"world":{"id":1,"beta":true}}'), /needs a position/);
});
