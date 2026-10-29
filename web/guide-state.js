export class GuideState {
  constructor() { this.channels = []; this.channelIndex = 0; this.programIndex = 0; this.tunedId = null; this.mode = 'guide'; }
  get selectedChannel() { return this.channels[this.channelIndex]; }
  get selectedProgram() { return this.selectedChannel?.programs[this.programIndex]; }
  setChannels(channels, now = Date.now()) {
    const id = this.selectedChannel?.id;
    this.channels = channels;
    this.channelIndex = Math.max(0, channels.findIndex(c => c.id === id));
    this.selectNow(now);
  }
  selectNow(now = Date.now()) {
    this.programIndex = Math.max(0, this.selectedChannel?.programs.findIndex(p => p.startMs <= now && p.endMs > now) ?? 0);
  }
  moveChannel(delta, now = Date.now()) {
    if (!this.channels.length) return;
    this.channelIndex = (this.channelIndex + delta + this.channels.length) % this.channels.length;
    this.selectNow(now);
  }
  moveProgram(delta) {
    this.programIndex = Math.max(0, Math.min((this.selectedChannel?.programs.length || 1) - 1, this.programIndex + delta));
  }
  selectChannel(id, now = Date.now()) {
    const index = this.channels.findIndex(c => c.id === id);
    if (index >= 0) { this.channelIndex = index; this.selectNow(now); }
  }
  tune() {
    if (!this.selectedChannel || this.selectedChannel.error) return null;
    this.tunedId = this.selectedChannel.id;
    return this.tunedId;
  }
}
