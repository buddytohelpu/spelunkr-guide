let worker, serial = 0;
const pending = new Map();

function getWorker() {
  if (worker) return worker;
  worker = new Worker(new URL('./broadcast-worker.js', import.meta.url), { type: 'module' });
  worker.onmessage = ({ data: response }) => {
    const request = pending.get(response.requestId);
    if (!request) return;
    request.finish();
    if (response.ok) request.resolve(response.data);
    else request.reject(new Error(response.error));
  };
  worker.onerror = () => {
    const error = new Error('The broadcast engine could not start. Reopen the app or update your system web browser.');
    for (const request of [...pending.values()]) { request.finish(); request.reject(error); }
    worker?.terminate();
    worker = null;
  };
  return worker;
}

export function requestBroadcast(action, { channelId, signal } = {}) {
  if (signal?.aborted) return Promise.reject(new DOMException('Channel changed', 'AbortError'));
  return new Promise((resolve, reject) => {
    const requestId = ++serial;
    let timeout;
    const finish = () => { clearTimeout(timeout); pending.delete(requestId); signal?.removeEventListener('abort', abort); };
    const abort = () => { finish(); reject(new DOMException('Channel changed', 'AbortError')); };
    timeout = setTimeout(() => { finish(); reject(new Error('The signal is taking too long. Trying again…')); }, 45000);
    signal?.addEventListener('abort', abort, { once: true });
    pending.set(requestId, { resolve, reject, finish });
    try { getWorker().postMessage({ requestId, action, channelId }); }
    catch (error) { finish(); reject(error); }
  });
}
