import test from 'node:test';
import assert from 'node:assert/strict';
import { GuideState } from '../web/guide-state.js';

const channels = [
  { id: 'a', programs: [{ key: 'a1', startMs: 0, endMs: 100 }, { key: 'a2', startMs: 100, endMs: 200 }] },
  { id: 'b', programs: [{ key: 'b1', startMs: 0, endMs: 200 }] },
  { id: 'broken', programs: [], error: 'No signal' },
];
test('browsing does not change the tuned channel until OK', () => {
  const s = new GuideState(); s.setChannels(channels, 10); s.tune();
  s.moveChannel(1, 10);
  assert.equal(s.selectedChannel.id, 'b'); assert.equal(s.tunedId, 'a');
  s.tune(); assert.equal(s.tunedId, 'b');
});
test('channel surfing wraps in both directions and resets to the current program', () => {
  const s = new GuideState(); s.setChannels(channels, 150);
  assert.equal(s.programIndex, 1);
  s.moveChannel(-1, 150); assert.equal(s.selectedChannel.id, 'broken');
  s.moveChannel(1, 150); assert.equal(s.selectedChannel.id, 'a'); assert.equal(s.programIndex, 1);
});
test('left/right stays within the available schedule and failed channels cannot tune', () => {
  const s = new GuideState(); s.setChannels(channels, 10);
  s.moveProgram(-100); assert.equal(s.programIndex, 0);
  s.moveProgram(100); assert.equal(s.programIndex, 1);
  s.selectChannel('broken', 10); assert.equal(s.tune(), null);
});
test('a lineup refresh keeps selection by channel identity', () => {
  const s = new GuideState(); s.setChannels(channels, 10); s.selectChannel('b', 10);
  s.setChannels([...channels].reverse(), 10);
  assert.equal(s.selectedChannel.id, 'b');
  s.setChannels([], 10); s.moveChannel(1); assert.equal(s.tune(), null);
});
