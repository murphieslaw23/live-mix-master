const CACHE_NAME = 'livemixmaster-shell-v2';
const SHELL_ASSETS = [
  './',
  './index.html',
  './offline.html',
  './manifest.json',
  './icons/livemixmaster-maskable.svg',
  './icons/livemixmaster-maskable-192.png',
  './icons/livemixmaster-maskable-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(SHELL_ASSETS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_NAME)
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (
    request.method !== 'GET' ||
    url.origin !== self.location.origin ||
    url.pathname.startsWith('/api/')
  ) {
    return;
  }

  event.respondWith(
    fetch(request)
      .then(async (response) => {
        if (response && response.status === 200 && response.type !== 'opaque') {
          const cache = await caches.open(CACHE_NAME);
          await cache.put(request, response.clone());
        }
        return response;
      })
      .catch(async (error) => {
        if (request.mode === 'navigate') {
          const offline = await caches.match('./offline.html');
          if (offline) {
            return offline;
          }
        }

        const cached = await caches.match(request);
        if (cached) {
          return cached;
        }

        throw error;
      }),
  );
});
