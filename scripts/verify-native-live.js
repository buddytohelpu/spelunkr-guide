// Optional network integration check: execute the shipped BrightScript against
// every current public channel and compare it with the pinned website scheduler.
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { nativeRun, playlistFor, referencePositions } from '../tests/native-helper.js';
import { resolveAt } from '../server/vendor/schedule-engine.js';
import { LIVE_BASE } from '../server/broadcast.js';

async function verify(fixture) {
  try {
    const actual = await nativeRun({ cases: [fixture] });
    const expected = referencePositions(fixture);
    for (let i = 0; i < expected.length; i++) assert.deepEqual(actual.cases[0][i], expected[i], `${fixture.id} at ${fixture.times[i]}`);
    return { id: fixture.id, positions: expected.length, ok: true };
  } catch (error) { return { id: fixture.id, ok: false, error: error.message, actual: error.actual, expected: error.expected }; }
}

if (!isMainThread) {
  parentPort.postMessage(await verify(workerData));
} else if (process.argv.includes('--retry-failed')) {
  const input = JSON.parse(await readFile('output/research/native-parity-input.json'));
  const report = JSON.parse(await readFile('output/research/native-parity-report.json'));
  for (let i = 0; i < report.results.length; i++) {
    if (!report.results[i].ok) {
      const result = await verify(input.fixtures.find(f => f.id === report.results[i].id));
      report.results[i] = result;
      console.log(`${result.ok ? 'PASS' : 'FAIL'} ${result.id}: ${result.ok ? result.positions + ' positions' : JSON.stringify(result)}`);
    }
  }
  report.verifiedAt = Date.now();
  report.positions = report.results.reduce((n, r) => n + (r.positions || 0), 0);
  await writeFile('output/research/native-parity-report.json', JSON.stringify(report, null, 2));
  console.log(`Checked ${report.channels} channels / ${report.positions} positions.`);
  if (report.results.some(r => !r.ok)) process.exitCode = 1;
} else {
  const assets = new Map();
  const json = path => {
    if (!assets.has(path)) assets.set(path, fetch(LIVE_BASE + path, { signal: AbortSignal.timeout(20000) }).then(r => { if (!r.ok) throw new Error(`${path}: ${r.status}`); return r.json(); }));
    return assets.get(path);
  };
  const lineup = await json('lineup.json');
  const at = Date.now();
  const fixtures = await Promise.all(lineup.channels.filter(c => c.dial != null && !c.debugOnly && !c.comingSoon).map(async channel => {
    const versions = await Promise.all(channel.versions.map(async pointer => {
      const manifest = await json(pointer.manifest);
      return { pointer, manifest, platform: manifest.platform ? await json(manifest.platform) : null };
    }));
    const fixture = { id: channel.id, versions, times: [at, at + 7200000, at + 259200000] };
    const playlist = playlistFor(fixture);
    let p = resolveAt(playlist, at);
    for (let i = 0; i < 4; i++) {
      fixture.times.push(p.endMs - 1, p.endMs);
      p = resolveAt(playlist, p.endMs);
    }
    return fixture;
  }));
  await mkdir('output/research', { recursive: true });
  await writeFile('output/research/native-parity-input.json', JSON.stringify({ observedAt: at, fixtures }));
  const queue = [...fixtures];
  const results = [];
  async function run() {
    while (queue.length) {
      const fixture = queue.shift();
      const result = await new Promise((resolve, reject) => {
        const worker = new Worker(new URL(import.meta.url), { workerData: fixture });
        worker.once('message', resolve);
        worker.once('error', reject);
        worker.once('exit', code => { if (code) reject(new Error(`Worker exited ${code}`)); });
      });
      results.push(result);
      console.log(`${result.ok ? 'PASS' : 'FAIL'} ${result.id}: ${result.ok ? result.positions + ' positions' : JSON.stringify(result)}`);
    }
  }
  await Promise.all(Array.from({ length: 4 }, run));
  const report = { observedAt: at, verifiedAt: Date.now(), channels: results.length, positions: results.reduce((n, r) => n + (r.positions || 0), 0), results };
  await writeFile('output/research/native-parity-report.json', JSON.stringify(report, null, 2));
  console.log(`Checked ${report.channels} channels / ${report.positions} positions.`);
  if (results.some(r => !r.ok)) process.exitCode = 1;
}
