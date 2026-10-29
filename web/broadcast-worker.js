import { Broadcast } from './broadcast.js';

const broadcast = new Broadcast();
self.onmessage = async ({ data: request }) => {
  try {
    let data;
    if (request.action === 'guide') data = await broadcast.guide();
    else if (request.action === 'tune') data = await broadcast.tune(request.channelId);
    else throw new Error('Unknown broadcast request');
    self.postMessage({ requestId: request.requestId, ok: true, data });
  } catch (error) {
    self.postMessage({ requestId: request.requestId, ok: false, error: error.message || 'The broadcast is temporarily unavailable.' });
  }
};
