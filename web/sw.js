const CACHE = 'do-v2';
const PRECACHE = [
  '/',
  '/www/style/main.css',
  '/www/style/landing.css',
  '/android-icon-192x192.png',
  '/favicon.ico',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(PRECACHE)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  // Only handle GET requests — POST (form submissions) are not cacheable
  if (e.request.method !== 'GET') return;

  const url = e.request.url;

  if (url.includes('/cgi-bin/')) {
    // Network-first: fetch live, save to cache, serve cache when offline
    e.respondWith(
      caches.open(CACHE).then(cache =>
        fetch(e.request).then(response => {
          if (response.ok) cache.put(e.request, response.clone());
          return response;
        }).catch(() => caches.match(e.request))
      )
    );
  } else {
    // Cache-first for static assets
    e.respondWith(
      caches.match(e.request).then(cached => {
        if (cached) return cached;
        return fetch(e.request).then(response => {
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE).then(c => c.put(e.request, clone));
          }
          return response;
        });
      })
    );
  }
});
