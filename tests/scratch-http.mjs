// Run: node tests/scratch-http.mjs <JSON requests exported by the Lua harness>
// PICKER_SOURCE picks the picker checkout; SCRATCH_HTTP_PORT the free loopback port (default 8950).
// Only the scratch child imports picker code; environment overrides precede imports.
import assert from 'node:assert/strict';
import { fork } from 'node:child_process';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile } from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const source = process.env.PICKER_SOURCE ?? 'C:/Users/User/Projects/chunk-picker-rs3/.local/claude-tools/plugin-port';
const port = Number(process.env.SCRATCH_HTTP_PORT ?? 8950);
const scratch = 'C:/Users/User/Projects/chunk-picker-rs3/.local/claude-tools/lua-harness/scratch-picker';
const origin = `http://127.0.0.1:${port}`;
const reportPath = '/api/plugin/v1/report';
const statusPath = '/api/plugin/v1/status';
const tasksPath = '/api/plugin/v1/tasks';
const self = fileURLToPath(import.meta.url);

function insideScratch(directory) {
  const relative = path.relative(path.resolve(scratch), path.resolve(directory));
  assert.ok(relative && !relative.startsWith('..') && !path.isAbsolute(relative), 'Scratch child requires a fresh subdirectory');
}

async function serve(directory) {
  insideScratch(directory);
  // Drop inherited operator selection, private add-ons and optional listeners.
  for (const key of Object.keys(process.env)) if (key.startsWith('RS3_')) delete process.env[key];
  Object.assign(process.env, {
    RS3_DATASET: 'open-starter',
    RS3_PACKS_DIR: path.join(directory, 'packs'),
    RS3_PACK_SELECTION: path.join(directory, 'packs', 'selection.json'),
    RS3_GAME_DATA_DIR: path.join(directory, 'game-data'),
    RS3_MAP_ASSETS_DIR: path.join(directory, 'map-assets'),
  });
  const moduleAt = relative => pathToFileURL(path.join(source, relative)).href;
  const { createServer } = await import(moduleAt('app/server.mjs'));
  const { createGroupState } = await import(moduleAt('app/core/state.mjs'));
  const definitions = {
    chunks: { '12850': { Name: 'Synthetic Lumbridge' }, '13613': { Name: 'Synthetic second chunk' } },
    walkableChunks: ['12850', '13613'], walkableChunksF2P: ['12850', '13613'],
  };
  let app;
  let stopping;
  const stop = () => stopping ??= (async () => { await app?.close(); if (process.connected) process.disconnect(); })();
  process.on('message', message => {
    if (message === 'stop') void stop();
    // Stands in for a player opening the task list in the picker, which saves it.
    if (message === 'load-tasks') void fetch(`${origin}/api/tasks?memberId=synthetic`, { redirect: 'error',
      headers: { Authorization: `Bearer ${app.store.getAccessToken()}` }, signal: AbortSignal.timeout(60000) })
      .then(async response => { await response.arrayBuffer(); process.send({ loaded: response.status }); })
      .catch(error => process.send({ loaded: `failed (${error.name})` }));
  });
  process.on('disconnect', () => { void stop(); });
  process.on('SIGTERM', () => { void stop(); });
  process.on('SIGINT', () => { void stop(); });
  try {
    app = await createServer({
      dataDir: path.join(directory, 'save'), host: '127.0.0.1', port,
      loopbackPort: undefined, publicOrigin: undefined, predictionPrewarm: false,
      definitions, taskMap: {},
      initialState: createGroupState([{ id: 'synthetic', name: 'Synthetic player', unlocked: ['12850'] }]),
      packsDir: path.join(directory, 'packs'), gameDataDir: path.join(directory, 'game-data'),
      mapAssetsDir: path.join(directory, 'map-assets'),
      resourcesRoot: path.join(directory, 'resources'), worldImagesRoot: path.join(directory, 'world-images'),
      privateAddonOptions: {},
    });
    await app.listen();
    // The fresh store generates its own master credential. Keep it in memory.
    const provision = await fetch(`${origin}/api/game-plugin/keys`, {
      method: 'POST', redirect: 'error',
      headers: { Authorization: `Bearer ${app.store.getAccessToken()}`, Origin: origin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ memberId: 'synthetic', label: 'Synthetic HTTP harness' }),
    });
    assert.equal(provision.status, 201, 'Scratch key provisioning failed');
    const { key } = await provision.json();
    assert.ok(typeof key === 'string' && /^gpk_[A-Za-z0-9_-]{43}$/.test(key), 'Scratch provisioning returned an invalid key');
    process.send({ ready: true, key });
  } catch (error) {
    // Report only controlled text: exception objects could contain credentials.
    process.send?.({ error: `Scratch startup failed (${error.code ?? error.name ?? 'error'})` });
    await stop();
    process.exitCode = 1;
  }
}

