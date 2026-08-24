const pending = new Map();
let seq = 1;

self.addEventListener('install', (event) => {
  try {
    self.skipWaiting();
  } catch (_) {}
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      await self.clients.claim();
    } catch (_) {}
  })());
});

function headersToObject(headers) {
  const out = {};
  try {
    for (const [k, v] of headers.entries()) out[k] = v;
  } catch (_) {}
  return out;
}

function base64ToUint8Array(b64) {
  const bin = atob(b64);
  const len = bin.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function uint8ArrayToBase64(bytes) {
  let bin = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
  }
  return btoa(bin);
}

self.addEventListener('message', (event) => {
  const msg = event && event.data;
  if (!msg || typeof msg.__p2p !== 'string' || !msg.__p2p.startsWith('sw_fetch_res')) return;
  const id = msg.id;
  if (!id || !pending.has(id)) return;
  const st = pending.get(id);
  if (!st) return;

  if (msg.__p2p === 'sw_fetch_res') {
    pending.delete(id);
    const { resolve, reject } = st;
    if (msg.error) {
      reject(new Error(msg.error));
      return;
    }
    try {
      const status = typeof msg.status === 'number' ? msg.status : 200;
      const headers = new Headers(msg.headers || {});
      let body = null;
      if (typeof msg.bodyBase64 === 'string' && msg.bodyBase64.length > 0) {
        body = base64ToUint8Array(msg.bodyBase64);
      } else if (typeof msg.bodyText === 'string') {
        body = msg.bodyText;
      }
      resolve(new Response(body, { status, headers }));
    } catch (e) {
      reject(e);
    }
    return;
  }

  if (msg.__p2p === 'sw_fetch_res_begin') {
    if (st.streamController) return;
    const status = typeof msg.status === 'number' ? msg.status : 200;
    const headers = new Headers(msg.headers || {});
    const stream = new ReadableStream({
      start(controller) {
        st.streamController = controller;
      },
      cancel() {
        try {
          pending.delete(id);
          // Notify client to abort
          self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clients => {
            clients.forEach(client => {
              client.postMessage({ __p2p: 'sw_fetch_abort', id });
            });
          });
        } catch (_) {}
      },
    });
    st.resolve(new Response(stream, { status, headers }));
    return;
  }

  if (msg.__p2p === 'sw_fetch_res_chunk') {
    if (!st.streamController) return;
    try {
      if (msg.chunk) {
        st.streamController.enqueue(msg.chunk);
      } else if (typeof msg.dataBase64 === 'string' && msg.dataBase64.length > 0) {
        st.streamController.enqueue(base64ToUint8Array(msg.dataBase64));
      }
    } catch (_) {}
    return;
  }

  if (msg.__p2p === 'sw_fetch_res_end') {
    pending.delete(id);
    try {
      if (st.streamController) st.streamController.close();
    } catch (_) {}
    return;
  }

  if (msg.__p2p === 'sw_fetch_res_error') {
    pending.delete(id);
    try {
      if (st.streamController) st.streamController.error(new Error(msg.error || 'p2p_error'));
    } catch (_) {}
    try {
      st.reject(new Error(msg.error || 'p2p_error'));
    } catch (_) {}
  }
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);
  // 支持部署在子路径（如 /client/__p2p__/api/...）
  if (!url.pathname.includes('/__p2p__/')) return;

  event.respondWith((async () => {
    const id = 'sw_' + (seq++);
    const headers = headersToObject(req.headers);

    let bodyBase64 = '';
    try {
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        const ab = await req.clone().arrayBuffer();
        if (ab && ab.byteLength > 0) {
          bodyBase64 = uint8ArrayToBase64(new Uint8Array(ab));
        }
      }
    } catch (_) {}

    const msg = {
      __p2p: 'sw_fetch',
      id,
      url: req.url,
      method: req.method,
      headers,
      bodyBase64,
    };

    const clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (!clientsList || clientsList.length === 0) {
      return new Response('No client', { status: 503 });
    }
    const client = clientsList.find(c => c && c.id === event.clientId) || clientsList[0];

    const resPromise = new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject, streamController: null });
      setTimeout(() => {
        if (!pending.has(id)) return;
        pending.delete(id);
        reject(new Error('timeout'));
      }, 30 * 60 * 1000);
    });

    try {
      clientsList.forEach(c => {
        try {
          c.postMessage(msg);
        } catch (_) {}
      });
    } catch (e) {
      pending.delete(id);
      return new Response('Bad Gateway', { status: 502 });
    }

    try {
      return await resPromise;
    } catch (_) {
      return new Response('Bad Gateway', { status: 502 });
    }
  })());
});
