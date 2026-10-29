import { buildPlaylist, hydrateVersion, resolveAt } from './vendor/schedule-engine.js';

export const LIVE_BASE = 'https://jbuopkuluyfjwgsrigry.supabase.co/storage/v1/object/public/broadcast/';
export const SNAPSHOT_BASE = 'https://spelunkr.tv/broadcast/';
export const MAX_ENGINE = 5;
const archiveFile = (id, file) => `https://archive.org/download/${encodeURIComponent(id)}/${file.split('/').map(encodeURIComponent).join('/')}`;

export class Broadcast {
  constructor({ fetcher = fetch, now = Date.now } = {}) {
    // Browser Worker.fetch requires its global receiver; Node's fetch tolerated an unbound method.
    this.fetcher = fetcher.bind(globalThis);
    this.now = now;
    this.assets = new Map();
    this.playlists = new Map();
    this.lineupAt = 0;
    this.source = 'live';
  }

  async json(url) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 12000);
    try {
      const response = await this.fetcher(url, { signal: controller.signal, headers: { accept: 'application/json' } });
      if (!response.ok) throw new Error(`Upstream returned ${response.status}`);
      return await response.json();
    } finally { clearTimeout(timeout); }
  }

  async asset(path, snapshot = false) {
    if (!/^(manifests|platform|details)\/[a-zA-Z0-9_./-]+\.json$/.test(path) || path.includes('..')) throw new Error('Invalid broadcast asset path');
    const key = `${snapshot}:${path}`;
    if (!this.assets.has(key)) {
      this.assets.set(key, this.json((snapshot ? SNAPSHOT_BASE : LIVE_BASE) + path).catch(async error => {
        if (!snapshot) return this.json(SNAPSHOT_BASE + path);
        throw error;
      }).catch(error => { this.assets.delete(key); throw error; }));
    }
    return this.assets.get(key);
  }

  async lineup() {
    if (this.lineupData && this.now() - this.lineupAt < 60000) return this.lineupData;
    if (this.lineupPending) return this.lineupPending;
    this.lineupPending = (async () => {
      let data;
      try { data = await this.json(LIVE_BASE + 'lineup.json'); this.source = 'live'; }
      catch {
        // A cached live schedule has priority over an older website snapshot.
        if (this.lineupData) { this.source = 'cached'; this.lineupAt = this.now(); return this.lineupData; }
        data = await this.json(SNAPSHOT_BASE + 'lineup.json'); this.source = 'snapshot';
      }
      if (!Array.isArray(data.channels)) throw new Error('The broadcast lineup is invalid');
      if (data.engine > MAX_ENGINE) throw new Error('Spelunkr updated its schedule engine. The adapter needs an engine update.');
      this.lineupData = { ...data, channels: data.channels.filter(c => c.dial != null && !c.debugOnly && !c.comingSoon).sort((a, b) => a.dial - b.dial) };
      this.lineupAt = this.now();
      return this.lineupData;
    })().finally(() => { this.lineupPending = null; });
    return this.lineupPending;
  }

  async channel(id) {
    const lineup = await this.lineup();
    const channel = lineup.channels.find(c => c.id === id);
    if (!channel) throw Object.assign(new Error('No such channel'), { status: 404 });
    const signature = JSON.stringify(channel.versions);
    const cached = this.playlists.get(id);
    if (cached?.signature === signature) return cached.promise;
    const snapshot = this.source === 'snapshot';
    const promise = Promise.all(channel.versions.map(async pointer => {
      const manifest = await this.asset(pointer.manifest, snapshot);
      if (manifest.engine > MAX_ENGINE) throw new Error('Unsupported schedule engine');
      const platform = manifest.platform ? await this.asset(manifest.platform, snapshot) : null;
      return hydrateVersion(manifest, platform, pointer);
    })).then(versions => ({ ...channel, playlist: buildPlaylist(id, versions) })).catch(error => {
      this.playlists.delete(id);
      throw error;
    });
    this.playlists.set(id, { signature, promise });
    // Bound old versions when live updates arrive. In-use playlist objects remain valid.
    if (this.assets.size > 250) this.assets.delete(this.assets.keys().next().value);
    return promise;
  }

  program(channel, position) {
    const { item } = position;
    return {
      key: position.key, type: item.type, id: item.id || '',
      title: item.title || (item.type === 'ad' ? 'A word from the past' : item.type === 'up-next' ? 'Up next' : 'Station break'),
      year: item.year || '', startMs: position.startMs, endMs: position.endMs,
      image: item.id ? `https://archive.org/services/img/${encodeURIComponent(item.id)}` : '',
      description: channel.description,
    };
  }

  async guide({ at = this.now(), hours = 2 } = {}) {
    const lineup = await this.lineup();
    const startMs = Math.floor(at / 1800000) * 1800000;
    const endMs = startMs + hours * 3600000;
    // Each channel can fail independently; keep its row visible and retry next refresh.
    const channels = await Promise.all(lineup.channels.map(async entry => {
      const row = { id: entry.id, number: entry.dial, name: entry.name, color: entry.color, description: entry.description, programs: [] };
      try {
        const channel = await this.channel(entry.id);
        row.now = this.program(channel, resolveAt(channel.playlist, at));
        let cursor = startMs;
        for (let count = 0; cursor < endMs && count < 600; count++) {
          const position = resolveAt(channel.playlist, cursor);
          if (position.endMs <= cursor) throw new Error('Schedule failed to advance');
          const program = this.program(channel, position);
          // Keep breaks in the timeline without making every station ID a tiny cell.
          const previous = row.programs[row.programs.length - 1];
          if (program.type !== 'video' && previous) previous.endMs = program.endMs;
          else row.programs.push(program);
          cursor = position.endMs;
        }
      } catch (error) { row.error = error.message; }
      return row;
    }));
    return { serverTime: this.now(), generatedAt: lineup.generatedAt, source: this.source, startMs, endMs, channels };
  }

  async mediaUrl(item) {
    let file = item.file || item.mp4;
    if (!file || !/\.(mp4|m4v|mov)$/i.test(file)) {
      const data = await this.json(`https://archive.org/metadata/${encodeURIComponent(item.id)}`);
      const candidates = (data.files || []).filter(f => /\.(mp4|m4v)$/i.test(f.name));
      file = (candidates.find(f => f.format === 'h.264 IA') || candidates.find(f => f.format === 'h.264') || candidates[0])?.name;
    }
    return file ? archiveFile(item.id, file) : null;
  }

  async tune(id) {
    const channel = await this.channel(id);
    const at = this.now();
    const position = resolveAt(channel.playlist, at);
    const { item } = position;
    const result = {
      serverTime: at, channel: { id, number: channel.dial, name: channel.name, color: channel.color },
      ...this.program(channel, position), offset: position.offsetExact,
      url: '', seek: 0, cards: [], audioUrl: '', audioSeek: 0,
    };
    if (item.type === 'video') {
      result.url = await this.mediaUrl(item) || '';
      result.seek = (item.inS || 0) + position.offsetExact;
      if (!result.url) result.message = 'This tape has no Roku-compatible video. The next program will tune automatically.';
    } else if (item.type === 'ad') {
      result.url = archiveFile(item.slice.tape, item.slice.file);
      result.seek = (item.slice.inMs || 0) / 1000 + position.offsetExact;
    } else {
      const groups = [item.channelBump, item.platformBump].filter(Boolean);
      let cursor = item.half === 'close' ? 0 : 3500;
      for (const [index, bump] of groups.entries()) {
        for (const slide of bump.slides || []) {
          const length = Math.max(2500, 1500 + slide.text.length * 55);
          result.cards.push({ text: slide.text, start: cursor, end: cursor + length });
          cursor += length;
        }
        cursor += 2000 + (index === 0 && groups.length > 1 ? 300 : 0);
      }
      const audio = item.channelAudio || item.platformAudio;
      if (audio?.filename) {
        const lineup = await this.lineup();
        // audio.url is the artist's attribution page, not an audio stream.
        result.audioUrl = `${lineup.audioBase || 'https://audio.spelunkr.tv/bumps/'}${encodeURIComponent(audio.filename)}`;
        result.audioSeek = (audio.startOffset || 0) + position.offsetExact;
      }
      if (item.type === 'up-next') {
        const next = resolveAt(channel.playlist, position.endMs);
        result.cards = [{ text: `UP NEXT\n${next.item.title || channel.name}`, start: 0, end: item.durMs }];
      }
    }
    // Request time must be reflected in seek; slow Archive metadata cannot move us behind live.
    const readyAt = this.now();
    result.seek += (readyAt - at) / 1000;
    result.audioSeek += (readyAt - at) / 1000;
    result.serverTime = readyAt;
    return result;
  }
}
