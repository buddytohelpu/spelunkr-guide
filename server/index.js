import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { networkInterfaces } from 'node:os';
import { Broadcast } from './broadcast.js';

const WEB_ROOT = path.resolve(fileURLToPath(new URL('../web/', import.meta.url)));
const MIME = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png', '.ttf': 'font/ttf', '.json': 'application/json' };
export function createApp({ broadcast = new Broadcast() } = {}) {
  return createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const json = (status, data) => { res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(data)); };
    try {
      if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
      if (req.method !== 'GET' && req.method !== 'HEAD') return json(405, { error: 'Method not allowed' });
      const url = new URL(req.url, 'http://localhost');
      if (url.pathname === '/api/health') return json(200, { ok: true, serverTime: Date.now() });
      if (url.pathname === '/api/guide') {
        const at = url.searchParams.has('at') ? Number(url.searchParams.get('at')) : Date.now();
        const hours = Number(url.searchParams.get('hours') || 2);
        if (!Number.isFinite(at) || Math.abs(at - Date.now()) > 86400000 || !Number.isFinite(hours) || hours < 1 || hours > 4) return json(400, { error: 'Guide range must be within a day of now and between one and four hours.' });
        return json(200, await broadcast.guide({ at, hours }));
      }
      if (url.pathname.startsWith('/api/tune/')) {
        const id = url.pathname.slice('/api/tune/'.length);
        if (!/^[a-z0-9-]+$/.test(id)) return json(400, { error: 'Invalid channel' });
        return json(200, await broadcast.tune(id));
      }
      if (url.pathname.startsWith('/api/')) return json(404, { error: 'Unknown API route' });
      const relative = decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname).replace(/^\/+/, '');
      const filename = path.resolve(WEB_ROOT, relative);
      if (!filename.startsWith(WEB_ROOT + path.sep)) return json(403, { error: 'Forbidden' });
      if (!(await stat(filename)).isFile()) return json(404, { error: 'Not found' });
      const data = await readFile(filename);
      res.writeHead(200, { 'Content-Type': MIME[path.extname(filename)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
      res.end(req.method === 'HEAD' ? undefined : data);
    } catch (error) {
      if (error.code === 'ENOENT') return json(404, { error: 'Not found' });
      console.error(error.message);
      json(error.status || 503, { error: error.message || 'The broadcast is temporarily unavailable' });
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 3000);
  const app = createApp();
  app.listen(port, '0.0.0.0', () => {
    console.log(`Spelunkr guide: http://localhost:${port}`);
    for (const iface of Object.values(networkInterfaces()).flat()) {
      if (iface.family === 'IPv4' && !iface.internal) console.log(`Browser guide:  http://${iface.address}:${port}`);
    }
  });
}
