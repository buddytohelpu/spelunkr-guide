import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server/index.js';

test('serves the guide, validates API inputs, and confines static files to web/', async t => {
  const app = createApp({ broadcast: { guide: async () => ({ channels: [] }), tune: async id => ({ channel: id }) } });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(() => { app.closeAllConnections(); app.close(); });
  const origin = `http://127.0.0.1:${app.address().port}`;
  const home = await fetch(origin);
  assert.equal(home.status, 200); assert.match(await home.text(), /THE CHANNEL GUIDE/);
  assert.deepEqual(await (await fetch(origin + '/api/guide')).json(), { channels: [] });
  assert.equal((await fetch(origin + '/api/guide?at=invalid')).status, 400);
  assert.equal((await fetch(origin + '/api/guide?hours=500')).status, 400);
  assert.equal((await fetch(origin + '/api/tune/bad%2Fchannel')).status, 400);
  assert.equal((await fetch(origin + '/%2e%2e%2fpackage.json')).status, 403);
  assert.equal((await fetch(origin + '/not-here')).status, 404);
  assert.equal((await fetch(origin + '/api/guide', { method: 'POST' })).status, 405);
});
