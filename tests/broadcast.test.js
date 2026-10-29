import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Broadcast, LIVE_BASE, SNAPSHOT_BASE } from '../server/broadcast.js';
import { buildPlaylist, hydrateVersion, resolveAt } from '../server/vendor/schedule-engine.js';

const fixture = JSON.parse(await readFile(new URL('./fixtures/website-schedule.json', import.meta.url)));
test('matches the production website runtime at the exact observed timestamp', () => {
  const playlist = buildPlaylist('computer-chronicles', [hydrateVersion(fixture.manifest, fixture.platform, fixture.pointer)]);
  const p = resolveAt(playlist, fixture.observedAt);
  assert.deepEqual({ key: p.key, id: p.item.id, offset: p.offset, startMs: p.startMs, endMs: p.endMs }, fixture.expected);
});

test('binds browser-native fetch to the global receiver for direct client requests', async () => {
  const broadcast = new Broadcast({ fetcher: async function () {
    assert.equal(this, globalThis);
    return { ok: true, json: async () => ({ engine: 5, channels: [] }) };
  } });
  assert.deepEqual((await broadcast.lineup()).channels, []);
});

test('preserves the bumper interval and enters the next show exactly on its boundary', () => {
  const playlist = buildPlaylist('computer-chronicles', [hydrateVersion(fixture.manifest, fixture.platform, fixture.pointer)]);
  const current = resolveAt(playlist, fixture.observedAt);
  const lastFrame = resolveAt(playlist, current.endMs - 1);
  assert.equal(lastFrame.item.id, current.item.id);
  const breakStart = resolveAt(playlist, current.endMs);
  assert.notEqual(breakStart.item.type, 'video');
  assert.equal(breakStart.offsetExact, 0);
  let cursor = breakStart;
  for (let i = 0; cursor.item.type !== 'video' && i < 10; i++) cursor = resolveAt(playlist, cursor.endMs);
  assert.equal(cursor.item.type, 'video');
  assert.equal(cursor.item.title, 'Best Online Computer Games');
  assert.equal(cursor.offsetExact, 0);
});

test('station audio uses the media host rather than its artist attribution page', async () => {
  const playlist = buildPlaylist('computer-chronicles', [hydrateVersion(fixture.manifest, fixture.platform, fixture.pointer)]);
  const broadcast = new Broadcast({ now: () => fixture.expected.endMs + 1 });
  broadcast.channel = async () => ({ id: 'computer-chronicles', dial: 13, name: 'COMPUTER CHRONICLES', description: '', playlist });
  broadcast.lineup = async () => ({ audioBase: 'https://audio.spelunkr.tv/bumps/' });
  const tune = await broadcast.tune('computer-chronicles');
  assert.match(tune.audioUrl, /^https:\/\/audio\.spelunkr\.tv\/bumps\/.+\.mp3$/);
  assert.ok(tune.cards.length > 0);
});

test('vintage ad clips include their tape in-point when joining live', async () => {
  const version = {
    v: 1, epochMs: 0, engine: 5, items: [{ id: 'movie', duration: 120 }],
    bumps: { channelBumps: [{ id: 'channel', slides: [{ text: 'Hello' }] }], platformBumps: [{ id: 'network', slides: [{ text: 'Spelunkr' }] }] },
    ads: { gapMs: 0, slices: [{ id: 'ad-1', tape: 'tape', file: 'commercial.mp4', inMs: 75000, lengthMs: 30000 }] },
  };
  const playlist = buildPlaylist('test', [version]);
  let position = resolveAt(playlist, 120000);
  for (let i = 0; position.item.type !== 'ad' && i < 5; i++) position = resolveAt(playlist, position.endMs);
  assert.equal(position.item.type, 'ad');
  const broadcast = new Broadcast({ now: () => position.startMs + 4250 });
  broadcast.channel = async () => ({ id: 'test', dial: 2, name: 'Test', description: '', playlist });
  const tune = await broadcast.tune('test');
  assert.equal(tune.seek, 79.25);
  assert.equal(tune.url, 'https://archive.org/download/tape/commercial.mp4');
});