function statusShape(body) {
  assert.deepEqual(Object.keys(body).sort(), ['v', 'player', 'chunkId', 'chunkName', 'state', 'activeTaskCount', 'unlockedChunkCount', 'pendingProgress', 'seenAt', 'nearby',
    'pickableCount', 'pendingRoll', 'partners'].sort());
  assert.ok(body.nearby === null || Array.isArray(body.nearby) && body.nearby.length <= 25 && body.nearby.every(row =>
    Object.keys(row).sort().join() === 'chunkId,state' && /^\d+$/.test(row.chunkId) && ['unlocked', 'locked', 'available', 'unknown'].includes(row.state)));
  assert.equal(body.nearby === null, body.chunkId === null);
  assert.equal(body.v, 1);
  assert.deepEqual(body.player, { id: 'synthetic', name: 'Synthetic player' });
  assert.ok(['unlocked', 'locked', 'available', 'unknown'].includes(body.state));
  assert.ok(body.activeTaskCount === null || Number.isSafeInteger(body.activeTaskCount) && body.activeTaskCount >= 0);
  assert.equal(body.unlockedChunkCount, 1);
  assert.ok(body.pickableCount === null || Number.isSafeInteger(body.pickableCount));
  assert.deepEqual(body.pendingRoll, []);
  assert.deepEqual(body.partners, [], 'A one-player save has no partners');
  assert.equal(typeof body.pendingProgress, 'boolean');
  assert.ok(body.chunkId === null || /^\d+$/.test(body.chunkId));
  assert.ok(body.chunkName === null || typeof body.chunkName === 'string');
  assert.ok(body.seenAt === null || Number.isFinite(Date.parse(body.seenAt)));
}

function tasksShape(body) {
  assert.deepEqual(Object.keys(body).sort(), ['v', 'ready', 'stale', 'stateRevision', 'chunkId', 'hereKnown', 'here', 'all', 'hereCount', 'allCount'].sort());
  assert.equal(body.v, 1);
  for (const key of ['ready', 'stale', 'hereKnown']) assert.equal(typeof body[key], 'boolean');
  assert.ok(Number.isSafeInteger(body.stateRevision));
  assert.ok(body.chunkId === null || /^\d+$/.test(body.chunkId));
  assert.ok(body.here.length <= 50 && body.all.length <= 100 && body.hereCount >= body.here.length && body.allCount >= body.all.length);
  for (const row of [...body.here, ...body.all]) {
    assert.ok(Object.keys(row).every(key => ['id', 'label', 'category', 'level'].includes(key)));
    assert.ok(typeof row.label === 'string' && row.label.length <= 120 && !/[\x00-\x1f]/.test(row.label));
  }
}

