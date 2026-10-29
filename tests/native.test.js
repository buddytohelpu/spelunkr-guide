import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolveAt } from '../server/vendor/schedule-engine.js';
import { nativeRun, playlistFor, referencePositions } from './native-helper.js';

test('native engine matches JavaScript unsigned PRNG, hashes, and UTF-16 bumper timing', async () => {
  const seeds = [0, 1, -1, 2147483647, -2147483648, 1831565813];
  const texts = ['', 'computer-chronicles-deck-12.1-0', 'Café — 📺'.repeat(12), 'हैलो नमस्ते'];
  const result = await nativeRun({ seeds, texts });
  const random = seeds.map(seed => {
    let t = seed;
    return Array.from({ length: 10 }, () => {
      t = t + 1831565813 | 0;
      let n = Math.imul(t ^ t >>> 15, 1 | t);
      n ^= n + Math.imul(n ^ n >>> 7, 61 | n);
      return ((n ^ n >>> 14) >>> 0) / 4294967296;
    });
  });
  assert.deepEqual(result.random, random);
  assert.deepEqual(result.hashes, texts.map(text => { let n = 0; for (let i = 0; i < text.length; i++) n = (n * 31 + text.charCodeAt(i)) | 0; return n; }));
  assert.deepEqual(result.lengths, texts.map(text => Math.max(2500, 1500 + text.length * 55)));
});

test('native scheduler matches observed website playback, station breaks, and both sides of epoch', async () => {
  const fixture = JSON.parse(await readFile(new URL('./fixtures/website-schedule.json', import.meta.url)));
  const channel = { id: 'computer-chronicles', versions: [fixture], times: [] };
  const playlist = playlistFor(channel);
  const observed = resolveAt(playlist, fixture.observedAt);
  channel.times = [fixture.observedAt, observed.endMs - 1, observed.endMs, resolveAt(playlist, observed.endMs).endMs, fixture.pointer.epochMs - 1, fixture.pointer.epochMs, fixture.pointer.epochMs + 1];
  const result = await nativeRun({ cases: [channel] });
  assert.deepEqual(result.cases[0], referencePositions(channel));
  assert.equal(result.cases[0][0].key, fixture.expected.key);
});

function synthetic() {
  const epoch = Date.UTC(2026, 11, 24);
  const bump = (id, text, extra = {}) => ({ id, slides: [{ text }], ...extra });
  const manifest = {
    engine: 5,
    items: Array.from({ length: 17 }, (_, i) => ({ id: `film-${i}`, duration: 73 + i * 17, year: i % 4 ? `${1940 + i * 4}` : undefined, offAir: i === 3 })),
    bumps: [bump('one', 'A 📺 on every block'.repeat(6)), bump('two', 'Hello'), bump('disabled', 'No', { active: false }), bump('seasonal', 'Winter 📼', { date_range: ['12-23', '01-02'] }), bump('dated', 'Special', { date_range: ['2026-12-24', '2026-12-24'] })],
    audio: [{ filename: 'one.mp3' }, { filename: 'two.mp3' }],
    block: { lengthMs: 700000, cardMs: 10000, stings: [{ track: 'sting.mp3', startMs: 1000, lengthMs: 11037 }] },
    ads: { gapMs: 300000, start: 833, decades: 2, slices: Array.from({ length: 37 }, (_, i) => ({ id: `ad-${i}`, lengthMs: 15501 + i * 139, year: `${1930 + i * 2}`, anywhere: i === 0 })) },
  };
  const platform = { bumps: [bump('network-1', 'Spelunkr'), bump('network-2', 'The Internet Archive'.repeat(5))], audio: [{ filename: 'network.mp3' }] };
  return { id: 'fixture', versions: [{ manifest, platform, pointer: { v: 1, epochMs: epoch, startIndex: 9 } }], times: [] };
}

test('native ads, seasonal decks, marathon cards, cycle carry, cache eviction, and version cutovers match the website', async () => {
  const fixture = synthetic();
  const playlist = playlistFor(fixture);
  let at = fixture.versions[0].pointer.epochMs;
  const last = at + 21000000;
  while (at < last) {
    const p = resolveAt(playlist, at);
    fixture.times.push(at, p.endMs - 1);
    at = p.endMs;
  }
  fixture.times.push(fixture.versions[0].pointer.epochMs + 1);
  const cutover = synthetic();
  cutover.versions.push({ ...cutover.versions[0], pointer: { v: 2, epochMs: at - 20000, effectiveAtMs: at + 15000, startIndex: 2 } });
  cutover.times = [at + 14999, at + 15000, at + 15001, at - 25000, cutover.versions[0].pointer.epochMs - 12000000];
  const result = await nativeRun({ cases: [fixture, cutover] });
  for (const [index, channel] of [fixture, cutover].entries()) {
    const expected = referencePositions(channel);
    for (let i = 0; i < expected.length; i++) assert.deepEqual(result.cases[index][i], expected[i], `case ${index}, time ${channel.times[i]}`);
  }
});