test('switches a published version mid-show at effectiveAtMs', () => {
  const versions = [
    { v: 1, epochMs: 100000, items: [{ id: 'a', duration: 100 }] },
    { v: 2, epochMs: 120000, effectiveAtMs: 150000, items: [{ id: 'b', duration: 100 }] },
  ];
  const playlist = buildPlaylist('test', versions);
  assert.equal(resolveAt(playlist, 149999).item.id, 'a');
  assert.equal(resolveAt(playlist, 149999).endMs, 150000);
  assert.equal(resolveAt(playlist, 150000).item.id, 'b');
  assert.equal(resolveAt(playlist, 150000).offset, 30);
});

function fakeBroadcast({ failLive = false, failManifest = false } = {}) {
  let at = 1000000;
  const lineup = { engine: 5, generatedAt: 'fixture', channels: [
    { id: 'sample', dial: 2, name: 'Sample', description: 'A test channel.', versions: [{ v: 1, epochMs: 1000000, manifest: 'manifests/sample/v1.json' }] },
    { id: 'hidden', dial: 3, debugOnly: true },
    { id: 'soon', dial: 4, comingSoon: true },
  ] };
  const manifest = { engine: 1, items: [{ id: 'tape', file: 'Folder/Film & Friends.mp4', title: 'A movie', duration: 300, inS: 10 }] };
  const calls = [];
  const broadcast = new Broadcast({ now: () => at, fetcher: async url => {
    calls.push(url);
    if (failLive && url.startsWith(LIVE_BASE)) throw new Error('offline');
    if (failManifest && url.includes('manifests/')) throw new Error('broken channel');
    return { ok: true, json: async () => url.endsWith('lineup.json') ? lineup : manifest };
  } });
  return { broadcast, calls, lineup, advance: ms => { at += ms; }, failLive: () => { failLive = true; } };
}

test('tunes trimmed videos at their live offset and escapes Archive paths', async () => {
  const { broadcast, advance } = fakeBroadcast();
  advance(31500);
  const data = await broadcast.tune('sample');
  assert.equal(data.seek, 41.5);
  assert.equal(data.startMs, 1000000);
  assert.equal(data.endMs, 1300000);
  assert.equal(data.url, 'https://archive.org/download/tape/Folder/Film%20%26%20Friends.mp4');
});

test('filters hidden channels and keeps a failed channel in the guide for recovery', async () => {
  const { broadcast } = fakeBroadcast({ failManifest: true });
  const guide = await broadcast.guide();
  assert.equal(guide.channels.length, 1);
  assert.equal(guide.channels[0].id, 'sample');
  assert.match(guide.channels[0].error, /broken channel/);
});

test('uses the website snapshot when live storage is unavailable on startup', async () => {
  const { broadcast, calls } = fakeBroadcast({ failLive: true });
  await broadcast.lineup();
  assert.equal(broadcast.source, 'snapshot');
  assert.ok(calls.includes(SNAPSHOT_BASE + 'lineup.json'));
});

test('retains the live schedule during outages instead of switching to an older snapshot', async () => {
  const f = fakeBroadcast();
  const live = await f.broadcast.lineup();
  f.advance(61000); f.failLive();
  assert.equal(await f.broadcast.lineup(), live);
  assert.equal(f.broadcast.source, 'cached');
  assert.equal(f.calls.filter(url => url.startsWith(SNAPSHOT_BASE)).length, 0);
});

test('rejects newer engines instead of silently drifting out of sync', async () => {
  const f = fakeBroadcast(); f.lineup.engine = 6;
  await assert.rejects(f.broadcast.lineup(), /engine update/);
});

test('shares manifest requests and never requests unknown channels', async () => {
  const { broadcast, calls } = fakeBroadcast();
  await Promise.all([broadcast.tune('sample'), broadcast.tune('sample')]);
  assert.equal(calls.filter(url => url.includes('manifests/')).length, 1);
  await assert.rejects(broadcast.tune('not-a-channel'), { status: 404 });
});