async function main(fixtureFile) {
  assert.ok(fixtureFile, 'Provide JSON fixtures exported by the actual Lua module');
  const document = JSON.parse(await readFile(path.resolve(fixtureFile), 'utf8'));
  const rows = Array.isArray(document) ? document : document.requests;
  assert.ok(Array.isArray(rows) && rows.length, 'Expected request array or {requests: [...]}');
  let previous = -1;
  const requests = rows.map(row => {
    const request = row.v === 1 ? { method: 'POST', path: reportPath, body: row } : row;
    const route = request.path ?? request.route;
    assert.ok([reportPath, statusPath, tasksPath].includes(route), 'Fixture may only select the plugin routes');
    assert.equal(request.method, route === reportPath ? 'POST' : 'GET');
    let body = request.body;
    if (typeof body === 'string') body = JSON.parse(body);
    if (route === reportPath) {
      assert.equal(body.v, 1);
      assert.ok(Number.isSafeInteger(body.seq) && body.seq > previous, 'Exported sequence must increase safely');
      previous = body.seq;
      assert.match(body.sentAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/);
      assert.ok(Number.isFinite(Date.parse(body.sentAt)));
    } else assert.equal(body, undefined, 'Plugin reads must have no body');
    return { method: request.method, path: route, body };
  });
  assert.ok(requests.some(row => row.path === reportPath), 'Need at least one real exported report');
  // Refuse to attach to any existing process, even a previous scratch server.
  const probe = net.createServer();
  await new Promise((resolve, reject) => { probe.once('error', reject); probe.listen(port, '127.0.0.1', resolve); });
  await new Promise((resolve, reject) => probe.close(error => error ? reject(error) : resolve()));
  await mkdir(scratch, { recursive: true });
  const directory = await mkdtemp(path.join(scratch, 'run-'));
  insideScratch(directory);
  const child = fork(self, ['--serve', directory], { cwd: directory, stdio: ['ignore', 'ignore', 'ignore', 'ipc'] });
  let key;
  const exited = once(child, 'exit');
  try {
    const ready = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Scratch startup timed out')), 60000);
      child.once('message', message => { clearTimeout(timer); message.ready ? resolve(message) : reject(new Error(message.error ?? 'Scratch startup failed')); });
      child.once('exit', () => { clearTimeout(timer); reject(new Error('Scratch child exited before readiness')); });
    });
    key = ready.key;
    async function request(row, expectedStatus = 200) {
      await delay(300); // Stay below the shared four requests/second budget.
      const response = await fetch(`${origin}${row.path}`, {
        method: row.method, redirect: 'error', signal: AbortSignal.timeout(10000),
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        ...(row.body === undefined ? {} : { body: JSON.stringify(row.body) }),
      });
      assert.equal(response.status, expectedStatus, `${row.method} ${row.path} expected ${expectedStatus}, got ${response.status}`);
      const result = await response.json();
      if (expectedStatus === 200) (row.path === tasksPath ? tasksShape : statusShape)(result);
      return result;
    }
    const initial = await request({ method: 'GET', path: statusPath });
    assert.equal(initial.chunkId, null);
    assert.equal(initial.pendingProgress, false);
    const revision = 0;
    let pending = false;
    for (const row of requests) {
      const result = await request(row);
      if (row.path === tasksPath) { assert.equal(result.ready, false, 'Nobody has opened the task list, so nothing was calculated'); continue; }
      if (row.body) {
        assert.equal(result.chunkId, String(row.body.position.x * 256 + row.body.position.z));
        pending ||= row.body.skills !== undefined || row.body.quests !== undefined;
      }
      assert.equal(result.pendingProgress, pending);
    }
    // Once the picker has saved a list, the plugin reads it without another calculation.
    child.send('load-tasks');
    const loaded = await new Promise(resolve => child.once('message', message => resolve(message.loaded)));
    // The isolated open-starter save has no task catalogue, so the picker answers 503 and the
    // list stays not ready. With task data the list must come back saved and current.
    assert.ok(loaded === 200 || loaded === 503, `The picker's own task load returned ${loaded}`);
    const tasks = await request({ method: 'GET', path: tasksPath });
    assert.equal(tasks.ready, loaded === 200); assert.equal(tasks.stale, false);
    if (tasks.ready) assert.equal(tasks.hereKnown, tasks.chunkId !== null);
    const lastReport = requests.filter(row => row.path === reportPath).at(-1);
    await request(lastReport, 409);
    const status = await request({ method: 'GET', path: statusPath });
    assert.equal(status.chunkId, String(lastReport.body.position.x * 256 + lastReport.body.position.z));
    // The in-memory report must not change the saved unlocks or revision.
    const saved = JSON.parse(await readFile(path.join(directory, 'save', 'state.json'), 'utf8'));
    const state = saved.state ?? saved;
    assert.equal(state.revision, revision);
    assert.deepEqual(state.members[0].unlocked, ['12850']);
    assert.equal(state.members[0].skillProgress, undefined);
    console.log(`PASS: ${requests.length} exported requests, status and task shapes (${tasks.ready ? `${tasks.allCount} active after a picker load` : 'no task data in this save'}), stale-sequence rejection and unchanged synthetic save`);
    console.log(`Source: ${source}\nRuntime: ${directory}\nEndpoint: ${origin} (scratch child only)`);
  } finally {
    key = undefined;
    if (child.connected) child.send('stop');
    let timer;
    const shutdownTimeout = new Promise(resolve => { timer = setTimeout(() => { child.kill(); resolve(); }, 12000); });
    await Promise.race([exited, shutdownTimeout]);
    clearTimeout(timer);
    if (child.exitCode === null && child.signalCode === null) await exited;
    console.log('Scratch server stopped. Synthetic runtime files retained locally.');
  }
}

try {
  if (process.argv[2] === '--serve') await serve(process.argv[3]);
  else await main(process.argv[2]);
} catch (error) {
  // Never dump fixture contents, HTTP headers, IPC messages or master/key values.
  console.error(`FAIL: ${error.message}`);
  process.exitCode = 1;
}
