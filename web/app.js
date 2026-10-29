import { GuideState } from './guide-state.js';
import { requestBroadcast } from './broadcast-client.js';

const $ = id => document.getElementById(id);
const state = new GuideState();
const video = $('video');
const audio = $('station-audio');
const time = ms => new Date(ms).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
let guide, broadcast, clockOffset = 0, generation = 0, tuneController, refreshing = false, tuning = false;
let nextTuneAt = Infinity, toastTimer, overlayTimer, videoReady = false, lastTickMinute = -1;
let appActive = true;
const platform = new URLSearchParams(location.search).get('native');
document.documentElement.dataset.platform = platform || 'browser';
if (new URLSearchParams(location.search).get('tv') === '1') document.documentElement.dataset.tv = 'true';
document.querySelector('.brand').search = location.search;
const now = () => Date.now() + clockOffset;
video.muted = !platform;
audio.muted = video.muted;
$('sound-button').textContent = video.muted ? 'SOUND OFF' : 'SOUND ON';
$('sound-button').setAttribute('aria-label', video.muted ? 'Unmute broadcast' : 'Mute broadcast');
function savedChannel() { try { return localStorage.getItem('spelunkr-channel'); } catch { return null; } }
function saveChannel(id) { try { localStorage.setItem('spelunkr-channel', id); } catch { /* private browsing */ } }
function toast(message) {
  $('toast').textContent = message;
  $('toast').classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $('toast').classList.remove('visible'), 3600);
}
function message(text = '') { $('playback-message').textContent = text; $('playback-message').classList.toggle('visible', !!text); }
async function refreshGuide(initial = false) {
  if (refreshing || !appActive) return;
  refreshing = true;
  try {
    guide = await requestBroadcast('guide');
    clockOffset = 0;
    const selectedKey = state.selectedProgram?.key;
    state.setChannels(guide.channels, now());
    if (selectedKey) {
      const i = state.selectedChannel?.programs.findIndex(p => p.key === selectedKey);
      if (i >= 0) state.programIndex = i;
    }
    $('loading-guide').hidden = true;
    $('loading-guide').style.display = 'none';
    $('channel-count').textContent = `${guide.channels.length} CHANNELS · ALWAYS SOMETHING ON`;
    $('schedule-status').textContent = guide.source === 'live' ? '24 HOURS / 7 DAYS' : `${guide.source.toUpperCase()} SCHEDULE`;
    $('schedule-status').classList.toggle('signal-off', guide.source !== 'live');
    if (initial) state.selectChannel(savedChannel() || 'it-came-from', now());
    render();
    if (initial) { state.tune(); await tuneChannel(state.tunedId); }
  } catch (error) {
    if (initial) {
      $('loading-guide').textContent = 'SIGNAL LOST. SELECT HERE TO RETRY.';
      $('loading-guide').style.cursor = 'pointer';
      $('loading-guide').onclick = () => refreshGuide(true);
      $('program-title').textContent = 'The antenna needs a moment.';
      $('program-time').textContent = 'Retrying in 15 seconds';
      setTimeout(() => refreshGuide(true), 15000);
    } else toast('Schedule unavailable. Your channel will keep playing.');
  } finally { refreshing = false; }
}
function render() {
  if (!guide) return;
  const width = guide.endMs - guide.startMs;
  const pct = at => (at - guide.startMs) / width * 100;
  $('times').innerHTML = Array.from({ length: 4 }, (_, i) => `<div class="time-slot">${escape(time(guide.startMs + i * 1800000))}</div>`).join('');
  $('guide-date').textContent = new Date(now()).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).toUpperCase();
  $('guide-rows').innerHTML = state.channels.map((channel, ci) => `<div class="guide-row ${ci === state.channelIndex ? 'selected' : ''}" role="row" data-channel="${ci}">
    <button class="channel-cell" role="rowheader" data-channel-button="${ci}" aria-label="Channel ${channel.number}, ${escape(channel.name)}"><span class="channel-number">${String(channel.number).padStart(2, '0')}</span><span class="channel-cell-copy"><span class="channel-cell-name">${escape(channel.name)}</span><span class="channel-cell-sub ${state.tunedId === channel.id ? 'tuned' : ''}">${state.tunedId === channel.id ? 'ON YOUR TELEVISION' : channel.error ? 'SIGNAL UNAVAILABLE' : '24/7 BROADCAST'}</span></span></button>
    <div class="program-track" role="row">${channel.error ? '<span class="row-error">Adjusting the antenna…</span>' : channel.programs.map((p, pi) => {
      const left = Math.max(0, pct(p.startMs)), right = Math.min(100, pct(p.endMs));
      if (right <= left) return '';
      return `<button role="gridcell" class="program-cell ${ci === state.channelIndex && pi === state.programIndex ? 'selected' : ''} ${p.endMs < now() ? 'is-past' : ''}" style="left:${left}%;width:${right - left}%" data-ci="${ci}" data-pi="${pi}" aria-selected="${ci === state.channelIndex && pi === state.programIndex}" aria-label="${escape(p.title)}, ${escape(time(p.startMs))}"><span class="cell-title">${p.startMs < guide.startMs ? '‹ ' : ''}${escape(p.title)}</span><span class="cell-sub">${escape(p.year)}${p.year ? ' · ' : ''}${escape(time(p.startMs))}${p.type !== 'video' ? ' · STATION ID' : ''}</span></button>`;
    }).join('')}<div class="now-line" style="left:${pct(now())}%"></div></div></div>`).join('');
  $('channel-position').textContent = `${String(state.channelIndex + 1).padStart(2, '0')} / ${state.channels.length}`;
  renderDetails();
  keepSelectionVisible();
}
function renderDetails() {
  const channel = state.selectedChannel;
  const program = state.selectedProgram;
  if (!channel) return;
  $('channel-number').textContent = `CH ${String(channel.number).padStart(2, '0')}`;
  $('channel-name').textContent = channel.name;
  $('program-title').textContent = program?.title || 'Adjusting the antenna…';
  $('program-year').textContent = program?.year || 'FROM THE ARCHIVE';
  $('program-time').textContent = program ? `${time(program.startMs)} – ${time(program.endMs)}` : 'Please stand by';
  $('program-description').textContent = channel.description;
  const upcoming = program?.startMs > now();
  const past = program?.endMs < now();
  $('program-status').textContent = upcoming ? 'UP NEXT' : past ? 'EARLIER' : 'LIVE NOW';
  $('program-status').classList.toggle('upcoming', upcoming || past);
  $('remaining').textContent = !program ? '' : upcoming ? `STARTS IN ${Math.max(1, Math.ceil((program.startMs - now()) / 60000))} MIN` : past ? 'TUNE IN TO WATCH LIVE' : `${Math.max(1, Math.ceil((program.endMs - now()) / 60000))} MIN REMAINING`;
  $('watch-button').disabled = !!channel.error;
}
function keepSelectionVisible() {
  const row = $('guide-rows').children[state.channelIndex];
  const viewport = $('guide-viewport');
  if (!row) return;
  const top = row.offsetTop, bottom = top + row.offsetHeight;
  if (top < viewport.scrollTop) viewport.scrollTo({ top, behavior: 'instant' });
  else if (bottom > viewport.scrollTop + viewport.clientHeight) viewport.scrollTo({ top: bottom - viewport.clientHeight, behavior: 'instant' });
}
function overlay() {
  if (!broadcast || state.mode !== 'watch') return;
  $('watch-channel').textContent = `CH ${broadcast.channel.number} / ${broadcast.channel.name} — ${broadcast.title}`;
  $('watch-overlay').hidden = false;
  clearTimeout(overlayTimer);
  overlayTimer = setTimeout(() => { $('watch-overlay').hidden = true; }, 4500);
}
function watchMode(enabled) {
  state.mode = enabled ? 'watch' : 'guide';
  $('television').classList.toggle('watch-mode', enabled);
  if (enabled) overlay();
  else { $('watch-overlay').hidden = true; state.selectChannel(state.tunedId, now()); render(); }
}
async function tuneChannel(id) {
  if (!id || !appActive) return;
  const request = ++generation;
  tuneController?.abort();
  tuneController = new AbortController();
  tuning = true;
  message('TUNING IN…');
  nextTuneAt = Infinity;
  // Stop the old channel immediately while a new one is requested.
  video.pause(); audio.pause();
  audio.onloadedmetadata = null;
  try {
    const data = await requestBroadcast('tune', { channelId: id, signal: tuneController.signal });
    if (request !== generation) return;
    clockOffset = 0;
    if (data.endMs <= now()) { tuning = false; return tuneChannel(id); }
    broadcast = data;
    saveChannel(id);
    state.tunedId = id;
    nextTuneAt = data.endMs;
    $('tuned-label').textContent = `CH ${data.channel.number} / ${data.channel.name}`;
    $('screen-bug').textContent = `SPELUNKR / ${data.channel.number}`;
    $('preview-poster').src = data.image || '';
    $('preview-poster').style.display = data.image ? 'block' : 'none';
    videoReady = false;
    video.style.visibility = 'hidden';
    $('station-card').classList.toggle('visible', !data.url);
    if (data.url) {
      video.src = data.url;
      video.load();
    } else {
      video.removeAttribute('src'); video.load();
      updateCard();
      message(data.message || '');
      if (data.audioUrl) {
        audio.src = data.audioUrl;
        audio.onloadedmetadata = () => {
          if (!appActive || request !== generation) return;
          audio.currentTime = data.audioSeek + Math.max(0, (now() - data.serverTime) / 1000);
          audio.play().catch(() => {});
        };
      } else { audio.removeAttribute('src'); audio.load(); }
    }
    render(); overlay();
  } catch (error) {
    if (request !== generation || error.name === 'AbortError') return;
    message('THE SIGNAL WANDERED OFF. TRYING AGAIN…');
    nextTuneAt = now() + 10000;
  } finally { if (request === generation) tuning = false; }
}
video.addEventListener('loadedmetadata', () => {
  if (!appActive) return;
  if (!broadcast?.url || !video.currentSrc.endsWith(new URL(broadcast.url).pathname)) return;
  const offset = broadcast.seek + Math.max(0, (now() - broadcast.serverTime) / 1000);
  video.currentTime = Math.min(offset, Number.isFinite(video.duration) ? Math.max(0, video.duration - .1) : offset);
  video.play().catch(() => { if (appActive) message('PRESS OK OR SOUND ON TO START THE BROADCAST'); });
});
video.addEventListener('playing', () => { videoReady = true; video.style.visibility = 'visible'; message(); });
video.addEventListener('waiting', () => { if (videoReady) message('ADJUSTING THE ANTENNA…'); });
video.addEventListener('error', () => { if (broadcast?.url) { message('THIS TAPE IS HAVING A MOMENT. RETRYING…'); nextTuneAt = Math.min(nextTuneAt, now() + 12000); } });
video.addEventListener('ended', () => { nextTuneAt = Math.min(nextTuneAt, now() + 1000); });
function updateCard() {
  if (!broadcast || broadcast.url) return;
  const offset = now() - broadcast.startMs;
  const card = broadcast.cards.find(c => offset >= c.start && offset < c.end);
  $('station-text').textContent = card?.text || (broadcast.type === 'up-next' ? 'UP NEXT' : 'YOU ARE WATCHING\n' + broadcast.channel.name);
}
function toggleSound() {
  video.muted = !video.muted;
  audio.muted = video.muted;
  $('sound-button').textContent = video.muted ? 'SOUND OFF' : 'SOUND ON';
  $('sound-button').setAttribute('aria-label', video.muted ? 'Unmute broadcast' : 'Mute broadcast');
  if (broadcast?.url) video.play().catch(() => message('The tape is still loading…'));
  else if (broadcast?.audioUrl) audio.play().catch(() => {});
}
function showHelp() { $('help-dialog').showModal(); }
function action(key) {
  if ($('help-dialog').open) {
    if (key === 'ok' || key === 'back' || key === 'help') $('help-dialog').close();
    else if (key === 'up' || key === 'down') $('help-dialog').scrollBy(0, key === 'up' ? -60 : 60);
    return;
  }
  if (!guide) { if (key === 'ok') refreshGuide(true); return; }
  if (key === 'help') return showHelp();
  if (key === 'back') { if ($('help-dialog').open) $('help-dialog').close(); else watchMode(false); return; }
  if (key === 'ok') {
    if (state.mode === 'watch') return watchMode(false);
    if (state.selectedProgram?.startMs > now()) toast(`Starts at ${time(state.selectedProgram.startMs)}. Tuning to what's live now.`);
    const id = state.tune();
    if (!id) return toast('The signal is unavailable. Try another channel.');
    if (broadcast?.channel.id !== id || video.error) tuneChannel(id);
    else if (broadcast.url) video.play().catch(() => {});
    watchMode(true);
    return;
  }
  if (key === 'up' || key === 'down') {
    if (state.mode === 'watch') state.selectChannel(state.tunedId, now());
    state.moveChannel(key === 'up' ? -1 : 1, now());
    if (state.mode === 'watch') tuneChannel(state.tune());
  } else if (state.mode === 'guide') state.moveProgram(key === 'left' ? -1 : 1);
  render();
}
$('guide-rows').addEventListener('click', e => {
  const program = e.target.closest('[data-ci]');
  const channel = e.target.closest('[data-channel-button]');
  if (program) {
    const ci = +program.dataset.ci, pi = +program.dataset.pi;
    const selected = state.channelIndex === ci && state.programIndex === pi;
    state.channelIndex = ci; state.programIndex = pi; render();
    if (selected) action('ok');
  } else if (channel) { state.channelIndex = +channel.dataset.channelButton; state.selectNow(now()); render(); }
});
document.addEventListener('keydown', e => {
  if ($('help-dialog').open) { if (e.key === 'Escape' || e.key === 'Enter') $('help-dialog').close(); return; }
  const keys = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', Enter: 'ok', Escape: 'back', Backspace: 'back', '*': 'help', '?': 'help' };
  if (e.key === 'Enter' && e.target.closest('button,a')) return;
  if (keys[e.key]) { e.preventDefault(); action(keys[e.key]); }
  else if (e.key.toLowerCase() === 'm') toggleSound();
});
document.querySelectorAll('[data-action]').forEach(b => b.addEventListener('click', () => action(b.dataset.action)));
$('watch-button').onclick = () => action('ok');
$('expand-button').onclick = () => watchMode(true);
$('sound-button').onclick = toggleSound;
$('help-button').onclick = showHelp;
$('close-help').onclick = $('got-it').onclick = () => $('help-dialog').close();
$('help-dialog').addEventListener('click', e => { if (e.target === $('help-dialog')) { const r = $('help-dialog').getBoundingClientRect(); if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) $('help-dialog').close(); } });
function handleBack() {
  if ($('help-dialog').open) { $('help-dialog').close(); return true; }
  if (state.mode === 'watch') { watchMode(false); return true; }
  return false;
}
function suspend() { appActive = false; tuneController?.abort(); video.pause(); audio.pause(); }
function resume() {
  const wasActive = appActive;
  appActive = true;
  if (!wasActive && state.tunedId) { refreshGuide(); tuneChannel(state.tunedId); }
}
window.spelunkr = Object.freeze({ action, handleBack, suspend, resume, toggleSound });
document.addEventListener('visibilitychange', () => { if (document.hidden) suspend(); else resume(); });
new ResizeObserver(keepSelectionVisible).observe($('guide-viewport'));
setInterval(() => {
  $('clock').textContent = time(now());
  if (appActive && broadcast && !tuning && now() >= nextTuneAt) tuneChannel(state.tunedId);
  updateCard();
  if (Math.floor(now() / 60000) !== lastTickMinute) { lastTickMinute = Math.floor(now() / 60000); renderDetails(); }
  // Buffering must not turn a synchronized channel into delayed video on demand.
  if (broadcast?.url && videoReady && !video.paused && !video.seeking && !tuning) {
    const target = broadcast.seek + (now() - broadcast.serverTime) / 1000;
    if (Math.abs(video.currentTime - target) > 5 && target < video.duration) video.currentTime = target;
  }
}, 1000);
setInterval(() => refreshGuide(), 60000);
refreshGuide(true);
