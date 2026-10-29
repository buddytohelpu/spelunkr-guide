import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { Writable } from 'node:stream';
import brs from '@rokucommunity/brs';
import { buildPlaylist, hydrateVersion, resolveAt } from '../server/vendor/schedule-engine.js';

export const playlistFor = fixture => buildPlaylist(fixture.id, fixture.versions.map(v => hydrateVersion(v.manifest, v.platform, v.pointer)));
export function projectPosition(p) {
  const item = p.item;
  return { key: p.key, type: item.type, id: item.id || '', startMs: p.startMs, endMs: p.endMs, offsetExact: p.offsetExact,
    adId: item.slice?.id || '', channelBump: item.channelBump?.id || '', platformBump: item.platformBump?.id || '',
    audio: item.channelAudio?.filename || '', audioOffset: item.channelAudio?.startOffset || 0 };
}
export function referencePositions(fixture) {
  const playlist = playlistFor(fixture);
  return fixture.times.map(at => projectPosition(resolveAt(playlist, at)));
}
export async function nativeRun(input) {
  const root = await mkdtemp(join(tmpdir(), 'spelunkr-native-'));
  let stdout = '', stderr = '';
  const stream = append => new Writable({ write(chunk, encoding, callback) { append(chunk.toString()); callback(); } });
  try {
    await writeFile(join(root, 'input.json'), JSON.stringify({ seeds: [], texts: [], cases: [], ...input }));
    await brs.execute(['roku/source/utils.brs', 'roku/source/schedule.brs', 'tests/native-harness.brs'].map(p => resolve(p)), {
      root, noColor: true, stdout: stream(s => { stdout += s; }), stderr: stream(s => { stderr += s; }),
    });
    if (stderr.trim()) throw new Error(stderr);
    return JSON.parse(stdout.trim());
  } catch (error) { throw new Error(`${error.message}\n${stderr}\n${stdout}`); }
  finally { await rm(root, { recursive: true, force: true }); }
}
